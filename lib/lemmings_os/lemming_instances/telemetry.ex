defmodule LemmingsOs.LemmingInstances.Telemetry do
  @moduledoc """
  Shared runtime telemetry helpers for lemming instances.

  This module centralizes event emission so executor, scheduler, pool, and
  snapshot code can share a consistent metadata contract without allowing
  telemetry failures to affect runtime behavior.
  """

  @type measurements :: map()
  @type metadata :: map()

  @doc """
  Emits a telemetry event and swallows observer failures.
  """
  @spec execute([atom()], measurements(), metadata()) :: :ok
  def execute(event, measurements, metadata)
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  rescue
    _exception ->
      :ok
  catch
    _kind, _reason ->
      :ok
  end

  @doc """
  Builds full instance hierarchy metadata with stable keys.
  """
  @spec instance_metadata(map() | struct() | nil, map()) :: metadata()
  def instance_metadata(instance, extra \\ %{}) when is_map(extra) do
    %{
      world_id: fetch(instance, :world_id),
      city_id: fetch(instance, :city_id),
      department_id: fetch(instance, :department_id),
      lemming_id: fetch(instance, :lemming_id),
      instance_id: fetch(instance, :id) || fetch(instance, :instance_id),
      resource_key: Map.get(extra, :resource_key),
      reason: Map.get(extra, :reason)
    }
    |> Map.merge(extra)
  end

  @doc """
  Builds scheduler candidate metadata with the full hierarchy keys.
  """
  @spec candidate_metadata(map(), map()) :: metadata()
  def candidate_metadata(candidate, extra \\ %{}) when is_map(candidate) and is_map(extra) do
    %{
      world_id: fetch(candidate, :world_id),
      city_id: fetch(candidate, :city_id),
      department_id: fetch(candidate, :department_id),
      lemming_id: fetch(candidate, :lemming_id),
      instance_id: fetch(candidate, :instance_id),
      resource_key: fetch(candidate, :resource_key) || Map.get(extra, :resource_key),
      reason: Map.get(extra, :reason)
    }
    |> Map.merge(extra)
  end

  @doc """
  Builds resource-pool metadata with the required hierarchy keys.
  """
  @spec pool_metadata(map()) :: metadata()
  def pool_metadata(extra \\ %{}) when is_map(extra) do
    %{
      world_id: nil,
      city_id: nil,
      department_id: Map.get(extra, :department_id),
      lemming_id: nil,
      instance_id: nil,
      resource_key: Map.get(extra, :resource_key),
      reason: Map.get(extra, :reason)
    }
    |> Map.merge(extra)
  end

  @doc """
  Builds DETS snapshot metadata with the required hierarchy keys.
  """
  @spec dets_metadata(binary(), map()) :: metadata()
  def dets_metadata(instance_id, extra \\ %{}) when is_binary(instance_id) and is_map(extra) do
    %{
      world_id: nil,
      city_id: nil,
      department_id: nil,
      lemming_id: nil,
      instance_id: instance_id,
      resource_key: nil,
      reason: Map.get(extra, :reason)
    }
    |> Map.merge(extra)
  end

  @doc """
  Builds tool-execution metadata with full hierarchy and tool identity keys.
  """
  @spec tool_execution_metadata(map() | struct() | nil, map(), map()) :: metadata()
  def tool_execution_metadata(instance, tool_execution, extra \\ %{})
      when is_map(tool_execution) and is_map(extra) do
    instance
    |> instance_metadata(%{
      tool_name: fetch(tool_execution, :tool_name),
      tool_execution_id: fetch(tool_execution, :id),
      tool_status: fetch(tool_execution, :status),
      duration_ms: fetch(tool_execution, :duration_ms),
      reason: Map.get(extra, :reason)
    })
    |> Map.merge(extra)
  end

  @doc """
  Normalizes internal reasons into stable telemetry-friendly tokens.
  """
  @spec reason_token(term()) :: String.t() | nil
  def reason_token(nil), do: nil
  def reason_token(reason) when is_atom(reason), do: Atom.to_string(reason)
  def reason_token(reason) when is_binary(reason), do: reason
  def reason_token({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  def reason_token(_reason), do: "runtime_error"

  defp fetch(instance, key) when is_map(instance) do
    Map.get(instance, key) || Map.get(instance, Atom.to_string(key))
  end

  defp fetch(_instance, _key), do: nil
end
