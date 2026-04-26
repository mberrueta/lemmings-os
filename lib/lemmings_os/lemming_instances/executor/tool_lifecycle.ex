defmodule LemmingsOs.LemmingInstances.Executor.ToolLifecycle do
  @moduledoc """
  Tool execution normalization and observability helpers.
  """

  require Logger

  alias LemmingsOs.LemmingInstances.Telemetry
  alias LemmingsOs.Runtime.ActivityLog

  @doc """
  Normalizes runtime tool errors into persisted error shape.
  """
  @spec normalize_tool_error(term()) :: %{code: String.t(), message: String.t(), details: map()}
  def normalize_tool_error(%{code: code, message: message} = error)
      when is_binary(code) and is_binary(message) do
    %{code: code, message: message, details: Map.get(error, :details, %{})}
  end

  def normalize_tool_error(other) do
    %{
      code: "tool.runtime.error",
      message: "Tool execution failed",
      details: %{reason: inspect(other)}
    }
  end

  @doc """
  Emits structured logs for tool lifecycle phases.
  """
  @spec log_tool_lifecycle(map(), :started | :completed | :failed, map()) :: :ok
  def log_tool_lifecycle(state, :started, tool_execution) do
    Logger.info("executor tool execution started",
      event: "instance.executor.tool_execution.started",
      operation: tool_execution.tool_name,
      status: tool_execution.status,
      instance_id: Map.get(state, :instance_id),
      lemming_id: map_field(Map.get(state, :instance), :lemming_id),
      world_id: map_field(Map.get(state, :instance), :world_id),
      city_id: map_field(Map.get(state, :instance), :city_id),
      department_id: Map.get(state, :department_id),
      current_item_id: current_item_id(Map.get(state, :current_item))
    )

    :ok
  end

  def log_tool_lifecycle(state, :completed, tool_execution) do
    Logger.info("executor tool execution completed",
      event: "instance.executor.tool_execution.completed",
      operation: tool_execution.tool_name,
      status: tool_execution.status,
      instance_id: Map.get(state, :instance_id),
      lemming_id: map_field(Map.get(state, :instance), :lemming_id),
      world_id: map_field(Map.get(state, :instance), :world_id),
      city_id: map_field(Map.get(state, :instance), :city_id),
      department_id: Map.get(state, :department_id),
      current_item_id: current_item_id(Map.get(state, :current_item))
    )

    :ok
  end

  def log_tool_lifecycle(state, :failed, tool_execution) do
    Logger.warning("executor tool execution failed",
      event: "instance.executor.tool_execution.failed",
      operation: tool_execution.tool_name,
      status: tool_execution.status,
      reason: tool_error_reason(tool_execution.error),
      instance_id: Map.get(state, :instance_id),
      lemming_id: map_field(Map.get(state, :instance), :lemming_id),
      world_id: map_field(Map.get(state, :instance), :world_id),
      city_id: map_field(Map.get(state, :instance), :city_id),
      department_id: Map.get(state, :department_id),
      current_item_id: current_item_id(Map.get(state, :current_item))
    )

    :ok
  end

  @doc """
  Emits telemetry events for tool lifecycle phases.
  """
  @spec emit_tool_telemetry(map(), :started | :completed | :failed, map()) :: :ok
  def emit_tool_telemetry(state, :started, tool_execution) do
    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :tool_execution, :started],
        %{count: 1},
        Telemetry.tool_execution_metadata(
          Map.get(state, :instance),
          tool_execution,
          %{instance_id: Map.get(state, :instance_id)}
        )
      )

    :ok
  end

  def emit_tool_telemetry(state, :completed, tool_execution) do
    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :tool_execution, :completed],
        %{count: 1, duration_ms: tool_execution.duration_ms || 0},
        Telemetry.tool_execution_metadata(
          Map.get(state, :instance),
          tool_execution,
          %{instance_id: Map.get(state, :instance_id)}
        )
      )

    :ok
  end

  def emit_tool_telemetry(state, :failed, tool_execution) do
    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :tool_execution, :failed],
        %{count: 1, duration_ms: tool_execution.duration_ms || 0},
        Telemetry.tool_execution_metadata(
          Map.get(state, :instance),
          tool_execution,
          %{
            instance_id: Map.get(state, :instance_id),
            reason: tool_error_reason(tool_execution.error)
          }
        )
      )

    :ok
  end

  @doc """
  Records runtime activity log entries for tool lifecycle phases.
  """
  @spec record_tool_activity(atom(), map(), atom(), map()) :: :ok
  def record_tool_activity(type, state, phase, tool_execution) do
    _ =
      ActivityLog.record(type, "tool_execution", "Tool #{phase}", %{
        instance_id: Map.get(state, :instance_id),
        lemming_id: map_field(Map.get(state, :instance), :lemming_id),
        world_id: map_field(Map.get(state, :instance), :world_id),
        city_id: map_field(Map.get(state, :instance), :city_id),
        department_id: Map.get(state, :department_id),
        tool_execution_id: tool_execution.id,
        tool_name: tool_execution.tool_name,
        status: tool_execution.status,
        reason: tool_error_reason(tool_execution.error)
      })

    :ok
  end

  defp tool_error_reason(%{"code" => code}) when is_binary(code), do: code
  defp tool_error_reason(%{code: code}) when is_binary(code), do: code
  defp tool_error_reason(_error), do: nil

  defp current_item_id(%{id: id}) when is_binary(id), do: id
  defp current_item_id(_current_item), do: nil

  defp map_field(map, field) when is_map(map) do
    Map.get(map, field) || Map.get(map, Atom.to_string(field))
  end

  defp map_field(_map, _field), do: nil
end
