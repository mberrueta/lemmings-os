defmodule LemmingsOsWeb.WorldLive do
  use LemmingsOsWeb, :live_view

  alias LemmingsOs.MockData
  import LemmingsOsWeb.MockShell

  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:world, dgettext("layout", ".page_title_world"))
     |> assign(:active_tab, "overview")
     |> assign(:snapshot, nil)
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

  defp load_snapshot(socket, import_result \\ nil) do
    case WorldPageSnapshot.build(snapshot_opts(import_result)) do
      {:ok, snapshot} ->
        snapshot = put_mock_world_cities(snapshot)

        socket
        |> assign(:snapshot, snapshot)
        |> assign(:last_import_result, normalize_import_result(import_result))

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> assign(:last_import_result, normalize_import_result(import_result))
    end
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

  # TODO(task 07 follow-up): replace `world.cities` with real world-scoped city
  # topology once the Cities slice exists. This mock data is attached explicitly
  # to the World snapshot so the remaining fake authority is visible in code.
  defp put_mock_world_cities(snapshot) do
    %{snapshot | world: Map.put(snapshot.world, :cities, mock_world_cities())}
  end

  defp mock_world_cities do
    MockData.cities()
    |> Enum.map(&to_world_map_city/1)
  end

  defp to_world_map_city(city) do
    %{
      id: city.id,
      name: city.name,
      region: city.region,
      color: city.accent,
      status: city.status,
      agents: city.id |> MockData.lemmings_for_city() |> length(),
      depts: city.id |> MockData.departments_for_city() |> length(),
      col: grid_coordinate(city.x, 44),
      row: grid_coordinate(city.y, 25)
    }
  end

  defp grid_coordinate(nil, _max_index), do: nil

  defp grid_coordinate(percent, max_index) do
    percent
    |> Kernel.*(max_index)
    |> Kernel./(100)
    |> round()
    |> max(0)
    |> min(max_index)
  end
end
