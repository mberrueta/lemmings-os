defmodule LemmingsOs.LemmingInstances.Executor.ToolStepRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.ToolStepRuntime
  alias LemmingsOs.ModelRuntime.Response

  doctest ToolStepRuntime

  test "execute_tool_call/3 runs success path and returns normalized result" do
    deps = %{
      now_fun: fn _state -> ~U[2026-04-26 18:05:00Z] end,
      emit_tool_requested: fn _state, _tool_name, _args -> :ok end,
      emit_tool_started: fn _state, _tool_name, _tool_execution_id, _args -> :ok end,
      emit_tool_rejected: fn _state, _tool_name, _reason -> :ok end,
      append_tool_call_context: fn state, _tool_name, _args ->
        Map.put(state, :context_appended?, true)
      end,
      create_tool_execution: fn state, _tool_name, _args, _started_at ->
        {:ok, %{id: "tool-1"}, state}
      end,
      runtime_world: fn _state -> {:ok, %{id: "world-1"}} end,
      execute_tool_runtime: fn _state, _world, _tool_name, _args -> {:ok, %{summary: "ok"}} end,
      persist_tool_outcome: fn state, tool_execution, _runtime_result, _started_at ->
        {:ok, tool_execution, state}
      end,
      normalize_tool_outcome_result: fn
        {:ok, tool_execution, state} -> {:ok, state, tool_execution}
        {:error, reason, state} -> {:error, reason, state}
      end
    }

    response =
      Response.new(
        action: :tool_call,
        tool_name: "web.fetch",
        tool_args: %{"url" => "https://example.com"},
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    assert {:ok, next_state, %{id: "tool-1"}} =
             ToolStepRuntime.execute_tool_call(%{context_messages: []}, response, deps)

    assert next_state.context_appended? == true
  end

  test "execute_tool_call/3 normalizes runtime world failure into executor-shaped error" do
    deps = %{
      now_fun: fn _state -> ~U[2026-04-26 18:06:00Z] end,
      emit_tool_requested: fn _state, _tool_name, _args -> :ok end,
      emit_tool_started: fn _state, _tool_name, _tool_execution_id, _args -> :ok end,
      emit_tool_rejected: fn _state, _tool_name, _reason -> :ok end,
      append_tool_call_context: fn state, _tool_name, _args -> state end,
      create_tool_execution: fn state, _tool_name, _args, _started_at ->
        {:ok, %{id: "tool-1"}, state}
      end,
      runtime_world: fn _state -> {:error, :world_missing} end,
      execute_tool_runtime: fn _state, _world, _tool_name, _args -> {:ok, %{summary: "ok"}} end,
      persist_tool_outcome: fn state, tool_execution, _runtime_result, _started_at ->
        {:ok, tool_execution, state}
      end,
      normalize_tool_outcome_result: fn
        {:ok, tool_execution, state} -> {:ok, state, tool_execution}
        {:error, reason, state} -> {:error, reason, state}
      end
    }

    response =
      Response.new(
        action: :tool_call,
        tool_name: "web.fetch",
        tool_args: %{"url" => "https://example.com"},
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    state = %{context_messages: []}

    assert {:error, :world_missing, ^state} =
             ToolStepRuntime.execute_tool_call(state, response, deps)
  end

  test "execute_tool_call/3 returns invalid_structured_output for non-tool responses" do
    deps = %{
      now_fun: fn _state -> ~U[2026-04-26 18:07:00Z] end,
      emit_tool_requested: fn _state, _tool_name, _args -> :ok end,
      emit_tool_started: fn _state, _tool_name, _tool_execution_id, _args -> :ok end,
      emit_tool_rejected: fn _state, _tool_name, _reason -> :ok end,
      append_tool_call_context: fn state, _tool_name, _args -> state end,
      create_tool_execution: fn state, _tool_name, _args, _started_at ->
        {:ok, %{id: "tool-1"}, state}
      end,
      runtime_world: fn _state -> {:ok, %{id: "world-1"}} end,
      execute_tool_runtime: fn _state, _world, _tool_name, _args -> {:ok, %{summary: "ok"}} end,
      persist_tool_outcome: fn state, tool_execution, _runtime_result, _started_at ->
        {:ok, tool_execution, state}
      end,
      normalize_tool_outcome_result: fn
        {:ok, tool_execution, state} -> {:ok, state, tool_execution}
        {:error, reason, state} -> {:error, reason, state}
      end
    }

    response =
      Response.new(
        action: :reply,
        reply: "done",
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    state = %{context_messages: []}

    assert {:error, :invalid_structured_output, ^state} =
             ToolStepRuntime.execute_tool_call(state, response, deps)
  end

  test "execute_tool_call/3 emits rejected result when creation fails before start" do
    deps = %{
      now_fun: fn _state -> ~U[2026-04-26 18:07:30Z] end,
      emit_tool_requested: fn _state, _tool_name, _args -> :ok end,
      emit_tool_started: fn _state, _tool_name, _tool_execution_id, _args -> :ok end,
      emit_tool_rejected: fn _state, _tool_name, _reason -> :ok end,
      append_tool_call_context: fn state, _tool_name, _args -> state end,
      create_tool_execution: fn state, _tool_name, _args, _started_at ->
        {:error, :tool_execution_unavailable, Map.put(state, :rejected?, true)}
      end,
      runtime_world: fn _state -> {:ok, %{id: "world-1"}} end,
      execute_tool_runtime: fn _state, _world, _tool_name, _args -> {:ok, %{summary: "ok"}} end,
      persist_tool_outcome: fn state, tool_execution, _runtime_result, _started_at ->
        {:ok, tool_execution, state}
      end,
      normalize_tool_outcome_result: fn
        {:ok, tool_execution, state} -> {:ok, state, tool_execution}
        {:error, reason, state} -> {:error, reason, state}
      end
    }

    response =
      Response.new(
        action: :tool_call,
        tool_name: "web.fetch",
        tool_args: %{"url" => "https://example.com"},
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    state = %{context_messages: []}

    assert {:error, :tool_execution_unavailable, rejected_state} =
             ToolStepRuntime.execute_tool_call(state, response, deps)

    assert rejected_state.rejected? == true
  end

  test "continue_after_tool_outcome/2 routes to finalization when tool status is ok" do
    deps = %{
      put_runtime_state: &Map.put(&1, :persisted?, true),
      start_execution: &Map.put(&1, :started_execution?, true),
      handle_model_retry: fn state, reason -> Map.put(state, :retry_reason, reason) end,
      max_tool_iterations: fn _config -> 8 end
    }

    state = %{
      tool_iteration_count: 0,
      config_snapshot: %{},
      finalization_context: %{tool_status: "ok"},
      phase: :action_selection,
      retry_count: 2,
      last_error: "boom",
      internal_error_details: %{kind: :x}
    }

    updated = ToolStepRuntime.continue_after_tool_outcome(state, deps)

    assert updated.phase == :finalizing
    assert updated.tool_iteration_count == 1
    assert updated.retry_count == 0
    assert updated.last_error == nil
    assert updated.internal_error_details == nil
    assert updated.persisted? == true
    assert updated.started_execution? == true
  end

  test "continue_tool_loop/2 retries when iteration limit is reached" do
    deps = %{
      put_runtime_state: &Map.put(&1, :persisted?, true),
      start_execution: &Map.put(&1, :started_execution?, true),
      handle_model_retry: fn state, reason -> Map.put(state, :retry_reason, reason) end,
      max_tool_iterations: fn _config -> 1 end
    }

    state = %{tool_iteration_count: 0, config_snapshot: %{}}

    updated = ToolStepRuntime.continue_tool_loop(state, deps)

    assert updated.tool_iteration_count == 1
    assert updated.retry_reason == :tool_iteration_limit_reached
    refute Map.get(updated, :started_execution?, false)
  end
end
