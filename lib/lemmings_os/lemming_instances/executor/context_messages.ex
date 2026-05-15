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
          "Only claim files, PDFs, HTML, or Gmail drafts as created when they appear in payload.deliverables.",
          "Treat payload.missing_deliverables as failed or missing deliverables.",
          "Treat payload.warnings as unverified child claims and do not present them as created deliverables.",
          "Do not guess file paths or read artifacts unless this payload explicitly includes a work-area-relative path or artifact reference.",
          "Decide what to do next."
        ]
        |> Enum.join(" ")
    }
  end

  @doc """
  Builds the structured payload embedded in delegated call-result context.
  """
  @spec lemming_call_result_payload(map()) :: map()
  def lemming_call_result_payload(call) do
    %{}
    |> maybe_put(:call_id, Map.get(call, :id))
    |> maybe_put(:caller_instance_id, Map.get(call, :caller_instance_id))
    |> maybe_put(:status, Map.get(call, :status))
    |> maybe_put(:callee_instance_id, Map.get(call, :callee_instance_id))
    |> maybe_put(:child_instance_id, Map.get(call, :callee_instance_id))
    |> maybe_put(:callee_lemming_id, Map.get(call, :callee_lemming_id))
    |> maybe_put(:callee_slug, nested_call_value(call, [:callee_lemming, :slug]))
    |> maybe_put(:callee_name, nested_call_value(call, [:callee_lemming, :name]))
    |> maybe_put(:root_call_id, Map.get(call, :root_call_id))
    |> maybe_put(:previous_call_id, Map.get(call, :previous_call_id))
    |> maybe_put(:request_text, Map.get(call, :request_text))
    |> maybe_put(:result_summary, Map.get(call, :result_summary))
    |> maybe_put(:error_summary, Map.get(call, :error_summary))
    |> maybe_put(:deliverables, call_value(call, :deliverables))
    |> maybe_put(:missing_deliverables, call_value(call, :missing_deliverables))
    |> maybe_put(:assumptions, call_value(call, :assumptions))
    |> maybe_put(:warnings, call_value(call, :warnings))
    |> maybe_put(:failure_details, call_value(call, :failure_details))
    |> maybe_put(:recovery_status, Map.get(call, :recovery_status))
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
        "As response to your previous tool request, the runtime executed #{tool_name}. Tool result for #{tool_name}: status=#{status} payload=#{Redaction.encode_redacted(tool_payload)}. #{tool_result_guidance(tool_name, tool_payload)}"
    }
  end

  defp tool_result_guidance("knowledge.search", tool_payload) when is_map(tool_payload) do
    tool_payload
    |> knowledge_search_context()
    |> knowledge_search_guidance()
  end

  defp tool_result_guidance(_tool_name, _tool_payload), do: "Decide what to do next."

  defp knowledge_search_context(tool_payload) do
    result = field(tool_payload, :result, %{})
    references = field(tool_payload, :references, %{})

    %{
      kind: field(result, :kind),
      chunks: field(references, :chunks, []),
      result: result,
      references: references,
      remaining_work: field(tool_payload, :remaining_work, [])
    }
  end

  defp field(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  defp knowledge_search_guidance(%{
         kind: kind,
         chunks: chunks,
         result: result,
         references: references,
         remaining_work: remaining_work
       }) do
    cond do
      is_list(chunks) and chunks != [] ->
        "Search returned chunk references. For exact factual answers, call knowledge.read with a returned chunk_ref before concluding not found. Decide what to do next."

      placeholder_continuation?(remaining_work) ->
        "Search returned no matching knowledge. The original request allows placeholders, so continue the quote workflow with those placeholders and list missing prices as assumptions."

      zero_results?(result) or zero_results?(references) ->
        "Search returned no matching knowledge. If the original user request explicitly allowed placeholders for missing prices, continue the quote workflow with those placeholders and list missing prices as assumptions. Otherwise ask for clarification or report missing knowledge."

      kind == "reference_file" and has_results?(result) ->
        "Search returned reference-file descriptors. If file content is needed, call knowledge.read with a returned reference_ref or knowledge_item_id. Decide what to do next."

      true ->
        "Decide what to do next."
    end
  end

  defp placeholder_continuation?(remaining_work) when is_list(remaining_work) do
    Enum.any?(remaining_work, fn
      value when is_binary(value) -> String.contains?(value, "$ XXX.XX")
      _value -> false
    end)
  end

  defp placeholder_continuation?(_remaining_work), do: false

  defp zero_results?(result) when is_map(result) do
    case Map.get(result, :count) || Map.get(result, "count") do
      0 -> true
      _count -> false
    end
  end

  defp has_results?(result) when is_map(result) do
    results = Map.get(result, :results) || Map.get(result, "results") || []
    is_list(results) and results != []
  end

  defp maybe_put(payload, _field, nil), do: payload
  defp maybe_put(payload, field, value), do: Map.put(payload, field, value)

  defp nested_call_value(map, [key]) when is_map(map) do
    case Map.get(map, key) do
      %Ecto.Association.NotLoaded{} -> nil
      value -> value
    end
  end

  defp nested_call_value(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      %Ecto.Association.NotLoaded{} -> nil
      nested when is_map(nested) -> nested_call_value(nested, rest)
      _other -> nil
    end
  end

  defp nested_call_value(_value, _path), do: nil

  defp call_value(call, field) when is_map(call) and is_atom(field) do
    Map.get(call, field) || Map.get(call, Atom.to_string(field))
  end

  defp lemming_call_result_guidance(%{status: "completed", result_summary: result_summary})
       when is_binary(result_summary) and result_summary != "" do
    "When status=completed, payload.result_summary is child usable result; payload.deliverables is the evidence for created files and drafts."
  end

  defp lemming_call_result_guidance(_payload) do
    "Treat this assistant-context message as prior runtime execution history, not as new user input."
  end
end
