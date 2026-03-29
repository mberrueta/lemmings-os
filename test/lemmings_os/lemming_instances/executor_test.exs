defmodule LemmingsOs.LemmingInstances.ExecutorTest do
  use LemmingsOs.DataCase, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.ModelRuntime.Response

  defmodule FakeModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:model_run, self(), config_snapshot, context_messages, current_item})
      end

      {:ok,
       Response.new(
         reply: "processed",
         provider: "fake",
         model: Map.get(config_snapshot, :model, "fake-model"),
         raw: %{current_item: current_item, context_messages: context_messages}
       )}
    end
  end

  defmodule CrashingModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      raise "boom"
    end
  end

  defmodule HangingModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      receive do
      after
        60_000 -> :ok
      end
    end
  end

  setup do
    ensure_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_dynamic_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)

    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Initial request")

    if :ets.whereis(:lemming_instance_runtime) != :undefined do
      :ets.delete_all_objects(:lemming_instance_runtime)
    end

    on_exit(fn ->
      if :ets.whereis(:lemming_instance_runtime) != :undefined do
        :ets.delete_all_objects(:lemming_instance_runtime)
      end
    end)

    {:ok, instance: instance, department_id: department.id}
  end

  test "S01: via_name and child_spec build the expected registry wiring", %{instance: instance} do
    assert Executor.via_name(instance.id) ==
             {:via, Registry, {LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id}}

    spec = Executor.child_spec(instance: instance, name: nil)
    assert spec.id == {Executor, instance.id}
    assert spec.start == {Executor, :start_link, [[instance: instance, name: nil]]}
  end

  test "S02: successful execution persists the assistant reply and returns to idle", %{
    instance: instance
  } do
    resource_key = "ollama:fake-model"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "fake-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "fake-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: FakeModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert ResourcePool.status(resource_key) == {1, 1}

    assert :ok = Executor.enqueue_work(pid, "Investigate the outage")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fake-model"}, _context_messages,
                    %{content: "Investigate the outage"}}

    assert_receive {:status_changed, %{status: "idle"}}
    assert ResourcePool.status(resource_key) == {0, 1}

    assert Executor.status(pid).status == "idle"

    messages = LemmingInstances.list_messages(instance)
    assert Enum.any?(messages, &(&1.role == "assistant" and &1.content == "processed"))

    GenServer.stop(pid)
  end

  test "S03: model crashes transition the executor to failed and release the pool token", %{
    instance: instance
  } do
    assert capture_log(fn ->
             resource_key = "ollama:fake-model"

             assert :ok = PubSub.subscribe_instance(instance.id)

             {:ok, pid} =
               Executor.start_link(
                 instance: instance,
                 config_snapshot: %{
                   runtime_config: %{max_retries: 1},
                   models_config: %{
                     profiles: %{default: %{provider: "ollama", model: "fake-model"}}
                   }
                 },
                 context_mod: LemmingInstances,
                 model_mod: CrashingModelRuntime,
                 pool_mod: ResourcePool,
                 pubsub_mod: Phoenix.PubSub,
                 dets_mod: nil,
                 ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                 name: nil
               )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert ResourcePool.status(resource_key) == {1, 1}

             assert :ok = Executor.enqueue_work(pid, "Crash please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}
             assert ResourcePool.status(resource_key) == {0, 1}

             assert Executor.status(pid).status == "failed"

             GenServer.stop(pid)
           end) =~ "executor model task crashed"
  end

  test "S04: hanging model execution times out and fails the executor", %{instance: instance} do
    resource_key = "ollama:hanging-model"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          runtime_config: %{max_retries: 1, model_timeout_ms: 10},
          models_config: %{
            profiles: %{default: %{provider: "ollama", model: "hanging-model"}}
          }
        },
        context_mod: LemmingInstances,
        model_mod: HangingModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert ResourcePool.status(resource_key) == {1, 1}

    assert :ok = Executor.enqueue_work(pid, "Hang please")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}
    assert_receive {:status_changed, %{status: "failed"}}

    assert ResourcePool.status(resource_key) == {0, 1}

    assert %{status: "failed", last_error: "Executor model task timed out."} =
             Executor.status(pid)

    GenServer.stop(pid)
  end

  test "S05: failed executions clear persisted DETS snapshots", %{instance: instance} do
    resource_key = "ollama:failed-snapshot"
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert capture_log(fn ->
             assert :ok = PubSub.subscribe_instance(instance.id)

             assert :ok =
                      DetsStore.snapshot(instance.id, %{
                        department_id: instance.department_id,
                        queue: :queue.new(),
                        current_item: nil,
                        retry_count: 0,
                        max_retries: 1,
                        context_messages: [],
                        status: :idle,
                        started_at: started_at,
                        last_activity_at: started_at
                      })

             assert {:ok, pid} =
                      Executor.start_link(
                        instance: instance,
                        config_snapshot: %{
                          runtime_config: %{max_retries: 1},
                          models_config: %{
                            profiles: %{default: %{provider: "ollama", model: "fake-model"}}
                          }
                        },
                        context_mod: LemmingInstances,
                        model_mod: CrashingModelRuntime,
                        pool_mod: ResourcePool,
                        pubsub_mod: Phoenix.PubSub,
                        dets_mod: DetsStore,
                        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                        name: nil
                      )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert :ok = Executor.enqueue_work(pid, "Crash please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}
             assert {:error, :not_found} = DetsStore.read(instance.id)

             GenServer.stop(pid)
           end) =~ "executor model task crashed"
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
