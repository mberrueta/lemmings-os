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

    assert {:ok, runtime_state} = LemmingInstances.get_runtime_state(instance.id)

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
