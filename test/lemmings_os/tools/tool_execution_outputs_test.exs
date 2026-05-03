defmodule LemmingsOs.Tools.ToolExecutionOutputsTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Tools.ToolExecutionOutputs
  doctest LemmingsOs.Tools.ToolExecutionOutputs

  test "extracts output_path for documents tools" do
    tool_execution = %{
      tool_name: "documents.markdown_to_html",
      result: %{"output_path" => "notes/triage.html"}
    }

    assert ToolExecutionOutputs.workspace_output_candidate(tool_execution) == %{
             relative_path: "notes/triage.html",
             filename: "triage.html"
           }
  end

  test "extracts legacy path for fs.write_text_file" do
    tool_execution = %{
      tool_name: "fs.write_text_file",
      result: %{"path" => "notes/triage.md"}
    }

    assert ToolExecutionOutputs.workspace_output_relative_path(tool_execution) ==
             "notes/triage.md"
  end

  test "does not treat fs.read_text_file path as output artifact candidate" do
    tool_execution = %{
      tool_name: "fs.read_text_file",
      result: %{"path" => "notes/input.md"}
    }

    assert ToolExecutionOutputs.workspace_output_candidate(tool_execution) == nil
  end

  test "rejects invalid relative paths" do
    tool_execution = %{
      tool_name: "documents.print_to_pdf",
      result: %{"output_path" => "../outside.pdf"}
    }

    assert ToolExecutionOutputs.workspace_output_candidate(tool_execution) == nil
  end
end
