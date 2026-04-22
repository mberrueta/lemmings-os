defmodule LemmingsOs.LemmingCallsRuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingInstances

  defmodule FakeRuntime do
    def spawn_session(lemming, request_text, _opts) do
      LemmingInstances.spawn_instance(lemming, request_text)
    end
  end

  defmodule FakeExecutor do
    def enqueue_work(pid, request_text) do
      send(pid, {:child_enqueue, request_text})
      :ok
    end
  end

  setup do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, slug: "ops")
    peer_department = insert(:department, world: world, city: city, slug: "research")

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        slug: "ops-manager"
      )

    worker =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        slug: "ops-worker",
        collaboration_role: "worker"
      )

    peer_manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: peer_department,
        status: "active",
        slug: "research-manager"
      )

    peer_worker =
      insert(:lemming,
        world: world,
        city: city,
        department: peer_department,
        status: "active",
        slug: "research-worker",
        collaboration_role: "worker"
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Manage work")
    {:ok, worker_instance} = LemmingInstances.spawn_instance(worker, "Do work")

    %{
      world: world,
      city: city,
      department: department,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      worker: worker,
      peer_manager: peer_manager,
      peer_worker: peer_worker
    }
  end

  test "S01: available_targets exposes same-department workers and peer managers only", %{
    manager_instance: manager_instance,
    worker_instance: worker_instance
  } do
    targets = LemmingCalls.available_targets(manager_instance)

    assert Enum.any?(targets, &(&1.slug == "ops-worker"))
    assert Enum.any?(targets, &(&1.slug == "research-manager"))
    refute Enum.any?(targets, &(&1.slug == "research-worker"))

    assert LemmingCalls.available_targets(worker_instance) == []
  end

  test "S02: request_call creates a running child call through runtime boundary", %{
    manager_instance: manager_instance
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "Draft the incident notes"},
               runtime_mod: FakeRuntime
             )

    assert call.status == "running"
    assert call.caller_instance_id == manager_instance.id
    assert call.request_text == "Draft the incident notes"
    assert is_binary(call.callee_instance_id)
  end

  test "S03: workers cannot request lemming calls", %{worker_instance: worker_instance} do
    assert {:error, :lemming_call_not_allowed} =
             LemmingCalls.request_call(
               worker_instance,
               %{target: "research-manager", request: "Coordinate this"},
               runtime_mod: FakeRuntime
             )
  end

  test "S04: continue_call enqueues work on active child and updates call", %{
    manager_instance: manager_instance
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    assert {:ok, updated_call} =
             LemmingCalls.request_call(
               manager_instance,
               %{
                 target: "ops-worker",
                 request: "Refine with costs",
                 continue_call_id: call.id
               },
               executor_pid: self(),
               executor_mod: FakeExecutor
             )

    assert updated_call.id == call.id
    assert updated_call.status == "running"
    assert_receive {:child_enqueue, "Refine with costs"}
  end

  test "S05: expired child continuation creates successor call", %{
    manager_instance: manager_instance
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    {:ok, _expired_instance} = LemmingInstances.update_status(child_instance, "expired", %{})

    assert {:ok, successor} =
             LemmingCalls.request_call(
               manager_instance,
               %{
                 target: "ops-worker",
                 request: "Continue after expiry",
                 continue_call_id: call.id
               },
               runtime_mod: FakeRuntime
             )

    assert successor.id != call.id
    assert successor.root_call_id == call.id
    assert successor.previous_call_id == call.id
    assert successor.status == "running"
  end

  test "S06: direct child input updates parent call record", %{manager_instance: manager_instance} do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    assert {:ok, _child_instance} =
             LemmingInstances.enqueue_work(child_instance, "Direct operator clarification",
               executor_pid: self(),
               executor_mod: FakeExecutor
             )

    assert_receive {:child_enqueue, "Direct operator clarification"}

    assert {:ok, updated_call} =
             LemmingCalls.get_call(call.id, world_id: manager_instance.world_id)

    assert updated_call.status == "running"
    assert updated_call.recovery_status == "direct_child_input"
  end
end
