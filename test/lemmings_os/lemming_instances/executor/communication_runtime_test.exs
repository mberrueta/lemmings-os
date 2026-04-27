defmodule LemmingsOs.LemmingInstances.Executor.CommunicationRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.CommunicationRuntime
  alias LemmingsOs.LemmingInstances.LemmingInstance

  doctest CommunicationRuntime

  defmodule TrackingCalls do
    def list_manager_calls(instance, _opts) do
      if Map.get(instance, :pending_calls?, false), do: [%{id: "pending"}], else: []
    end

    def sync_child_instance_terminal(instance, status, attrs) do
      if is_pid(Map.get(instance, :test_pid)) do
        send(instance.test_pid, {:child_terminal_synced, status, attrs})
      end

      :ok
    end
  end

  defmodule TargetCalls do
    def available_targets(_instance), do: [%{slug: "ops-worker"}]
  end

  defmodule RequestCalls do
    def request_call(_instance, attrs, _opts),
      do: {:ok, %{id: "call-1", request_text: attrs.request}}
  end

  defmodule CapturingRequestCalls do
    def request_call(instance, attrs, opts) do
      send(instance.config_snapshot.test_pid, {:request_call_opts, opts})
      {:ok, %{id: "call-1", request_text: attrs.request}}
    end
  end

  defmodule RejectingCalls do
    def request_call(_instance, _attrs, _opts), do: {:error, :not_allowed}
  end

  test "instance_with_runtime_snapshot/2 replaces config snapshot in instance map" do
    instance = %LemmingInstance{id: "instance-1", config_snapshot: %{model: "old"}}
    config_snapshot = %{model: "new"}

    updated = CommunicationRuntime.instance_with_runtime_snapshot(instance, config_snapshot)

    assert updated.id == "instance-1"
    assert updated.config_snapshot == %{model: "new"}
  end

  test "model_config_snapshot/3 augments config with available targets" do
    base_config = %{model: "fake-model"}
    instance = %{id: "instance-1", config_snapshot: base_config}

    assert %{model: "fake-model"} =
             CommunicationRuntime.model_config_snapshot(base_config, nil, instance)

    assert %{model: "fake-model", lemming_call_targets: [%{slug: "ops-worker"}]} =
             CommunicationRuntime.model_config_snapshot(base_config, TargetCalls, instance)
  end

  test "append_call_request_context/2 appends lemming call request message" do
    state = %{context_messages: [%{role: "user", content: "Delegate this"}]}
    attrs = %{target: "ops-worker", request: "Draft child notes", continue_call_id: nil}

    updated = CommunicationRuntime.append_call_request_context(state, attrs)

    assert length(updated.context_messages) == 2

    assert String.contains?(
             List.last(updated.context_messages).content,
             "Assistant requested lemming_call"
           )
  end

  test "execute_lemming_call/2 appends context and returns normalized success/error" do
    response =
      LemmingsOs.ModelRuntime.Response.new(
        action: :lemming_call,
        lemming_target: "ops-worker",
        lemming_request: "Draft child notes",
        continue_call_id: nil,
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    base_state = %{
      instance: %{id: "instance-1", config_snapshot: %{}},
      config_snapshot: %{model: "fake-model"},
      context_messages: [],
      lemming_calls_mod: RequestCalls
    }

    assert {:ok, next_state, %{id: "call-1"}} =
             CommunicationRuntime.execute_lemming_call(base_state, response)

    assert String.contains?(
             List.last(next_state.context_messages).content,
             "Assistant requested lemming_call"
           )

    rejecting_state = %{base_state | lemming_calls_mod: RejectingCalls}

    assert {:error, {:lemming_call_failed, :not_allowed}, rejected_state} =
             CommunicationRuntime.execute_lemming_call(rejecting_state, response)

    assert String.contains?(
             List.last(rejected_state.context_messages).content,
             "Assistant requested lemming_call"
           )
  end

  test "execute_lemming_call/2 passes parent work_area_ref as hidden runtime opts" do
    response =
      LemmingsOs.ModelRuntime.Response.new(
        action: :lemming_call,
        lemming_target: "ops-worker",
        lemming_request: "Draft child notes",
        continue_call_id: nil,
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    state = %{
      instance: %{id: "instance-1", config_snapshot: %{}},
      config_snapshot: %{test_pid: self()},
      context_messages: [],
      lemming_calls_mod: CapturingRequestCalls,
      work_area_ref: "root-instance-1"
    }

    assert {:ok, _next_state, %{id: "call-1"}} =
             CommunicationRuntime.execute_lemming_call(state, response)

    assert_receive {:request_call_opts,
                    [
                      runtime_opts: [
                        executor_opts: [work_area_ref: "root-instance-1"]
                      ]
                    ]}
  end

  test "resume_after_lemming_call/3 resumes processing when state is eligible" do
    deps = %{
      emit_resume_requested: fn _state, _call -> :ok end,
      emit_resume_started: fn _state, _call -> :ok end,
      emit_resume_rejected: fn _state, _reason -> :ok end,
      emit_resume_completed: fn _state, _call -> :ok end,
      cancel_idle_timer: &Map.put(&1, :idle_timer_cancelled?, true),
      transition_to: fn state, status, attrs ->
        state
        |> Map.put(:status, status)
        |> Map.put(:stopped_at, attrs.stopped_at)
      end,
      put_runtime_state: fn state -> Map.update(state, :persist_count, 1, &(&1 + 1)) end,
      start_execution: &Map.put(&1, :started_execution?, true)
    }

    state = %{
      status: "idle",
      current_item: %{id: "item-1"},
      model_task_pid: nil,
      context_messages: [%{role: "user", content: "Delegate this"}],
      retry_count: 2,
      last_error: "boom",
      internal_error_details: %{kind: :model_timeout}
    }

    call = %{status: "completed", result_summary: "Done"}

    assert {:ok, next_state} = CommunicationRuntime.resume_after_lemming_call(state, call, deps)
    assert next_state.status == "processing"
    assert next_state.started_execution? == true
    assert next_state.idle_timer_cancelled? == true
    assert next_state.persist_count == 1
    assert next_state.retry_count == 0
    assert next_state.last_error == nil
    assert next_state.internal_error_details == nil
  end

  test "resume_after_lemming_call/3 rejects in terminal or invalid state" do
    deps = %{
      emit_resume_requested: fn _state, _call -> :ok end,
      emit_resume_started: fn _state, _call -> :ok end,
      emit_resume_rejected: fn _state, _reason -> :ok end,
      emit_resume_completed: fn _state, _call -> :ok end,
      cancel_idle_timer: & &1,
      transition_to: fn state, _status, _attrs -> state end,
      put_runtime_state: & &1,
      start_execution: & &1
    }

    terminal_state = %{status: "failed", current_item: %{id: "item-1"}, model_task_pid: nil}
    call = %{status: "completed"}

    assert {{:error, :terminal_instance}, ^terminal_state} =
             CommunicationRuntime.resume_after_lemming_call(terminal_state, call, deps)

    invalid_state = %{status: "idle", current_item: nil, model_task_pid: nil}

    assert {{:error, :resume_not_possible}, ^invalid_state} =
             CommunicationRuntime.resume_after_lemming_call(invalid_state, call, deps)
  end

  test "resume_after_lemming_call/3 rejects non-terminal child calls" do
    deps = %{
      emit_resume_requested: fn _state, _call -> :ok end,
      emit_resume_started: fn _state, _call -> :ok end,
      emit_resume_rejected: fn _state, _reason -> :ok end,
      emit_resume_completed: fn _state, _call -> :ok end,
      cancel_idle_timer: & &1,
      transition_to: fn state, _status, _attrs -> state end,
      put_runtime_state: & &1,
      start_execution: & &1
    }

    state = %{status: "idle", current_item: %{id: "item-1"}, model_task_pid: nil}
    call = %{status: "running"}

    assert {{:error, :child_call_not_terminal}, ^state} =
             CommunicationRuntime.resume_after_lemming_call(state, call, deps)
  end

  test "resume_after_lemming_call/3 emits requested before rejection and does not start" do
    parent = self()

    deps = %{
      emit_resume_requested: fn _state, _call ->
        send(parent, :requested)
        :ok
      end,
      emit_resume_started: fn _state, _call ->
        send(parent, :started)
        :ok
      end,
      emit_resume_rejected: fn _state, reason ->
        send(parent, {:rejected, reason})
        :ok
      end,
      emit_resume_completed: fn _state, _call -> :ok end,
      cancel_idle_timer: & &1,
      transition_to: fn state, _status, _attrs -> state end,
      put_runtime_state: & &1,
      start_execution: & &1
    }

    terminal_state = %{status: "failed", current_item: %{id: "item-1"}, model_task_pid: nil}
    call = %{status: "completed"}

    assert {{:error, :terminal_instance}, ^terminal_state} =
             CommunicationRuntime.resume_after_lemming_call(terminal_state, call, deps)

    assert_received :requested
    assert_received {:rejected, :terminal_instance}
    refute_received :started
  end

  test "continue_after_lemming_call/2 runs release, clears errors, persists, and idles" do
    deps = %{
      release_resource: fn state -> Map.put(state, :released?, true) end,
      put_runtime_state: fn state -> Map.update(state, :persist_count, 1, &(&1 + 1)) end,
      transition_to: fn state, status, attrs ->
        state
        |> Map.put(:status, status)
        |> Map.put(:stopped_at, attrs.stopped_at)
      end
    }

    state = %{
      status: "processing",
      persist_count: 0,
      last_error: "boom",
      internal_error_details: %{kind: :model_timeout}
    }

    updated = CommunicationRuntime.continue_after_lemming_call(state, deps)

    assert updated.status == "idle"
    assert updated.released? == true
    assert updated.persist_count == 2
    assert updated.last_error == nil
    assert updated.internal_error_details == nil
    assert Map.get(updated, :stopped_at) == nil
  end

  test "maybe_sync_child_terminal/2 skips idle sync while manager still has pending child calls" do
    state = %{
      lemming_calls_mod: TrackingCalls,
      instance: %{id: "instance-1", test_pid: self(), pending_calls?: true},
      context_messages: [%{role: "assistant", content: "Final child answer"}],
      last_error: nil,
      now_fun: fn -> ~U[2026-04-26 17:00:00Z] end
    }

    assert ^state = CommunicationRuntime.maybe_sync_child_terminal(state, "idle")
    refute_receive {:child_terminal_synced, _status, _attrs}
  end

  test "maybe_sync_child_terminal/2 syncs idle when no pending child calls and carries summary" do
    state = %{
      lemming_calls_mod: TrackingCalls,
      instance: %{id: "instance-1", test_pid: self(), pending_calls?: false},
      context_messages: [%{role: "assistant", content: "Final child answer"}],
      last_error: nil,
      now_fun: fn -> ~U[2026-04-26 17:01:00Z] end
    }

    assert ^state = CommunicationRuntime.maybe_sync_child_terminal(state, "idle")

    assert_receive {:child_terminal_synced, "idle", attrs}
    assert attrs.result_summary == "Final child answer"
    assert attrs.error_summary == nil
    assert attrs.completed_at == ~U[2026-04-26 17:01:00Z]
  end

  test "maybe_sync_child_terminal/2 syncs failed status regardless of pending manager calls" do
    state = %{
      lemming_calls_mod: TrackingCalls,
      instance: %{id: "instance-1", test_pid: self(), pending_calls?: true},
      context_messages: [%{role: "assistant", content: "Final child answer"}],
      last_error: "model timeout",
      now_fun: fn -> ~U[2026-04-26 17:02:00Z] end
    }

    assert ^state = CommunicationRuntime.maybe_sync_child_terminal(state, "failed")

    assert_receive {:child_terminal_synced, "failed", attrs}
    assert attrs.result_summary == nil
    assert attrs.error_summary == "model timeout"
    assert attrs.completed_at == ~U[2026-04-26 17:02:00Z]
  end
end
