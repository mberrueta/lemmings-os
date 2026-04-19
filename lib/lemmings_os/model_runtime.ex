defmodule LemmingsOs.ModelRuntime do
  @moduledoc """
  Runtime boundary for model execution.
  """

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.ModelRuntime.Providers.Ollama
  alias LemmingsOs.ModelRuntime.Response

  @structured_output_contract """
  Return JSON only with this shape:

  {"action":"reply","reply":"visible user-facing text"}
  or
  {"action":"tool_call","tool_name":"fs.read_text_file","args":{"path":"notes.txt"}}

  Only "reply" and "tool_call" actions are supported in this MVP.
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
    with {:ok, provider_mod} <- resolve_provider_module(config_snapshot),
         {:ok, model} <- resolve_model(config_snapshot),
         {:ok, request} <- build_request(config_snapshot, history, current_request, model),
         {:ok, provider_response} <- provider_mod.chat(request, provider_opts(config_snapshot)) do
      validate_provider_response(provider_response, model)
    end
  end

  def run(_config_snapshot, _history, _current_request), do: {:error, :invalid_request}

  @doc false
  @spec structured_output_contract() :: String.t()
  def structured_output_contract, do: @structured_output_contract

  @doc false
  @spec runtime_rules() :: String.t()
  def runtime_rules, do: @runtime_rules

  defp validate_provider_response(provider_response, requested_model)
       when is_map(provider_response) do
    with {:ok, content} <- provider_content(provider_response),
         {:ok, parsed} <- Jason.decode(content),
         {:ok, action_payload} <- parse_structured_output(parsed) do
      {:ok,
       Response.new(
         action: action_payload.action,
         reply: action_payload.reply,
         tool_name: action_payload.tool_name,
         tool_args: action_payload.tool_args,
         provider: provider_label(provider_response),
         model: response_field(provider_response, :model) || requested_model,
         input_tokens: response_field(provider_response, :input_tokens),
         output_tokens: response_field(provider_response, :output_tokens),
         total_tokens: response_field(provider_response, :total_tokens),
         usage: response_field(provider_response, :usage),
         raw: response_field(provider_response, :raw) || provider_response
       )}
    else
      {:error, :unknown_action} -> {:error, :unknown_action}
      {:error, _reason} -> {:error, :invalid_structured_output}
    end
  end

  defp validate_provider_response(_provider_response, _requested_model) do
    {:error, :provider_error}
  end

  defp parse_structured_output(%{"action" => "reply", "reply" => reply}) when is_binary(reply) do
    if Helpers.blank?(reply) do
      {:error, :invalid_structured_output}
    else
      {:ok, %{action: :reply, reply: reply, tool_name: nil, tool_args: nil}}
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
      {:ok, %{action: :tool_call, reply: nil, tool_name: tool_name, tool_args: args}}
    end
  end

  defp parse_structured_output(%{"action" => "tool_call"}),
    do: {:error, :invalid_structured_output}

  defp parse_structured_output(%{"action" => action}) when is_binary(action),
    do: {:error, :unknown_action}

  defp parse_structured_output(_other), do: {:error, :invalid_structured_output}

  defp provider_content(provider_response) do
    case response_field(provider_response, :content) do
      content when is_binary(content) ->
        if Helpers.blank?(content), do: {:error, :provider_error}, else: {:ok, content}

      _ ->
        {:error, :provider_error}
    end
  end

  defp build_request(config_snapshot, history, current_request, model) do
    with {:ok, current_message} <- normalize_current_message(current_request) do
      messages =
        config_snapshot
        |> build_messages(history, current_message)

      {:ok, %{model: model, messages: messages, format: "json"}}
    end
  end

  defp build_messages(config_snapshot, history, current_message) do
    system_message = %{role: "system", content: system_message(config_snapshot)}
    normalized_history = normalize_history(history)

    messages =
      case List.last(normalized_history) do
        ^current_message -> normalized_history
        _ -> normalized_history ++ [current_message]
      end

    [system_message | messages]
  end

  defp system_message(config_snapshot) do
    [
      instructions_from_snapshot(config_snapshot),
      @structured_output_contract,
      @runtime_rules
    ]
    |> Enum.reject(&Helpers.blank?/1)
    |> Enum.join("\n\n")
  end

  defp normalize_history(history) do
    history
    |> Enum.flat_map(fn
      %{role: role, content: content} when is_binary(content) ->
        maybe_message(role, content)

      %{"role" => role, "content" => content} when is_binary(content) ->
        maybe_message(role, content)

      _ ->
        []
    end)
  end

  defp maybe_message("system", _content), do: []
  defp maybe_message(:system, _content), do: []

  defp maybe_message(role, content) when role in ["user", "assistant", :user, :assistant] do
    [%{role: normalize_role(role), content: content}]
  end

  defp maybe_message(_role, _content), do: []

  defp normalize_role(role) when role in [:user, "user"], do: "user"
  defp normalize_role(role) when role in [:assistant, "assistant"], do: "assistant"

  defp normalize_current_message(%{content: nil}), do: {:error, :invalid_request}
  defp normalize_current_message(%{content: ""}), do: {:error, :invalid_request}

  defp normalize_current_message(%{content: content}) when is_binary(content),
    do: {:ok, %{role: "user", content: content}}

  defp normalize_current_message(%{"content" => nil}), do: {:error, :invalid_request}
  defp normalize_current_message(%{"content" => ""}), do: {:error, :invalid_request}

  defp normalize_current_message(%{"content" => content}) when is_binary(content),
    do: {:ok, %{role: "user", content: content}}

  defp normalize_current_message(nil), do: {:error, :invalid_request}
  defp normalize_current_message(""), do: {:error, :invalid_request}

  defp normalize_current_message(content) when is_binary(content),
    do: {:ok, %{role: "user", content: content}}

  defp normalize_current_message(_other), do: {:error, :invalid_request}

  defp instructions_from_snapshot(config_snapshot) do
    response_field(config_snapshot, :instructions) ||
      response_field(config_snapshot, :instructions_text) ||
      ""
  end

  defp resolve_provider_module(config_snapshot) do
    provider_module_for(provider_hint(config_snapshot))
  end

  defp provider_hint(config_snapshot) do
    response_field(config_snapshot, :provider_module) ||
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

  defp nested_field(map, [key | rest]) when is_map(map) do
    case response_field(map, key) do
      nil -> nil
      next -> nested_field(next, rest)
    end
  end

  defp nested_field(value, []), do: value
  defp nested_field(_value, _rest), do: nil
end
