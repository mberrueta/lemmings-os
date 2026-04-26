defmodule LemmingsOs.LemmingInstances.Executor.ToolStepRuntime do
  @moduledoc """
  Runtime orchestration for tool-call execution flow.

  This module routes tool-step progression (tool execution + post-tool
  branching) using explicit injected dependencies from `Executor`.

  It is an internal runtime helper. `Executor` remains the coordinator and
  process boundary.
  """

  alias LemmingsOs.ModelRuntime.Response

  @type execute_result :: {:ok, map(), map()} | {:error, term(), map()}
  @type post_tool_deps :: %{
          put_runtime_state: (map() -> map()),
          start_execution: (map() -> map()),
          handle_model_retry: (map(), term() -> map()),
          max_tool_iterations: (map() -> non_neg_integer())
        }
  @type execute_deps :: %{
          now_fun: (map() -> DateTime.t()),
          emit_tool_requested: (map(), String.t(), map() -> :ok),
          emit_tool_started: (map(), String.t(), String.t() | nil, map() -> :ok),
          emit_tool_rejected: (map(), String.t(), atom() -> :ok),
          append_tool_call_context: (map(), String.t(), map() -> map()),
          create_tool_execution: (map(), String.t(), map(), DateTime.t() ->
                                    {:ok, map(), map()} | {:error, term(), map()}),
          runtime_world: (map() -> {:ok, map()} | {:error, term()}),
          execute_tool_runtime: (map(), map(), String.t(), map() ->
                                   {:ok, map()} | {:error, term()}),
          persist_tool_outcome: (map(), map(), {:ok, map()} | {:error, term()}, DateTime.t() ->
                                   {:ok, map(), map()} | {:error, term(), map()}),
          normalize_tool_outcome_result: ({:ok, map(), map()} | {:error, term(), map()} ->
                                            execute_result())
        }

  @doc """
  Chooses the next runtime path after tool outcome persistence.

  - `tool_status == "ok"` starts finalization phase.
  - other statuses continue the tool loop with iteration controls.

  ## Examples

      iex> deps = %{
      ...>   put_runtime_state: & &1,
      ...>   start_execution: fn state -> Map.put(state, :started_execution?, true) end,
      ...>   handle_model_retry: fn state, reason -> Map.put(state, :retry_reason, reason) end,
      ...>   max_tool_iterations: fn _config -> 8 end
      ...> }
      iex> state = %{tool_iteration_count: 0, config_snapshot: %{}, finalization_context: %{tool_status: "ok"}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.ToolStepRuntime.continue_after_tool_outcome(state, deps)
      iex> {updated.phase, updated.tool_iteration_count, updated.started_execution?}
      {:finalizing, 1, true}
  """
  @spec continue_after_tool_outcome(map(), post_tool_deps()) :: map()
  def continue_after_tool_outcome(state, deps) when is_map(state) and is_map(deps) do
    case state.finalization_context do
      %{tool_status: "ok"} -> start_finalization_phase(state, deps)
      _finalization_context -> continue_tool_loop(state, deps)
    end
  end

  @doc """
  Executes a model-selected tool call using injected runtime callbacks.

  ## Examples

      iex> deps = %{
      ...>   now_fun: fn _state -> ~U[2026-04-26 18:00:00Z] end,
      ...>   emit_tool_requested: fn _state, _tool_name, _args -> :ok end,
      ...>   emit_tool_started: fn _state, _tool_name, _tool_execution_id, _args -> :ok end,
      ...>   emit_tool_rejected: fn _state, _tool_name, _reason -> :ok end,
      ...>   append_tool_call_context: fn state, _tool_name, _args -> state end,
      ...>   create_tool_execution: fn state, _tool_name, _args, _started_at -> {:ok, %{id: "tool-1"}, state} end,
      ...>   runtime_world: fn _state -> {:ok, %{id: "world-1"}} end,
      ...>   execute_tool_runtime: fn _state, _world, _tool_name, _args -> {:ok, %{summary: "ok"}} end,
      ...>   persist_tool_outcome: fn state, tool_execution, _runtime_result, _started_at -> {:ok, tool_execution, state} end,
      ...>   normalize_tool_outcome_result: fn
      ...>     {:ok, tool_execution, state} -> {:ok, state, tool_execution}
      ...>     {:error, reason, state} -> {:error, reason, state}
      ...>   end
      ...> }
      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :tool_call,
      ...>     tool_name: "web.fetch",
      ...>     tool_args: %{"url" => "https://example.com"},
      ...>     provider: "fake",
      ...>     model: "fake-model",
      ...>     raw: %{}
      ...>   )
      iex> state = %{context_messages: []}
      iex> {:ok, _next_state, %{id: "tool-1"}} =
      ...>   LemmingsOs.LemmingInstances.Executor.ToolStepRuntime.execute_tool_call(state, response, deps)
  """
  @spec execute_tool_call(map(), Response.t() | term(), execute_deps()) :: execute_result()
  def execute_tool_call(
        state,
        %Response{tool_name: tool_name, tool_args: tool_args},
        deps
      )
      when is_map(state) and is_binary(tool_name) and is_map(tool_args) and is_map(deps) do
    started_at = deps.now_fun.(state)
    _ = emit_tool_event(deps, :emit_tool_requested, state, tool_name, tool_args)
    state = deps.append_tool_call_context.(state, tool_name, tool_args)

    with {:ok, tool_execution, state} <-
           deps.create_tool_execution.(state, tool_name, tool_args, started_at),
         {:ok, world} <- deps.runtime_world.(state) do
      _ = emit_tool_started(deps, state, tool_name, Map.get(tool_execution, :id), tool_args)

      state
      |> deps.persist_tool_outcome.(
        tool_execution,
        deps.execute_tool_runtime.(state, world, tool_name, tool_args),
        started_at
      )
      |> deps.normalize_tool_outcome_result.()
    else
      {:error, reason, next_state} ->
        _ = emit_tool_rejection(deps, next_state, tool_name, reason)
        {:error, reason, next_state}

      {:error, reason} ->
        _ = emit_tool_rejection(deps, state, tool_name, reason)
        {:error, reason, state}
    end
  end

  def execute_tool_call(state, _response, _deps), do: {:error, :invalid_structured_output, state}

  @doc """
  Starts finalization phase after a successful tool execution.

  ## Examples

      iex> deps = %{
      ...>   put_runtime_state: & &1,
      ...>   start_execution: fn state -> Map.put(state, :started_execution?, true) end,
      ...>   handle_model_retry: fn state, _reason -> state end,
      ...>   max_tool_iterations: fn _config -> 8 end
      ...> }
      iex> state = %{tool_iteration_count: 1, phase: :action_selection, retry_count: 2, last_error: "boom", internal_error_details: %{kind: :x}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.ToolStepRuntime.start_finalization_phase(state, deps)
      iex> {updated.phase, updated.tool_iteration_count, updated.retry_count, updated.last_error}
      {:finalizing, 2, 0, nil}
  """
  @spec start_finalization_phase(map(), post_tool_deps()) :: map()
  def start_finalization_phase(state, deps) when is_map(state) and is_map(deps) do
    next_iteration_count = state.tool_iteration_count + 1

    state
    |> Map.put(:phase, :finalizing)
    |> Map.put(:tool_iteration_count, next_iteration_count)
    |> Map.put(:retry_count, 0)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> deps.put_runtime_state.()
    |> deps.start_execution.()
  end

  @doc """
  Continues tool loop by incrementing iteration count and enforcing limits.

  ## Examples

      iex> deps = %{
      ...>   put_runtime_state: & &1,
      ...>   start_execution: fn state -> Map.put(state, :started_execution?, true) end,
      ...>   handle_model_retry: fn state, reason -> Map.put(state, :retry_reason, reason) end,
      ...>   max_tool_iterations: fn _config -> 2 end
      ...> }
      iex> state = %{tool_iteration_count: 0, config_snapshot: %{}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.ToolStepRuntime.continue_tool_loop(state, deps)
      iex> {updated.tool_iteration_count, updated.started_execution?}
      {1, true}
  """
  @spec continue_tool_loop(map(), post_tool_deps()) :: map()
  def continue_tool_loop(state, deps) when is_map(state) and is_map(deps) do
    next_iteration_count = state.tool_iteration_count + 1
    continue_tool_loop(state, next_iteration_count, deps)
  end

  defp continue_tool_loop(state, next_iteration_count, deps)
       when is_map(state) and is_map(deps) do
    if next_iteration_count >= deps.max_tool_iterations.(state.config_snapshot) do
      deps.handle_model_retry.(
        %{state | tool_iteration_count: next_iteration_count},
        :tool_iteration_limit_reached
      )
    else
      state
      |> Map.put(:tool_iteration_count, next_iteration_count)
      |> deps.put_runtime_state.()
      |> deps.start_execution.()
    end
  end

  defp emit_tool_event(deps, key, state, tool_name, tool_args) do
    Map.get(deps, key, fn _state, _tool_name, _tool_args -> :ok end).(state, tool_name, tool_args)
  end

  defp emit_tool_rejection(deps, state, tool_name, reason) do
    Map.get(deps, :emit_tool_rejected, fn _state, _tool_name, _reason -> :ok end).(
      state,
      tool_name,
      reason
    )
  end

  defp emit_tool_started(deps, state, tool_name, tool_execution_id, tool_args) do
    Map.get(deps, :emit_tool_started, fn _state, _tool_name, _tool_execution_id, _tool_args ->
      :ok
    end).(state, tool_name, tool_execution_id, tool_args)
  end
end
