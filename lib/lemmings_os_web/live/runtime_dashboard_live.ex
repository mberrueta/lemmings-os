defmodule LemmingsOsWeb.RuntimeDashboardLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Helpers
  alias LemmingsOs.Runtime.Status

  @refresh_interval 10_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_shell(:runtime, "Runtime Dashboard")
      |> refresh_dashboard()

    if connected?(socket) do
      Process.send_after(self(), :refresh_runtime_dashboard, @refresh_interval)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_runtime_dashboard, socket) do
    Process.send_after(self(), :refresh_runtime_dashboard, @refresh_interval)
    {:noreply, refresh_dashboard(socket)}
  end

  defp refresh_dashboard(socket) do
    assign(socket, :runtime_dashboard, Status.dashboard_snapshot())
  end

  defp service_help(:activity_log),
    do: "In-memory feed of recent runtime events used by the logs and operator views."

  defp service_help(:runtime_table_owner),
    do: "Keeps the named ETS runtime table alive for active instance state."

  defp service_help(:executor_supervisor),
    do: "DynamicSupervisor responsible for per-instance executor processes."

  defp service_help(:pool_supervisor),
    do: "DynamicSupervisor responsible for per-resource pool processes."

  defp service_help(:scheduler_supervisor),
    do: "DynamicSupervisor responsible for per-department scheduler processes."

  defp service_help(:executor_registry),
    do: "Registry that maps instance IDs to live executor processes."

  defp service_help(:scheduler_registry),
    do: "Registry that maps department IDs to live scheduler processes."

  defp service_help(:pool_registry),
    do: "Registry that maps resource keys to live resource pool processes."

  defp service_help(_service), do: "Runtime infrastructure service."

  defp bool_tone(true), do: "success"
  defp bool_tone(false), do: "danger"

  defp pool_tone(%{alive?: false}), do: "danger"
  defp pool_tone(%{available?: true}), do: "success"
  defp pool_tone(%{current: current, max: max}) when current >= max, do: "warning"
  defp pool_tone(_pool), do: "default"

  defp entry_tone(%{executor_alive?: false}), do: "warning"
  defp entry_tone(%{status: "failed"}), do: "danger"
  defp entry_tone(%{status: "retrying"}), do: "warning"
  defp entry_tone(%{status: "processing"}), do: "info"
  defp entry_tone(%{status: "queued"}), do: "accent"
  defp entry_tone(_entry), do: "default"

  defp queue_detail(%{queue_depth: queue_depth, current_item_id: current_item_id}) do
    [
      "queue=#{queue_depth}",
      current_item_id && "current=#{current_item_id}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp format_dt(nil), do: "-"
  defp format_dt(value), do: Helpers.format_datetime(value, nil_label: "-")
end
