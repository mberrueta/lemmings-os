defmodule LemmingsOsWeb.CitiesLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    cities = MockData.cities()

    {:ok,
     socket
     |> assign_shell(:cities, dgettext("layout", ".page_title_cities"))
     |> assign(:cities, cities)
     |> assign(:selected_city, List.first(cities))}
  end

  def handle_params(params, _uri, socket) do
    selected_city = MockData.find_city(params["city"]) || List.first(socket.assigns.cities)

    {:noreply,
     socket
     |> assign(:selected_city, selected_city)
     |> put_shell_breadcrumb([
       shell_item(:cities, "/cities"),
       shell_item(selected_city.id, "/cities?city=#{selected_city.id}")
     ])}
  end
end
