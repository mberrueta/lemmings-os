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
         {:ok, city} <- Cities.fetch_city(world, city_id) do
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
         {:ok, city} <- Cities.fetch_city(world, city_id),
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

  # ============================================
  # Private Helpers
  # ============================================

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

  defp fetch_snapshot_world(%{world: %{id: world_id}}) do
    Worlds.fetch_world(world_id)
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
end
