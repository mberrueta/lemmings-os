defmodule LemmingsOs.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.Runtime

  defmodule RejectingExecutorApi do
    def enqueue_work(_pid, _content), do: {:error, :executor_unavailable}
    def resume_pending(_pid, _content), do: {:error, :executor_unavailable}
  end

  setup do
    start_supervised!(
      {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.ExecutorRegistry}
    )

    start_supervised!(
      {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.SchedulerRegistry}
    )

    start_supervised!({Registry, keys: :unique, name: LemmingsOs.LemmingInstances.PoolRegistry})
    start_supervised!(LemmingsOs.LemmingInstances.RuntimeTableOwner)

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.PoolSupervisor, strategy: :one_for_one}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.ExecutorSupervisor, strategy: :one_for_one}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.SchedulerSupervisor, strategy: :one_for_one}
    )

    :ok
  end

  test "S01: spawn_session/3 persists an instance and its first user message" do
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
             Runtime.spawn_session(lemming, "Summarize the roadmap",
               scheduler_opts: [admission_mode: :manual]
             )

    assert instance.status == "created"

    work_area_root =
      :lemmings_os
      |> Application.fetch_env!(:work_areas_path)
      |> Path.expand()

    assert File.dir?(Path.join(work_area_root, instance.id))

    assert eventually_status(instance.id) == "queued"

    [message] = LemmingInstances.list_messages(instance)
    assert {message.role, message.content} == {"user", "Summarize the roadmap"}
  end

  test "S01b: spawn_session/3 returns an error when initial executor admission is rejected" do
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

    assert {:error, :executor_unavailable} =
             Runtime.spawn_session(lemming, "Summarize the roadmap",
               executor_api_mod: RejectingExecutorApi,
               scheduler_opts: [admission_mode: :manual]
             )

    [instance] = LemmingInstances.list_instances(world, lemming_id: lemming.id)
    [message] = LemmingInstances.list_messages(instance)

    assert instance.status == "created"
    assert {message.role, message.content} == {"user", "Summarize the roadmap"}
  end

  test "S02: recover_created_sessions/1 requeues a stale created instance" do
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

    assert {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")

    assert {:ok, 1} =
             Runtime.recover_created_sessions(scheduler_opts: [admission_mode: :manual])

    assert eventually_status(instance.id) == "queued"

    [message] = LemmingInstances.list_messages(instance)
    assert {message.role, message.content} == {"user", "Summarize the roadmap"}
  end

  test "S03: recover_created_sessions/1 reattaches idle instances so follow-ups can queue" do
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

    assert {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, idle_instance} =
             LemmingInstances.update_status(instance, "idle", %{
               started_at: now,
               last_activity_at: now
             })

    assert {:ok, 1} =
             Runtime.recover_created_sessions(scheduler_opts: [admission_mode: :manual])

    assert [{executor_pid, _value}] =
             Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, idle_instance.id)

    assert {:ok, ^idle_instance} =
             LemmingInstances.enqueue_work(idle_instance, "Continue with risks",
               executor_pid: executor_pid
             )

    assert eventually_status(idle_instance.id) == "queued"
  end

  test "S04: recover_created_sessions/1 respects the configured recovery limit" do
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

    assert {:ok, first_instance} = LemmingInstances.spawn_instance(lemming, "First request")
    assert {:ok, second_instance} = LemmingInstances.spawn_instance(lemming, "Second request")
    assert {:ok, third_instance} = LemmingInstances.spawn_instance(lemming, "Third request")

    assert {:ok, 2} =
             Runtime.recover_created_sessions(limit: 2, scheduler_opts: [admission_mode: :manual])

    recovered_ids =
      [first_instance.id, second_instance.id, third_instance.id]
      |> Enum.filter(fn instance_id ->
        Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance_id) != []
      end)

    assert length(recovered_ids) == 2

    Enum.each(recovered_ids, fn instance_id ->
      assert eventually_status(instance_id) == "queued"
    end)

    unrecovered_ids = [first_instance.id, second_instance.id, third_instance.id] -- recovered_ids

    assert length(unrecovered_ids) == 1

    [unrecovered_id] = unrecovered_ids

    assert [] = Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, unrecovered_id)

    assert Repo.get!(LemmingsOs.LemmingInstances.LemmingInstance, unrecovered_id).status ==
             "created"
  end

  test "S05: retry_session/2 requeues a failed instance when its executor is down" do
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

    assert {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Retry the failed request")
    assert {:ok, failed_instance} = LemmingInstances.update_status(instance, "failed", %{})

    assert {:ok, retried_instance} =
             Runtime.retry_session(failed_instance, scheduler_opts: [admission_mode: :manual])

    assert retried_instance.id == failed_instance.id
    assert retried_instance.status == "created"

    assert [{executor_pid, _value}] =
             Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, failed_instance.id)

    assert is_pid(executor_pid)
    assert eventually_status(failed_instance.id) == "queued"
  end

  test "S06: spawn_session/3 returns created instance behind the runtime boundary" do
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
             Runtime.spawn_session(lemming, "Boundary check",
               scheduler_opts: [admission_mode: :manual]
             )

    assert %LemmingsOs.LemmingInstances.LemmingInstance{} = instance
    assert instance.status == "created"
    assert is_binary(instance.id)
  end

  defp eventually_status(instance_id, attempts \\ 10)

  defp eventually_status(instance_id, 0), do: Executor.status(instance_id).status

  defp eventually_status(instance_id, attempts) do
    status = Executor.status(instance_id).status

    if status == "queued" do
      status
    else
      Process.sleep(50)
      eventually_status(instance_id, attempts - 1)
    end
  end
end
