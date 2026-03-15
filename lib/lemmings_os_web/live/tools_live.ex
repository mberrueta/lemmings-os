defmodule LemmingsOsWeb.ToolsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:tools, dgettext("layout", ".page_title_tools"))
     |> assign(:tools, MockData.tools())}
  end
end
