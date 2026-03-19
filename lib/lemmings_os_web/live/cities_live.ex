defmodule LemmingsOsWeb.CitiesLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell
  import LemmingsOsWeb.WorldComponents

  alias LemmingsOs.Helpers
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:cities, dgettext("layout", ".page_title_cities"))
     |> assign(:snapshot, nil)
     |> load_snapshot(params)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load_snapshot(socket, params)}
  end

  defp load_snapshot(socket, params) do
    case CitiesPageSnapshot.build(city_id: params["city"]) do
      {:ok, snapshot} ->
        socket
        |> assign(:snapshot, snapshot)
        |> stream(:cities, snapshot.cities, reset: true)
        |> put_shell_breadcrumb(shell_breadcrumb(snapshot))

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> stream(:cities, [], reset: true)
        |> put_shell_breadcrumb([shell_item(:cities, "/cities")])
    end
  end

  defp shell_breadcrumb(%{selected_city: nil}), do: [shell_item(:cities, "/cities")]

  defp shell_breadcrumb(%{selected_city: %{id: id, name: name}}),
    do: [shell_item(:cities, "/cities"), shell_item(name || id, "/cities?city=#{id}")]
end
