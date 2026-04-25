defmodule LemmingsOs.LemmingInstances.Executor.FinalizationPayload do
  @moduledoc """
  Pure helpers for tool-result and finalization prompt shaping.
  """

  alias LemmingsOs.Helpers

  @doc """
  Builds the tool-result payload embedded in assistant context.
  """
  @spec tool_result_payload(map()) :: map()
  def tool_result_payload(%{status: "ok"} = tool_execution) do
    result = tool_execution.result || %{}

    %{
      ok: true,
      action_taken: tool_execution.summary,
      artifacts_created: tool_result_artifacts(result),
      important_details: tool_result_details(result, tool_execution),
      remaining_work: [],
      preview: truncate_tool_preview(tool_execution.preview)
    }
  end

  def tool_result_payload(%{status: "error"} = tool_execution) do
    %{
      ok: false,
      action_taken: tool_execution.summary,
      artifacts_created: [],
      important_details: [],
      remaining_work: ["Review tool error and decide the next step."],
      error: tool_execution.error
    }
  end

  def tool_result_payload(tool_execution) do
    result = tool_execution.result || %{}

    %{
      ok: tool_execution.status == "ok",
      action_taken: tool_execution.summary,
      artifacts_created: tool_result_artifacts(result),
      important_details: tool_result_details(result, tool_execution),
      remaining_work: [],
      preview: truncate_tool_preview(tool_execution.preview),
      error: tool_execution.error
    }
  end

  @doc """
  Builds the normalized finalization context persisted in executor state.
  """
  @spec build_finalization_context(binary(), map(), map()) :: map()
  def build_finalization_context(original_goal, tool_execution, tool_payload) do
    %{
      tool_name: tool_execution.tool_name,
      tool_status: tool_execution.status,
      tool_result_payload: tool_payload,
      original_goal: original_goal,
      completed_action: tool_execution.summary,
      artifacts_created: Map.get(tool_payload, :artifacts_created, []),
      important_details: Map.get(tool_payload, :important_details, []),
      remaining_work: Map.get(tool_payload, :remaining_work, [])
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
          "- Repair reason: #{repair_reason}",
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
      original_goal,
      "",
      "Last completed action:",
      completed_action,
      "",
      "Artifacts created:",
      bullet_list_or_none(artifacts_created),
      "",
      "Important details:",
      bullet_list_or_none(important_details),
      "",
      "Remaining work:",
      bullet_list_or_none(remaining_work),
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
  defp bullet_list_or_none(values), do: Enum.map_join(values, "\n", &"- #{&1}")

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
      tool_execution.preview
    ]
    |> Enum.filter(&present_detail?/1)
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

  defp present_detail?(value) when is_binary(value), do: value != ""
  defp present_detail?(_value), do: false

  defp truncate_tool_preview(preview) when is_binary(preview) do
    String.slice(preview, 0, 160)
  end

  defp truncate_tool_preview(_preview), do: nil
end
