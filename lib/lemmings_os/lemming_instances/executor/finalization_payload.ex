defmodule LemmingsOs.LemmingInstances.Executor.FinalizationPayload do
  @moduledoc """
  Pure helpers for tool-result and finalization prompt shaping.
  """

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.Executor.Redaction

  @doc """
  Builds the tool-result payload embedded in assistant context.
  """
  @spec tool_result_payload(map()) :: map()
  def tool_result_payload(%{status: "ok"} = tool_execution) do
    result = tool_execution.result || %{}

    %{
      ok: true,
      action_taken: redact_text(tool_execution.summary),
      artifacts_created: tool_result_artifacts(result),
      important_details: tool_result_details(result, tool_execution),
      references: tool_result_references(tool_execution, result),
      remaining_work: tool_remaining_work(tool_execution, result),
      preview: redact_text(tool_result_preview(tool_execution))
    }
  end

  def tool_result_payload(%{status: "error"} = tool_execution) do
    %{
      ok: false,
      action_taken: redact_text(tool_execution.summary),
      artifacts_created: [],
      important_details: [],
      references: %{},
      remaining_work: ["Review tool error and decide the next step."],
      error: Redaction.redact(tool_execution.error)
    }
  end

  def tool_result_payload(tool_execution) do
    result = tool_execution.result || %{}

    %{
      ok: tool_execution.status == "ok",
      action_taken: redact_text(tool_execution.summary),
      artifacts_created: tool_result_artifacts(result),
      important_details: tool_result_details(result, tool_execution),
      references: tool_result_references(tool_execution, result),
      remaining_work: tool_remaining_work(tool_execution, result),
      preview: redact_text(tool_result_preview(tool_execution)),
      error: Redaction.redact(tool_execution.error)
    }
  end

  @doc """
  Adds goal-specific continuation guidance to a tool payload.
  """
  @spec apply_goal_context(map(), map(), binary()) :: map()
  def apply_goal_context(
        tool_payload,
        %{tool_name: "knowledge.search"} = tool_execution,
        original_goal
      )
      when is_map(tool_payload) and is_binary(original_goal) do
    if zero_result_knowledge_search?(tool_execution) and placeholders_allowed?(original_goal) do
      Map.update(
        tool_payload,
        :remaining_work,
        placeholder_remaining_work(),
        &Enum.uniq(&1 ++ placeholder_remaining_work())
      )
    else
      tool_payload
    end
  end

  def apply_goal_context(tool_payload, _tool_execution, _original_goal), do: tool_payload

  @doc """
  Builds the normalized finalization context persisted in executor state.
  """
  @spec build_finalization_context(binary(), map(), map()) :: map()
  def build_finalization_context(original_goal, tool_execution, tool_payload) do
    %{
      tool_name: tool_execution.tool_name,
      tool_status: tool_execution.status,
      tool_result_payload: tool_payload,
      original_goal: redact_text(original_goal),
      completed_action: redact_text(tool_execution.summary),
      artifacts_created: redact_list(Map.get(tool_payload, :artifacts_created, [])),
      important_details: redact_list(Map.get(tool_payload, :important_details, [])),
      remaining_work: redact_list(Map.get(tool_payload, :remaining_work, []))
    }
  end

  @doc """
  Builds the post-tool finalization prompt sent in finalization phase.
  """
  @spec build_post_tool_success_prompt(map(), binary()) :: binary()
  def build_post_tool_success_prompt(finalization_context, fallback_goal) do
    finalization_context = finalization_context || %{}
    original_goal = Map.get(finalization_context, :original_goal) || fallback_goal
    completed_action = Map.get(finalization_context, :completed_action) || "Tool completed"
    artifacts_created = Map.get(finalization_context, :artifacts_created, [])
    important_details = Map.get(finalization_context, :important_details, [])
    remaining_work = Map.get(finalization_context, :remaining_work, [])
    repair_reason = Map.get(finalization_context, :repair_reason)

    repair_section =
      if is_binary(repair_reason) do
        [
          "Repair Notice:",
          "- Your previous post-tool response was empty, invalid, or not usable.",
          "- Repair reason: #{redact_text(repair_reason)}",
          "- Return a concise final user-facing answer now."
        ]
      else
        []
      end

    [
      "Finalization Phase:",
      "- The last tool execution completed successfully.",
      "- You must now produce the final user-facing response.",
      "- The response must not be empty.",
      "",
      "Original user goal:",
      redact_text(original_goal),
      "",
      "Last completed action:",
      redact_text(completed_action),
      "",
      "Artifacts created:",
      bullet_list_or_none(redact_list(artifacts_created)),
      "",
      "Important details:",
      bullet_list_or_none(redact_list(important_details)),
      "",
      "Remaining work:",
      bullet_list_or_none(redact_list(remaining_work)),
      "",
      "Response rule:",
      "- If the task is complete, summarize what was done and mention the created artifacts.",
      "- If more work is needed, explain the next step clearly for the user.",
      "- Do not request another tool call in this phase.",
      "- Return action=reply with a useful final answer for the user.",
      "",
      repair_section
    ]
    |> List.flatten()
    |> Enum.reject(&Helpers.blank?/1)
    |> Enum.join("\n")
  end

  defp bullet_list_or_none([]), do: "- none"
  defp bullet_list_or_none(values), do: Enum.map_join(values, "\n", &"- #{redact_text(&1)}")

  defp tool_result_path(%{"path" => path}) when is_binary(path), do: path
  defp tool_result_path(%{path: path}) when is_binary(path), do: path
  defp tool_result_path(_result), do: nil

  defp tool_result_artifacts(result) do
    case tool_result_path(result) do
      path when is_binary(path) -> [path]
      _path -> []
    end
  end

  defp tool_result_details(result, tool_execution) do
    [
      tool_result_workspace_path(result),
      tool_result_root_path(result),
      tool_result_bytes_detail(result),
      Map.get(tool_execution, :preview)
    ]
    |> Enum.filter(&present_detail?/1)
    |> Enum.map(&redact_text/1)
    |> Enum.take(4)
  end

  defp tool_result_workspace_path(%{"workspace_path" => workspace_path})
       when is_binary(workspace_path),
       do: "Workspace path: #{workspace_path}"

  defp tool_result_workspace_path(%{workspace_path: workspace_path})
       when is_binary(workspace_path),
       do: "Workspace path: #{workspace_path}"

  defp tool_result_workspace_path(_result), do: nil

  defp tool_result_root_path(%{"root_path" => root_path}) when is_binary(root_path),
    do: "Root path: #{root_path}"

  defp tool_result_root_path(%{root_path: root_path}) when is_binary(root_path),
    do: "Root path: #{root_path}"

  defp tool_result_root_path(_result), do: nil

  defp tool_result_bytes_detail(%{"bytes" => bytes}) when is_integer(bytes),
    do: "Bytes written: #{bytes}"

  defp tool_result_bytes_detail(%{bytes: bytes}) when is_integer(bytes),
    do: "Bytes written: #{bytes}"

  defp tool_result_bytes_detail(_result), do: nil

  defp tool_result_references(%{tool_name: "knowledge.search"}, result) do
    case knowledge_search_result_payload(result) do
      payload when is_map(payload) ->
        kind = map_value(payload, :kind)
        results = map_value(payload, :results)
        count = map_value(payload, :count)

        knowledge_search_references(kind, results, count)

      _other ->
        %{}
    end
  end

  defp tool_result_references(_tool_execution, _result), do: %{}

  defp tool_remaining_work(%{tool_name: "knowledge.search"}, result) do
    case knowledge_search_result_payload(result) do
      payload when is_map(payload) ->
        kind = map_value(payload, :kind)
        results = map_value(payload, :results)

        knowledge_search_remaining_work(kind, results)

      _other ->
        []
    end
  end

  defp tool_remaining_work(_tool_execution, _result), do: []

  defp tool_result_preview(%{tool_name: "knowledge.search"}), do: nil

  defp tool_result_preview(tool_execution) do
    truncate_tool_preview(tool_execution.preview)
  end

  defp knowledge_search_result_payload(result) when is_map(result),
    do: map_value(result, :result)

  defp knowledge_search_result_payload(_result), do: nil

  defp knowledge_search_references("source_file", results, count) when is_list(results) do
    %{
      kind: "source_file",
      count: count || length(results),
      chunks:
        results
        |> Enum.take(5)
        |> Enum.map(&knowledge_search_chunk_reference/1)
        |> Enum.reject(&(&1 == %{}))
    }
  end

  defp knowledge_search_references("reference_file", results, count) when is_list(results) do
    %{
      kind: "reference_file",
      count: count || length(results),
      reference_files:
        results
        |> Enum.take(5)
        |> Enum.map(&knowledge_search_reference_file_reference/1)
        |> Enum.reject(&(&1 == %{}))
    }
  end

  defp knowledge_search_references(_kind, _results, _count), do: %{}

  defp knowledge_search_remaining_work("source_file", results)
       when is_list(results) and results != [] do
    [
      "Use knowledge.read with returned chunk_ref values before concluding exact factual answers."
    ]
  end

  defp knowledge_search_remaining_work("reference_file", results)
       when is_list(results) and results != [] do
    [
      "Use knowledge.read with returned reference_ref or knowledge_item_id values when file content is needed."
    ]
  end

  defp knowledge_search_remaining_work(_kind, _results), do: []

  defp zero_result_knowledge_search?(%{result: result}) when is_map(result) do
    case knowledge_search_result_payload(result) do
      payload when is_map(payload) ->
        (map_value(payload, :count) || 0) == 0

      _payload ->
        false
    end
  end

  defp zero_result_knowledge_search?(_tool_execution), do: false

  defp placeholders_allowed?(text) when is_binary(text) do
    normalized = String.downcase(text)

    String.contains?(normalized, "placeholder") or
      String.contains?(normalized, "$ xxx.xx") or
      String.contains?(normalized, "xxx.xx")
  end

  defp placeholder_remaining_work do
    [
      "No price knowledge was found, but the user explicitly allowed placeholders. Continue the quote workflow using `$ XXX.XX` for unavailable prices, and report those prices as assumptions/missing information."
    ]
  end

  defp knowledge_search_chunk_reference(row) when is_map(row) do
    %{}
    |> maybe_put(:chunk_ref, map_value(row, :chunk_ref))
    |> maybe_put(:title, map_value(row, :title))
    |> maybe_put(:source_file_type, map_value(row, :source_file_type))
    |> maybe_put(:snippet, row |> map_value(:snippet) |> truncate_tool_preview() |> redact_text())
  end

  defp knowledge_search_chunk_reference(_row), do: %{}

  defp knowledge_search_reference_file_reference(row) when is_map(row) do
    %{}
    |> maybe_put(:reference_ref, map_value(row, :reference_ref))
    |> maybe_put(:knowledge_item_id, map_value(row, :knowledge_item_id))
    |> maybe_put(:title, map_value(row, :title) |> redact_text())
    |> maybe_put(:reference_file_type, map_value(row, :reference_file_type))
  end

  defp knowledge_search_reference_file_reference(_row), do: %{}

  defp present_detail?(value) when is_binary(value), do: value != ""
  defp present_detail?(_value), do: false

  defp redact_list(values) when is_list(values), do: Enum.map(values, &redact_text/1)
  defp redact_list(value), do: redact_text(value)

  defp redact_text(value) when is_binary(value), do: Redaction.redact_string(value)
  defp redact_text(value), do: value

  defp truncate_tool_preview(preview) when is_binary(preview) do
    String.slice(preview, 0, 160)
  end

  defp truncate_tool_preview(_preview), do: nil

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
