defmodule LemmingsOs.LemmingInstances.Executor.CommunicationRuntime do
  @moduledoc """
  Runtime orchestration for multi-lemming collaboration steps.

  This module executes narrow collaboration runtime flows (delegation, resume,
  child-terminal sync) through explicit dependency callbacks injected by
  `Executor`.

  It is an internal runtime helper. `Executor` remains the only
  GenServer/process boundary.
  """

  alias LemmingsOs.LemmingInstances.Executor.Communication
  alias LemmingsOs.LemmingInstances.Executor.ContextMessages

  @type continue_deps :: %{
          release_resource: (map() -> map()),
          put_runtime_state: (map() -> map()),
          transition_to: (map(), String.t(), map() -> map())
        }
  @type resume_deps :: %{
          emit_resume_requested: (map(), map() -> :ok),
          emit_resume_started: (map(), map() -> :ok),
          emit_resume_rejected: (map(), atom() -> :ok),
          emit_resume_completed: (map(), map() -> :ok),
          cancel_idle_timer: (map() -> map()),
          transition_to: (map(), String.t(), map() -> map()),
          put_runtime_state: (map() -> map()),
          start_execution: (map() -> map())
        }
  @type execute_result :: {:ok, map(), map()} | {:error, term(), map()}

  @doc """
  Resumes a paused manager execution after a delegated call reaches terminal state.

  Emits runtime resume events via injected callbacks while preserving executor
  return-shapes.

  ## Examples

      iex> deps = %{
      ...>   emit_resume_requested: fn _state, _call -> :ok end,
      ...>   emit_resume_started: fn _state, _call -> :ok end,
      ...>   emit_resume_rejected: fn _state, _reason -> :ok end,
      ...>   emit_resume_completed: fn _state, _call -> :ok end,
      ...>   cancel_idle_timer: & &1,
      ...>   transition_to: fn state, status, _attrs -> Map.put(state, :status, status) end,
      ...>   put_runtime_state: & &1,
      ...>   start_execution: fn state -> Map.put(state, :started_execution?, true) end
      ...> }
      iex> state = %{status: "idle", current_item: %{id: "item-1"}, model_task_pid: nil, context_messages: [], retry_count: 2, last_error: "boom", internal_error_details: %{kind: :x}}
      iex> call = %{status: "completed", result_summary: "Done"}
      iex> {:ok, updated} = LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.resume_after_lemming_call(state, call, deps)
      iex> {updated.status, updated.started_execution?, updated.retry_count, updated.last_error}
      {"processing", true, 0, nil}
  """
  @spec resume_after_lemming_call(map(), map(), resume_deps()) ::
          {:ok, map()} | {{:error, :terminal_instance | :resume_not_possible}, map()}
  def resume_after_lemming_call(state, call, deps)
      when is_map(state) and is_map(call) and is_map(deps) do
    _ = emit_resume_event(deps, :emit_resume_requested, state, call)

    case Communication.resume_rejection_reason(
           state.status,
           state.current_item,
           state.model_task_pid
         ) do
      nil ->
        _ = emit_resume_event(deps, :emit_resume_started, state, call)

        next_state =
          state
          |> Communication.prepare_state_for_resume(call)
          |> deps.cancel_idle_timer.()
          |> deps.transition_to.("processing", %{stopped_at: nil})
          |> deps.put_runtime_state.()
          |> deps.start_execution.()

        _ = deps.emit_resume_completed.(next_state, call)
        {:ok, next_state}

      reason ->
        _ = emit_resume_rejection(deps, state, reason)
        {{:error, reason}, state}
    end
  end

  @doc """
  Executes delegated-call request flow using runtime state and response payload.

  ## Examples

      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :lemming_call,
      ...>     lemming_target: "ops-worker",
      ...>     lemming_request: "Draft child notes",
      ...>     continue_call_id: nil,
      ...>     provider: "fake",
      ...>     model: "fake-model",
      ...>     raw: %{}
      ...>   )
      iex> state = %{instance: %{id: "instance-1", config_snapshot: %{}}, config_snapshot: %{}, context_messages: [], lemming_calls_mod: nil}
      iex> {:error, :lemming_call_unavailable, _state} =
      ...>   LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.execute_lemming_call(state, response)
  """
  @spec execute_lemming_call(map(), LemmingsOs.ModelRuntime.Response.t()) :: execute_result()
  def execute_lemming_call(state, %LemmingsOs.ModelRuntime.Response{} = response)
      when is_map(state) do
    instance = instance_with_runtime_snapshot(state.instance, state.config_snapshot)
    attrs = Communication.lemming_call_attrs(response)
    state = append_call_request_context(state, attrs)

    case Communication.request_call(state.lemming_calls_mod, instance, response) do
      {:ok, _attrs, call} -> {:ok, state, call}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc """
  Builds an instance struct/map carrying the latest runtime config snapshot.

  ## Examples

      iex> instance = %{id: "instance-1", config_snapshot: %{model: "old"}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.instance_with_runtime_snapshot(instance, %{model: "new"})
      iex> updated.config_snapshot
      %{model: "new"}
  """
  @spec instance_with_runtime_snapshot(map(), map()) :: map()
  def instance_with_runtime_snapshot(instance, config_snapshot)
      when is_map(instance) and is_map(config_snapshot) do
    %{instance | config_snapshot: config_snapshot}
  end

  @doc """
  Builds model config snapshot augmented with available lemming-call targets.

  ## Examples

      iex> base_config = %{model: "fake-model"}
      iex> instance = %{id: "instance-1", config_snapshot: base_config}
      iex> LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.model_config_snapshot(base_config, nil, instance)
      %{model: "fake-model"}
  """
  @spec model_config_snapshot(map(), module() | nil, map()) :: map()
  def model_config_snapshot(config_snapshot, lemming_calls_mod, instance)
      when is_map(config_snapshot) and is_map(instance) do
    targets = Communication.available_targets(lemming_calls_mod, instance)
    Communication.put_targets_in_config(config_snapshot, targets)
  end

  @doc """
  Appends the delegated-call request context message into state history.

  ## Examples

      iex> state = %{context_messages: [%{role: "user", content: "Delegate this"}]}
      iex> attrs = %{target: "ops-worker", request: "Draft child notes", continue_call_id: nil}
      iex> updated = LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.append_call_request_context(state, attrs)
      iex> length(updated.context_messages)
      2
      iex> String.contains?(List.last(updated.context_messages).content, "Assistant requested lemming_call")
      true
  """
  @spec append_call_request_context(map(), map()) :: map()
  def append_call_request_context(state, attrs) when is_map(state) and is_map(attrs) do
    lemming_call_message = ContextMessages.lemming_call_message(attrs)
    %{state | context_messages: state.context_messages ++ [lemming_call_message]}
  end

  @doc """
  Continues runtime flow after a delegated call is created.

  Releases the current resource, clears transient errors, persists runtime
  state, transitions to idle, and persists runtime state again.

  ## Examples

      iex> deps = %{
      ...>   release_resource: fn state -> Map.put(state, :released?, true) end,
      ...>   put_runtime_state: fn state -> Map.update(state, :persist_count, 1, &(&1 + 1)) end,
      ...>   transition_to: fn state, status, attrs -> state |> Map.put(:status, status) |> Map.put(:stopped_at, attrs.stopped_at) end
      ...> }
      iex> state = %{status: "processing", persist_count: 0, last_error: "boom", internal_error_details: %{kind: :x}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.continue_after_lemming_call(state, deps)
      iex> {updated.status, updated.released?, updated.persist_count, updated.last_error, updated.internal_error_details}
      {"idle", true, 2, nil, nil}
  """
  @spec continue_after_lemming_call(map(), continue_deps()) :: map()
  def continue_after_lemming_call(state, deps) when is_map(state) and is_map(deps) do
    state
    |> deps.release_resource.()
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> deps.put_runtime_state.()
    |> deps.transition_to.("idle", %{stopped_at: nil})
    |> deps.put_runtime_state.()
  end

  @doc """
  Synchronizes child terminal status when runtime rules require it.

  Returns the original `state` map (updated externally by the executor).

  ## Examples

      iex> state = %{status: "idle", lemming_calls_mod: nil, instance: %{}, context_messages: [], last_error: nil, now_fun: fn -> ~U[2026-04-26 16:00:00Z] end}
      iex> updated = LemmingsOs.LemmingInstances.Executor.CommunicationRuntime.maybe_sync_child_terminal(state, "processing")
      iex> updated.status
      "idle"
  """
  @spec maybe_sync_child_terminal(map(), String.t()) :: map()
  def maybe_sync_child_terminal(state, status) when is_map(state) and is_binary(status) do
    pending? = Communication.pending_manager_calls?(state.lemming_calls_mod, state.instance)

    case Communication.child_terminal_sync_decision(status, pending?) do
      :sync ->
        attrs =
          Communication.child_terminal_sync_attrs(
            status,
            state.context_messages,
            state.last_error,
            state.now_fun.()
          )

        _ =
          Communication.sync_child_instance_terminal(
            state.lemming_calls_mod,
            state.instance,
            status,
            attrs
          )

        state

      :skip ->
        state
    end
  end

  defp emit_resume_event(deps, key, state, call) do
    Map.get(deps, key, fn _state, _call -> :ok end).(state, call)
  end

  defp emit_resume_rejection(deps, state, reason) do
    Map.get(deps, :emit_resume_rejected, fn _state, _reason -> :ok end).(state, reason)
  end
end
