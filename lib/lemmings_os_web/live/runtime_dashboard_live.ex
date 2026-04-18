defmodule LemmingsOsWeb.RuntimeDashboardLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Helpers
  alias LemmingsOs.Runtime.Status

  @refresh_interval 10_000
  @recent_runtime_limit 10

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_shell(:runtime, dgettext("lemmings", ".title_runtime_dashboard"))
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
    assign(
      socket,
      :runtime_dashboard,
      Status.dashboard_snapshot(recent_limit: @recent_runtime_limit)
    )
  end

  defp service_help(:activity_log),
    do: dgettext("lemmings", ".runtime_service_help_activity_log")

  defp service_help(:runtime_table_owner),
    do: dgettext("lemmings", ".runtime_service_help_runtime_table_owner")

  defp service_help(:executor_supervisor),
    do: dgettext("lemmings", ".runtime_service_help_executor_supervisor")

  defp service_help(:pool_supervisor),
    do: dgettext("lemmings", ".runtime_service_help_pool_supervisor")

  defp service_help(:scheduler_supervisor),
    do: dgettext("lemmings", ".runtime_service_help_scheduler_supervisor")

  defp service_help(:executor_registry),
    do: dgettext("lemmings", ".runtime_service_help_executor_registry")

  defp service_help(:scheduler_registry),
    do: dgettext("lemmings", ".runtime_service_help_scheduler_registry")

  defp service_help(:pool_registry),
    do: dgettext("lemmings", ".runtime_service_help_pool_registry")

  defp service_help(_service), do: dgettext("lemmings", ".runtime_service_help_default")

  defp service_label(:activity_log),
    do: dgettext("lemmings", ".runtime_service_label_activity_log")

  defp service_label(:runtime_table_owner),
    do: dgettext("lemmings", ".runtime_service_label_runtime_table_owner")

  defp service_label(:executor_supervisor),
    do: dgettext("lemmings", ".runtime_service_label_executor_supervisor")

  defp service_label(:pool_supervisor),
    do: dgettext("lemmings", ".runtime_service_label_pool_supervisor")

  defp service_label(:scheduler_supervisor),
    do: dgettext("lemmings", ".runtime_service_label_scheduler_supervisor")

  defp service_label(:executor_registry),
    do: dgettext("lemmings", ".runtime_service_label_executor_registry")

  defp service_label(:scheduler_registry),
    do: dgettext("lemmings", ".runtime_service_label_scheduler_registry")

  defp service_label(:pool_registry),
    do: dgettext("lemmings", ".runtime_service_label_pool_registry")

  defp service_label(service), do: service |> to_string() |> String.replace("_", " ")

  defp bool_tone(true), do: "success"
  defp bool_tone(false), do: "danger"

  defp pool_tone(%{alive?: false}), do: "danger"
  defp pool_tone(%{available?: true}), do: "success"
  defp pool_tone(%{current: current, max: max}) when current >= max, do: "warning"
  defp pool_tone(_pool), do: "default"

  defp queue_detail(%{queue_depth: queue_depth, current_item_id: current_item_id}) do
    [
      dgettext("lemmings", ".runtime_queue_detail", count: queue_depth),
      current_item_id && dgettext("lemmings", ".runtime_current_detail", id: current_item_id)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp format_dt(nil), do: "-"
  defp format_dt(value), do: Helpers.format_datetime(value, nil_label: "-")
end
