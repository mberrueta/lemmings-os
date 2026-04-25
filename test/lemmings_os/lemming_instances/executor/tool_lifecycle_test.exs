defmodule LemmingsOs.LemmingInstances.Executor.ToolLifecycleTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.ToolLifecycle

  test "normalize_tool_error/1 keeps explicit code/message/details" do
    normalized =
      ToolLifecycle.normalize_tool_error(%{
        code: "tool.web.request_failed",
        message: "Web fetch request failed",
        details: %{reason: "dns"}
      })

    assert normalized.code == "tool.web.request_failed"
    assert normalized.message == "Web fetch request failed"
    assert normalized.details == %{reason: "dns"}
  end

  test "normalize_tool_error/1 falls back to generic error payload" do
    normalized = ToolLifecycle.normalize_tool_error(:unexpected)

    assert normalized.code == "tool.runtime.error"
    assert normalized.message == "Tool execution failed"
    assert normalized.details[:reason] == ":unexpected"
  end

  test "emit_tool_telemetry/3 emits expected metadata for failed phase" do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "tool-lifecycle-test-#{inspect(ref)}",
        [:lemmings_os, :runtime, :tool_execution, :failed],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    state = %{
      instance_id: "instance-1",
      instance: %{
        id: "instance-1",
        world_id: "world-1",
        city_id: "city-1",
        department_id: "dept-1",
        lemming_id: "lemming-1"
      }
    }

    tool_execution = %{
      id: "tool-1",
      tool_name: "web.fetch",
      status: "error",
      duration_ms: 12,
      error: %{code: "tool.web.request_failed"}
    }

    assert :ok = ToolLifecycle.emit_tool_telemetry(state, :failed, tool_execution)

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :failed],
                    %{count: 1, duration_ms: 12}, metadata}

    assert metadata.instance_id == "instance-1"
    assert metadata.tool_execution_id == "tool-1"
    assert metadata.tool_name == "web.fetch"
    assert metadata.reason == "tool.web.request_failed"

    :telemetry.detach("tool-lifecycle-test-#{inspect(ref)}")
  end
end
