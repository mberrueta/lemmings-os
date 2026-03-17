defmodule LemmingsOsWeb.HomeLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOsWeb.PageData.HomeDashboardSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:home, dgettext("layout", ".page_title_home"))
     |> assign(:snapshot, HomeDashboardSnapshot.build())}
  end
end
