defmodule LemmingsOs.LemmingInstances.Executor.RuntimeStoreTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.RuntimeStore

  @runtime_table :runtime_store_test_table

  defmodule FakeEtsMod do
    def put(instance_id, runtime_state) do
      send(self(), {:ets_put, instance_id, runtime_state})
      :ok
    end

    def delete(instance_id) do
      send(self(), {:ets_delete, instance_id})
      :ok
    end
  end

  defmodule FakeDetsAsyncMod do
    def snapshot_async(instance_id, runtime_state) do
      send(
        Map.get(runtime_state, :test_pid, self()),
        {:dets_snapshot_async, instance_id, runtime_state}
      )

      :ok
    end
  end

  defmodule FakeDetsSyncMod do
    def snapshot(instance_id, runtime_state) do
      send(
        Map.get(runtime_state, :test_pid, self()),
        {:dets_snapshot, instance_id, runtime_state}
      )

      :ok
    end
  end

  defmodule FakeDetsDeleteMod do
    def delete(instance_id) do
      send(self(), {:dets_delete, instance_id})
      :ok
    end
  end

  setup do
    if :ets.whereis(@runtime_table) == :undefined do
      :ets.new(@runtime_table, [:named_table, :public, :set])
    else
      :ets.delete_all_objects(@runtime_table)
    end

    on_exit(fn ->
      if :ets.whereis(@runtime_table) != :undefined do
        :ets.delete(@runtime_table)
      end
    end)

    :ok
  end

  test "put_runtime_state/3 writes directly to ETS when ets_mod is nil" do
    state = %{instance_id: "instance-1", ets_mod: nil}
    runtime_state = %{status: :idle}

    assert RuntimeStore.put_runtime_state(state, runtime_state, @runtime_table) == state
    assert :ets.lookup(@runtime_table, "instance-1") == [{"instance-1", runtime_state}]
  end

  test "put_runtime_state/3 delegates to injected ets_mod when available" do
    state = %{instance_id: "instance-1", ets_mod: FakeEtsMod}
    runtime_state = %{status: :queued}

    assert RuntimeStore.put_runtime_state(state, runtime_state, @runtime_table) == state
    assert_receive {:ets_put, "instance-1", %{status: :queued}}
  end

  test "snapshot_on_idle/2 no-ops when dets_mod is nil" do
    state = %{instance_id: "instance-1", dets_mod: nil}
    runtime_state = %{status: :idle}

    assert RuntimeStore.snapshot_on_idle(state, runtime_state) == state
    refute_receive {:dets_snapshot_async, _, _}
  end

  test "snapshot_on_idle/2 uses snapshot_async when available" do
    state = %{instance_id: "instance-1", dets_mod: FakeDetsAsyncMod}
    runtime_state = %{status: :idle, test_pid: self()}

    assert RuntimeStore.snapshot_on_idle(state, runtime_state) == state
    assert_receive {:dets_snapshot_async, "instance-1", %{status: :idle, test_pid: _pid}}
  end

  test "snapshot_on_idle/2 falls back to async task wrapping snapshot/2" do
    state = %{instance_id: "instance-1", dets_mod: FakeDetsSyncMod}
    runtime_state = %{status: :idle, test_pid: self()}

    assert RuntimeStore.snapshot_on_idle(state, runtime_state) == state
    assert_receive {:dets_snapshot, "instance-1", %{status: :idle, test_pid: _pid}}
  end

  test "cleanup_snapshot/1 deletes snapshot via dets_mod when available" do
    state = %{instance_id: "instance-1", dets_mod: FakeDetsDeleteMod}

    assert RuntimeStore.cleanup_snapshot(state) == state
    assert_receive {:dets_delete, "instance-1"}
  end

  test "cleanup_runtime/2 deletes direct ETS row when ets_mod is nil" do
    state = %{instance_id: "instance-1", ets_mod: nil, dets_mod: nil}
    :ets.insert(@runtime_table, {"instance-1", %{status: :idle}})

    assert RuntimeStore.cleanup_runtime(state, @runtime_table) == state
    assert :ets.lookup(@runtime_table, "instance-1") == []
  end

  test "cleanup_runtime/2 delegates deletes to injected ets and dets mods" do
    state = %{instance_id: "instance-1", ets_mod: FakeEtsMod, dets_mod: FakeDetsDeleteMod}

    assert RuntimeStore.cleanup_runtime(state, @runtime_table) == state
    assert_receive {:ets_delete, "instance-1"}
    assert_receive {:dets_delete, "instance-1"}
  end
end
