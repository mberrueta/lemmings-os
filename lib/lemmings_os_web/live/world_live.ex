defmodule LemmingsOsWeb.WorldLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:world, dgettext("layout", ".page_title_world"))
     |> assign(:cities, MockData.cities())
     |> assign(:departments, MockData.departments())
     |> assign(:lemmings, MockData.lemmings())}
  end

  def handle_event("navigate_city", %{"city_id" => city_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/cities?#{%{city: city_id}}")}
  end
end
