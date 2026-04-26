defmodule LemmingsOs.LemmingInstances.Executor.RetryRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.RetryRuntime

  doctest RetryRuntime

  test "handle_model_retry/3 schedules retry when below max retries" do
    deps = %{
      release_resource: &Map.put(&1, :released?, true),
      cleanup_snapshot: &Map.put(&1, :snapshot_cleaned?, true),
      transition_to: fn state, status, _attrs -> Map.put(state, :status, status) end,
      put_runtime_state: &Map.put(&1, :persisted?, true),
      schedule_retry: &Map.put(&1, :retry_scheduled?, true)
    }

    state = %{retry_count: 0, max_retries: 3, now_fun: fn -> ~U[2026-04-26 20:10:00Z] end}
    updated = RetryRuntime.handle_model_retry(state, :provider_error, deps)

    assert updated.status == "retrying"
    assert updated.retry_count == 1
    assert updated.retry_scheduled? == true
    assert updated.persisted? == true
    refute Map.get(updated, :released?, false)
  end

  test "handle_model_retry/3 fails terminally when max retries reached" do
    deps = %{
      release_resource: &Map.put(&1, :released?, true),
      cleanup_snapshot: &Map.put(&1, :snapshot_cleaned?, true),
      transition_to: fn state, status, attrs ->
        state
        |> Map.put(:status, status)
        |> Map.put(:stopped_at, attrs.stopped_at)
      end,
      put_runtime_state: &Map.put(&1, :persisted?, true),
      schedule_retry: &Map.put(&1, :retry_scheduled?, true)
    }

    state = %{retry_count: 1, max_retries: 2, now_fun: fn -> ~U[2026-04-26 20:11:00Z] end}
    updated = RetryRuntime.handle_model_retry(state, :provider_error, deps)

    assert updated.status == "failed"
    assert updated.retry_count == 2
    assert updated.released? == true
    assert updated.snapshot_cleaned? == true
    assert updated.persisted? == true
    refute Map.get(updated, :retry_scheduled?, false)
    assert %DateTime{} = updated.stopped_at
  end
end
