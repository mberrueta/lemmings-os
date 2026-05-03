defmodule LemmingsOs.Tools.ToolExecutionOutputs do
  @moduledoc """
  Helpers for deriving workspace file-output paths from persisted tool executions.
  """

  @type candidate :: %{relative_path: String.t(), filename: String.t()}

  @doc """
  Returns a normalized workspace file-output candidate for a tool execution.

  The function extracts a safe relative path from persisted tool args/result
  and returns `%{relative_path, filename}`. It returns `nil` when no safe
  output path can be derived.

  ## Examples

      iex> LemmingsOs.Tools.ToolExecutionOutputs.workspace_output_candidate(%{
      ...>   tool_name: "documents.markdown_to_html",
      ...>   result: %{"output_path" => "notes/triage.html"}
      ...> })
      %{relative_path: "notes/triage.html", filename: "triage.html"}

      iex> LemmingsOs.Tools.ToolExecutionOutputs.workspace_output_candidate(%{
      ...>   tool_name: "documents.print_to_pdf",
      ...>   result: %{"output_path" => "../outside.pdf"}
      ...> })
      nil
  """
  @spec workspace_output_candidate(map()) :: candidate() | nil
  def workspace_output_candidate(tool_execution) when is_map(tool_execution) do
    case workspace_output_relative_path(tool_execution) do
      path when is_binary(path) ->
        %{relative_path: path, filename: Path.basename(path)}

      _other ->
        nil
    end
  end

  @doc """
  Returns only the safe relative workspace output path for a tool execution.

  Resolution priority:

  1. `result.output_path`
  2. `args.output_path`
  3. Legacy `fs.write_text_file` fallback (`result.path`, then `args.path`)

  ## Examples

      iex> LemmingsOs.Tools.ToolExecutionOutputs.workspace_output_relative_path(%{
      ...>   tool_name: "documents.print_to_pdf",
      ...>   result: %{"output_path" => "triage/sample.pdf"}
      ...> })
      "triage/sample.pdf"

      iex> LemmingsOs.Tools.ToolExecutionOutputs.workspace_output_relative_path(%{
      ...>   tool_name: "fs.write_text_file",
      ...>   result: %{"path" => "notes/out.md"}
      ...> })
      "notes/out.md"

      iex> LemmingsOs.Tools.ToolExecutionOutputs.workspace_output_relative_path(%{
      ...>   tool_name: "fs.read_text_file",
      ...>   result: %{"path" => "notes/in.md"}
      ...> })
      nil
  """
  @spec workspace_output_relative_path(map()) :: String.t() | nil
  def workspace_output_relative_path(tool_execution) when is_map(tool_execution) do
    tool_execution
    |> output_path_candidates()
    |> Enum.find(&safe_relative_path?/1)
  end

  defp output_path_candidates(tool_execution) do
    result = map_value(tool_execution, :result)
    args = map_value(tool_execution, :args)
    tool_name = map_value(tool_execution, :tool_name)

    [
      map_value(result, :output_path),
      map_value(args, :output_path)
    ] ++ maybe_legacy_path_candidates(tool_name, result, args)
  end

  defp maybe_legacy_path_candidates("fs.write_text_file", result, args) do
    [
      map_value(result, :path),
      map_value(args, :path)
    ]
  end

  defp maybe_legacy_path_candidates(_tool_name, _result, _args), do: []

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil

  defp safe_relative_path?(path) when is_binary(path) do
    path_segments = String.split(path, "/", trim: true)

    path != "" and Path.type(path) == :relative and path_segments != [] and
      Enum.all?(path_segments, &(&1 not in [".", ".."]))
  end

  defp safe_relative_path?(_path), do: false
end
