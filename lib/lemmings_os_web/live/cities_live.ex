defmodule LemmingsOsWeb.CitiesLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:cities, "Cities")
     |> assign(:cities, MockData.cities())
     |> assign(:selected_city, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :selected_city, MockData.find_city(params["city"]))}
  end
end
