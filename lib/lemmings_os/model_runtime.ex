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
  Return JSON only with one of these shapes:

  {"action":"reply","reply":"visible user-facing text"}
  {"action":"tool_call","target":"<available-tool-id>","args":{}}
  {"action":"lemming_call","target":"<available-lemming-slug>","args":{"request":"bounded task text"}}
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

  defp validate_provider_response(
         provider_response,
         requested_model,
         config_snapshot,
         debug_overrides \\ %{}
       )

  defp validate_provider_response(
         provider_response,
         requested_model,
         config_snapshot,
         debug_overrides
       )
       when is_map(provider_response) do
    with {:ok, content} <- provider_content(provider_response, requested_model),
         {:ok, action_payload, diagnostics} <-
           parse_and_validate_provider_content(content, provider_response, config_snapshot) do
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
         raw: provider_raw_with_debug(provider_response, Map.merge(diagnostics, debug_overrides))
       )}
    else
      {:error, {kind, metadata}}
      when kind in [:provider_invalid_response] and is_map(metadata) ->
        {:error, {kind, metadata}}

      {:error, :unknown_action, diagnostics} ->
        {:error, unknown_action_error(provider_response, requested_model, diagnostics)}

      {:error, reason, diagnostics} ->
        {:error,
         invalid_structured_output_error(provider_response, requested_model, reason, diagnostics)}
    end
  end

  defp validate_provider_response(
         provider_response,
         requested_model,
         _config_snapshot,
         _debug_overrides
       ) do
    {:error,
     {:provider_invalid_response,
      %{
        provider: nil,
        model: requested_model,
        reason: "non_map_provider_response",
        raw: provider_response
      }}}
  end

  defp parse_and_validate_provider_content(content, provider_response, config_snapshot)
       when is_binary(content) do
    valid_actions = valid_actions(config_snapshot)
    valid_targets = valid_targets(config_snapshot)

    case extract_json_payload(content, provider_response) do
      {:ok, extracted_json, parse_source} ->
        parse_extracted_provider_json(
          content,
          extracted_json,
          parse_source,
          valid_actions,
          valid_targets
        )

      {:error, parse_error} ->
        diagnostics =
          diagnostics_for_parse_failure(
            content,
            %{
              parse_status: "error",
              parse_error: inspect(parse_error),
              extracted_json: nil,
              normalized_payload: nil,
              parse_source: nil
            },
            nil,
            %{valid_actions: valid_actions, valid_targets: valid_targets}
          )

        {:error, :invalid_structured_output, diagnostics}
    end
  end

  defp parse_extracted_provider_json(
         content,
         extracted_json,
         parse_source,
         valid_actions,
         valid_targets
       ) do
    case parse_structured_output(extracted_json) do
      {:ok, action_payload, normalized_payload} ->
        validate_parsed_action(
          content,
          extracted_json,
          normalized_payload,
          parse_source,
          action_payload,
          valid_actions,
          valid_targets
        )

      {:error, :missing_action, _payload, normalized_payload} ->
        diagnostics =
          parse_failure_diagnostics(
            content,
            extracted_json,
            normalized_payload,
            parse_source,
            "missing_action",
            valid_actions,
            valid_targets
          )

        {:error, :invalid_structured_output, diagnostics}

      {:error, :unknown_action, _payload, normalized_payload} ->
        diagnostics =
          parse_failure_diagnostics(
            content,
            extracted_json,
            normalized_payload,
            parse_source,
            "invalid_action",
            valid_actions,
            valid_targets
          )

        {:error, :unknown_action, diagnostics}

      {:error, parse_error} when parse_error in [:invalid_args, :missing_action] ->
        diagnostics =
          parse_failure_diagnostics(
            content,
            extracted_json,
            extracted_json,
            parse_source,
            Atom.to_string(parse_error),
            valid_actions,
            valid_targets
          )

        {:error, :invalid_structured_output, diagnostics}

      {:error, parse_error} ->
        diagnostics =
          diagnostics_for_parse_failure(
            content,
            %{
              parse_status: "error",
              parse_error: inspect(parse_error),
              extracted_json: extracted_json,
              normalized_payload: nil,
              parse_source: parse_source
            },
            nil,
            %{valid_actions: valid_actions, valid_targets: valid_targets}
          )

        {:error, :invalid_structured_output, diagnostics}
    end
  end

  defp validate_parsed_action(
         content,
         extracted_json,
         normalized_payload,
         parse_source,
         action_payload,
         valid_actions,
         valid_targets
       ) do
    case validate_action_payload(action_payload, valid_actions, valid_targets) do
      {:ok, validation_result} ->
        {:ok, action_payload,
         %{
           raw_model_output: content,
           parser_result:
             parser_result("ok", nil, extracted_json, normalized_payload, parse_source),
           validation_result: validation_result,
           retry_attempted: false
         }}

      {:error, validation_error} ->
        diagnostics =
          parse_failure_diagnostics(
            content,
            extracted_json,
            normalized_payload,
            parse_source,
            Atom.to_string(validation_error),
            valid_actions,
            valid_targets
          )

        {:error, :invalid_structured_output, diagnostics}
    end
  end

  defp parse_failure_diagnostics(
         content,
         extracted_json,
         normalized_payload,
         parse_source,
         validation_error,
         valid_actions,
         valid_targets
       ) do
    diagnostics_for_parse_failure(
      content,
      %{
        parse_status: "ok",
        parse_error: nil,
        extracted_json: extracted_json,
        normalized_payload: normalized_payload,
        parse_source: parse_source
      },
      validation_error,
      %{valid_actions: valid_actions, valid_targets: valid_targets}
    )
  end

  defp extract_json_payload(content, provider_response) when is_binary(content) do
    trimmed = String.trim(content)

    trimmed
    |> decode_direct_json()
    |> case do
      {:error, direct_error} -> fallback_json_payload(trimmed, provider_response, direct_error)
      result -> result
    end
  end

  defp decode_direct_json(content) do
    case Jason.decode(content) do
      {:ok, %{} = parsed} -> {:ok, parsed, "direct_json"}
      {:ok, _other} -> {:error, :json_root_not_object}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fallback_json_payload(content, provider_response, direct_error) do
    with {:error, _legacy_error} <-
           maybe_parse_legacy_structured_output(content, provider_response),
         {:error, _extract_error} <- extract_first_json_object(content) do
      {:error, direct_error}
    else
      {:ok, parsed, parse_source} -> {:ok, parsed, parse_source}
      {:ok, parsed} -> {:ok, parsed, "extracted_json"}
    end
  end

  defp maybe_parse_legacy_structured_output(content, provider_response) do
    if legacy_structured_output_enabled?(provider_response) do
      case parse_legacy_structured_output(content) do
        {:ok, parsed} -> {:ok, parsed, "legacy_text"}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :legacy_structured_output_disabled}
    end
  end

  defp legacy_structured_output_enabled?(provider_response) do
    case response_field(provider_response, :legacy_structured_output) do
      true -> true
      _other -> false
    end
  end

  defp parse_structured_output(%{"action" => "reply", "reply" => reply} = payload)
       when is_binary(reply) do
    if Helpers.blank?(reply) do
      {:error, :invalid_structured_output}
    else
      normalized_payload = Map.take(payload, ["action", "reply"])

      {:ok,
       %{
         action: :reply,
         reply: reply,
         tool_name: nil,
         tool_args: nil,
         lemming_target: nil,
         lemming_request: nil,
         continue_call_id: nil
       }, normalized_payload}
    end
  end

  defp parse_structured_output(%{"action" => "reply"}), do: {:error, :invalid_args}

  defp parse_structured_output(%{
         "action" => "tool_call",
         "target" => target,
         "args" => args
       })
       when is_binary(target) and is_map(args) do
    if Helpers.blank?(target) do
      {:error, :invalid_structured_output}
    else
      normalized_payload = %{"action" => "tool_call", "target" => target, "args" => args}

      {:ok,
       %{
         action: :tool_call,
         reply: nil,
         tool_name: target,
         tool_args: args,
         lemming_target: nil,
         lemming_request: nil,
         continue_call_id: nil
       }, normalized_payload}
    end
  end

  defp parse_structured_output(%{
         "action" => "tool_call",
         "tool_name" => tool_name,
         "args" => args
       })
       when is_binary(tool_name) and is_map(args) do
    parse_structured_output(%{"action" => "tool_call", "target" => tool_name, "args" => args})
  end

  defp parse_structured_output(%{"action" => "tool_call"}), do: {:error, :invalid_args}

  defp parse_structured_output(
         %{
           "action" => "lemming_call",
           "target" => target,
           "args" => args
         } = payload
       )
       when is_binary(target) and is_map(args) do
    request = Map.get(args, "request")

    if is_binary(request) do
      parse_structured_output(%{
        "action" => "lemming_call",
        "target" => target,
        "request" => request,
        "continue_call_id" => Map.get(payload, "continue_call_id")
      })
    else
      {:error, :invalid_args}
    end
  end

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
      {:error, :invalid_args}
    else
      normalized_payload =
        %{
          "action" => "lemming_call",
          "target" => target,
          "args" => %{"request" => request}
        }
        |> maybe_put_continue_call_id(continue_call_id)

      {:ok,
       %{
         action: :lemming_call,
         reply: nil,
         tool_name: nil,
         tool_args: nil,
         lemming_target: target,
         lemming_request: request,
         continue_call_id: continue_call_id
       }, normalized_payload}
    end
  end

  defp parse_structured_output(%{"action" => "lemming_call"}), do: {:error, :invalid_args}

  defp parse_structured_output(%{"action" => action} = payload) when is_binary(action),
    do: {:error, :unknown_action, payload, payload}

  defp parse_structured_output(%{} = payload), do: {:error, :missing_action, payload, payload}

  defp parse_structured_output(_other), do: {:error, :invalid_structured_output}

  defp validate_action_payload(action_payload, valid_actions, valid_targets) do
    action = Atom.to_string(action_payload.action)

    cond do
      action not in valid_actions ->
        {:error, :action_unavailable}

      action_payload.action == :tool_call and
          action_payload.tool_name not in Map.get(valid_targets, "tool_call", []) ->
        {:error, :invalid_tool_target}

      action_payload.action == :tool_call and invalid_tool_args?(action_payload) ->
        {:error, :invalid_args}

      action_payload.action == :lemming_call and
          action_payload.lemming_target not in Map.get(valid_targets, "lemming_call", []) ->
        {:error, :lemming_target_unavailable}

      true ->
        {:ok,
         %{
           validation_error: nil,
           valid_actions: valid_actions,
           valid_targets: valid_targets
         }}
    end
  end

  defp invalid_tool_args?(%{tool_name: "web.search", tool_args: args}) when is_map(args),
    do: not present_binary?(Map.get(args, "query"))

  defp invalid_tool_args?(%{tool_name: "web.fetch", tool_args: args}) when is_map(args),
    do: not present_binary?(Map.get(args, "url"))

  defp invalid_tool_args?(%{tool_name: "fs.read_text_file", tool_args: args}) when is_map(args),
    do: not present_binary?(Map.get(args, "path"))

  defp invalid_tool_args?(%{tool_name: "fs.write_text_file", tool_args: args}) when is_map(args),
    do: not (present_binary?(Map.get(args, "path")) and present_binary?(Map.get(args, "content")))

  defp invalid_tool_args?(_action_payload), do: false

  defp present_binary?(value), do: is_binary(value) and not Helpers.blank?(value)

  defp parser_result(parse_status, parse_error, extracted_json, normalized_payload, parse_source) do
    %{
      parse_status: parse_status,
      parse_error: parse_error,
      parse_source: parse_source,
      extracted_json: extracted_json,
      normalized_action: normalized_action(normalized_payload)
    }
  end

  defp diagnostics_for_parse_failure(raw_model_output, parse_info, validation_error, valid_info) do
    %{
      raw_model_output: raw_model_output,
      parser_result:
        parser_result(
          parse_info.parse_status,
          parse_info.parse_error,
          parse_info.extracted_json,
          parse_info.normalized_payload,
          parse_info.parse_source
        ),
      validation_result: %{
        validation_error: validation_error,
        validation_error_details:
          validation_error_details(validation_error, parse_info.normalized_payload, valid_info),
        valid_actions: valid_info.valid_actions,
        valid_targets: valid_info.valid_targets
      },
      retry_attempted: false
    }
  end

  defp validation_error_details(nil, _parsed_payload, _valid_info), do: nil

  defp validation_error_details(validation_error, parsed_payload, valid_info) do
    %{
      code: validation_error,
      message: validation_error_message(validation_error),
      parsed_payload: parsed_payload,
      expected_actions: valid_info.valid_actions,
      expected_targets: valid_info.valid_targets
    }
  end

  defp validation_error_message("missing_action"),
    do: "Model output must include an action field."

  defp validation_error_message("invalid_action"),
    do: "Model output action is not one of the expected actions."

  defp validation_error_message("action_unavailable"),
    do: "Model output action is not available in this runtime context."

  defp validation_error_message("invalid_tool_target"),
    do: "Model output tool target is not available in this runtime context."

  defp validation_error_message("invalid_args"),
    do: "Model output arguments do not match the selected action contract."

  defp validation_error_message("lemming_target_unavailable"),
    do: "Model output lemming target is not available in this runtime context."

  defp validation_error_message(validation_error),
    do: "Model output validation failed: #{validation_error}."

  defp normalized_action(%{"action" => action}) when is_binary(action), do: action
  defp normalized_action(_payload), do: nil

  defp maybe_put_continue_call_id(payload, nil), do: payload

  defp maybe_put_continue_call_id(payload, continue_call_id),
    do: Map.put(payload, "continue_call_id", continue_call_id)

  defp valid_actions(config_snapshot) do
    capabilities = build_capabilities(config_snapshot)

    ["reply"]
    |> maybe_append_valid_action("tool_call", capabilities.tools?)
    |> maybe_append_valid_action("lemming_call", capabilities.lemming_calls?)
  end

  defp maybe_append_valid_action(actions, action, true), do: actions ++ [action]
  defp maybe_append_valid_action(actions, _action, _enabled?), do: actions

  defp valid_targets(config_snapshot) do
    capabilities = build_capabilities(config_snapshot)

    %{
      "tool_call" => Enum.map(capabilities.tools, & &1.id),
      "lemming_call" => Enum.map(capabilities.lemming_call_targets, & &1.slug)
    }
  end

  defp provider_raw_with_debug(provider_response, diagnostics) do
    provider_response
    |> response_field(:raw)
    |> case do
      raw when is_map(raw) -> raw
      _other -> provider_response
    end
    |> Map.merge(diagnostics)
  end

  defp extract_first_json_object(content) when is_binary(content) do
    content
    |> :binary.matches("{")
    |> Enum.find_value(&first_json_object_from_start(content, &1))
    |> case do
      nil -> {:error, :json_object_not_found}
      result -> result
    end
  end

  defp first_json_object_from_start(content, {start, 1}) do
    content
    |> :binary.matches("}")
    |> Enum.filter(fn {finish, 1} -> finish > start end)
    |> Enum.find_value(fn {finish, 1} ->
      content
      |> binary_part(start, finish - start + 1)
      |> decode_json_object_candidate()
    end)
  end

  defp decode_json_object_candidate(candidate) do
    case Jason.decode(candidate) do
      {:ok, %{} = parsed} -> {:ok, parsed}
      _other -> nil
    end
  end

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
      {:ok, %{"action" => "tool_call", "target" => raw_tool_name, "args" => args}}
    else
      _other -> {:error, :invalid_structured_output}
    end
  end

  defp parse_legacy_lemming_call(content) do
    with <<"Assistant requested lemming_call with arguments: ", payload_json::binary>> <-
           content,
         {:ok, payload} <- Jason.decode(payload_json) do
      {:ok, Map.put(payload, "action", "lemming_call")}
    else
      _other -> {:error, :invalid_structured_output}
    end
  end

  defp nil_if_blank(nil), do: nil

  defp nil_if_blank(value) when is_binary(value),
    do: if(Helpers.blank?(value), do: nil, else: value)

  defp nil_if_blank(_value), do: :invalid_continue_call_id

  defp provider_content(provider_response, requested_model) do
    case response_field(provider_response, :content) do
      content when is_binary(content) ->
        {:ok, content}

      _ ->
        {:error,
         provider_invalid_response_error(provider_response, requested_model, :missing_content)}
    end
  end

  defp provider_invalid_response_error(provider_response, requested_model, reason) do
    {:provider_invalid_response,
     %{
       provider: provider_label(provider_response),
       model: response_field(provider_response, :model) || requested_model,
       reason: Atom.to_string(reason),
       content: response_field(provider_response, :content),
       raw_model_output: normalized_raw_model_output(provider_response),
       raw: response_field(provider_response, :raw) || provider_response
     }}
  end

  defp invalid_structured_output_error(provider_response, requested_model, reason, diagnostics) do
    {:invalid_structured_output,
     %{
       reason: inspect(reason),
       provider: provider_label(provider_response),
       model: response_field(provider_response, :model) || requested_model,
       content: response_field(provider_response, :content),
       raw: response_field(provider_response, :raw) || provider_response
     }
     |> Map.merge(diagnostics)
     |> put_validation_error_provider_context()}
  end

  defp unknown_action_error(provider_response, requested_model, diagnostics) do
    {:unknown_action,
     %{
       provider: provider_label(provider_response),
       model: response_field(provider_response, :model) || requested_model,
       content: response_field(provider_response, :content),
       raw: response_field(provider_response, :raw) || provider_response
     }
     |> Map.merge(diagnostics)
     |> put_validation_error_provider_context()}
  end

  defp normalized_raw_model_output(provider_response) do
    case response_field(provider_response, :content) do
      content when is_binary(content) ->
        content

      nil ->
        case response_field(provider_response, :raw) || provider_response do
          raw when is_map(raw) -> Jason.encode!(raw)
          raw -> inspect(raw)
        end

      content ->
        inspect(content)
    end
  end

  defp put_validation_error_provider_context(
         %{validation_result: %{} = validation_result} = metadata
       ) do
    provider_context = %{
      provider: Map.get(metadata, :provider),
      model: Map.get(metadata, :model)
    }

    validation_result =
      case Map.get(validation_result, :validation_error_details) do
        %{} = details ->
          Map.put(details, :provider, provider_context.provider)
          |> Map.put(:model, provider_context.model)

        details ->
          details
      end
      |> then(&Map.put(validation_result, :validation_error_details, &1))

    %{metadata | validation_result: validation_result}
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

  defp current_message_in_history?(history, %{request_id: request_id} = current_message)
       when is_binary(request_id) and request_id != "" do
    Enum.any?(history, &(&1.request_id == request_id)) ||
      current_message_matches_last_history?(history, current_message)
  end

  defp current_message_in_history?(history, current_message),
    do: current_message_matches_last_history?(history, current_message)

  defp current_message_matches_last_history?(history, current_message) do
    case List.last(history) do
      ^current_message ->
        true

      %{role: role, content: content} ->
        role == current_message.role and content == current_message.content

      _other ->
        false
    end
  end

  defp system_message(config_snapshot) do
    capabilities = build_capabilities(config_snapshot)

    [
      platform_runtime_context(),
      lemming_identity_message(config_snapshot),
      lemming_instructions_message(config_snapshot),
      available_tools_message(capabilities),
      available_lemming_calls_message(capabilities),
      retrieval_decision_policy_message(capabilities),
      manager_planning_rules_message(capabilities),
      loop_state_semantics_message(capabilities),
      @runtime_rules,
      immediate_response_instruction(),
      tool_response_rules_message(capabilities),
      knowledge_tool_rules_message(capabilities),
      lemming_call_rules_message(capabilities),
      important_output_contract(capabilities)
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
    - On each turn, choose exactly one next action listed in the output contract.
    - When a runtime action is returned, the app executes it and sends the result back in later assistant-context messages.
    - If the latest completed runtime result already satisfies the request, return a final reply instead of repeating the same successful action.
    """
  end

  defp lemming_identity_message(config_snapshot) do
    identity_lines =
      [
        lemming_identity_name(config_snapshot),
        lemming_identity_slug(config_snapshot),
        lemming_identity_department(config_snapshot),
        lemming_identity_role(config_snapshot),
        lemming_identity_description(config_snapshot)
      ]
      |> Enum.reject(&Helpers.blank?/1)

    case identity_lines do
      [] ->
        nil

      lines ->
        Enum.join(["Lemming Identity:" | lines], "\n")
    end
  end

  defp lemming_identity_name(config_snapshot) do
    case response_field(config_snapshot, :name) do
      name when is_binary(name) and name != "" -> "- Name: #{name}"
      _name -> nil
    end
  end

  defp lemming_identity_slug(config_snapshot) do
    case response_field(config_snapshot, :slug) do
      slug when is_binary(slug) and slug != "" -> "- Slug: #{slug}"
      _slug -> nil
    end
  end

  defp lemming_identity_department(config_snapshot) do
    department_name = response_field(config_snapshot, :department_name)
    department_slug = response_field(config_snapshot, :department_slug)

    cond do
      is_binary(department_name) and department_name != "" ->
        "- Department: #{department_name}"

      is_binary(department_slug) and department_slug != "" ->
        "- Department: #{department_slug}"

      true ->
        nil
    end
  end

  defp lemming_identity_role(config_snapshot) do
    case response_field(config_snapshot, :collaboration_role) do
      role when is_binary(role) and role != "" -> "- Effective role: #{role}"
      _role -> nil
    end
  end

  defp lemming_identity_description(config_snapshot) do
    case response_field(config_snapshot, :description) do
      description when is_binary(description) and description != "" ->
        "- Purpose/description: #{description}"

      _description ->
        nil
    end
  end

  defp lemming_instructions_message(config_snapshot) do
    case instructions_from_snapshot(config_snapshot) do
      instructions when is_binary(instructions) and instructions != "" ->
        "Lemming Instructions:\n#{instructions}"

      _instructions ->
        nil
    end
  end

  defp available_tools_message(%{tools: []}), do: nil

  defp available_tools_message(%{tools: tools}) do
    tool_lines =
      Enum.map_join(tools, "\n", fn tool ->
        description =
          [tool.description, tool_argument_contract(tool.id)]
          |> Enum.reject(&Helpers.blank?/1)
          |> Enum.join(" ")

        if Helpers.blank?(description) do
          "- #{tool.id}"
        else
          "- #{tool.id}: #{description}"
        end
      end)

    guidance_lines =
      ["Use exact argument keys from each contract."] ++ maybe_file_write_guidance(tools)

    ["Available Tools:", tool_lines | guidance_lines]
    |> Enum.join("\n")
  end

  defp maybe_file_write_guidance(tools) do
    if Enum.any?(tools, &(&1.id == "fs.write_text_file")) do
      ["For file creation or file updates, use fs.write_text_file."]
    else
      []
    end
  end

  defp retrieval_decision_policy_message(%{knowledge_search?: true, knowledge_read?: true}) do
    """
    Retrieval Decision Policy:
    - Knowledge has distinct categories: memories are stored notes, source files are indexed searchable documents, reference files are fixed operator-managed files, and artifacts are generated outputs outside Knowledge unless promoted by an operator.
    - For factual questions that depend on company memories, source files, or reference files (pricing, SKUs, policies, contracts, templates, headers, footers, style assets), do not guess.
    - Prefer `knowledge.search` first with a broad department-scoped query unless an exact source type, tag, or reference category is already known. Do not over-constrain the first search with guessed tags or source_file_type values.
    - To discover reusable fixed files, call `knowledge.search` with `kind: \"reference_file\"`; this returns safe descriptors such as `reference_ref`, `knowledge_item_id`, type, title, and tags.
    - If search returns chunk references, you must call `knowledge.read` on candidate chunks before declaring "not found".
    - If reference-file search returns candidate descriptors, call `knowledge.read` with `reference_ref` or `knowledge_item_id` when the task needs the file content; unsupported files return descriptor-only status instead of bytes.
    - For exact-value requests (price/SKU/contract term), do not finalize from snippets alone; verify with `knowledge.read`.
    - `knowledge.store` stores memories only. It cannot create, edit, archive, delete, or promote source files, reference files, or artifacts.
    - If retrieval returns no relevant evidence and the user explicitly allowed placeholders for missing values, continue using placeholders and report the missing values as assumptions. Otherwise reply with that limitation and ask for clarifying scope or file details.
    """
  end

  defp retrieval_decision_policy_message(%{knowledge_search?: true}) do
    """
    Retrieval Decision Policy:
    - Knowledge has distinct categories: memories are stored notes, source files are indexed searchable documents, reference files are fixed operator-managed files, and artifacts are generated outputs outside Knowledge unless promoted by an operator.
    - For factual questions that depend on company memories, source files, or reference files (pricing, SKUs, policies, contracts, templates, headers, footers, style assets), do not guess.
    - Prefer `knowledge.search` first with a broad department-scoped query unless an exact source type, tag, or reference category is already known. Do not over-constrain the first search with guessed tags or source_file_type values.
    - Use `kind: \"reference_file\"` to discover reusable fixed files by safe descriptors; no mutation tools are available for reference files.
    - If retrieval returns no relevant evidence and the user explicitly allowed placeholders for missing values, continue using placeholders and report the missing values as assumptions. Otherwise reply with that limitation and ask for clarifying scope or file details.
    """
  end

  defp retrieval_decision_policy_message(_capabilities), do: nil

  defp tool_argument_contract("fs.read_text_file") do
    "required `path` (WorkArea-relative string)."
  end

  defp tool_argument_contract("fs.write_text_file") do
    "required `path` (WorkArea-relative string), required `content` (UTF-8 string)."
  end

  defp tool_argument_contract("web.search") do
    "required `query` (string)."
  end

  defp tool_argument_contract("web.fetch") do
    "required `url` (http/https URL string)."
  end

  defp tool_argument_contract("knowledge.search") do
    "`kind` defaults to `source_file`. For source files: required `query`; optional `source_file_type`, `tags`, `scope` (`world|city|department|lemming` or scoped id map), `top_k` (positive integer, max 20). For reference files: use `kind: \"reference_file\"`; optional `query`/`q`, `reference_file_type`/`type`, `category`, `tags`, `status`, `owner_scope`, `scope`, `limit` (max 20), `offset`; returns descriptors only."
  end

  defp tool_argument_contract("knowledge.read") do
    "For source files: required `chunk_ref`. For reference files: required `reference_ref` or `knowledge_item_id` with optional `kind: \"reference_file\"`. Optional `scope` (`world|city|department|lemming` or scoped id map) and `max_chars` (positive integer, max 8000). Returns bounded text or descriptor-only status; never raw bytes or storage refs."
  end

  defp tool_argument_contract("knowledge.store") do
    "required `title` and `content`; optional `tags`; optional `scope` (`world|city|department|lemming` or scoped id map). Memory-only tool: does not accept source-file, reference-file, artifact, path, or mutation fields."
  end

  defp tool_argument_contract("documents.markdown_to_html") do
    "required `source_path` (WorkArea-relative `.md`); compatibility alias: `markdown_path` when `source_path` is omitted; optional `output_path` (defaults to same path with `.html`); optional `overwrite` (boolean, default `true`)."
  end

  defp tool_argument_contract("documents.print_to_pdf") do
    "required `source_path` (WorkArea-relative supported source); optional `output_path` (defaults to same path with `.pdf`); optional `overwrite` (default `true`); optional `print_raw_file` (default `false`); optional `header_path`/`footer_path`; optional `style_paths` (list of `.css`); optional `paper_size`, `landscape`, `margin_top`, `margin_bottom`, `margin_left`, `margin_right`."
  end

  defp tool_argument_contract("email.create_draft") do
    "required `connection_ref` (`gmail`), `to` (recipient email string, comma-separated string, or list), `subject`, and `body`; optional `cc`/`bcc` (list, string, comma-separated string, nil, or blank; default []); optional `body_format` (`text/plain` default, or `text/html`); optional `artifact_ids` (list, default []). Creates a Gmail draft only; never sends email."
  end

  defp tool_argument_contract(_tool_id), do: nil

  defp available_lemming_calls_message(%{lemming_call_targets: []}), do: nil

  defp available_lemming_calls_message(%{lemming_call_targets: targets}) do
    target_lines =
      Enum.map_join(targets, "\n", fn target ->
        "- #{target.slug}: #{target_description(target)}"
      end)

    [
      "Available Lemming Calls:",
      target_lines
    ]
    |> Enum.join("\n")
  end

  defp target_description(target) do
    case [target.description, target.capability] |> Enum.reject(&Helpers.blank?/1) do
      [description | _rest] -> description
      [] -> "No capability description provided."
    end
  end

  defp manager_planning_rules_message(%{manager?: true}) do
    """
    Manager Planning Rules:
    - For every non-trivial user request, first form a short operational plan before choosing the next action.
    - First decide whether the user input is sufficient.
    - If critical information is missing, ask a concise clarification question.
    - If input is sufficient, decompose the request into bounded specialist tasks.
    - Execute one next action at a time.
    - Prefer delegation over direct execution when Available Lemming Calls exist.
    - Track remaining work using prior tool and lemming-call results.
    - Do not produce a final answer until required delegated work is complete, failed, or explicitly unavailable.
    - Do not output the plan unless the user explicitly asks for it.
    """
  end

  defp manager_planning_rules_message(_capabilities), do: nil

  defp loop_state_semantics_message(capabilities) do
    lines =
      [
        "Loop State Semantics:",
        "- Prior assistant execution-context messages may appear in history.",
        "- Treat assistant-context execution messages as prior runtime history, not as new user requests.",
        "- Use the configured identity, the original user request, and the latest runtime result to decide the next action."
      ] ++
        tool_loop_lines(capabilities) ++
        lemming_loop_lines(capabilities) ++
        [
          "- Do not invent file paths, output files, or artifacts unless runtime payload explicitly mentions them."
        ]

    Enum.join(lines, "\n")
  end

  defp tool_loop_lines(%{tools?: true}) do
    [
      "- `Assistant requested tool <tool_name> with arguments: <json>` means you already chose that tool on a prior turn.",
      "- `Tool result for <tool_name>: status=<status> payload=<json>` means the runtime executed your prior tool request and is returning the outcome to you now."
    ]
  end

  defp tool_loop_lines(_capabilities), do: []

  defp lemming_loop_lines(%{lemming_calls?: true}) do
    [
      "- `Assistant requested lemming_call with arguments: <json>` means you already delegated that bounded task on a prior turn.",
      "- `Lemming call result: status=<status> payload=<json>` means the runtime is returning delegated outcome to you now.",
      "- When a completed child payload includes `result_summary`, treat it as usable delegated result history.",
      "- When a completed child result already satisfies the task, prefer replying or making the next bounded delegation."
    ]
  end

  defp lemming_loop_lines(_capabilities), do: []

  defp immediate_response_instruction do
    """
    Immediate Response Instruction:
    - Read the conversation messages below and decide the next action now.
    - Return exactly one valid JSON object.
    - Do not explain your reasoning.
    - Do not add text before or after the JSON object.
    - Do not invent files, PDFs, drafts, artifacts, tool results, or delegated results.
    """
  end

  defp tool_response_rules_message(%{tools?: true}) do
    """
    Tool Response Rules:
    - If the latest tool result already satisfies the user request, return a final reply.
    - If another available tool action is required, return one tool_call.
    - Only call tools listed in Available Tools.
    """
  end

  defp tool_response_rules_message(_capabilities), do: nil

  defp knowledge_tool_rules_message(%{knowledge_search?: true, knowledge_read?: true}) do
    """
    Knowledge Tool Rules:
    - If the latest knowledge.search result includes chunk references and the task asks for an exact factual value, call knowledge.read before any "not found" conclusion.
    - If the latest knowledge.search result includes reference-file descriptors and the task needs file content, call knowledge.read with a returned reference_ref or knowledge_item_id.
    """
  end

  defp knowledge_tool_rules_message(_capabilities), do: nil

  defp lemming_call_rules_message(%{lemming_calls?: true}) do
    """
    Lemming Call Rules:
    - If delegation is needed, call one lemming listed in Available Lemming Calls.
    - If the latest completed lemming call result already satisfies the user request, return a final reply or make one next bounded lemming_call.
    - Do not invent target slugs.
    - Keep each delegated request specific and bounded.
    """
  end

  defp lemming_call_rules_message(_capabilities), do: nil

  defp important_output_contract(capabilities) do
    action_blocks =
      [
        {"Final reply", ~s({"action":"reply","reply":"visible user-facing text"})}
      ]
      |> maybe_append_tool_action(capabilities)
      |> maybe_append_lemming_action(capabilities)
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {{label, example}, index} ->
        "#{index}. #{label}:\n#{example}"
      end)

    rules =
      []
      |> maybe_append_tool_action_rules(capabilities)
      |> maybe_append_lemming_action_rules(capabilities)
      |> Enum.join("\n\n")

    [
      "Return exactly one JSON object.",
      "Available actions:",
      action_blocks,
      rules
    ]
    |> Enum.reject(&Helpers.blank?/1)
    |> Enum.join("\n\n")
  end

  defp maybe_append_tool_action(actions, %{tools?: true}) do
    actions ++
      [{"Tool call", ~s({"action":"tool_call","target":"<available-tool-id>","args":{}})}]
  end

  defp maybe_append_tool_action(actions, _capabilities), do: actions

  defp maybe_append_lemming_action(actions, %{lemming_calls?: true}) do
    actions ++
      [
        {"Lemming call",
         ~s({"action":"lemming_call","target":"<available-lemming-slug>","args":{"request":"bounded task text"}})}
      ]
  end

  defp maybe_append_lemming_action(actions, _capabilities), do: actions

  defp maybe_append_tool_action_rules(rules, %{tools?: true}) do
    rules ++
      [
        """
        For tool_call:
        - target must be one of the IDs listed in Available Tools.
        - args must match the selected tool contract.
        - do not invent tool IDs.
        """
      ]
  end

  defp maybe_append_tool_action_rules(rules, _capabilities), do: rules

  defp maybe_append_lemming_action_rules(rules, %{lemming_calls?: true}) do
    rules ++
      [
        """
        For lemming_call:
        - target must be one of the slugs listed in Available Lemming Calls.
        - request must be specific and bounded.
        - do not invent target slugs.
        """
      ]
  end

  defp maybe_append_lemming_action_rules(rules, _capabilities), do: rules

  defp build_capabilities(config_snapshot) do
    tools = available_tools(config_snapshot)
    tool_ids = Enum.map(tools, & &1.id)
    lemming_targets = lemming_call_targets(config_snapshot)

    %{
      tools: tools,
      tools?: tools != [],
      lemming_call_targets: lemming_targets,
      lemming_calls?: lemming_targets != [],
      manager?: manager_role?(config_snapshot),
      knowledge_search?: "knowledge.search" in tool_ids,
      knowledge_read?: "knowledge.read" in tool_ids
    }
  end

  defp manager_role?(config_snapshot) do
    response_field(config_snapshot, :collaboration_role) == "manager"
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
    case response_field(target, :slug) do
      slug when is_binary(slug) and slug != "" ->
        capability = response_field(target, :capability) || ""
        role = response_field(target, :role) || ""

        [
          %{
            slug: slug,
            capability: capability,
            role: role,
            department_slug: response_field(target, :department_slug) || "same-department",
            description: response_field(target, :description) || ""
          }
        ]

      _other ->
        []
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
         {:ok, response} <-
           validate_or_repair_provider_response(
             provider_mod,
             request,
             provider_response,
             candidate.model,
             config_snapshot
           ) do
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

  defp validate_or_repair_provider_response(
         provider_mod,
         request,
         provider_response,
         model,
         config_snapshot
       ) do
    case validate_provider_response(provider_response, model, config_snapshot) do
      {:ok, response} ->
        {:ok, response}

      {:error, {kind, metadata} = reason}
      when kind in [:invalid_structured_output, :unknown_action] and is_map(metadata) ->
        repair_provider_response(
          provider_mod,
          request,
          provider_response,
          model,
          config_snapshot,
          reason
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp repair_provider_response(
         provider_mod,
         request,
         _provider_response,
         model,
         config_snapshot,
         {kind, metadata}
       ) do
    repair_request = build_repair_request(request, kind, metadata)

    case provider_mod.chat(repair_request, provider_opts(config_snapshot)) do
      {:ok, retry_provider_response} ->
        retry_debug = %{
          retry_attempted: true,
          invalid_output:
            Map.get(metadata, :raw_model_output) || Map.get(metadata, "raw_model_output"),
          retry_output: response_field(retry_provider_response, :content),
          retry_request: repair_request
        }

        case validate_provider_response(
               retry_provider_response,
               model,
               config_snapshot,
               retry_debug
             ) do
          {:ok, response} ->
            {:ok, response}

          {:error, {retry_kind, retry_metadata}} when is_map(retry_metadata) ->
            {:error,
             {retry_kind,
              retry_metadata
              |> Map.put(:retry_attempted, true)
              |> Map.put(:retry_output, response_field(retry_provider_response, :content))
              |> Map.put(:retry_request, repair_request)
              |> Map.put(:final_parse_error, final_parse_error(retry_metadata))}}
        end

      {:error, retry_reason} ->
        {:error,
         {kind,
          metadata
          |> Map.put(:retry_attempted, true)
          |> Map.put(:retry_error, inspect(retry_reason))
          |> Map.put(:retry_request, repair_request)
          |> Map.put(:final_parse_error, inspect(retry_reason))}}

      _other ->
        {:error,
         {kind,
          metadata
          |> Map.put(:retry_attempted, true)
          |> Map.put(:retry_error, "unexpected_repair_result")
          |> Map.put(:retry_request, repair_request)
          |> Map.put(:final_parse_error, "unexpected_repair_result")}}
    end
  end

  defp build_repair_request(request, kind, metadata) do
    repair_prompt = """
    Correction required: your previous model output could not be used.
    Error: #{Atom.to_string(kind)} #{metadata_error_summary(metadata)}
    Invalid output:
    #{Map.get(metadata, :raw_model_output) || Map.get(metadata, "raw_model_output") || Map.get(metadata, :content) || Map.get(metadata, "content")}

    Return exactly one valid JSON object. Do not include prose or markdown.
    Valid actions: #{inspect(metadata_valid_actions(metadata))}
    Valid targets: #{inspect(metadata_valid_targets(metadata))}
    Valid JSON shapes:
    {"action":"reply","reply":"visible user-facing text"}
    {"action":"tool_call","target":"<available-tool-id>","args":{}}
    {"action":"lemming_call","target":"<available-lemming-slug>","args":{"request":"bounded task text"}}
    """

    messages =
      request
      |> Map.get(:messages, [])
      |> Kernel.++([%{role: "user", content: repair_prompt}])

    %{request | messages: messages}
  end

  defp metadata_error_summary(metadata) do
    validation_error = get_in(metadata, [:validation_result, :validation_error])
    parse_error = get_in(metadata, [:parser_result, :parse_error])

    [validation_error, parse_error]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp metadata_valid_actions(metadata),
    do: get_in(metadata, [:validation_result, :valid_actions]) || []

  defp metadata_valid_targets(metadata),
    do: get_in(metadata, [:validation_result, :valid_targets]) || %{}

  defp final_parse_error(metadata) do
    get_in(metadata, [:validation_result, :validation_error]) ||
      get_in(metadata, [:parser_result, :parse_error]) ||
      Map.get(metadata, :reason) ||
      Map.get(metadata, "reason")
  end

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
