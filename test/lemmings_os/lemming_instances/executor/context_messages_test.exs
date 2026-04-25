defmodule LemmingsOs.LemmingInstances.Executor.ContextMessagesTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.ContextMessages

  test "tool_call_message/2 encodes tool name and args" do
    message = ContextMessages.tool_call_message("web.fetch", %{"url" => "https://example.com"})

    assert message.role == "assistant"
    assert String.contains?(message.content, "Assistant requested tool web.fetch")
    assert String.contains?(message.content, "\"url\":\"https://example.com\"")
  end

  test "lemming_call_result_message/1 includes safe guidance and payload fields" do
    message =
      ContextMessages.lemming_call_result_message(%{
        id: "call-1",
        status: "completed",
        result_summary: "Draft child notes complete."
      })

    assert message.role == "assistant"
    assert String.contains?(message.content, "Lemming call result: status=completed")
    assert String.contains?(message.content, "\"call_id\":\"call-1\"")
    assert String.contains?(message.content, "\"result_summary\":\"Draft child notes complete.\"")
    assert String.contains?(message.content, "payload.result_summary is child usable result")
    assert String.contains?(message.content, "Do not guess file paths or read artifacts")
  end

  test "tool_result_message/2 includes tool execution status and payload" do
    message =
      ContextMessages.tool_result_message(
        %{tool_name: "fs.write_text_file", status: "ok"},
        %{ok: true, artifacts_created: ["sample.md"]}
      )

    assert message.role == "assistant"
    assert String.contains?(message.content, "runtime executed fs.write_text_file")
    assert String.contains?(message.content, "status=ok")
    assert String.contains?(message.content, "\"artifacts_created\":[\"sample.md\"]")
  end
end
