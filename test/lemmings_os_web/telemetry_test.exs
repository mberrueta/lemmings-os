defmodule LemmingsOsWeb.TelemetryTest do
  use ExUnit.Case, async: true

  test "metrics/0 includes tool execution lifecycle metrics" do
    metric_names =
      LemmingsOsWeb.Telemetry.metrics()
      |> Enum.map(& &1.name)

    assert [:lemmings_os, :runtime, :tool_execution, :started, :count] in metric_names
    assert [:lemmings_os, :runtime, :tool_execution, :completed, :count] in metric_names
    assert [:lemmings_os, :runtime, :tool_execution, :failed, :count] in metric_names
    assert [:lemmings_os, :runtime, :tool_execution, :completed, :duration_ms] in metric_names
    assert [:lemmings_os, :runtime, :tool_execution, :failed, :duration_ms] in metric_names
  end
end
