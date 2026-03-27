defmodule LemmingsOs.LemmingInstances.ExecutorTest do
  use LemmingsOs.DataCase, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingInstances
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

  setup do
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

    {:ok, pool_pid} =
      ResourcePool.start_link(resource_key: resource_key, name: nil, gate: :open, pubsub_mod: nil)

    assert :ok = ResourcePool.checkout(pool_pid, holder: pid)
    assert ResourcePool.status(pool_pid) == {1, 1}

    assert :ok = Executor.enqueue_work(pid, "Investigate the outage")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fake-model"}, _context_messages,
                    %{content: "Investigate the outage"}}

    assert_receive {:status_changed, %{status: "idle"}}
    assert ResourcePool.status(pool_pid) == {0, 1}

    assert Executor.status(pid).status == "idle"

    messages = LemmingInstances.list_messages(instance)
    assert Enum.any?(messages, &(&1.role == "assistant" and &1.content == "processed"))

    GenServer.stop(pid)
    GenServer.stop(pool_pid)
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

             {:ok, pool_pid} =
               ResourcePool.start_link(
                 resource_key: resource_key,
                 name: nil,
                 gate: :open,
                 pubsub_mod: nil
               )

             assert :ok = ResourcePool.checkout(pool_pid, holder: pid)
             assert ResourcePool.status(pool_pid) == {1, 1}

             assert :ok = Executor.enqueue_work(pid, "Crash please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}
             assert ResourcePool.status(pool_pid) == {0, 1}

             assert Executor.status(pid).status == "failed"

             GenServer.stop(pid)
             GenServer.stop(pool_pid)
           end) =~ "executor model task crashed"
  end
end
