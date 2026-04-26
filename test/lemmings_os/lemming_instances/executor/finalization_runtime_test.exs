defmodule LemmingsOs.LemmingInstances.Executor.FinalizationRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.FinalizationRuntime

  doctest FinalizationRuntime

  test "schedule_repair/3 marks repair attempt, clears errors, and persists" do
    deps = %{
      put_runtime_state: &Map.put(&1, :persisted?, true),
      release_resource: & &1,
      cleanup_snapshot: & &1,
      transition_to: fn state, _status, _attrs -> state end
    }

    state = %{
      finalization_repair_attempted?: false,
      last_error: "boom",
      internal_error_details: %{kind: :x},
      finalization_context: %{}
    }

    updated = FinalizationRuntime.schedule_repair(state, :empty_final_response, deps)

    assert updated.finalization_repair_attempted? == true
    assert updated.last_error == nil
    assert updated.internal_error_details == nil
    assert updated.finalization_context.repair_reason == ":empty_final_response"
    assert updated.persisted? == true
  end

  test "fail_without_retry/3 sets terminal failure fields and runs cleanup chain" do
    deps = %{
      put_runtime_state: &Map.put(&1, :persisted?, true),
      release_resource: &Map.put(&1, :released?, true),
      cleanup_snapshot: &Map.put(&1, :snapshot_cleaned?, true),
      transition_to: fn state, status, attrs ->
        state
        |> Map.put(:status, status)
        |> Map.put(:stopped_at, attrs.stopped_at)
      end
    }

    state = %{max_retries: 3, now_fun: fn -> ~U[2026-04-26 19:10:00Z] end}

    updated = FinalizationRuntime.fail_without_retry(state, :provider_error, deps)

    assert updated.status == "failed"
    assert updated.retry_count == 3
    assert updated.released? == true
    assert updated.snapshot_cleaned? == true
    assert updated.persisted? == true
    assert is_binary(updated.last_error)
    assert is_map(updated.internal_error_details)
    assert %DateTime{} = updated.stopped_at
  end
end
