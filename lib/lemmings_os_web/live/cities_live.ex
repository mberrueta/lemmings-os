defmodule LemmingsOsWeb.CitiesLive do
  @moduledoc """
  Operator-facing Cities LiveView.

  Provides list, detail, create, edit, and delete flows for City metadata
  and local override config. All context calls are World-scoped.

  ## Authorization

  This LiveView does not enforce authentication or per-user authorization.
  It is intended as an internal operator console, not a public-facing surface.
  It assumes network-level access control (e.g. internal network, VPN, or
  reverse proxy auth) is in place before traffic reaches this route.

  ## Assigns

  - `:snapshot` — `CitiesPageSnapshot.t()` or nil when no world is available
  - `:form` — `Phoenix.HTML.Form.t()` or nil when no form is open
  - `:form_mode` — `:new | :edit` when a form is open, nil otherwise
  - `:form_city_id` — city ID being edited, nil for new city forms
  - `:editing_city` — `City.t()` struct stashed during edit flow to avoid re-querying on each keystroke
  """

  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell
  import LemmingsOsWeb.WorldComponents

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections
  alias LemmingsOs.Helpers
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds
  alias LemmingsOsWeb.ConnectionsSurface
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  @detail_tabs ~w(overview secrets connections)

  def mount(params, _session, socket) do
    connection_types = Connections.list_connection_types()

    {:ok,
     socket
     |> assign_shell(:cities, dgettext("layout", ".page_title_cities"))
     |> assign(:snapshot, nil)
     |> assign(:form, nil)
     |> assign(:form_mode, nil)
     |> assign(:form_city_id, nil)
     |> assign(:editing_city, nil)
     |> assign(:city_secret_form, blank_secret_form())
     |> assign(:city_secret_metadata, [])
     |> assign(:city_secret_env_policy, [])
     |> assign(:city_secret_activity, [])
     |> assign(:selected_city_tab, "overview")
     |> assign(:city_connection_types, connection_types)
     |> assign(:city_connection_create_form, ConnectionsSurface.create_form(connection_types))
     |> assign(:city_connection_create_open, false)
     |> assign(:city_connection_rows, [])
     |> assign(:city_connection_editing_id, nil)
     |> assign(:city_connection_edit_form, nil)
     |> load_snapshot(params)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load_snapshot(socket, params)}
  end

  # ============================================
  # City Form Events
  # ============================================

  def handle_event("new_city", _params, socket) do
    changeset = City.changeset(%City{}, %{})
    form = to_form(changeset, as: :city)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:form_mode, :new)
     |> assign(:form_city_id, nil)}
  end

  def handle_event("edit_city", %{"id" => city_id}, socket) do
    with %{snapshot: %{} = snapshot} <- socket.assigns,
         {:ok, world} <- fetch_snapshot_world(snapshot),
         %City{} = city <- Cities.get_city(world, city_id) do
      changeset = City.changeset(city, %{})
      form = to_form(changeset, as: :city)

      {:noreply,
       socket
       |> assign(:form, form)
       |> assign(:form_mode, :edit)
       |> assign(:form_city_id, city_id)
       |> assign(:editing_city, city)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, dgettext("world", ".flash_city_not_found"))}
    end
  end

  def handle_event("validate_city", %{"city" => params}, socket) do
    changeset =
      case socket.assigns.form_mode do
        :edit -> build_edit_changeset(socket, params)
        _ -> City.changeset(%City{}, params)
      end

    form = to_form(changeset, as: :city)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save_city", %{"city" => params}, socket) do
    case socket.assigns.form_mode do
      :new -> create_city(socket, params)
      :edit -> update_city(socket, params)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:form, nil)
     |> assign(:form_mode, nil)
     |> assign(:form_city_id, nil)
     |> assign(:editing_city, nil)}
  end

  def handle_event("select_city_tab", %{"tab" => tab}, socket) when tab in @detail_tabs do
    params = city_detail_params(socket, %{tab: tab})
    {:noreply, push_patch(socket, to: ~p"/cities?#{params}")}
  end

  def handle_event("delete_city", %{"id" => city_id}, socket) do
    with %{snapshot: %{} = snapshot} <- socket.assigns,
         {:ok, world} <- fetch_snapshot_world(snapshot),
         %City{} = city <- Cities.get_city(world, city_id),
         {:ok, _city} <- Cities.delete_city(city) do
      socket =
        socket
        |> put_flash(:info, dgettext("world", ".flash_city_deleted"))
        |> push_patch(to: ~p"/cities")

      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, dgettext("world", ".flash_city_delete_error"))}

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("world", ".flash_city_not_found"))}
    end
  end

  def handle_event("save_city_secret", %{"secret" => params}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, _metadata} <- SecretBank.upsert_secret(city, params["bank_key"], params["value"]) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_saved"))
       |> assign(:city_secret_form, blank_secret_form())
       |> push_event("secret_form:reset", %{form_id: "city-secret-form"})
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, :invalid_key} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("errors", ".error_invalid_key")
         )
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{form_id: "city-secret-form", field: "bank_key"})}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_value_required"))
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{form_id: "city-secret-form", field: "value"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_save_failed"))
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))}
    end
  end

  def handle_event("delete_city_secret", %{"bank-key" => bank_key}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, _metadata} <- SecretBank.delete_secret(city, bank_key) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_deleted"))
       |> push_event("secret_form:focus", %{form_id: "city-secret-form", field: "bank_key"})
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

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

  def handle_event("edit_city_secret", %{"bank-key" => bank_key}, socket) do
    {:noreply,
     socket
     |> assign(:city_secret_form, secret_form_with_key(bank_key))
     |> push_event("secret_form:focus", %{form_id: "city-secret-form", field: "value"})}
  end

  def handle_event(
        "change_city_connection_create_type",
        %{"connection_create" => %{"type" => type}},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :city_connection_create_form,
       ConnectionsSurface.create_form(socket.assigns.city_connection_types, %{"type" => type})
     )}
  end

  def handle_event("open_city_connection_create", _params, socket) do
    {:noreply, assign(socket, :city_connection_create_open, true)}
  end

  def handle_event("close_city_connection_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:city_connection_create_open, false)
     |> assign(
       :city_connection_create_form,
       ConnectionsSurface.create_form(socket.assigns.city_connection_types)
     )}
  end

  def handle_event("create_city_connection", %{"connection_create" => params}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, attrs} <- ConnectionsSurface.parse_connection_form_params(params),
         {:ok, _connection} <- Connections.create_connection(city, attrs) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_created"))
       |> assign(:city_connection_create_open, false)
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:city_connection_create_open, true)
         |> assign(:city_connection_create_form, to_form(changeset, as: :connection_create))}

      {:error, :invalid_payload} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_invalid_payload"))}
    end
  end

  def handle_event("start_city_connection_edit", %{"connection_id" => connection_id}, socket) do
    case find_local_connection_row(socket.assigns.city_connection_rows, connection_id) do
      {:ok, row} ->
        {:noreply,
         socket
         |> assign(:city_connection_editing_id, connection_id)
         |> assign(:city_connection_edit_form, ConnectionsSurface.edit_form(row.connection))}

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("cancel_city_connection_edit", _params, socket) do
    {:noreply, assign(socket, city_connection_editing_id: nil, city_connection_edit_form: nil)}
  end

  def handle_event(
        "change_city_connection_edit_type",
        %{"connection_edit" => %{"connection_id" => connection_id, "type" => type}},
        socket
      ) do
    case find_local_connection_row(socket.assigns.city_connection_rows, connection_id) do
      {:ok, row} ->
        config_text =
          ConnectionsSurface.default_config_text(socket.assigns.city_connection_types, type)

        params = %{
          "connection_id" => row.connection.id,
          "type" => type,
          "status" => row.connection.status,
          "config" => config_text
        }

        {:noreply,
         assign(socket, :city_connection_edit_form, ConnectionsSurface.edit_form(params))}

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("save_city_connection_edit", %{"connection_edit" => params}, socket) do
    connection_id = Map.get(params, "connection_id", "")

    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, row} <-
           find_local_connection_row(socket.assigns.city_connection_rows, connection_id),
         {:ok, attrs} <- ConnectionsSurface.parse_connection_form_params(params),
         {:ok, _connection} <- Connections.update_connection(city, row.connection, attrs) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_updated"))
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, :invalid_payload} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_invalid_payload"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("delete_city_connection", %{"connection_id" => connection_id}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, row} <-
           find_local_connection_row(socket.assigns.city_connection_rows, connection_id),
         {:ok, _connection} <- Connections.delete_connection(city, row.connection) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_deleted"))
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event(
        "city_connection_lifecycle",
        %{"connection_id" => connection_id, "action" => action},
        socket
      ) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, row} <-
           find_local_connection_row(socket.assigns.city_connection_rows, connection_id),
         {:ok, _connection} <- run_connection_lifecycle(city, row.connection, action) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_status_updated"))
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("test_city_connection", %{"type" => type}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, _result} <- Connections.test_connection(city, type) do
      snapshot_params = city_detail_params(socket, %{city: city.id})

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_tested"))
       |> load_snapshot(snapshot_params)}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_city_unavailable"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_test_failed"))}
    end
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp load_snapshot(socket, params) do
    case CitiesPageSnapshot.build(city_id: params["city"]) do
      {:ok, snapshot} ->
        selected_tab = normalize_detail_tab(params["tab"], snapshot.selected_city)

        socket
        |> assign(:snapshot, snapshot)
        |> assign(:selected_city_tab, selected_tab)
        |> stream(:cities, snapshot.cities, reset: true)
        |> assign_city_secret_surface(snapshot)
        |> assign_city_connection_surface(snapshot)
        |> put_shell_breadcrumb(shell_breadcrumb(snapshot))

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> assign(:selected_city_tab, "overview")
        |> stream(:cities, [], reset: true)
        |> assign(:city_secret_form, blank_secret_form())
        |> assign(:city_secret_metadata, [])
        |> assign(:city_secret_env_policy, [])
        |> assign(:city_secret_activity, [])
        |> reset_city_connection_surface()
        |> put_shell_breadcrumb([shell_item(:cities, "/cities")])
    end
  end

  defp shell_breadcrumb(%{selected_city: nil}), do: [shell_item(:cities, "/cities")]

  defp shell_breadcrumb(%{selected_city: %{id: id, name: name}}),
    do: [shell_item(:cities, "/cities"), shell_item(name || id, "/cities?city=#{id}")]

  defp fetch_snapshot_world(%{world: %{id: world_id}}) do
    case Worlds.get_world(world_id) do
      %{} = world -> {:ok, world}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_snapshot_world(_snapshot), do: {:error, :not_found}

  defp build_edit_changeset(socket, params) do
    case socket.assigns do
      %{editing_city: %City{} = city} -> City.changeset(city, params)
      _ -> City.changeset(%City{}, params)
    end
  end

  defp create_city(socket, params) do
    with %{snapshot: %{} = snapshot} <- socket.assigns,
         {:ok, world} <- fetch_snapshot_world(snapshot),
         {:ok, _city} <- Cities.create_city(world, params) do
      socket =
        socket
        |> assign(:form, nil)
        |> assign(:form_mode, nil)
        |> assign(:form_city_id, nil)
        |> assign(:editing_city, nil)
        |> put_flash(:info, dgettext("world", ".flash_city_created"))
        |> push_patch(to: ~p"/cities")

      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: :city)
        {:noreply, assign(socket, :form, form)}

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("world", ".flash_city_save_error"))}
    end
  end

  defp update_city(socket, params) do
    with %{snapshot: %{} = snapshot} <- socket.assigns,
         %{editing_city: %City{} = city} <- socket.assigns,
         {:ok, _world} <- fetch_snapshot_world(snapshot),
         {:ok, updated_city} <- Cities.update_city(city, params) do
      socket =
        socket
        |> assign(:form, nil)
        |> assign(:form_mode, nil)
        |> assign(:form_city_id, nil)
        |> assign(:editing_city, nil)
        |> put_flash(:info, dgettext("world", ".flash_city_updated"))
        |> push_patch(to: ~p"/cities?city=#{updated_city.id}")

      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset, as: :city)
        {:noreply, assign(socket, :form, form)}

      _ ->
        {:noreply, put_flash(socket, :error, dgettext("world", ".flash_city_save_error"))}
    end
  end

  defp assign_city_secret_surface(socket, %{selected_city: nil}),
    do: reset_city_secret_surface(socket)

  defp assign_city_secret_surface(socket, %{selected_city: %{id: city_id}} = snapshot)
       when is_binary(city_id) do
    with {:ok, world} <- fetch_snapshot_world(snapshot),
         %City{} = city <- Cities.get_city(world, city_id) do
      socket
      |> assign(:city_secret_metadata, SecretBank.list_effective_metadata(city))
      |> assign(:city_secret_env_policy, SecretBank.list_env_fallback_policy())
      |> assign(:city_secret_activity, SecretBank.list_recent_activity(city, limit: 10))
    else
      _ -> reset_city_secret_surface(socket)
    end
  end

  defp assign_city_secret_surface(socket, _snapshot), do: reset_city_secret_surface(socket)

  defp reset_city_secret_surface(socket) do
    socket
    |> assign(:city_secret_form, blank_secret_form())
    |> assign(:city_secret_metadata, [])
    |> assign(:city_secret_env_policy, [])
    |> assign(:city_secret_activity, [])
  end

  defp assign_city_connection_surface(socket, %{selected_city: nil}),
    do: reset_city_connection_surface(socket)

  defp assign_city_connection_surface(socket, %{selected_city: %{id: city_id}} = snapshot)
       when is_binary(city_id) do
    with {:ok, world} <- fetch_snapshot_world(snapshot),
         %City{} = city <- Cities.get_city(world, city_id) do
      socket
      |> assign(:city_connection_rows, Connections.list_visible_connections(city))
      |> assign(
        :city_connection_create_form,
        ConnectionsSurface.create_form(socket.assigns.city_connection_types)
      )
      |> assign(:city_connection_create_open, false)
      |> assign(:city_connection_editing_id, nil)
      |> assign(:city_connection_edit_form, nil)
    else
      _ -> reset_city_connection_surface(socket)
    end
  end

  defp assign_city_connection_surface(socket, _snapshot),
    do: reset_city_connection_surface(socket)

  defp reset_city_connection_surface(socket) do
    socket
    |> assign(:city_connection_rows, [])
    |> assign(
      :city_connection_create_form,
      ConnectionsSurface.create_form(socket.assigns.city_connection_types)
    )
    |> assign(:city_connection_create_open, false)
    |> assign(:city_connection_editing_id, nil)
    |> assign(:city_connection_edit_form, nil)
  end

  defp load_selected_city_scope(%{
         assigns: %{snapshot: %{selected_city: %{id: city_id}} = snapshot}
       })
       when is_binary(city_id) do
    with {:ok, world} <- fetch_snapshot_world(snapshot),
         %City{} = city <- Cities.get_city(world, city_id) do
      {:ok, city}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp load_selected_city_scope(_socket), do: {:error, :invalid_scope}

  defp blank_secret_form, do: to_form(%{"bank_key" => "", "value" => ""}, as: :secret)

  defp secret_form_with_key(bank_key) do
    to_form(%{"bank_key" => String.trim(bank_key || ""), "value" => ""}, as: :secret)
  end

  defp normalize_detail_tab(_tab, nil), do: "overview"
  defp normalize_detail_tab(tab, _selected_city) when tab in @detail_tabs, do: tab
  defp normalize_detail_tab(_tab, _selected_city), do: "overview"

  defp city_detail_params(socket, overrides) do
    selected_city_id =
      case socket.assigns.snapshot do
        %{selected_city: %{id: city_id}} when is_binary(city_id) -> city_id
        _ -> nil
      end

    base =
      %{}
      |> maybe_put_param(:city, selected_city_id)
      |> maybe_put_param(:tab, socket.assigns.selected_city_tab)

    Enum.reduce(overrides, base, fn
      {_key, nil}, acc -> acc
      {"tab", "overview"}, acc -> Map.delete(acc, "tab")
      {:tab, "overview"}, acc -> Map.delete(acc, "tab")
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  defp find_local_connection_row(rows, connection_id) do
    case Enum.find(rows, &(&1.local? and &1.connection.id == connection_id)) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  defp run_connection_lifecycle(scope, connection, "enable"),
    do: Connections.enable_connection(scope, connection)

  defp run_connection_lifecycle(scope, connection, "disable"),
    do: Connections.disable_connection(scope, connection)

  defp run_connection_lifecycle(_scope, _connection, _action), do: {:error, :invalid_action}
end
