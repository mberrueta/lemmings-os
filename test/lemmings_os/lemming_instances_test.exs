defmodule LemmingsOs.LemmingInstancesTest do
  use LemmingsOs.DataCase, async: false

  doctest LemmingsOs.LemmingInstances

  import ExUnit.CaptureLog
  import LemmingsOs.Factory

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  defmodule FakeExecutor do
    def enqueue_work(pid, content) do
      send(pid, {:executor_enqueue, content})
      :ok
    end
  end

  defmodule CrashOnEnqueueExecutor do
    def enqueue_work(pid, content) do
      Process.exit(pid, :kill)
      LemmingsOs.LemmingInstances.Executor.enqueue_work(pid, content)
    end
  end

  setup do
    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    Repo.delete_all(Message)
    Repo.delete_all(LemmingInstance)
    Repo.delete_all(Lemming)
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    :ok
  end

  test "S01: enqueue_work persists the follow-up message and forwards to the executor" do
    instance = spawn_idle_instance()

    assert {:ok, ^instance} =
             LemmingInstances.enqueue_work(instance, "Continue with risks",
               executor_pid: self(),
               executor_mod: FakeExecutor
             )

    assert_receive {:executor_enqueue, "Continue with risks"}

    messages = LemmingInstances.list_messages(instance)

    assert Enum.sort(Enum.map(messages, &{&1.role, &1.content})) == [
             {"user", "Continue with risks"},
             {"user", "Investigate the outage"}
           ]
  end

  test "S02: terminal instances reject follow-up work" do
    instance = spawn_idle_instance()

    assert {:error, :terminal_instance} =
             LemmingInstances.enqueue_work(%{instance | status: "failed"}, "Try again",
               executor_pid: self(),
               executor_mod: FakeExecutor
             )

    refute_receive {:executor_enqueue, _content}

    messages = LemmingInstances.list_messages(instance)
    assert Enum.map(messages, &{&1.role, &1.content}) == [{"user", "Investigate the outage"}]
  end

  test "S02b: enqueue_work defaults opts to [] for arity-2 callers" do
    instance = spawn_idle_instance()

    assert capture_log(fn ->
             assert {:error, :executor_unavailable} =
                      LemmingInstances.enqueue_work(instance, "Continue with risks")
           end) =~ "follow-up request could not be queued"
  end

  test "S02c: enqueue_work does not acknowledge success when executor admission is not confirmed" do
    instance = spawn_idle_instance()
    dead_pid = spawn(fn -> :ok end)
    monitor_ref = Process.monitor(dead_pid)

    assert_receive {:DOWN, ^monitor_ref, :process, ^dead_pid, _reason}

    assert capture_log(fn ->
             assert {:error, :executor_unavailable} =
                      LemmingInstances.enqueue_work(instance, "Continue with risks",
                        executor_pid: dead_pid
                      )
           end) =~ "follow-up request could not be queued"

    assert Enum.sort(Enum.map(LemmingInstances.list_messages(instance), &{&1.role, &1.content})) ==
             [
               {"user", "Continue with risks"},
               {"user", "Investigate the outage"}
             ]
  end

  test "S02d: enqueue_work returns an error when the executor dies after registry resolution" do
    instance = spawn_idle_instance()
    parent = self()

    executor_pid =
      spawn(fn ->
        {:ok, _} =
          Registry.register(LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id, :race)

        send(parent, {:executor_registered, self()})

        receive do
          :stop -> :ok
        end
      end)

    monitor_ref = Process.monitor(executor_pid)

    assert_receive {:executor_registered, ^executor_pid}

    assert capture_log(fn ->
             assert {:error, :executor_unavailable} =
                      LemmingInstances.enqueue_work(instance, "Continue with risks",
                        executor_mod: CrashOnEnqueueExecutor
                      )
           end) =~ "follow-up request could not be queued"

    assert_receive {:DOWN, ^monitor_ref, :process, ^executor_pid, :killed}
  end

  test "S03: spawn_instance serializes config snapshots without __meta__ or not loaded associations" do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "active"
      )

    lemming =
      Lemming
      |> Repo.get!(lemming.id)
      |> Repo.preload([:world, :city, :department])

    assert {:ok, instance} =
             LemmingInstances.spawn_instance(lemming, "Investigate the outage", preload: false)

    assert is_map(instance.config_snapshot)
    refute Map.has_key?(instance.config_snapshot, :__meta__)
    refute Map.has_key?(instance.config_snapshot, "__meta__")
  end

  test "S04: get_runtime_state/1 normalizes persisted runtime state from DETS" do
    instance = spawn_idle_instance()
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    last_activity_at = DateTime.add(started_at, 5, :second)

    assert :ok =
             DetsStore.snapshot(instance.id, %{
               department_id: instance.department_id,
               queue:
                 :queue.from_list([
                   %{
                     id: "msg-queued",
                     content: "Continue with risks",
                     origin: :user,
                     inserted_at: started_at
                   }
                 ]),
               current_item: %{id: "msg-current", content: "Investigate the outage"},
               retry_count: 1,
               max_retries: 3,
               context_messages: [],
               last_error: "provider timeout",
               status: :retrying,
               started_at: started_at,
               last_activity_at: last_activity_at
             })

    assert {:ok, runtime_state} =
             LemmingInstances.get_runtime_state(instance.id, world_id: instance.world_id)

    assert runtime_state == %{
             retry_count: 1,
             max_retries: 3,
             queue_depth: 1,
             current_item: %{id: "msg-current", content: "Investigate the outage"},
             last_error: "provider timeout",
             status: "retrying",
             started_at: started_at,
             last_activity_at: last_activity_at
           }
  end

  test "S04b: get_runtime_state/2 requires explicit world scope and enforces it" do
    instance = spawn_idle_instance()
    other_world = insert(:world)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Process.whereis(DetsStore) do
      pid when is_pid(pid) -> :ok
      nil -> start_supervised!(DetsStore)
    end

    assert :ok =
             DetsStore.snapshot(instance.id, %{
               department_id: instance.department_id,
               queue: :queue.new(),
               current_item: nil,
               retry_count: 0,
               max_retries: 3,
               context_messages: [],
               status: :idle,
               started_at: now,
               last_activity_at: now
             })

    assert {:error, :not_found} = LemmingInstances.get_runtime_state(instance.id)

    assert {:error, :not_found} =
             LemmingInstances.get_runtime_state(instance.id, world: other_world)

    assert {:ok, _runtime_state} =
             LemmingInstances.get_runtime_state(instance.id, world_id: instance.world_id)
  end

  test "S05: spawn_instance rejects blank initial requests and inactive lemmings" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "draft"
      )

    assert {:error, :empty_request_text} = LemmingInstances.spawn_instance(lemming, "   ")
    assert {:error, :lemming_not_active} = LemmingInstances.spawn_instance(lemming, "Run now")
  end

  test "S06: list_instances/2 is world scoped and supports filters" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    other_world = insert(:world)
    other_city = insert(:city, world: other_world)
    other_department = insert(:department, world: other_world, city: other_city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    other_lemming =
      insert(:lemming,
        world: other_world,
        city: other_city,
        department: other_department,
        status: "active"
      )

    assert {:ok, queued_instance} = LemmingInstances.spawn_instance(lemming, "First request")
    assert {:ok, idle_instance} = LemmingInstances.spawn_instance(lemming, "Second request")
    assert {:ok, _other_instance} = LemmingInstances.spawn_instance(other_lemming, "Other world")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, idle_instance} =
             LemmingInstances.update_status(idle_instance, "idle", %{last_activity_at: now})

    idle_instance_id = idle_instance.id
    queued_instance_id = queued_instance.id

    assert Enum.sort(Enum.map(LemmingInstances.list_instances(world), & &1.id)) ==
             Enum.sort([idle_instance_id, queued_instance_id])

    assert [%LemmingInstance{id: ^idle_instance_id}] =
             LemmingInstances.list_instances(world, status: "idle")

    assert [%LemmingInstance{id: ^queued_instance_id}] =
             LemmingInstances.list_instances(world, lemming_id: lemming.id, status: "created")
  end

  test "S07: get_instance/2 enforces world scope" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    other_world = insert(:world)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    assert {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Scoped request")

    instance_id = instance.id

    assert {:ok, %LemmingInstance{id: ^instance_id}} =
             LemmingInstances.get_instance(instance.id, world: world)

    assert {:error, :not_found} = LemmingInstances.get_instance(instance.id, world: other_world)
    assert {:error, :not_found} = LemmingInstances.get_instance(instance.id)
  end

  test "S08: list_messages/1 returns messages in chronological order" do
    instance = spawn_idle_instance()
    [initial_message] = LemmingInstances.list_messages(instance)
    earlier = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.truncate(:second)

    {1, _} =
      Message
      |> where([message], message.id == ^initial_message.id)
      |> Repo.update_all(set: [inserted_at: earlier])

    assert {:ok, ^instance} =
             LemmingInstances.enqueue_work(instance, "Continue with risks",
               executor_pid: self(),
               executor_mod: FakeExecutor
             )

    assert_receive {:executor_enqueue, "Continue with risks"}

    assert Enum.map(LemmingInstances.list_messages(instance), & &1.content) == [
             "Investigate the outage",
             "Continue with risks"
           ]
  end

  test "S09: topology_summary/1 reports total and active instance counts" do
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

    assert {:ok, active_instance} = LemmingInstances.spawn_instance(lemming, "Active")
    assert {:ok, failed_instance} = LemmingInstances.spawn_instance(lemming, "Failed")
    assert {:ok, expired_instance} = LemmingInstances.spawn_instance(lemming, "Expired")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _} =
             LemmingInstances.update_status(failed_instance, "failed", %{stopped_at: now})

    assert {:ok, _} =
             LemmingInstances.update_status(active_instance, "idle", %{last_activity_at: now})

    assert {:ok, _} =
             LemmingInstances.update_status(expired_instance, "expired", %{stopped_at: now})

    assert LemmingInstances.topology_summary(world) == %{
             instance_count: 3,
             active_instance_count: 1
           }
  end

  defp spawn_idle_instance do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "active"
      )

    {:ok, instance} =
      LemmingInstances.spawn_instance(lemming, "Investigate the outage")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, instance} =
      LemmingInstances.update_status(instance, "idle", %{
        started_at: now,
        last_activity_at: now
      })

    instance
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
end
