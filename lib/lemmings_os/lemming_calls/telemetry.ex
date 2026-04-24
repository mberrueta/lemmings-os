defmodule LemmingsOs.LemmingCalls.Telemetry do
  @moduledoc """
  Shared observability helpers for durable lemming call lifecycle events.
  """

  alias LemmingsOs.LemmingCalls.LemmingCall

  @type measurements :: map()
  @type metadata :: map()

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

  @spec call_metadata(LemmingCall.t() | map() | nil, map()) :: metadata()
  def call_metadata(call, extra \\ %{}) when is_map(extra) do
    %{
      world_id: fetch(call, :world_id),
      city_id: fetch(call, :city_id),
      department_id: fetch(call, :caller_department_id),
      caller_department_id: fetch(call, :caller_department_id),
      callee_department_id: fetch(call, :callee_department_id),
      caller_instance_id: fetch(call, :caller_instance_id),
      callee_instance_id: fetch(call, :callee_instance_id),
      lemming_call_id: fetch(call, :id) || Map.get(extra, :lemming_call_id),
      status: fetch(call, :status),
      recovery_status: fetch(call, :recovery_status),
      previous_call_id: fetch(call, :previous_call_id),
      root_call_id: fetch(call, :root_call_id),
      reason: Map.get(extra, :reason)
    }
    |> Map.merge(extra)
  end

  @spec duration_ms(LemmingCall.t() | map() | nil) :: non_neg_integer()
  def duration_ms(call) do
    started_at = fetch(call, :started_at)
    completed_at = fetch(call, :completed_at)

    case {started_at, completed_at} do
      {%DateTime{} = started_at, %DateTime{} = completed_at} ->
        max(DateTime.diff(completed_at, started_at, :millisecond), 0)

      _ ->
        0
    end
  end

  defp fetch(call, key) when is_map(call) do
    Map.get(call, key) || Map.get(call, Atom.to_string(key))
  end

  defp fetch(_call, _key), do: nil
end
