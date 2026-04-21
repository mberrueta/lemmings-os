defmodule LemmingsOsWeb.TelemetryTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingInstances

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

  test "emit_runtime_snapshot/0 emits aggregate runtime instance measurements" do
    ref = attach([:lemmings_os, :runtime, :instances])

    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    {:ok, created_instance} = LemmingInstances.spawn_instance(lemming, "created")
    {:ok, idle_instance} = LemmingInstances.spawn_instance(lemming, "idle")
    {:ok, failed_instance} = LemmingInstances.spawn_instance(lemming, "failed")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _updated_idle_instance} =
             LemmingInstances.update_status(idle_instance, "idle", %{last_activity_at: now})

    assert {:ok, _updated_failed_instance} =
             LemmingInstances.update_status(failed_instance, "failed", %{stopped_at: now})

    LemmingsOsWeb.Telemetry.emit_runtime_snapshot()

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :instances], measurements,
                    metadata}

    assert metadata.source == :poller
    assert measurements.total >= 3
    assert measurements.created >= 1
    assert measurements.idle >= 1
    assert measurements.failed >= 1
    assert is_binary(created_instance.id)

    detach(ref)
  end

  defp attach(event) do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "web-telemetry-test-#{inspect(ref)}",
        event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    ref
  end

  defp detach(ref) do
    :telemetry.detach("web-telemetry-test-#{inspect(ref)}")
  end
end
