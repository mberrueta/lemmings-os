defmodule LemmingsOsWeb.HomeLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:home, "Home")
     |> assign(:cities, MockData.cities())
     |> assign(:departments, MockData.departments())
     |> assign(:lemmings, MockData.lemmings())
     |> assign(:activity_log, MockData.recent_activity(6))}
  end
end
