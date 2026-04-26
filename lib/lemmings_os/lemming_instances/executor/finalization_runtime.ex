defmodule LemmingsOs.LemmingInstances.Executor.FinalizationRuntime do
  @moduledoc """
  Runtime orchestration for finalization repair and terminal-failure flows.

  This module performs narrow finalization side-effect chains via injected
  dependencies (persist, cleanup, transition), while `Executor` owns
  coordination.

  It is an internal runtime helper, not a public control-plane API.
  """

  alias LemmingsOs.LemmingInstances.Executor.TransitionsData

  @type deps :: %{
          put_runtime_state: (map() -> map()),
          release_resource: (map() -> map()),
          cleanup_snapshot: (map() -> map()),
          transition_to: (map(), String.t(), map() -> map())
        }

  @doc """
  Schedules one finalization repair attempt and persists runtime state.

  ## Examples

      iex> deps = %{put_runtime_state: &Map.put(&1, :persisted?, true), release_resource: & &1, cleanup_snapshot: & &1, transition_to: fn state, _status, _attrs -> state end}
      iex> state = %{finalization_repair_attempted?: false, last_error: "boom", internal_error_details: %{kind: :x}, finalization_context: %{}}
      iex> updated = LemmingsOs.LemmingInstances.Executor.FinalizationRuntime.schedule_repair(state, :empty_final_response, deps)
      iex> {updated.finalization_repair_attempted?, updated.last_error, updated.internal_error_details, updated.persisted?}
      {true, nil, nil, true}
  """
  @spec schedule_repair(map(), term(), deps()) :: map()
  def schedule_repair(state, reason, deps) when is_map(state) and is_map(deps) do
    state
    |> Map.put(:finalization_repair_attempted?, true)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> put_in([:finalization_context, :repair_reason], inspect(reason))
    |> deps.put_runtime_state.()
  end

  @doc """
  Fails immediately without retry and performs cleanup + transition.

  ## Examples

      iex> deps = %{
      ...>   put_runtime_state: &Map.put(&1, :persisted?, true),
      ...>   release_resource: &Map.put(&1, :released?, true),
      ...>   cleanup_snapshot: &Map.put(&1, :snapshot_cleaned?, true),
      ...>   transition_to: fn state, status, attrs -> state |> Map.put(:status, status) |> Map.put(:stopped_at, attrs.stopped_at) end
      ...> }
      iex> state = %{max_retries: 3, now_fun: fn -> ~U[2026-04-26 19:00:00Z] end}
      iex> updated = LemmingsOs.LemmingInstances.Executor.FinalizationRuntime.fail_without_retry(state, :provider_error, deps)
      iex> {updated.status, updated.retry_count, updated.released?, updated.snapshot_cleaned?, updated.persisted?}
      {"failed", 3, true, true, true}
  """
  @spec fail_without_retry(map(), term(), deps()) :: map()
  def fail_without_retry(state, reason, deps) when is_map(state) and is_map(deps) do
    state
    |> Map.put(:retry_count, state.max_retries)
    |> Map.put(:last_error, TransitionsData.last_error_message(reason))
    |> Map.put(:internal_error_details, TransitionsData.internal_error_details(reason))
    |> deps.release_resource.()
    |> deps.cleanup_snapshot.()
    |> deps.transition_to.("failed", %{stopped_at: state.now_fun.()})
    |> deps.put_runtime_state.()
  end
end
