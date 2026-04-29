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
  alias LemmingsOs.Helpers
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  def mount(params, _session, socket) do
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
     |> assign(:city_secret_activity, [])
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
      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", "Secret saved"))
       |> assign(:city_secret_form, blank_secret_form())
       |> push_event("secret_form:reset", %{form_id: "city-secret-form"})
       |> load_snapshot(%{"city" => city.id})}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("world", "City is unavailable"))}

      {:error, :invalid_key} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("errors", ".error_invalid_key")
         )
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", "Secret value is required"))
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", "Failed to save secret"))
         |> assign(:city_secret_form, secret_form_with_key(params["bank_key"]))}
    end
  end

  def handle_event("delete_city_secret", %{"bank-key" => bank_key}, socket) do
    with {:ok, city} <- load_selected_city_scope(socket),
         {:ok, _metadata} <- SecretBank.delete_secret(city, bank_key) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", "Local secret deleted"))
       |> load_snapshot(%{"city" => city.id})}
    else
      {:error, :invalid_scope} ->
        {:noreply, put_flash(socket, :error, dgettext("world", "City is unavailable"))}

      {:error, :inherited_secret_not_deletable} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("world", "Only local values can be deleted at this scope")
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, dgettext("world", "Secret key not found"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("world", "Failed to delete secret"))}
    end
  end

  def handle_event("edit_city_secret", %{"bank-key" => bank_key}, socket) do
    {:noreply, assign(socket, :city_secret_form, secret_form_with_key(bank_key))}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp load_snapshot(socket, params) do
    case CitiesPageSnapshot.build(city_id: params["city"]) do
      {:ok, snapshot} ->
        socket
        |> assign(:snapshot, snapshot)
        |> stream(:cities, snapshot.cities, reset: true)
        |> assign_city_secret_surface(snapshot)
        |> put_shell_breadcrumb(shell_breadcrumb(snapshot))

      {:error, :not_found} ->
        socket
        |> assign(:snapshot, nil)
        |> stream(:cities, [], reset: true)
        |> assign(:city_secret_form, blank_secret_form())
        |> assign(:city_secret_metadata, [])
        |> assign(:city_secret_activity, [])
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
    |> assign(:city_secret_activity, [])
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
end
