defmodule LemmingsOs.LemmingCallsRuntimeTest do
  use LemmingsOs.DataCase, async: false

  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingCalls.PubSub
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Runtime.ActivityLog

  defmodule FakeRuntime do
    def spawn_session(lemming, request_text, _opts) do
      LemmingInstances.spawn_instance(lemming, request_text)
    end
  end

  defmodule CapturingRuntime do
    def spawn_session(lemming, request_text, opts) do
      if test_pid = Keyword.get(opts, :test_pid) do
        send(test_pid, {:spawned_child_request, request_text, opts})
      end

      LemmingInstances.spawn_instance(lemming, request_text)
    end
  end

  defmodule FakeExecutor do
    def enqueue_work(pid, request_text) do
      send(pid, {:child_enqueue, request_text})
      :ok
    end
  end

  defmodule FakeManagerExecutor do
    use GenServer

    def start_link({test_pid, instance_id}) do
      GenServer.start_link(__MODULE__, test_pid,
        name: LemmingInstances.Executor.via_name(instance_id)
      )
    end

    @impl true
    def init(test_pid), do: {:ok, test_pid}

    @impl true
    def handle_call({:resume_after_lemming_call, call}, _from, test_pid) do
      send(test_pid, {:manager_resumed_after_call, call})
      {:reply, :ok, test_pid}
    end
  end

  setup do
    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    ensure_process_started!(ActivityLog)
    ActivityLog.clear()

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
        slug: "ops-manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
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
        slug: "research-manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
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

  test "S01b: lemming.call is default-deny for target visibility and requests", %{
    world: world,
    city: city,
    department: department
  } do
    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        slug: "limited-manager"
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Manage limited work")

    assert LemmingCalls.available_targets(manager_instance) == []

    log =
      capture_log(fn ->
        assert {:error, :target_not_available} =
                 LemmingCalls.request_call(
                   manager_instance,
                   %{target: "ops-worker", request: "Draft the incident notes"},
                   runtime_mod: FakeRuntime
                 )
      end)

    assert log =~ "lemming call request failed"
    assert log =~ "reason=target_not_available"
  end

  test "S01c: denied lemming.call overrides allow list", %{
    world: world,
    city: city,
    department: department
  } do
    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        slug: "denied-manager",
        tools_config: %{allowed_tools: ["lemming.call"], denied_tools: ["lemming.call"]}
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Manage denied work")

    assert LemmingCalls.available_targets(manager_instance) == []
  end

  test "S02: request_call creates a running child call through runtime boundary", %{
    manager_instance: manager_instance
  } do
    created_ref = attach([:lemmings_os, :runtime, :lemming_call, :created])
    started_ref = attach([:lemmings_os, :runtime, :lemming_call, :started])

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

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :created],
                    %{count: 1}, created_metadata}

    assert created_metadata.lemming_call_id == call.id
    assert created_metadata.caller_instance_id == manager_instance.id
    assert created_metadata.callee_instance_id == call.callee_instance_id

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :started],
                    %{count: 1}, started_metadata}

    assert started_metadata.lemming_call_id == call.id
    assert started_metadata.status == "running"

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "lemming_call" and &1.action == "Lemming call created" and
                 &1.metadata[:lemming_call_id] == call.id)
           )

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "lemming_call" and &1.action == "Lemming call started" and
                 &1.metadata[:lemming_call_id] == call.id)
           )

    detach(created_ref)
    detach(started_ref)
  end

  test "S02b: request_call includes referenced caller artifact content for child handoff", %{
    manager_instance: manager_instance
  } do
    {:ok, %{absolute_path: absolute_path}} =
      LemmingInstances.artifact_absolute_path(manager_instance, "proposal.md")

    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, "# Existing Proposal\n\nOriginal body.\n")

    assert {:ok, _call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "Improve proposal.md for enterprise buyers"},
               runtime_mod: CapturingRuntime,
               runtime_opts: [test_pid: self()]
             )

    assert_receive {:spawned_child_request, child_request, _opts}
    assert child_request =~ "Improve proposal.md for enterprise buyers"
    assert child_request =~ "Delegation Artifact Context:"
    assert child_request =~ "Artifact: proposal.md"
    assert child_request =~ "# Existing Proposal"

    assert child_request =~
             "Do not call fs.read_text_file for these paths unless runtime later provides them inside your own workspace."
  end

  test "S02c: request_call passes runtime opts to spawned child", %{
    manager_instance: manager_instance
  } do
    assert {:ok, _call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "Draft shared notes"},
               runtime_mod: CapturingRuntime,
               runtime_opts: [test_pid: self(), executor_opts: [work_area_ref: "root-instance-1"]]
             )

    assert_receive {:spawned_child_request, "Draft shared notes", opts}
    assert opts[:executor_opts][:work_area_ref] == "root-instance-1"
  end

  test "S03: workers cannot request lemming calls", %{worker_instance: worker_instance} do
    log =
      capture_log(fn ->
        assert {:error, :lemming_call_not_allowed} =
                 LemmingCalls.request_call(
                   worker_instance,
                   %{target: "research-manager", request: "Coordinate this"},
                   runtime_mod: FakeRuntime
                 )
      end)

    assert log =~ "lemming call request failed"
    assert log =~ "event=lemming_call.request_failed"
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
    recovered_ref = attach([:lemmings_os, :runtime, :lemming_call, :recovered])

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

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :recovered],
                    %{count: 1}, recovered_metadata}

    assert recovered_metadata.lemming_call_id == successor.id
    assert recovered_metadata.previous_call_id == call.id

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "lemming_call" and &1.action == "Lemming call recovered" and
                 &1.metadata[:lemming_call_id] == successor.id)
           )

    detach(recovered_ref)
  end

  test "S05a: failed expired call can create successor call", %{
    manager_instance: manager_instance
  } do
    recovered_ref = attach([:lemmings_os, :runtime, :lemming_call, :recovered])

    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    {:ok, expired_instance} = LemmingInstances.update_status(child_instance, "expired", %{})

    capture_log(fn ->
      assert :ok =
               LemmingCalls.sync_child_instance_terminal(expired_instance, "expired", %{
                 error_summary: "Expired before completion"
               })
    end)

    assert {:ok, expired_call} =
             LemmingCalls.get_call(call.id, world_id: manager_instance.world_id)

    assert expired_call.status == "failed"
    assert expired_call.recovery_status == "expired"

    assert {:ok, successor} =
             LemmingCalls.request_call(
               manager_instance,
               %{
                 target: "ops-worker",
                 request: "Continue after synced expiry",
                 continue_call_id: call.id
               },
               runtime_mod: FakeRuntime
             )

    assert successor.id != call.id
    assert successor.root_call_id == call.id
    assert successor.previous_call_id == call.id
    assert successor.status == "running"

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :recovered],
                    %{count: 1}, recovered_metadata}

    assert recovered_metadata.lemming_call_id == successor.id
    assert recovered_metadata.previous_call_id == call.id

    detach(recovered_ref)
  end

  test "S05aa: expired continuation honors revoked target availability", %{
    manager_instance: manager_instance,
    worker: worker
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    {:ok, expired_instance} = LemmingInstances.update_status(child_instance, "expired", %{})

    capture_log(fn ->
      assert :ok =
               LemmingCalls.sync_child_instance_terminal(expired_instance, "expired", %{
                 error_summary: "Expired before completion"
               })
    end)

    assert {:ok, _worker} = Lemmings.update_lemming(worker, %{status: "archived"})

    assert {:error, :lemming_call_not_allowed} =
             LemmingCalls.request_call(
               manager_instance,
               %{
                 target: "ops-worker",
                 request: "Continue after target revoked",
                 continue_call_id: call.id
               },
               runtime_mod: FakeRuntime
             )
  end

  test "S05b: completed call with expired child cannot create successor", %{
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

    {:ok, _completed_call} = LemmingCalls.update_call_status(call, "completed")
    {:ok, _expired_instance} = LemmingInstances.update_status(child_instance, "expired", %{})

    log =
      capture_log(fn ->
        assert {:error, :call_terminal} =
                 LemmingCalls.request_call(
                   manager_instance,
                   %{
                     target: "ops-worker",
                     request: "Continue after terminal expiry",
                     continue_call_id: call.id
                   },
                   runtime_mod: FakeRuntime
                 )
      end)

    assert log =~ "lemming call request failed"
    assert log =~ "reason=call_terminal"

    assert [persisted_call] =
             LemmingCalls.list_calls(manager_instance.world_id,
               caller_instance_id: manager_instance.id
             )

    assert persisted_call.id == call.id
    assert persisted_call.status == "completed"
  end

  test "S06: direct child input updates parent call record", %{manager_instance: manager_instance} do
    recovery_pending_ref = attach([:lemmings_os, :runtime, :lemming_call, :recovery_pending])

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

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :recovery_pending],
                    %{count: 1}, metadata}

    assert metadata.lemming_call_id == call.id
    assert metadata.recovery_status == "direct_child_input"

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "lemming_call" and &1.action == "Lemming call recovery pending" and
                 &1.metadata[:lemming_call_id] == call.id)
           )

    detach(recovery_pending_ref)
  end

  test "S06a: child terminal markers update partial and needs-more-context states", %{
    manager_instance: manager_instance
  } do
    assert {:ok, partial_call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, partial_child} =
      LemmingInstances.get_instance(
        partial_call.callee_instance_id,
        world_id: manager_instance.world_id
      )

    capture_log(fn ->
      assert :ok =
               LemmingCalls.sync_child_instance_terminal(partial_child, "idle", %{
                 result_summary: "PARTIAL_RESULT: Drafted first half; blocked on pricing."
               })
    end)

    assert {:ok, updated_partial} =
             LemmingCalls.get_call(partial_call.id, world_id: manager_instance.world_id)

    assert updated_partial.status == "partial_result"
    assert updated_partial.result_summary == "Drafted first half; blocked on pricing."

    assert {:ok, context_call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "Second pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, context_child} =
      LemmingInstances.get_instance(
        context_call.callee_instance_id,
        world_id: manager_instance.world_id
      )

    capture_log(fn ->
      assert :ok =
               LemmingCalls.sync_child_instance_terminal(context_child, "idle", %{
                 result_summary: "[needs_more_context] Need customer segment before continuing."
               })
    end)

    assert {:ok, updated_context} =
             LemmingCalls.get_call(context_call.id, world_id: manager_instance.world_id)

    assert updated_context.status == "needs_more_context"
    assert updated_context.result_summary == "Need customer segment before continuing."
  end

  test "S07: terminal child sync emits call completion, dead, PubSub, and safe logs", %{
    manager_instance: manager_instance
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    assert :ok = PubSub.subscribe_call(call.id)
    assert :ok = PubSub.subscribe_instance_calls(manager_instance.id)
    call_id = call.id

    completed_ref = attach([:lemmings_os, :runtime, :lemming_call, :completed])
    dead_ref = attach([:lemmings_os, :runtime, :lemming_call, :dead])

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    completed_log =
      capture_log(fn ->
        assert :ok =
                 LemmingCalls.sync_child_instance_terminal(child_instance, "idle", %{
                   result_summary:
                     "Product-visible result summary that is safe to show and not the raw payload."
                 })
      end)

    assert completed_log =~ "caller executor unavailable for lemming call resume"
    assert completed_log =~ "event=lemming_call.caller_resume_unavailable"

    assert_receive {:lemming_call_upserted, %{lemming_call_id: ^call_id, status: "completed"}}

    assert_receive {:lemming_call_status_changed,
                    %{
                      lemming_call_id: ^call_id,
                      previous_status: "running",
                      status: "completed"
                    }}

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :completed],
                    %{count: 1, duration_ms: duration_ms}, completed_metadata}

    assert duration_ms >= 0
    assert completed_metadata.lemming_call_id == call.id
    assert completed_metadata.callee_instance_id == child_instance.id

    assert {:ok, completed_call} =
             LemmingCalls.get_call(call.id, world_id: manager_instance.world_id)

    assert completed_call.status == "completed"

    assert {:ok, _running_call} =
             LemmingCalls.update_call_status(completed_call, "running", %{
               started_at: DateTime.utc_now() |> DateTime.truncate(:second),
               completed_at: nil,
               result_summary: nil,
               error_summary: nil,
               recovery_status: nil
             })

    dead_log =
      capture_log(fn ->
        assert :ok =
                 LemmingCalls.sync_child_instance_terminal(child_instance, "expired", %{
                   error_summary: "Expired after no response"
                 })
      end)

    assert dead_log =~ "caller executor unavailable for lemming call resume"
    assert dead_log =~ "event=lemming_call.caller_resume_unavailable"

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :lemming_call, :dead],
                    %{count: 1, duration_ms: dead_duration_ms}, dead_metadata}

    assert dead_duration_ms >= 0
    assert dead_metadata.lemming_call_id == call.id
    assert dead_metadata.recovery_status == "expired"

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "lemming_call" and &1.action == "Lemming call dead" and
                 &1.metadata[:lemming_call_id] == call.id)
           )

    detach(completed_ref)
    detach(dead_ref)
  end

  test "S08: terminal child sync resumes caller executor with completed call", %{
    manager_instance: manager_instance
  } do
    assert {:ok, call} =
             LemmingCalls.request_call(
               manager_instance,
               %{target: "ops-worker", request: "First pass"},
               runtime_mod: FakeRuntime
             )

    {:ok, _pid} = start_supervised({FakeManagerExecutor, {self(), manager_instance.id}})

    {:ok, child_instance} =
      LemmingInstances.get_instance(call.callee_instance_id, world_id: manager_instance.world_id)

    assert :ok =
             LemmingCalls.sync_child_instance_terminal(child_instance, "idle", %{
               result_summary: "Completed child result"
             })

    assert_receive {:manager_resumed_after_call, resumed_call}
    assert resumed_call.id == call.id
    assert resumed_call.status == "completed"
    assert resumed_call.result_summary == "Completed child result"
  end

  defp attach(event) do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "lemming-calls-telemetry-test-#{inspect(ref)}",
        event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    ref
  end

  defp ensure_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> pid
      nil -> start_supervised!({Registry, keys: :unique, name: name})
    end
  end

  defp detach(ref) do
    :telemetry.detach("lemming-calls-telemetry-test-#{inspect(ref)}")
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
