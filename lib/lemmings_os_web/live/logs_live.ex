defmodule LemmingsOsWeb.LogsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:logs, dgettext("layout", ".page_title_logs"))
     |> assign(:activity_log, MockData.global_activity_log())}
  end
end
