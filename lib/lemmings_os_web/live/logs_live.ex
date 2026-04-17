defmodule LemmingsOsWeb.LogsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Runtime.Status

  @refresh_interval 2_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_shell(:logs, dgettext("layout", ".page_title_logs"))
      |> refresh_runtime_state()

    if connected?(socket) do
      Process.send_after(self(), :refresh_runtime_state, @refresh_interval)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_runtime_state, socket) do
    Process.send_after(self(), :refresh_runtime_state, @refresh_interval)
    {:noreply, refresh_runtime_state(socket)}
  end

  defp refresh_runtime_state(socket) do
    assign(
      socket,
      runtime_snapshot: Status.snapshot(),
      activity_log: ActivityLog.recent_events(80)
    )
  end

  defp activity_class(:error), do: "text-red-400"
  defp activity_class(:system), do: "text-amber-400"
  defp activity_class(_type), do: "text-emerald-400"
end
