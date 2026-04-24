defmodule LemmingsOs.ModelRuntime do
  @moduledoc """
  Runtime boundary for model execution.
  """

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.ModelRuntime.Providers.Ollama
  alias LemmingsOs.ModelRuntime.Response
  alias LemmingsOs.Tools.Catalog

  @structured_output_contract """
  Return JSON only with this shape:

  {"action":"reply","reply":"visible user-facing text"}
  or
  {"action":"tool_call","tool_name":"fs.read_text_file","args":{"path":"notes.txt"}}
  or, when lemming-call capabilities are listed in system context,
  {"action":"lemming_call","target":"slug-or-capability","request":"bounded task text","continue_call_id":null}
  """

  @runtime_rules """
  - Return valid JSON only.
  - Do not wrap the JSON in markdown fences.
  - Do not emit extra keys.
  - Keep the reply user-facing.
  """

  @doc """
  Executes the configured provider with an assembled prompt.

  ## Examples

      iex> config_snapshot = %{
      ...>   instructions: "Be concise.",
      ...>   provider_module: LemmingsOs.ModelRuntimeTest.FakeProvider,
      ...>   model: "test-model"
      ...> }
      iex> history = [%{role: "user", content: "Hello"}]
      iex> current_request = %{content: "Hello"}
      iex> {:ok, response} = LemmingsOs.ModelRuntime.run(config_snapshot, history, current_request)
      iex> response.reply
      "ok"
  """
  @spec run(map(), [map()], map() | String.t()) ::
          {:ok, Response.t()}
          | {:error, term()}
  def run(config_snapshot, history, current_request)
      when is_map(config_snapshot) and is_list(history) do
    with {:ok, candidates} <- resolve_model_candidates(config_snapshot) do
      run_with_candidates(config_snapshot, history, current_request, candidates, [])
    end
  end

  def run(_config_snapshot, _history, _current_request), do: {:error, :invalid_request}

  @doc """
  Builds the exact provider request payload that would be sent to the model.

  This is intended for operator/debug surfaces that need to inspect the
  assembled system prompt, normalized history, and current request before the
  provider call happens.
  """
  @spec debug_request(map(), [map()], map() | String.t()) ::
          {:ok, %{provider: String.t() | nil, model: String.t(), request: map()}}
          | {:error, term()}
  def debug_request(config_snapshot, history, current_request)
      when is_map(config_snapshot) and is_list(history) do
    with {:ok, %{model: model} = candidate} <- primary_model_candidate(config_snapshot),
         {:ok, request} <- build_request(config_snapshot, history, current_request, model) do
      {:ok,
       %{
         provider: provider_hint_label(config_snapshot, candidate),
         model: model,
         request: request
       }}
    end
  end

  def debug_request(_config_snapshot, _history, _current_request), do: {:error, :invalid_request}

  @doc false
  @spec structured_output_contract() :: String.t()
  def structured_output_contract, do: @structured_output_contract

  @doc false
  @spec runtime_rules() :: String.t()
  def runtime_rules, do: @runtime_rules

  defp validate_provider_response(provider_response, requested_model)
       when is_map(provider_response) do
    with {:ok, content} <- provider_content(provider_response),
         {:ok, action_payload} <- parse_provider_content(content, provider_response) do
      {:ok,
       Response.new(
         action: action_payload.action,
         reply: action_payload.reply,
         tool_name: action_payload.tool_name,
         tool_args: action_payload.tool_args,
         lemming_target: action_payload.lemming_target,
         lemming_request: action_payload.lemming_request,
         continue_call_id: action_payload.continue_call_id,
         provider: provider_label(provider_response),
         model: response_field(provider_response, :model) || requested_model,
         input_tokens: response_field(provider_response, :input_tokens),
         output_tokens: response_field(provider_response, :output_tokens),
         total_tokens: response_field(provider_response, :total_tokens),
         usage: response_field(provider_response, :usage),
         raw: response_field(provider_response, :raw) || provider_response
       )}
    else
      {:error, :unknown_action} ->
        {:error, unknown_action_error(provider_response, requested_model)}

      {:error, reason} ->
        {:error, invalid_structured_output_error(provider_response, requested_model, reason)}
    end
  end

  defp validate_provider_response(_provider_response, _requested_model) do
    {:error, :provider_error}
  end

  defp parse_provider_content(content, provider_response) when is_binary(content) do
    trimmed = String.trim(content)

    case Jason.decode(trimmed) do
      {:ok, parsed} -> parse_structured_output(parsed)
      {:error, _reason} -> maybe_parse_legacy_structured_output(trimmed, provider_response)
    end
  end

  defp maybe_parse_legacy_structured_output(content, provider_response) do
    if legacy_structured_output_enabled?(provider_response) do
      parse_legacy_structured_output(content)
    else
      {:error, :invalid_structured_output}
    end
  end

  defp legacy_structured_output_enabled?(provider_response) do
    case response_field(provider_response, :legacy_structured_output) do
      true -> true
      _other -> false
    end
  end

  defp parse_structured_output(%{"action" => "reply", "reply" => reply}) when is_binary(reply) do
    if Helpers.blank?(reply) do
      {:error, :invalid_structured_output}
    else
      {:ok,
       %{
         action: :reply,
         reply: reply,
         tool_name: nil,
         tool_args: nil,
         lemming_target: nil,
         lemming_request: nil,
         continue_call_id: nil
       }}
    end
  end

  defp parse_structured_output(%{"action" => "reply"}), do: {:error, :invalid_structured_output}

  defp parse_structured_output(%{
         "action" => "tool_call",
         "tool_name" => tool_name,
         "args" => args
       })
       when is_binary(tool_name) and is_map(args) do
    if Helpers.blank?(tool_name) do
      {:error, :invalid_structured_output}
    else
      {:ok,
       %{
         action: :tool_call,
         reply: nil,
         tool_name: tool_name,
         tool_args: args,
         lemming_target: nil,
         lemming_request: nil,
         continue_call_id: nil
       }}
    end
  end

  defp parse_structured_output(%{"action" => "tool_call"}),
    do: {:error, :invalid_structured_output}

  defp parse_structured_output(
         %{
           "action" => "lemming_call",
           "target" => target,
           "request" => request
         } = payload
       )
       when is_binary(target) and is_binary(request) do
    continue_call_id = nil_if_blank(Map.get(payload, "continue_call_id"))

    if Helpers.blank?(target) or Helpers.blank?(request) or
         continue_call_id == :invalid_continue_call_id do
      {:error, :invalid_structured_output}
    else
      {:ok,
       %{
         action: :lemming_call,
         reply: nil,
         tool_name: nil,
         tool_args: nil,
         lemming_target: target,
         lemming_request: request,
         continue_call_id: continue_call_id
       }}
    end
  end

  defp parse_structured_output(%{"action" => "lemming_call"}),
    do: {:error, :invalid_structured_output}

  defp parse_structured_output(%{"action" => action}) when is_binary(action),
    do: {:error, :unknown_action}

  defp parse_structured_output(_other), do: {:error, :invalid_structured_output}

  defp parse_legacy_structured_output(content) when is_binary(content) do
    cond do
      legacy_tool_call_match?(content) ->
        parse_legacy_tool_call(content)

      legacy_lemming_call_match?(content) ->
        parse_legacy_lemming_call(content)

      true ->
        {:error, :invalid_structured_output}
    end
  end

  defp legacy_tool_call_match?(content) do
    String.starts_with?(content, "Assistant requested tool ") and
      String.contains?(content, " with arguments: ")
  end

  defp legacy_lemming_call_match?(content) do
    String.starts_with?(content, "Assistant requested lemming_call with arguments: ")
  end

  defp parse_legacy_tool_call(content) do
    with [tool_name, args_json] <- String.split(content, " with arguments: ", parts: 2),
         <<"Assistant requested tool ", raw_tool_name::binary>> <- tool_name,
         false <- Helpers.blank?(raw_tool_name),
         {:ok, args} <- Jason.decode(args_json),
         true <- is_map(args) do
      parse_structured_output(%{
        "action" => "tool_call",
        "tool_name" => raw_tool_name,
        "args" => args
      })
    else
      _other -> {:error, :invalid_structured_output}
    end
  end

  defp parse_legacy_lemming_call(content) do
    with <<"Assistant requested lemming_call with arguments: ", payload_json::binary>> <-
           content,
         {:ok, payload} <- Jason.decode(payload_json) do
      parse_structured_output(Map.put(payload, "action", "lemming_call"))
    else
      _other -> {:error, :invalid_structured_output}
    end
  end

  defp nil_if_blank(nil), do: nil

  defp nil_if_blank(value) when is_binary(value),
    do: if(Helpers.blank?(value), do: nil, else: value)

  defp nil_if_blank(_value), do: :invalid_continue_call_id

  defp provider_content(provider_response) do
    case response_field(provider_response, :content) do
      content when is_binary(content) ->
        if Helpers.blank?(content), do: {:error, :provider_error}, else: {:ok, content}

      _ ->
        {:error, :provider_error}
    end
  end

  defp invalid_structured_output_error(provider_response, requested_model, reason) do
    {:invalid_structured_output,
     %{
       reason: inspect(reason),
       provider: provider_label(provider_response),
       model: response_field(provider_response, :model) || requested_model,
       content: response_field(provider_response, :content),
       raw: response_field(provider_response, :raw) || provider_response
     }}
  end

  defp unknown_action_error(provider_response, requested_model) do
    {:unknown_action,
     %{
       provider: provider_label(provider_response),
       model: response_field(provider_response, :model) || requested_model,
       content: response_field(provider_response, :content),
       raw: response_field(provider_response, :raw) || provider_response
     }}
  end

  defp build_request(config_snapshot, history, current_request, model) do
    with {:ok, current_message} <- normalize_current_message(current_request) do
      messages =
        config_snapshot
        |> build_messages(history, current_message)
        |> Enum.map(&provider_message/1)

      {:ok, %{model: model, messages: messages, format: "json"}}
    end
  end

  defp build_messages(config_snapshot, history, current_message) do
    system_message = %{role: "system", content: system_message(config_snapshot)}
    normalized_history = normalize_history(history)

    messages =
      if current_message_in_history?(normalized_history, current_message) do
        normalized_history
      else
        normalized_history ++ [current_message]
      end

    [system_message | messages]
  end

  defp current_message_in_history?(history, %{request_id: request_id})
       when is_binary(request_id) and request_id != "" do
    Enum.any?(history, &(&1.request_id == request_id))
  end

  defp current_message_in_history?(history, current_message) do
    List.last(history) == current_message
  end

  defp system_message(config_snapshot) do
    [
      platform_runtime_context(),
      configured_identity_message(config_snapshot),
      available_tools_message(config_snapshot),
      available_lemming_calls_message(config_snapshot),
      loop_state_semantics_message(),
      @runtime_rules,
      immediate_response_instruction(),
      important_output_contract()
    ]
    |> Enum.reject(&Helpers.blank?/1)
    |> Enum.join("\n\n")
  end

  defp platform_runtime_context do
    """
    Platform Runtime Context:
    - You are running as a Lemming agent inside a multi-agent application runtime.
    - Your administrator configures your identity, purpose, and expertise.
    - The runtime adds tool availability, execution rules, and loop-state context.
    - On each turn, choose exactly one next action: either return a final user-facing reply, request one tool call, or request one listed lemming call when available.
    - When a tool call or lemming call is returned, the app executes it and sends the result back in later assistant-context messages.
    - If the latest tool result or completed child result already satisfies the request, return a final reply instead of repeating the same successful action.
    """
  end

  defp configured_identity_message(config_snapshot) do
    identity_lines =
      [
        configured_identity_name(config_snapshot),
        configured_identity_description(config_snapshot),
        configured_identity_instructions(config_snapshot)
      ]
      |> Enum.reject(&Helpers.blank?/1)

    case identity_lines do
      [] ->
        nil

      lines ->
        Enum.join(["Configured Lemming Identity:" | lines], "\n")
    end
  end

  defp configured_identity_name(config_snapshot) do
    case response_field(config_snapshot, :name) do
      name when is_binary(name) and name != "" -> "Name: #{name}"
      _name -> nil
    end
  end

  defp configured_identity_description(config_snapshot) do
    case response_field(config_snapshot, :description) do
      description when is_binary(description) and description != "" ->
        "Description: #{description}"

      _description ->
        nil
    end
  end

  defp configured_identity_instructions(config_snapshot) do
    case instructions_from_snapshot(config_snapshot) do
      instructions when is_binary(instructions) and instructions != "" ->
        "Instructions:\n#{instructions}"

      _instructions ->
        nil
    end
  end

  defp available_tools_message(config_snapshot) do
    tool_lines =
      config_snapshot
      |> available_tools()
      |> Enum.map_join("\n", fn tool ->
        "- #{tool.id}: #{tool.description}"
      end)

    [
      "Available Tools:",
      tool_lines,
      "For file creation or file updates, use fs.write_text_file.",
      "After a successful tool call, prefer returning a final reply instead of repeating the same tool call with the same arguments."
    ]
    |> Enum.join("\n")
  end

  defp available_lemming_calls_message(config_snapshot) do
    targets = lemming_call_targets(config_snapshot)

    case targets do
      [] ->
        nil

      targets ->
        target_lines =
          Enum.map_join(targets, "\n", fn target ->
            "- #{target.capability}: target=#{target.slug}; role=#{target.role}; department=#{target.department_slug}; #{target.description}"
          end)

        [
          "Available Lemming Calls:",
          target_lines,
          "Managers may delegate one bounded task to a listed target.",
          "Use continue_call_id only when refining a prior call id supplied by runtime context."
        ]
        |> Enum.join("\n")
    end
  end

  defp loop_state_semantics_message do
    """
    Loop State Semantics:
    - Prior assistant tool decisions appear in assistant-context messages.
    - Prior assistant lemming-call decisions also appear in assistant-context messages.
    - `Assistant requested tool <tool_name> with arguments: <json>` means you already chose that tool on a prior turn.
    - `Assistant requested lemming_call with arguments: <json>` means you already delegated that bounded task on a prior turn.
    - `Tool result for <tool_name>: status=<status> payload=<json>` means the runtime executed your prior tool request and is returning the outcome to you now.
    - `Lemming call result: status=<status> payload=<json>` means the runtime is returning delegated outcome to you now.
    - Treat those assistant-context messages as prior execution history, not as new user requests.
    - When a completed child payload includes `result_summary`, treat it as usable delegated result history.
    - When a completed child result already satisfies the task, prefer replying or making the next bounded delegation.
    - Do not invent file paths, output files, or artifacts unless runtime payload explicitly mentions them.
    - Use the configured identity, the original user request, and the latest runtime result to decide the next action.
    """
  end

  defp immediate_response_instruction do
    """
    Immediate Response Instruction:
    - Read the conversation messages below and decide the next action now.
    - If the latest tool result already satisfies the user request, return a final `reply`.
    - If the latest completed lemming call result already satisfies the user request, return a final `reply` or one next bounded `lemming_call`.
    - If another tool action is still required, return one `tool_call`.
    - Treat tool and lemming-call assistant-context messages as prior runtime execution history, not as new user input.
    - Do not invent file paths, output files, or artifacts unless the runtime payload explicitly includes them.
    - Do not explain your reasoning.
    - Do not add any text before or after the JSON object.
    - Return exactly one JSON object matching the output contract below.
    """
  end

  defp important_output_contract do
    """
    IMPORTANT: RESPOND WITH JSON ONLY.

    Decide what to do next by returning exactly one JSON shape:

    {"action":"reply","reply":"visible user-facing text"}
    or
    {"action":"tool_call","tool_name":"fs.read_text_file","args":{"path":"notes.txt"}}
    or, when Available Lemming Calls are listed,
    {"action":"lemming_call","target":"slug-or-capability","request":"bounded task text","continue_call_id":null}

    Option A: final reply to the user.
    Option B: one tool call for the runtime to execute.
    Option C: one lemming call for the runtime to execute within listed boundaries.
    """
  end

  defp lemming_call_targets(config_snapshot) do
    config_snapshot
    |> response_field(:lemming_call_targets)
    |> normalize_lemming_call_targets()
  end

  defp normalize_lemming_call_targets(targets) when is_list(targets) do
    Enum.flat_map(targets, &normalize_lemming_call_target/1)
  end

  defp normalize_lemming_call_targets(_targets), do: []

  defp normalize_lemming_call_target(%{} = target) do
    with slug when is_binary(slug) <- response_field(target, :slug),
         capability when is_binary(capability) <- response_field(target, :capability),
         role when is_binary(role) <- response_field(target, :role) do
      [
        %{
          slug: slug,
          capability: capability,
          role: role,
          department_slug: response_field(target, :department_slug) || "same-department",
          description: response_field(target, :description) || ""
        }
      ]
    else
      _other -> []
    end
  end

  defp normalize_lemming_call_target(_target), do: []

  defp available_tools(config_snapshot) do
    catalog_tools = Catalog.list_tools()
    allowed_tools = tools_config_list(config_snapshot, :allowed_tools)
    denied_tools = MapSet.new(tools_config_list(config_snapshot, :denied_tools))

    catalog_tools
    |> maybe_filter_allowed_tools(allowed_tools)
    |> Enum.reject(&MapSet.member?(denied_tools, &1.id))
  end

  defp maybe_filter_allowed_tools(tool_names, []), do: tool_names

  defp maybe_filter_allowed_tools(tools, allowed_tools) do
    Enum.filter(tools, &(&1.id in allowed_tools))
  end

  defp tools_config_list(config_snapshot, field) do
    config_snapshot
    |> tools_config_value(field)
    |> normalize_tool_name_list()
  end

  defp tools_config_value(config_snapshot, field) do
    config_snapshot
    |> response_field(:tools_config)
    |> case do
      tools_config when is_map(tools_config) -> response_field(tools_config, field)
      _tools_config -> nil
    end
  end

  defp normalize_tool_name_list(tool_names) when is_list(tool_names) do
    Enum.filter(tool_names, &is_binary/1)
  end

  defp normalize_tool_name_list(_tool_names), do: []

  defp normalize_history(history) do
    history
    |> Enum.flat_map(fn
      %{role: role, content: content} = message when is_binary(content) ->
        maybe_message(role, content, message)

      %{"role" => role, "content" => content} = message when is_binary(content) ->
        maybe_message(role, content, message)

      _ ->
        []
    end)
  end

  defp maybe_message("system", _content, _message), do: []
  defp maybe_message(:system, _content, _message), do: []

  defp maybe_message(role, content, message)
       when role in ["user", "assistant", :user, :assistant] do
    [
      %{
        role: normalize_role(role),
        content: content,
        request_id: request_id(message)
      }
    ]
  end

  defp maybe_message(_role, _content, _message), do: []

  defp normalize_role(role) when role in [:user, "user"], do: "user"
  defp normalize_role(role) when role in [:assistant, "assistant"], do: "assistant"

  defp normalize_current_message(%{content: nil}), do: {:error, :invalid_request}
  defp normalize_current_message(%{content: ""}), do: {:error, :invalid_request}

  defp normalize_current_message(%{content: content} = message) when is_binary(content),
    do: {:ok, %{role: "user", content: content, request_id: request_id(message)}}

  defp normalize_current_message(%{"content" => nil}), do: {:error, :invalid_request}
  defp normalize_current_message(%{"content" => ""}), do: {:error, :invalid_request}

  defp normalize_current_message(%{"content" => content} = message) when is_binary(content),
    do: {:ok, %{role: "user", content: content, request_id: request_id(message)}}

  defp normalize_current_message(nil), do: {:error, :invalid_request}
  defp normalize_current_message(""), do: {:error, :invalid_request}

  defp normalize_current_message(content) when is_binary(content),
    do: {:ok, %{role: "user", content: content, request_id: nil}}

  defp normalize_current_message(_other), do: {:error, :invalid_request}

  defp provider_message(message), do: Map.take(message, [:role, :content])

  defp request_id(%{request_id: request_id}) when is_binary(request_id), do: request_id
  defp request_id(%{"request_id" => request_id}) when is_binary(request_id), do: request_id
  defp request_id(%{id: id}) when is_binary(id), do: id
  defp request_id(%{"id" => id}) when is_binary(id), do: id
  defp request_id(_message), do: nil

  defp instructions_from_snapshot(config_snapshot) do
    response_field(config_snapshot, :instructions) ||
      response_field(config_snapshot, :instructions_text) ||
      ""
  end

  defp run_with_candidates(
         _config_snapshot,
         _history,
         _current_request,
         [],
         _attempts
       ),
       do: {:error, :missing_model}

  defp run_with_candidates(
         config_snapshot,
         history,
         current_request,
         [%{} = candidate | rest],
         attempts
       ) do
    with {:ok, provider_mod} <- resolve_provider_module(config_snapshot, candidate),
         {:ok, request} <-
           build_request(config_snapshot, history, current_request, candidate.model),
         {:ok, provider_response} <- provider_mod.chat(request, provider_opts(config_snapshot)),
         {:ok, response} <- validate_provider_response(provider_response, candidate.model) do
      {:ok, response}
    else
      {:error, reason} ->
        attempt = attempt_metadata(candidate, reason)

        if fallback_error?(reason) and rest != [] do
          run_with_candidates(
            config_snapshot,
            history,
            current_request,
            rest,
            attempts ++ [attempt]
          )
        else
          {:error, attach_attempts(reason, attempts ++ [attempt])}
        end

      other ->
        other
    end
  end

  defp resolve_model_candidates(config_snapshot) do
    case model_candidates(config_snapshot) do
      [] -> {:error, :missing_model}
      candidates -> {:ok, candidates}
    end
  end

  defp primary_model_candidate(config_snapshot) do
    with {:ok, [candidate | _rest]} <- resolve_model_candidates(config_snapshot) do
      {:ok, candidate}
    end
  end

  defp model_candidates(config_snapshot) do
    case ConfigSnapshot.model_candidates(config_snapshot) do
      [] ->
        case resolve_model(config_snapshot) do
          {:ok, model} ->
            [
              %{
                provider: provider_hint_label(config_snapshot),
                model: model,
                resource_key: candidate_resource_key(provider_hint_label(config_snapshot), model)
              }
            ]

          _other ->
            []
        end

      candidates ->
        candidates
    end
  end

  defp candidate_resource_key(provider, model)
       when is_binary(provider) and provider != "" and is_binary(model) and model != "" do
    "#{provider}:#{model}"
  end

  defp candidate_resource_key(_provider, model) when is_binary(model), do: model
  defp candidate_resource_key(_provider, _model), do: nil

  defp attempt_metadata(candidate, reason) do
    %{
      provider: Map.get(candidate, :provider),
      model: Map.get(candidate, :model),
      resource_key:
        Map.get(candidate, :resource_key) ||
          candidate_resource_key(Map.get(candidate, :provider), Map.get(candidate, :model)),
      reason: fallback_reason_label(reason)
    }
  end

  defp fallback_reason_label({kind, _metadata}) when is_atom(kind), do: Atom.to_string(kind)
  defp fallback_reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp fallback_reason_label(reason), do: inspect(reason)

  defp fallback_error?(:invalid_request), do: false
  defp fallback_error?(:missing_model), do: false
  defp fallback_error?(_reason), do: true

  defp attach_attempts({kind, metadata}, attempts) when is_atom(kind) and is_map(metadata) do
    {kind, Map.put(metadata, :attempts, attempts)}
  end

  defp attach_attempts(reason, _attempts), do: reason

  defp resolve_provider_module(config_snapshot, candidate) do
    provider_module_for(provider_hint(config_snapshot, candidate))
  end

  defp provider_hint(config_snapshot, candidate) do
    response_field(config_snapshot, :provider_module) ||
      Map.get(candidate, :provider) ||
      ConfigSnapshot.provider(config_snapshot) ||
      response_field(config_snapshot, :provider) ||
      nested_field(config_snapshot, [:model_runtime, :provider]) ||
      nested_field(config_snapshot, [:model_runtime, :provider_module]) ||
      Ollama
  end

  defp provider_module_for(module) when is_atom(module) do
    cond do
      module == :ollama -> {:ok, Ollama}
      function_exported?(module, :chat, 2) -> {:ok, module}
      true -> {:error, :unsupported_provider}
    end
  end

  defp provider_module_for("ollama"), do: {:ok, Ollama}
  defp provider_module_for(_other), do: {:error, :unsupported_provider}

  defp resolve_model(config_snapshot) do
    candidates = [
      ConfigSnapshot.model(config_snapshot),
      response_field(config_snapshot, :model),
      response_field(config_snapshot, :default_model),
      Application.get_env(:lemmings_os, :model_runtime, [])
      |> Keyword.get(:default_model)
    ]

    case Enum.find(candidates, &is_binary/1) do
      nil -> {:error, :missing_model}
      model -> {:ok, model}
    end
  end

  defp provider_opts(_config_snapshot) do
    runtime_config = Application.get_env(:lemmings_os, :model_runtime, [])
    ollama_config = Keyword.get(runtime_config, :ollama, [])

    [
      base_url: Keyword.get(ollama_config, :base_url, "http://localhost:11434"),
      timeout: Keyword.get(runtime_config, :timeout, 120_000)
    ]
  end

  defp provider_label(provider_response) do
    case response_field(provider_response, :provider) do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> "ollama"
    end
  end

  defp response_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp provider_hint_label(config_snapshot), do: provider_hint_label(config_snapshot, %{})

  defp provider_hint_label(config_snapshot, candidate) do
    case provider_hint(config_snapshot, candidate) do
      provider when is_atom(provider) -> Atom.to_string(provider)
      provider when is_binary(provider) -> provider
      _provider -> nil
    end
  end

  defp nested_field(map, [key | rest]) when is_map(map) do
    case response_field(map, key) do
      nil -> nil
      next -> nested_field(next, rest)
    end
  end

  defp nested_field(value, []), do: value
  defp nested_field(_value, _rest), do: nil
end
