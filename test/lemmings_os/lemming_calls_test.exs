defmodule LemmingsOs.LemmingCallsTest do
  use LemmingsOs.DataCase, async: false

  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo

  doctest LemmingsOs.LemmingCalls
  doctest LemmingsOs.LemmingCalls.LemmingCall

  defmodule SpawnOnlyRuntime do
    def spawn_session(lemming, request_text, opts) do
      with {:ok, instance} <- LemmingInstances.spawn_instance(lemming, request_text) do
        if observer_pid = Keyword.get(opts, :observer_pid) do
          send(observer_pid, {:spawned_child, instance.id})
        end

        {:ok, instance}
      end
    end
  end

  describe "list_calls/2" do
    setup [:call_graph_fixture]

    test "S01: scopes results to the requested world and status", %{
      world: world,
      other_world: other_world,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      other_world_manager_instance: other_world_manager_instance,
      other_world_worker_instance: other_world_worker_instance,
      caller_department: caller_department,
      callee_department: callee_department,
      manager: manager,
      worker: worker,
      other_world_manager: other_world_manager,
      other_world_worker: other_world_worker
    } do
      matching_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "accepted"
        )

      _non_matching_status =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "failed"
        )

      _other_world_call =
        insert(:lemming_call,
          world: other_world.world,
          city: other_world.city,
          caller_department: other_world.caller_department,
          callee_department: other_world.callee_department,
          caller_lemming: other_world_manager,
          callee_lemming: other_world_worker,
          caller_instance: other_world_manager_instance,
          callee_instance: other_world_worker_instance,
          status: "accepted"
        )

      assert [found_call] = LemmingCalls.list_calls(world.world, status: "accepted")
      assert found_call.id == matching_call.id
      assert found_call.world_id == world.world.id
    end

    test "S02: supports successor, department, id, and preload filters within world scope", %{
      world: world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department,
      peer_manager: peer_manager,
      peer_manager_instance: peer_manager_instance,
      peer_department: peer_department
    } do
      root_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "accepted"
        )

      matching_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "completed",
          root_call_id: root_call.id,
          previous_call_id: root_call.id
        )

      _wrong_department_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: peer_department,
          callee_department: callee_department,
          caller_lemming: peer_manager,
          callee_lemming: worker,
          caller_instance: peer_manager_instance,
          callee_instance: worker_instance,
          status: "completed",
          root_call_id: root_call.id,
          previous_call_id: root_call.id
        )

      assert [found_call] =
               LemmingCalls.list_calls(
                 world.world.id,
                 department_id: caller_department.id,
                 root_call_id: root_call.id,
                 previous_call_id: root_call.id,
                 ids: [matching_call.id],
                 statuses: ["accepted", "completed"],
                 preload: [:caller_instance]
               )

      assert found_call.id == matching_call.id
      assert Ecto.assoc_loaded?(found_call.caller_instance)
    end
  end

  describe "get_call/2" do
    setup [:call_graph_fixture]

    test "S03: returns the call only when the explicit world scope and filters match", %{
      world: world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department
    } do
      call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "accepted"
        )

      assert {:ok, found_call} =
               LemmingCalls.get_call(call.id,
                 world: world.world,
                 status: "accepted",
                 preload: [:callee_instance]
               )

      assert found_call.id == call.id
      assert Ecto.assoc_loaded?(found_call.callee_instance)
    end

    test "S04: returns not_found for missing world scope, wrong world, and mismatched filters", %{
      world: world,
      other_world: other_world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department
    } do
      call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "accepted"
        )

      assert {:error, :not_found} = LemmingCalls.get_call(call.id, [])
      assert {:error, :not_found} = LemmingCalls.get_call(call.id, world_id: other_world.world.id)

      assert {:error, :not_found} =
               LemmingCalls.get_call(call.id, world_id: world.world.id, status: "failed")

      assert {:error, :not_found} =
               LemmingCalls.get_call(Ecto.UUID.generate(), world_id: world.world.id)
    end
  end

  describe "create_call/2" do
    setup [:call_graph_fixture]

    test "S05: derives world, city, department, and lemming identities from instance ids", %{
      world: world,
      other_world: other_world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department
    } do
      assert {:ok, call} =
               LemmingCalls.create_call(
                 %{
                   "caller_instance_id" => manager_instance.id,
                   "callee_instance_id" => worker_instance.id,
                   "request_text" => "Coordinate the incident write-up",
                   "world_id" => other_world.world.id,
                   "city_id" => other_world.city.id,
                   "caller_department_id" => other_world.caller_department.id,
                   "callee_department_id" => other_world.callee_department.id,
                   "caller_lemming_id" => other_world.manager.id,
                   "callee_lemming_id" => other_world.worker.id
                 },
                 world: world.world
               )

      assert call.world_id == world.world.id
      assert call.city_id == world.city.id
      assert call.caller_department_id == caller_department.id
      assert call.callee_department_id == callee_department.id
      assert call.caller_lemming_id == manager.id
      assert call.callee_lemming_id == worker.id
      assert call.caller_instance_id == manager_instance.id
      assert call.callee_instance_id == worker_instance.id
      assert call.request_text == "Coordinate the incident write-up"
      assert call.status == "accepted"
    end

    test "S06: accepts same-world successor references when root and previous calls are in scope",
         %{
           world: world,
           manager: manager,
           worker: worker,
           manager_instance: manager_instance,
           worker_instance: worker_instance,
           caller_department: caller_department,
           callee_department: callee_department
         } do
      root_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "completed"
        )

      assert {:ok, successor_call} =
               LemmingCalls.create_call(
                 %{
                   caller_instance_id: manager_instance.id,
                   callee_instance_id: worker_instance.id,
                   request_text: "Continue from the earlier result",
                   root_call_id: root_call.id,
                   previous_call_id: root_call.id,
                   status: "needs_more_context"
                 },
                 world_id: world.world.id
               )

      assert successor_call.root_call_id == root_call.id
      assert successor_call.previous_call_id == root_call.id
      assert successor_call.status == "needs_more_context"
    end

    test "S07: requires explicit world scope and both instance ids", %{
      world: world,
      manager_instance: manager_instance
    } do
      assert {:error, :missing_world_scope} =
               LemmingCalls.create_call(%{
                 caller_instance_id: manager_instance.id,
                 request_text: "Need a reviewer"
               })

      assert {:error, :missing_instance_ids} =
               LemmingCalls.create_call(
                 %{caller_instance_id: manager_instance.id, request_text: "Need a reviewer"},
                 world_id: world.world.id
               )
    end

    test "S08: rejects cross-city caller and callee pairs even inside one world", %{
      world: world,
      remote_worker_instance: remote_worker_instance,
      manager_instance: manager_instance
    } do
      assert {:error, :cross_city_call} =
               LemmingCalls.create_call(
                 %{
                   caller_instance_id: manager_instance.id,
                   callee_instance_id: remote_worker_instance.id,
                   request_text: "Coordinate with remote support"
                 },
                 world: world.world
               )
    end

    test "S09: rejects successor calls outside world scope", %{
      world: world,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      other_world_root_call: other_world_root_call
    } do
      assert {:error, :call_not_found} =
               LemmingCalls.create_call(
                 %{
                   caller_instance_id: manager_instance.id,
                   callee_instance_id: worker_instance.id,
                   request_text: "Continue from foreign successor",
                   root_call_id: other_world_root_call.id,
                   previous_call_id: other_world_root_call.id
                 },
                 world_id: world.world.id
               )
    end

    test "S10: surfaces changeset errors for invalid persisted attrs", %{
      world: world,
      manager_instance: manager_instance,
      worker_instance: worker_instance
    } do
      changeset =
        capture_log(fn ->
          assert {:error, changeset} =
                   LemmingCalls.create_call(
                     %{
                       caller_instance_id: manager_instance.id,
                       callee_instance_id: worker_instance.id,
                       request_text: "   ",
                       status: "accepted"
                     },
                     world: world.world
                   )

          send(self(), {:captured_changeset, changeset})
        end)
        |> then(fn _log ->
          assert_receive {:captured_changeset, changeset}
          changeset
        end)

      refute changeset.valid?
      assert %{request_text: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update_call_status/3" do
    setup [:call_graph_fixture]

    test "S11: persists status transitions, summaries, and timestamps", %{
      world: world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department
    } do
      call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "running"
        )

      started_at = ~U[2026-04-24 12:00:00Z]
      completed_at = ~U[2026-04-24 12:15:00Z]

      assert {:ok, updated_call} =
               LemmingCalls.update_call_status(call, "completed", %{
                 started_at: started_at,
                 completed_at: completed_at,
                 result_summary: "Work finished successfully",
                 error_summary: nil,
                 recovery_status: "recovered"
               })

      assert updated_call.status == "completed"
      assert updated_call.started_at == started_at
      assert updated_call.completed_at == completed_at
      assert updated_call.result_summary == "Work finished successfully"
      assert updated_call.recovery_status == "recovered"

      persisted_call = Repo.get!(LemmingCall, call.id)
      assert persisted_call.status == "completed"
      assert persisted_call.completed_at == completed_at
      assert persisted_call.result_summary == "Work finished successfully"
    end

    test "S12: returns changeset errors and leaves persistence unchanged for invalid statuses", %{
      world: world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      callee_department: callee_department
    } do
      call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "running",
          result_summary: "Still working"
        )

      changeset =
        capture_log(fn ->
          assert {:error, changeset} = LemmingCalls.update_call_status(call, "impossible", %{})
          send(self(), {:captured_changeset, changeset})
        end)
        |> then(fn _log ->
          assert_receive {:captured_changeset, changeset}
          changeset
        end)

      assert %{status: [_ | _]} = errors_on(changeset)

      persisted_call = Repo.get!(LemmingCall, call.id)
      assert persisted_call.status == "running"
      assert persisted_call.result_summary == "Still working"
    end
  end

  describe "request_call/3 compensation" do
    setup [:call_graph_fixture]

    test "S13: expires spawned child when call insert fails after runtime spawn", %{
      world: world,
      manager_instance: manager_instance,
      peer_manager: peer_manager
    } do
      create_failure =
        %LemmingCall{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:request_text, "db insert failed")

      assert capture_log(fn ->
               assert {:error, ^create_failure} =
                        LemmingCalls.request_call(
                          manager_instance,
                          %{target: peer_manager.slug, request: "Draft notes"},
                          runtime_mod: SpawnOnlyRuntime,
                          runtime_opts: [observer_pid: self()],
                          create_call_fun: fn _attrs, _opts -> {:error, create_failure} end
                        )
             end) =~ "lemming call request failed"

      assert_receive {:spawned_child, child_id}

      assert {:ok, child_instance} =
               LemmingInstances.get_instance(child_id, world_id: world.world.id)

      assert child_instance.status == "expired"
      assert child_instance.stopped_at
      assert [] = LemmingCalls.list_calls(world.world)
    end

    test "S14: expires spawned child when running status update fails after call insert", %{
      world: world,
      manager_instance: manager_instance,
      peer_manager: peer_manager
    } do
      update_failure =
        %LemmingCall{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:status, "db update failed")

      assert capture_log(fn ->
               assert {:error, ^update_failure} =
                        LemmingCalls.request_call(
                          manager_instance,
                          %{target: peer_manager.slug, request: "Draft notes"},
                          runtime_mod: SpawnOnlyRuntime,
                          runtime_opts: [observer_pid: self()],
                          update_call_status_fun: fn _call, _status, _attrs ->
                            {:error, update_failure}
                          end
                        )
             end) =~ "lemming call request failed"

      assert_receive {:spawned_child, child_id}

      assert {:ok, child_instance} =
               LemmingInstances.get_instance(child_id, world_id: world.world.id)

      assert child_instance.status == "expired"

      assert [call] = LemmingCalls.list_calls(world.world)
      assert call.status == "accepted"
      assert call.callee_instance_id == child_id
    end

    test "S15: expires spawned child when DB persistence raises after runtime spawn", %{
      world: world,
      manager_instance: manager_instance,
      peer_manager: peer_manager
    } do
      assert capture_log(fn ->
               assert {:error, %RuntimeError{message: "database unavailable"}} =
                        LemmingCalls.request_call(
                          manager_instance,
                          %{target: peer_manager.slug, request: "Draft notes"},
                          runtime_mod: SpawnOnlyRuntime,
                          runtime_opts: [observer_pid: self()],
                          create_call_fun: fn _attrs, _opts ->
                            raise "database unavailable"
                          end
                        )
             end) =~ "lemming call request failed"

      assert_receive {:spawned_child, child_id}

      assert {:ok, child_instance} =
               LemmingInstances.get_instance(child_id, world_id: world.world.id)

      assert child_instance.status == "expired"
      assert [] = LemmingCalls.list_calls(world.world)
    end
  end

  describe "list_manager_calls/2 and list_child_calls/2" do
    setup [:call_graph_fixture]

    test "S13: list_manager_calls scopes by caller instance and honors filters", %{
      world: world,
      manager: manager,
      worker: worker,
      peer_worker: peer_worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      peer_worker_instance: peer_worker_instance,
      caller_department: caller_department,
      callee_department: callee_department,
      peer_department: peer_department
    } do
      _accepted_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "accepted"
        )

      matching_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: peer_department,
          caller_lemming: manager,
          callee_lemming: peer_worker,
          caller_instance: manager_instance,
          callee_instance: peer_worker_instance,
          status: "completed"
        )

      _other_manager_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: peer_department,
          callee_department: callee_department,
          caller_lemming: world.peer_manager,
          callee_lemming: worker,
          caller_instance: world.peer_manager_instance,
          callee_instance: worker_instance,
          status: "completed"
        )

      assert [found_call] =
               LemmingCalls.list_manager_calls(manager_instance,
                 statuses: ["completed"],
                 preload: [:callee_instance]
               )

      assert found_call.id == matching_call.id
      assert Ecto.assoc_loaded?(found_call.callee_instance)
    end

    test "S14: list_child_calls scopes by callee instance and honors caller filters", %{
      world: world,
      manager: manager,
      worker: worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      caller_department: caller_department,
      peer_department: peer_department
    } do
      _caller_department_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: world.callee_department,
          caller_lemming: manager,
          callee_lemming: worker,
          caller_instance: manager_instance,
          callee_instance: worker_instance,
          status: "running"
        )

      matching_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: peer_department,
          callee_department: world.callee_department,
          caller_lemming: world.peer_manager,
          callee_lemming: worker,
          caller_instance: world.peer_manager_instance,
          callee_instance: worker_instance,
          status: "needs_more_context"
        )

      _other_child_call =
        insert(:lemming_call,
          world: world.world,
          city: world.city,
          caller_department: caller_department,
          callee_department: peer_department,
          caller_lemming: manager,
          callee_lemming: world.peer_worker,
          caller_instance: manager_instance,
          callee_instance: world.peer_worker_instance,
          status: "needs_more_context"
        )

      assert [found_call] =
               LemmingCalls.list_child_calls(worker_instance,
                 caller_department_id: peer_department.id,
                 statuses: ["needs_more_context"],
                 preload: [:caller_instance]
               )

      assert found_call.id == matching_call.id
      assert Ecto.assoc_loaded?(found_call.caller_instance)
    end
  end

  describe "manager?/1 and worker?/1" do
    test "S15: returns role booleans from collaboration_role" do
      assert LemmingCalls.manager?(%Lemming{collaboration_role: "manager"})
      refute LemmingCalls.manager?(%Lemming{collaboration_role: "worker"})

      assert LemmingCalls.worker?(%Lemming{collaboration_role: "worker"})
      refute LemmingCalls.worker?(%Lemming{collaboration_role: "manager"})
    end
  end

  defp call_graph_fixture(_context) do
    world = insert(:world)
    city = insert(:city, world: world, status: "active", slug: "alpha-city")
    caller_department = insert(:department, world: world, city: city, slug: "ops")
    callee_department = insert(:department, world: world, city: city, slug: "research")
    peer_department = insert(:department, world: world, city: city, slug: "support")

    remote_city = insert(:city, world: world, status: "active", slug: "beta-city")
    remote_department = insert(:department, world: world, city: remote_city, slug: "field")

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: caller_department,
        status: "active",
        slug: "ops-manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
      )

    worker =
      insert(:lemming,
        world: world,
        city: city,
        department: callee_department,
        status: "active",
        slug: "research-worker",
        collaboration_role: "worker"
      )

    peer_manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: peer_department,
        status: "active",
        slug: "support-manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
      )

    peer_worker =
      insert(:lemming,
        world: world,
        city: city,
        department: peer_department,
        status: "active",
        slug: "support-worker",
        collaboration_role: "worker"
      )

    remote_worker =
      insert(:lemming,
        world: world,
        city: remote_city,
        department: remote_department,
        status: "active",
        slug: "field-worker",
        collaboration_role: "worker"
      )

    manager_instance = insert_instance(manager)
    worker_instance = insert_instance(worker)
    peer_manager_instance = insert_instance(peer_manager)
    peer_worker_instance = insert_instance(peer_worker)
    remote_worker_instance = insert_instance(remote_worker)

    other_world = insert(:world)
    other_world_city = insert(:city, world: other_world, status: "active", slug: "gamma-city")

    other_world_caller_department =
      insert(:department, world: other_world, city: other_world_city, slug: "sales")

    other_world_callee_department =
      insert(:department, world: other_world, city: other_world_city, slug: "legal")

    other_world_manager =
      insert(:manager_lemming,
        world: other_world,
        city: other_world_city,
        department: other_world_caller_department,
        status: "active",
        slug: "sales-manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
      )

    other_world_worker =
      insert(:lemming,
        world: other_world,
        city: other_world_city,
        department: other_world_callee_department,
        status: "active",
        slug: "legal-worker",
        collaboration_role: "worker"
      )

    other_world_manager_instance = insert_instance(other_world_manager)
    other_world_worker_instance = insert_instance(other_world_worker)

    other_world_root_call =
      insert(:lemming_call,
        world: other_world,
        city: other_world_city,
        caller_department: other_world_caller_department,
        callee_department: other_world_callee_department,
        caller_lemming: other_world_manager,
        callee_lemming: other_world_worker,
        caller_instance: other_world_manager_instance,
        callee_instance: other_world_worker_instance,
        status: "completed"
      )

    %{
      world: %{
        world: world,
        city: city,
        caller_department: caller_department,
        callee_department: callee_department,
        peer_department: peer_department,
        remote_city: remote_city,
        remote_department: remote_department,
        manager: manager,
        worker: worker,
        peer_manager: peer_manager,
        peer_worker: peer_worker,
        manager_instance: manager_instance,
        worker_instance: worker_instance,
        peer_manager_instance: peer_manager_instance,
        peer_worker_instance: peer_worker_instance,
        remote_worker_instance: remote_worker_instance
      },
      other_world: %{
        world: other_world,
        city: other_world_city,
        caller_department: other_world_caller_department,
        callee_department: other_world_callee_department,
        manager: other_world_manager,
        worker: other_world_worker,
        manager_instance: other_world_manager_instance,
        worker_instance: other_world_worker_instance
      },
      caller_department: caller_department,
      callee_department: callee_department,
      peer_department: peer_department,
      manager: manager,
      worker: worker,
      peer_manager: peer_manager,
      peer_worker: peer_worker,
      manager_instance: manager_instance,
      worker_instance: worker_instance,
      peer_manager_instance: peer_manager_instance,
      peer_worker_instance: peer_worker_instance,
      remote_worker_instance: remote_worker_instance,
      other_world_manager: other_world_manager,
      other_world_worker: other_world_worker,
      other_world_manager_instance: other_world_manager_instance,
      other_world_worker_instance: other_world_worker_instance,
      other_world_root_call: other_world_root_call
    }
  end

  defp insert_instance(lemming) do
    insert(:lemming_instance,
      lemming: lemming,
      world: lemming.world,
      city: lemming.city,
      department: lemming.department,
      config_snapshot: instance_config_snapshot(lemming),
      status: "idle"
    )
  end

  defp instance_config_snapshot(lemming) do
    allowed_tools =
      lemming
      |> Map.get(:tools_config)
      |> case do
        %{allowed_tools: tools} when is_list(tools) -> tools
        _tools_config -> []
      end

    denied_tools =
      lemming
      |> Map.get(:tools_config)
      |> case do
        %{denied_tools: tools} when is_list(tools) -> tools
        _tools_config -> []
      end

    %{
      tools_config: %{allowed_tools: allowed_tools, denied_tools: denied_tools},
      models_config: %{},
      runtime_config: %{}
    }
  end
end
