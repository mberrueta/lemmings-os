defmodule LemmingsOs.LemmingInstances.DetsStoreTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.DetsStore

  setup do
    id = "instance-dets-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      _ = DetsStore.delete(id)
    end)

    {:ok, instance_id: id}
  end

  test "S01: ready and init_store report the supervised store as available" do
    assert :ok = DetsStore.init_store()
    assert :ok = DetsStore.ready?()
  end

  test "S02: start_link/1 returns already_started for the supervised singleton" do
    assert {:error, {:already_started, pid}} = DetsStore.start_link([])
    assert is_pid(pid)
  end

  test "S03: snapshot, read, and delete persist the runtime state", %{instance_id: id} do
    state = %{
      department_id: "dept-dets",
      queue: :queue.new(),
      current_item: nil,
      retry_count: 0,
      max_retries: 3,
      context_messages: [],
      status: :idle,
      started_at: DateTime.utc_now(),
      last_activity_at: DateTime.utc_now()
    }

    assert :ok = DetsStore.snapshot(id, state)
    assert {:ok, snapshot} = DetsStore.read(id)
    assert snapshot.department_id == "dept-dets"
    assert :ok = DetsStore.delete(id)
    assert {:error, :not_found} = DetsStore.read(id)
  end
end
