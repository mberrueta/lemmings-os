defmodule LemmingsOs.LemmingInstances.Executor.RetryRuntime do
  @moduledoc """
  Retry/failure runtime orchestration for model-step errors.

  Keeps retry-count and terminal-failure branching explicit while delegating
  side effects through injected callbacks.
  """

  alias LemmingsOs.LemmingInstances.Executor.TransitionsData

  @type deps :: %{
          release_resource: (map() -> map()),
          cleanup_snapshot: (map() -> map()),
          transition_to: (map(), String.t(), map() -> map()),
          put_runtime_state: (map() -> map()),
          schedule_retry: (map() -> map())
        }

  @doc """
  Applies retry or terminal-failure flow for a model/runtime error reason.

  ## Examples

      iex> deps = %{
      ...>   release_resource: &Map.put(&1, :released?, true),
      ...>   cleanup_snapshot: &Map.put(&1, :snapshot_cleaned?, true),
      ...>   transition_to: fn state, status, _attrs -> Map.put(state, :status, status) end,
      ...>   put_runtime_state: &Map.put(&1, :persisted?, true),
      ...>   schedule_retry: &Map.put(&1, :retry_scheduled?, true)
      ...> }
      iex> state = %{retry_count: 0, max_retries: 2, now_fun: fn -> ~U[2026-04-26 20:00:00Z] end}
      iex> updated = LemmingsOs.LemmingInstances.Executor.RetryRuntime.handle_model_retry(state, :provider_error, deps)
      iex> {updated.status, updated.retry_count, updated.retry_scheduled?}
      {"retrying", 1, true}
  """
  @spec handle_model_retry(map(), term(), deps()) :: map()
  def handle_model_retry(state, reason, deps) when is_map(state) and is_map(deps) do
    next_retry = state.retry_count + 1
    error_message = TransitionsData.last_error_message(reason)
    internal_error_details = TransitionsData.internal_error_details(reason)

    if next_retry >= state.max_retries do
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> Map.put(:internal_error_details, internal_error_details)
      |> deps.release_resource.()
      |> deps.cleanup_snapshot.()
      |> deps.transition_to.("failed", %{stopped_at: state.now_fun.()})
      |> deps.put_runtime_state.()
    else
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> Map.put(:internal_error_details, internal_error_details)
      |> deps.transition_to.("retrying", %{})
      |> deps.put_runtime_state.()
      |> deps.schedule_retry.()
    end
  end
end
