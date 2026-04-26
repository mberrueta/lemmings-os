defmodule LemmingsOs.LemmingInstances.Executor.FinalizationPayloadTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.FinalizationPayload

  test "tool_result_payload/1 for ok status includes artifacts and details" do
    tool_execution = %{
      status: "ok",
      summary: "Wrote file sample.md",
      preview: String.duplicate("a", 200),
      result: %{
        "path" => "sample.md",
        "workspace_path" => "/workspace/test/sample.md",
        "root_path" => "/workspace/test",
        "bytes" => 80
      }
    }

    payload = FinalizationPayload.tool_result_payload(tool_execution)

    assert payload.ok == true
    assert payload.action_taken == "Wrote file sample.md"
    assert payload.artifacts_created == ["sample.md"]
    assert payload.remaining_work == []
    assert payload.preview == String.duplicate("a", 160)
    assert "Workspace path: /workspace/test/sample.md" in payload.important_details
    assert "Root path: /workspace/test" in payload.important_details
    assert "Bytes written: 80" in payload.important_details
  end

  test "tool_result_payload/1 redacts obvious secret-like text in tool strings" do
    tool_execution = %{
      status: "ok",
      summary: "Saved Authorization: Bearer abc123",
      preview: "https://x.test?token=abc123",
      result: %{
        "path" => "sample.md",
        "workspace_path" => "/workspace/test/sample.md",
        "root_path" => "/workspace/test",
        "bytes" => 80
      }
    }

    payload = FinalizationPayload.tool_result_payload(tool_execution)

    assert payload.action_taken == "Saved Authorization: Bearer [REDACTED]"
    assert payload.preview == "https://x.test?token=[REDACTED]"
    assert Enum.any?(payload.important_details, &String.contains?(&1, "[REDACTED]"))
    refute Enum.any?(payload.important_details, &String.contains?(&1, "abc123"))
  end

  test "tool_result_payload/1 for error status keeps guidance and error payload" do
    tool_execution = %{
      status: "error",
      summary: "Web fetch failed",
      error: %{"code" => "tool.web.request_failed"}
    }

    payload = FinalizationPayload.tool_result_payload(tool_execution)

    assert payload.ok == false
    assert payload.action_taken == "Web fetch failed"
    assert payload.artifacts_created == []
    assert payload.important_details == []
    assert payload.remaining_work == ["Review tool error and decide the next step."]
    assert payload.error == %{"code" => "tool.web.request_failed"}
  end

  test "build_finalization_context/3 normalizes context fields" do
    tool_execution = %{
      tool_name: "fs.write_text_file",
      status: "ok",
      summary: "Created sample.md"
    }

    tool_payload = %{
      artifacts_created: ["sample.md"],
      important_details: ["Bytes written: 80"],
      remaining_work: []
    }

    context =
      FinalizationPayload.build_finalization_context(
        "Create sample.md for my boss",
        tool_execution,
        tool_payload
      )

    assert context.tool_name == "fs.write_text_file"
    assert context.tool_status == "ok"
    assert context.original_goal == "Create sample.md for my boss"
    assert context.completed_action == "Created sample.md"
    assert context.artifacts_created == ["sample.md"]
    assert context.important_details == ["Bytes written: 80"]
  end

  test "build_post_tool_success_prompt/2 includes repair section when repair reason exists" do
    prompt =
      FinalizationPayload.build_post_tool_success_prompt(
        %{
          original_goal: "Create sample.md for my boss",
          completed_action: "Created sample.md",
          artifacts_created: ["sample.md"],
          important_details: [],
          remaining_work: [],
          repair_reason: "empty_final_response"
        },
        "fallback goal"
      )

    assert String.contains?(prompt, "Finalization Phase:")
    assert String.contains?(prompt, "Original user goal:")
    assert String.contains?(prompt, "Create sample.md for my boss")
    assert String.contains?(prompt, "Repair Notice:")
    assert String.contains?(prompt, "empty_final_response")
  end
end
