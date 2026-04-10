defmodule LemmingsOs.LemmingInstances.DepartmentSchedulerTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.DepartmentScheduler
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool

  setup do
    :ok = EtsStore.init_table()
    :ets.delete_all_objects(:lemming_instance_runtime)
    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    ensure_registry!(LemmingsOs.LemmingInstances.SchedulerRegistry)
    ensure_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_dynamic_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)
    :ok
  end

  test "S01: via_name and child_spec build the expected registry wiring" do
    assert DepartmentScheduler.via_name("dept-1") ==
             {:via, Registry, {LemmingsOs.LemmingInstances.SchedulerRegistry, "dept-1"}}

    spec = DepartmentScheduler.child_spec(department_id: "dept-1")
    assert spec.id == {DepartmentScheduler, "dept-1"}
    assert spec.start == {DepartmentScheduler, :start_link, [[department_id: "dept-1"]]}
  end

  test "S02: oldest_eligible_first sorts queued candidates by age" do
    candidates = [
      %{instance_id: "instance-new", work_item: %{inserted_at: ~U[2024-01-01 01:00:00Z]}},
      %{instance_id: "instance-old", work_item: %{inserted_at: ~U[2024-01-01 00:00:00Z]}}
    ]

    assert [%{instance_id: "instance-old"}, %{instance_id: "instance-new"}] =
             DepartmentScheduler.oldest_eligible_first(candidates)
  end

  test "S03: admit_next reserves capacity for the executor pid and broadcasts admission" do
    department_id = "dept-scheduler"
    instance_id = "instance-scheduler"
    resource_key = "ollama:test"
    executor_name = Executor.via_name(instance_id)

    {:ok, executor_pid} = Agent.start_link(fn -> nil end, name: executor_name)

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert {:ok, _state} =
             EtsStore.put(instance_id, %{
               department_id: department_id,
               world_id: Ecto.UUID.generate(),
               queue:
                 :queue.from_list([
                   %{
                     id: "msg-old",
                     content: "Oldest item",
                     origin: :user,
                     inserted_at: ~U[2024-01-01 00:00:00Z]
                   }
                 ]),
               current_item: nil,
               config_snapshot: %{
                 models_config: %{profiles: %{default: %{provider: "ollama", model: "test"}}}
               },
               resource_key: resource_key,
               retry_count: 0,
               max_retries: 3,
               context_messages: [],
               status: :queued,
               started_at: nil,
               last_activity_at: nil
             })

    assert :ok = PubSub.subscribe_scheduler(department_id)

    {:ok, pid} =
      DepartmentScheduler.start_link(
        department_id: department_id,
        admission_mode: :manual,
        ets_mod: EtsStore,
        pool_mod: ResourcePool,
        context_mod: nil,
        pubsub_mod: Phoenix.PubSub,
        name: nil
      )

    assert :ok = DepartmentScheduler.admit_next(pid)

    assert_receive {:scheduler_admit,
                    %{
                      department_id: ^department_id,
                      instance_id: ^instance_id,
                      resource_key: ^resource_key
                    }}

    assert ResourcePool.status(resource_key) == {1, 1}

    assert :ok = ResourcePool.checkin(resource_key, executor_pid)

    GenServer.stop(pid)
    GenServer.stop(executor_pid)
  end

  test "S04: auto mode reacts to work_available and admits queued work" do
    department_id = "dept-auto"
    instance_id = "instance-auto"
    resource_key = "ollama:auto"
    executor_name = Executor.via_name(instance_id)

    {:ok, executor_pid} = Agent.start_link(fn -> nil end, name: executor_name)

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert {:ok, _state} =
             EtsStore.put(instance_id, %{
               department_id: department_id,
               world_id: Ecto.UUID.generate(),
               queue:
                 :queue.from_list([
                   %{
                     id: "msg-auto",
                     content: "Auto admitted item",
                     origin: :user,
                     inserted_at: ~U[2024-01-01 00:00:00Z]
                   }
                 ]),
               current_item: nil,
               config_snapshot: %{
                 models_config: %{profiles: %{default: %{provider: "ollama", model: "auto"}}}
               },
               resource_key: resource_key,
               retry_count: 0,
               max_retries: 3,
               context_messages: [],
               status: :queued,
               started_at: nil,
               last_activity_at: nil
             })

    assert :ok = PubSub.subscribe_scheduler(department_id)

    {:ok, pid} =
      DepartmentScheduler.start_link(
        department_id: department_id,
        admission_mode: :auto,
        ets_mod: EtsStore,
        pool_mod: ResourcePool,
        context_mod: nil,
        pubsub_mod: Phoenix.PubSub,
        name: nil
      )

    assert :ok = PubSub.broadcast_work_available(department_id)

    assert_receive {:scheduler_admit,
                    %{
                      department_id: ^department_id,
                      instance_id: ^instance_id,
                      resource_key: ^resource_key
                    }}

    GenServer.stop(pid)
    GenServer.stop(executor_pid)
  end

  defp ensure_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({Registry, keys: :unique, name: name})
        :ok
    end
  end

  defp ensure_dynamic_supervisor!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({DynamicSupervisor, name: name, strategy: :one_for_one})
        :ok
    end
  end
end
