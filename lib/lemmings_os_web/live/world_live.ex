defmodule LemmingsOsWeb.WorldLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Helpers
  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:world, dgettext("layout", ".page_title_world"))
     |> assign(:active_tab, "overview")
     |> assign(:snapshot, nil)
     |> assign(:cities, [])
     |> assign(:last_import_result, nil)
     |> load_snapshot()}
  end

  def handle_event("refresh_status", _params, socket) do
    {:noreply, load_snapshot(socket)}
  end

  def handle_event("import_bootstrap", _params, socket) do
    import_result = import_bootstrap(socket.assigns.snapshot)
    {:noreply, load_snapshot(socket, import_result)}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, normalize_tab(tab))}
  end

  def handle_event("navigate_city", %{"city_id" => city_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/cities?city=#{city_id}")}
  end

  defp load_snapshot(socket, import_result \\ nil) do
    case WorldPageSnapshot.build(snapshot_opts(import_result)) do
      {:ok, snapshot} ->
        cities = load_world_cities(snapshot.world.id)

        socket
        |> assign(:snapshot, snapshot)
        |> assign(:cities, cities)
        |> assign(:last_import_result, normalize_import_result(import_result))

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> assign(:cities, [])
        |> assign(:last_import_result, normalize_import_result(import_result))
    end
  end

  defp load_world_cities(world_id) when is_binary(world_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    freshness = freshness_threshold_seconds()

    world_id
    |> Cities.list_cities()
    |> Enum.map(&to_city_summary(&1, now, freshness))
  end

  defp to_city_summary(%City{} = city, now, freshness) do
    liveness = City.liveness(city, now, freshness)

    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      node_name: city.node_name,
      status: city.status,
      liveness: liveness,
      last_seen_at: city.last_seen_at,
      last_seen_at_label: Helpers.format_datetime(city.last_seen_at)
    }
  end

  defp freshness_threshold_seconds do
    Application.get_env(:lemmings_os, :runtime_city_heartbeat, [])
    |> Keyword.get(:freshness_threshold_seconds, 90)
  end

  defp snapshot_opts(nil), do: []
  defp snapshot_opts(import_result), do: [immediate_import_result: import_result]

  defp import_bootstrap(%{bootstrap: %{path: path, source: source}})
       when is_binary(path) and path != "" do
    Importer.sync_default_world(path: path, source: source || "persisted")
  end

  defp import_bootstrap(_snapshot), do: Importer.sync_default_world()

  defp normalize_import_result({:ok, result}), do: result
  defp normalize_import_result({:error, result}), do: result
  defp normalize_import_result(nil), do: nil

  defp normalize_tab("overview"), do: "overview"
  defp normalize_tab("import"), do: "import"
  defp normalize_tab("bootstrap"), do: "bootstrap"
  defp normalize_tab("runtime"), do: "runtime"
  defp normalize_tab(_tab), do: "overview"
end
