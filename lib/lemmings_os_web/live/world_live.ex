defmodule LemmingsOsWeb.WorldLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Helpers
  alias LemmingsOs.SecretBank
  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:world, dgettext("layout", ".page_title_world"))
     |> assign(:active_tab, "overview")
     |> assign(:snapshot, nil)
     |> assign(:cities, [])
     |> assign(:last_import_result, nil)
     |> assign(:world_secret_form, blank_secret_form())
     |> assign(:world_secret_metadata, [])
     |> assign(:world_secret_env_policy, [])
     |> assign(:world_secret_activity, [])
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

  def handle_event("save_world_secret", %{"secret" => params}, socket) do
    with {:ok, world} <- load_world_scope(socket),
         {:ok, _metadata} <- SecretBank.upsert_secret(world, params["bank_key"], params["value"]) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_saved"))
       |> assign(:world_secret_form, blank_secret_form())
       |> push_event("secret_form:reset", %{form_id: "world-secret-form"})
       |> assign_world_secret_surface(world)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_world_unavailable"))}

      {:error, :invalid_key} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("errors", ".error_invalid_key")
         )
         |> assign(:world_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{form_id: "world-secret-form", field: "bank_key"})}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_value_required"))
         |> assign(:world_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{form_id: "world-secret-form", field: "value"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_save_failed"))
         |> assign(:world_secret_form, secret_form_with_key(params["bank_key"]))}
    end
  end

  def handle_event("delete_world_secret", %{"bank-key" => bank_key}, socket) do
    with {:ok, world} <- load_world_scope(socket),
         {:ok, _metadata} <- SecretBank.delete_secret(world, bank_key) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_deleted"))
       |> push_event("secret_form:focus", %{form_id: "world-secret-form", field: "bank_key"})
       |> assign_world_secret_surface(world)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_world_unavailable"))}

      {:error, :inherited_secret_not_deletable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("errors", ".error_secret_inherited_not_deletable")
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_secret_key_not_found"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_secret_delete_failed"))}
    end
  end

  def handle_event("edit_world_secret", %{"bank-key" => bank_key}, socket) do
    {:noreply,
     socket
     |> assign(:world_secret_form, secret_form_with_key(bank_key))
     |> push_event("secret_form:focus", %{form_id: "world-secret-form", field: "value"})}
  end

  defp load_snapshot(socket, import_result \\ nil) do
    case WorldPageSnapshot.build(snapshot_opts(import_result)) do
      {:ok, snapshot} ->
        cities = load_world_cities(snapshot.world.id)

        socket
        |> assign(:snapshot, snapshot)
        |> assign(:cities, cities)
        |> assign(:last_import_result, normalize_import_result(import_result))
        |> assign_world_secret_surface(snapshot.world.id)

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> assign(:cities, [])
        |> assign(:last_import_result, normalize_import_result(import_result))
        |> assign(:world_secret_form, blank_secret_form())
        |> assign(:world_secret_metadata, [])
        |> assign(:world_secret_env_policy, [])
        |> assign(:world_secret_activity, [])
    end
  end

  defp load_world_cities(world_id) when is_binary(world_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    freshness = freshness_threshold_seconds()
    world = %World{id: world_id}

    Cities.list_cities(world)
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
  defp normalize_tab("secrets"), do: "secrets"
  defp normalize_tab(_tab), do: "overview"

  defp load_world_scope(%{assigns: %{snapshot: %{world: %{id: world_id}}}})
       when is_binary(world_id) do
    case Worlds.get_world(world_id) do
      %World{} = world -> {:ok, world}
      nil -> {:error, :invalid_scope}
    end
  end

  defp load_world_scope(_socket), do: {:error, :invalid_scope}

  defp assign_world_secret_surface(socket, world_id) when is_binary(world_id) do
    case Worlds.get_world(world_id) do
      %World{} = world -> assign_world_secret_surface(socket, world)
      nil -> assign_world_secret_surface(socket, nil)
    end
  end

  defp assign_world_secret_surface(socket, %World{} = world) do
    socket
    |> assign(:world_secret_metadata, SecretBank.list_effective_metadata(world))
    |> assign(:world_secret_env_policy, SecretBank.list_env_fallback_policy())
    |> assign(:world_secret_activity, SecretBank.list_recent_activity(world, limit: 10))
  end

  defp assign_world_secret_surface(socket, nil) do
    socket
    |> assign(:world_secret_form, blank_secret_form())
    |> assign(:world_secret_metadata, [])
    |> assign(:world_secret_env_policy, [])
    |> assign(:world_secret_activity, [])
  end

  defp blank_secret_form, do: to_form(%{"bank_key" => "", "value" => ""}, as: :secret)

  defp secret_form_with_key(bank_key) do
    to_form(%{"bank_key" => String.trim(bank_key || ""), "value" => ""}, as: :secret)
  end
end
