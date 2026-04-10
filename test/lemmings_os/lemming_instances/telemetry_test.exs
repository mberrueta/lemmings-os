defmodule LemmingsOs.LemmingInstances.TelemetryTest do
  use LemmingsOs.DataCase, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingInstances.DepartmentScheduler
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner

  setup do
    ensure_process_started!(RuntimeTableOwner)
    :ok = EtsStore.init_table()
    :ets.delete_all_objects(:lemming_instance_runtime)

    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    ensure_registry!(LemmingsOs.LemmingInstances.SchedulerRegistry)
    ensure_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_dynamic_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)

    ensure_process_started!(LemmingsOs.LemmingInstances.DetsStore)

    on_exit(fn ->
      if :ets.whereis(:lemming_instance_runtime) != :undefined do
        :ets.delete_all_objects(:lemming_instance_runtime)
      end
    end)

    :ok
  end

  test "emits created telemetry when a runtime instance is spawned" do
    ref = attach([:lemmings_os, :instance, :created])

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

    assert {:ok, instance} =
             LemmingsOs.LemmingInstances.spawn_instance(lemming, "Initial request")

    assert_receive {:telemetry_event, [:lemmings_os, :instance, :created], %{count: 1}, metadata}

    assert metadata.instance_id == instance.id
    assert metadata.world_id == world.id
    assert metadata.city_id == city.id
    assert metadata.department_id == department.id
    assert metadata.lemming_id == lemming.id
    assert metadata.status == "created"
    assert is_binary(metadata.message_id)

    detach(ref)
  end

  test "emits started telemetry when an executor boots" do
    ref = attach([:lemmings_os, :instance, :started])

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

    assert {:ok, instance} =
             LemmingsOs.LemmingInstances.spawn_instance(lemming, "Initial request")

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        context_mod: nil,
        model_mod: nil,
        pubsub_mod: nil,
        dets_mod: nil,
        ets_mod: EtsStore,
        idle_timeout_ms: nil,
        name: nil
      )

    assert_receive {:telemetry_event, [:lemmings_os, :instance, :started], %{count: 1}, metadata}

    assert metadata.instance_id == instance.id
    assert metadata.world_id == world.id
    assert metadata.city_id == city.id
    assert metadata.department_id == department.id
    assert metadata.lemming_id == lemming.id

    GenServer.stop(pid)
    detach(ref)
  end

  test "emits scheduler and pool telemetry for denied and granted admissions" do
    capture_log(fn ->
      denial_ref = attach([:lemmings_os, :scheduler, :admission_denied])
      grant_ref = attach([:lemmings_os, :scheduler, :admission_granted])
      exhausted_ref = attach([:lemmings_os, :pool, :exhausted])

      department_id = Ecto.UUID.generate()
      world_id = Ecto.UUID.generate()
      city_id = Ecto.UUID.generate()
      lemming_id = Ecto.UUID.generate()
      instance_id = Ecto.UUID.generate()
      resource_key = "ollama:test-telemetry"
      executor_name = Executor.via_name(instance_id)

      {:ok, executor_pid} = Agent.start_link(fn -> nil end, name: executor_name)

      {:ok, pool_pid} =
        start_supervised(
          {ResourcePool, resource_key: resource_key, gate: :closed, pubsub_mod: nil, capacity: 1}
        )

      assert {:ok, _state} =
               EtsStore.put(instance_id, %{
                 department_id: department_id,
                 world_id: world_id,
                 city_id: city_id,
                 lemming_id: lemming_id,
                 queue:
                   :queue.from_list([
                     %{
                       id: "msg-1",
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

      assert_receive {:telemetry_event, [:lemmings_os, :pool, :exhausted], %{count: 1}, exhausted}
      assert exhausted.department_id == department_id
      assert exhausted.resource_key == resource_key

      assert_receive {:telemetry_event, [:lemmings_os, :scheduler, :admission_denied],
                      %{count: 1}, denied}

      assert denied.instance_id == instance_id
      assert denied.world_id == world_id
      assert denied.city_id == city_id
      assert denied.department_id == department_id
      assert denied.lemming_id == lemming_id

      assert :ok = ResourcePool.open_gate(pool_pid)
      assert :ok = DepartmentScheduler.admit_next(pid)

      assert_receive {:telemetry_event, [:lemmings_os, :scheduler, :admission_granted],
                      %{count: 1}, granted}

      assert granted.instance_id == instance_id
      assert granted.world_id == world_id
      assert granted.city_id == city_id
      assert granted.department_id == department_id
      assert granted.lemming_id == lemming_id
      assert granted.resource_key == resource_key

      GenServer.stop(pid)
      GenServer.stop(executor_pid)
      detach(denial_ref)
      detach(grant_ref)
      detach(exhausted_ref)
    end)
  end

  test "emits DETS snapshot_written telemetry when a snapshot is stored" do
    ref = attach([:lemmings_os, :dets, :snapshot_written])

    assert :ok =
             DetsStore.snapshot("instance-snapshot", %{
               department_id: "dept-1",
               queue: :queue.new(),
               current_item: nil,
               retry_count: 0,
               max_retries: 3,
               context_messages: [],
               status: :idle,
               started_at: DateTime.utc_now(),
               last_activity_at: DateTime.utc_now()
             })

    assert_receive {:telemetry_event, [:lemmings_os, :dets, :snapshot_written], %{count: 1},
                    metadata}

    assert metadata.instance_id == "instance-snapshot"
    assert metadata.table == :lemming_instance_snapshots

    detach(ref)
  end

  defp attach(event) do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "telemetry-test-#{inspect(ref)}",
        event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    ref
  end

  defp detach(ref) do
    :telemetry.detach("telemetry-test-#{inspect(ref)}")
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

  defp ensure_process_started!(child) do
    case Process.whereis(child) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!(child)
        :ok
    end
  end
end
