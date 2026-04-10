defmodule LemmingsOs.LemmingInstances.EtsStoreTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner

  setup do
    start_supervised!(RuntimeTableOwner)
    :ok = EtsStore.init_table()
    :ets.delete_all_objects(:lemming_instance_runtime)
    :ok
  end

  defp base_state(department_id, status \\ :created) do
    %{
      department_id: department_id,
      queue: :queue.new(),
      current_item: nil,
      retry_count: 0,
      max_retries: 3,
      context_messages: [],
      status: status,
      started_at: nil,
      last_activity_at: nil
    }
  end

  test "S01: put, get, update, delete, and cleanup manage runtime rows" do
    assert {:ok, stored} = EtsStore.put("instance-1", base_state("dept-1"))
    assert stored.department_id == "dept-1"
    assert {:ok, fetched} = EtsStore.get("instance-1")
    assert fetched.department_id == "dept-1"

    assert {:ok, updated} = EtsStore.update("instance-1", %{status: :queued})
    assert updated.status == :queued

    assert :ok = EtsStore.delete("instance-1")
    assert {:error, :not_found} = EtsStore.get("instance-1")

    assert {:ok, _stored} = EtsStore.put("instance-1", base_state("dept-1"))
    assert :ok = EtsStore.cleanup("instance-1")
    assert {:error, :not_found} = EtsStore.get("instance-1")
  end

  test "S02: list_by_status returns matching rows for a department" do
    assert {:ok, _} = EtsStore.put("instance-1", base_state("dept-1", :queued))
    assert {:ok, _} = EtsStore.put("instance-2", base_state("dept-1", :queued))
    assert {:ok, _} = EtsStore.put("instance-3", base_state("dept-2", :queued))

    assert [{"instance-1", _}, {"instance-2", _}] =
             EtsStore.list_by_status(:queued, "dept-1")
  end

  test "S03: enqueue_work_item, dequeue_work_item, and get_queue_depth manage the queue" do
    assert {:ok, _} = EtsStore.put("instance-1", base_state("dept-1"))

    work_item = %{
      id: "msg-1",
      content: "Investigate the outage",
      origin: :user,
      inserted_at: DateTime.utc_now()
    }

    assert {:ok, updated} = EtsStore.enqueue_work_item("instance-1", work_item)
    assert :queue.len(updated.queue) == 1
    assert EtsStore.get_queue_depth("instance-1") == 1

    assert {:ok, dequeued} = EtsStore.dequeue_work_item("instance-1")
    assert dequeued.id == "msg-1"
    assert EtsStore.get_queue_depth("instance-1") == 0
  end

  test "S04: init_table/0 asks the runtime table owner to recreate a deleted table" do
    true = :ets.delete(:lemming_instance_runtime)

    assert :ok = EtsStore.init_table()
    assert :ets.whereis(:lemming_instance_runtime) != :undefined
  end
end
