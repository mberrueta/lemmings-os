defmodule LemmingsOs.LemmingInstances.Executor.ModelStepPayload do
  @moduledoc """
  Pure payload and sanitization helpers for executor model-step traces.
  """

  alias LemmingsOs.LemmingInstances.Executor.Redaction
  alias LemmingsOs.ModelRuntime.Response

  @redacted "[REDACTED]"
  @max_debug_string_length 16_000
  @sensitive_key_patterns [
    "api_key",
    "apikey",
    "password",
    "passwd",
    "passphrase",
    "token",
    "secret",
    "authorization",
    "auth"
  ]

  @doc """
  Builds normalized model-step result attributes from one model execution result.
  """
  @spec model_step_result_attrs(term(), DateTime.t(), integer()) :: map()
  def model_step_result_attrs({:ok, %Response{} = response}, completed_at, duration_ms) do
    %{
      status: "ok",
      response_payload: sanitize_json_map(response.raw),
      parsed_output: sanitize_json_map(parsed_output(response)),
      provider: response.provider,
      model: response.model,
      input_tokens: response.input_tokens,
      output_tokens: response.output_tokens,
      total_tokens: response.total_tokens,
      usage: sanitize_json_map(response.usage),
      completed_at: completed_at,
      duration_ms: max(duration_ms, 0)
    }
  end

  def model_step_result_attrs({:error, reason}, completed_at, duration_ms) do
    error_payload = model_step_error_payload(reason)

    %{
      status: "error",
      response_payload: model_step_error_response_payload(error_payload),
      parsed_output: model_step_error_parsed_output(error_payload),
      provider: Map.get(error_payload, "provider"),
      model: Map.get(error_payload, "model"),
      error: error_payload,
      completed_at: completed_at,
      duration_ms: max(duration_ms, 0)
    }
  end

  def model_step_result_attrs(_result, completed_at, duration_ms) do
    %{
      status: "error",
      error: %{"reason" => "unexpected_model_result"},
      completed_at: completed_at,
      duration_ms: max(duration_ms, 0)
    }
  end

  @doc """
  Sanitizes arbitrary terms into JSON-safe maps/lists/scalars for trace storage.
  """
  @spec sanitize_json_map(term()) :: term()
  def sanitize_json_map(nil), do: nil
  def sanitize_json_map(value), do: sanitize_json_term(value)

  defp parsed_output(%Response{action: :reply} = response) do
    %{"action" => "reply", "reply" => response.reply}
  end

  defp parsed_output(%Response{action: :tool_call} = response) do
    %{
      "action" => "tool_call",
      "target" => response.tool_name,
      "args" => sanitize_json_map(response.tool_args)
    }
  end

  defp parsed_output(%Response{action: :lemming_call} = response) do
    %{
      "action" => "lemming_call",
      "target" => response.lemming_target,
      "args" => %{"request" => response.lemming_request}
    }
  end

  defp sanitize_json_term(nil), do: nil

  defp sanitize_json_term(value) when is_binary(value),
    do: sanitize_debug_string(value)

  defp sanitize_json_term(value) when is_boolean(value) or is_number(value),
    do: value

  defp sanitize_json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp sanitize_json_term(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp sanitize_json_term(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp sanitize_json_term(%Date{} = value), do: Date.to_iso8601(value)
  defp sanitize_json_term(%Time{} = value), do: Time.to_iso8601(value)

  defp sanitize_json_term(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> sanitize_json_term()
  end

  defp sanitize_json_term(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      if sensitive_key?(key) do
        {to_string(key), @redacted}
      else
        {to_string(key), sanitize_json_term(nested_value)}
      end
    end)
  end

  defp sanitize_json_term(value) when is_list(value) do
    Enum.map(value, &sanitize_json_term/1)
  end

  defp sanitize_json_term(value) when is_tuple(value) do
    %{"tuple" => value |> Tuple.to_list() |> Enum.map(&sanitize_json_term/1)}
  end

  defp sanitize_json_term(value), do: inspect(value)

  defp sanitize_debug_string(value) do
    value
    |> Redaction.redact_string()
    |> redact_local_paths()
    |> truncate_debug_string()
  end

  defp redact_local_paths(value) do
    value
    |> String.replace("[HOST_PATH_REDACTED]", "<local-path>")
    |> then(fn value ->
      Regex.replace(
        ~r/(?<![\w.-])\/(?:home|Users|mnt|tmp|var|private|opt|data\d*)\/[^\s"'`<>{}\]]+\.dets\b/,
        value,
        "<runtime-dets-path>"
      )
    end)
    |> then(fn redacted ->
      Regex.replace(
        ~r/(?<![\w.-])\/(?:home|Users|mnt|tmp|var|private|opt|data\d*)\/[^\s"'`<>{}\]]+/,
        redacted,
        "<local-path>"
      )
    end)
  end

  defp truncate_debug_string(value) do
    if String.length(value) > @max_debug_string_length do
      String.slice(value, 0, @max_debug_string_length) <>
        "\n[TRUNCATED #{String.length(value) - @max_debug_string_length} characters]"
    else
      value
    end
  end

  defp sensitive_key?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(&Enum.any?(@sensitive_key_patterns, fn pattern -> String.contains?(&1, pattern) end))
  end

  defp model_step_error_payload({kind, metadata})
       when kind in [:invalid_structured_output, :unknown_action] and is_map(metadata) do
    metadata
    |> sanitize_json_map()
    |> Map.put("kind", Atom.to_string(kind))
    |> Map.put_new("reason", Atom.to_string(kind))
  end

  defp model_step_error_payload({kind, metadata}) when is_atom(kind) and is_map(metadata) do
    metadata
    |> sanitize_json_map()
    |> Map.put("kind", Atom.to_string(kind))
    |> Map.put_new("reason", Atom.to_string(kind))
  end

  defp model_step_error_payload(reason) do
    %{"reason" => inspect(reason)}
  end

  defp model_step_error_response_payload(%{"raw" => raw}) when is_map(raw), do: raw
  defp model_step_error_response_payload(_error_payload), do: nil

  defp model_step_error_parsed_output(%{"content" => content}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, parsed} -> sanitize_json_map(parsed)
      {:error, _reason} -> nil
    end
  end

  defp model_step_error_parsed_output(_error_payload), do: nil
end
