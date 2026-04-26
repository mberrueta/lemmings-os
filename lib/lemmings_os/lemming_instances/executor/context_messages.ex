defmodule LemmingsOs.LemmingInstances.Executor.ContextMessages do
  @moduledoc """
  Pure helpers for assistant-context message construction in executor loops.
  """

  alias LemmingsOs.LemmingInstances.Executor.Redaction

  @doc """
  Builds the assistant context message recording a model-selected tool call.
  """
  @spec tool_call_message(binary(), map()) :: map()
  def tool_call_message(tool_name, tool_args) when is_binary(tool_name) and is_map(tool_args) do
    %{
      role: "assistant",
      content:
        "Assistant requested tool #{tool_name} with arguments: #{Redaction.encode_redacted(tool_args)}"
    }
  end

  @doc """
  Builds the assistant context message recording a model-selected lemming call.
  """
  @spec lemming_call_message(map()) :: map()
  def lemming_call_message(attrs) when is_map(attrs) do
    %{
      role: "assistant",
      content:
        "Assistant requested lemming_call with arguments: #{Redaction.encode_redacted(attrs)}"
    }
  end

  @doc """
  Builds the assistant context message that feeds delegated call outcomes back
  into the model loop.
  """
  @spec lemming_call_result_message(map()) :: map()
  def lemming_call_result_message(call) when is_map(call) do
    payload = lemming_call_result_payload(call)

    %{
      role: "assistant",
      content:
        [
          "As runtime execution history for your previous lemming_call request,",
          "the runtime is returning delegated outcome now.",
          "Lemming call result: status=#{Map.get(call, :status)} payload=#{Redaction.encode_redacted(payload)}.",
          lemming_call_result_guidance(payload),
          "Do not guess file paths or read artifacts unless this payload explicitly includes a path or artifact reference.",
          "Decide what to do next."
        ]
        |> Enum.join(" ")
    }
  end

  @doc """
  Builds the assistant context message that feeds tool outcomes into the model
  loop.
  """
  @spec tool_result_message(map(), map()) :: map()
  def tool_result_message(tool_execution, tool_payload)
      when is_map(tool_execution) and is_map(tool_payload) do
    tool_name = Map.get(tool_execution, :tool_name)
    status = Map.get(tool_execution, :status)

    %{
      role: "assistant",
      content:
        "As response to your previous tool request, the runtime executed #{tool_name}. Tool result for #{tool_name}: status=#{status} payload=#{Redaction.encode_redacted(tool_payload)}. Decide what to do next."
    }
  end

  defp lemming_call_result_payload(call) do
    %{}
    |> maybe_put(:call_id, Map.get(call, :id))
    |> maybe_put(:status, Map.get(call, :status))
    |> maybe_put(:callee_instance_id, Map.get(call, :callee_instance_id))
    |> maybe_put(:root_call_id, Map.get(call, :root_call_id))
    |> maybe_put(:previous_call_id, Map.get(call, :previous_call_id))
    |> maybe_put(:result_summary, Map.get(call, :result_summary))
    |> maybe_put(:error_summary, Map.get(call, :error_summary))
    |> maybe_put(:recovery_status, Map.get(call, :recovery_status))
  end

  defp maybe_put(payload, _field, nil), do: payload
  defp maybe_put(payload, field, value), do: Map.put(payload, field, value)

  defp lemming_call_result_guidance(%{status: "completed", result_summary: result_summary})
       when is_binary(result_summary) and result_summary != "" do
    "When status=completed, payload.result_summary is child usable result."
  end

  defp lemming_call_result_guidance(_payload) do
    "Treat this assistant-context message as prior runtime execution history, not as new user input."
  end
end
