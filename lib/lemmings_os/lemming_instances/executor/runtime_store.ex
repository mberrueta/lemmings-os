defmodule LemmingsOs.LemmingInstances.Executor.RuntimeStore do
  @moduledoc """
  Runtime-state persistence and snapshot helpers for executor state maps.
  """

  @doc """
  Writes runtime state into ETS (directly or through injected `ets_mod`).
  """
  @spec put_runtime_state(map(), map(), atom()) :: map()
  def put_runtime_state(
        %{ets_mod: nil, instance_id: instance_id} = state,
        runtime_state,
        runtime_table
      )
      when is_atom(runtime_table) do
    _ = :ets.insert(runtime_table, {instance_id, runtime_state})
    state
  end

  def put_runtime_state(
        %{ets_mod: ets_mod, instance_id: instance_id} = state,
        runtime_state,
        runtime_table
      )
      when is_atom(runtime_table) and is_atom(ets_mod) do
    with true <- function_exported?(ets_mod, :put, 2) do
      _ = ets_mod.put(instance_id, runtime_state)
    end

    state
  end

  @doc """
  Stores best-effort DETS snapshots when a `dets_mod` implementation is present.
  """
  @spec snapshot_on_idle(map(), map()) :: map()
  def snapshot_on_idle(%{dets_mod: nil} = state, _runtime_state), do: state

  def snapshot_on_idle(%{dets_mod: dets_mod, instance_id: instance_id} = state, runtime_state)
      when is_atom(dets_mod) do
    _ = dispatch_snapshot(instance_id, runtime_state, dets_mod)
    state
  end

  @doc """
  Deletes persisted idle snapshot state when available.
  """
  @spec cleanup_snapshot(map()) :: map()
  def cleanup_snapshot(%{dets_mod: nil} = state), do: state

  def cleanup_snapshot(%{dets_mod: dets_mod, instance_id: instance_id} = state)
      when is_atom(dets_mod) do
    with true <- function_exported?(dets_mod, :delete, 1) do
      _ = dets_mod.delete(instance_id)
    end

    state
  end

  @doc """
  Cleans up active runtime state from ETS and DETS backends.
  """
  @spec cleanup_runtime(map(), atom()) :: map()
  def cleanup_runtime(state, runtime_table) when is_atom(runtime_table) do
    _ = delete_ets_state(state, runtime_table)
    _ = delete_dets_state(state)

    state
  end

  defp dispatch_snapshot(instance_id, runtime_state, dets_mod) when is_atom(dets_mod) do
    case snapshot_strategy(dets_mod) do
      :async ->
        _ = dets_mod.snapshot_async(instance_id, runtime_state)

      :sync ->
        _ =
          Task.start(fn ->
            _ = dets_mod.snapshot(instance_id, runtime_state)
          end)

      :none ->
        :ok
    end
  end

  defp snapshot_strategy(dets_mod) when is_atom(dets_mod) do
    cond do
      function_exported?(dets_mod, :snapshot_async, 2) -> :async
      function_exported?(dets_mod, :snapshot, 2) -> :sync
      true -> :none
    end
  end

  defp delete_ets_state(%{ets_mod: nil, instance_id: instance_id}, runtime_table) do
    _ = :ets.delete(runtime_table, instance_id)
  end

  defp delete_ets_state(%{ets_mod: ets_mod, instance_id: instance_id}, _runtime_table)
       when is_atom(ets_mod) do
    with true <- function_exported?(ets_mod, :delete, 1) do
      _ = ets_mod.delete(instance_id)
    end
  end

  defp delete_dets_state(%{dets_mod: nil}), do: :ok

  defp delete_dets_state(%{dets_mod: dets_mod, instance_id: instance_id})
       when is_atom(dets_mod) do
    with true <- function_exported?(dets_mod, :delete, 1) do
      _ = dets_mod.delete(instance_id)
    end
  end
end
