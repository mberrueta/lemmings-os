defmodule LemmingsOsWeb.WorldLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:world, "World")
     |> assign(:cities, MockData.cities())
     |> assign(:departments, MockData.departments())
     |> assign(:lemmings, MockData.lemmings())}
  end
end
