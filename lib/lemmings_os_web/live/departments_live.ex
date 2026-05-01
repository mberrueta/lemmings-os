defmodule LemmingsOsWeb.DepartmentsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Connections
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.ConnectionsSurface
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot
  alias LemmingsOsWeb.PageData.DepartmentCollaborationSnapshot

  @detail_tabs ~w(overview lemmings settings secrets connections)

  def mount(_params, _session, socket) do
    connection_types = Connections.list_connection_types()

    {:ok,
     socket
     |> assign_shell(:departments, dgettext("layout", ".page_title_departments"))
     |> assign(:cities, [])
     |> assign(:city_selector_form, to_form(%{"city_id" => ""}, as: :city_selector))
     |> assign(:world, nil)
     |> assign(:selected_city, nil)
     |> assign(:departments, [])
     |> assign(:selected_department, nil)
     |> assign(:selected_department_tab, "overview")
     |> assign(:department_settings_form, nil)
     |> assign(:department_effective_config, nil)
     |> assign(:department_local_overrides, nil)
     |> assign(:department_lemmings, [])
     |> assign(:department_primary_manager, nil)
     |> assign(:department_secret_form, blank_secret_form())
     |> assign(:department_secret_metadata, [])
     |> assign(:department_secret_env_policy, [])
     |> assign(:department_secret_activity, [])
     |> assign(:department_connection_types, connection_types)
     |> assign(
       :department_connection_create_form,
       ConnectionsSurface.create_form(connection_types)
     )
     |> assign(:department_connection_create_open, false)
     |> assign(:department_connection_rows, [])
     |> assign(:department_connection_editing_id, nil)
     |> assign(:department_connection_edit_form, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  def handle_event("navigate_department", %{"department_id" => department_id}, socket) do
    params =
      case socket.assigns.selected_city do
        %{id: city_id} -> %{city: city_id, dept: department_id}
        _ -> %{dept: department_id}
      end

    {:noreply, push_patch(socket, to: ~p"/departments?#{params}")}
  end

  def handle_event("change_city", %{"city_selector" => %{"city_id" => city_id}}, socket)
      when is_binary(city_id) do
    params =
      case city_id do
        "" -> %{}
        _ -> %{city: city_id}
      end

    {:noreply, push_patch(socket, to: ~p"/departments?#{params}")}
  end

  def handle_event("select_department_tab", %{"tab" => tab}, socket) when tab in @detail_tabs do
    {:noreply, push_patch(socket, to: ~p"/departments?#{detail_params(socket, %{tab: tab})}")}
  end

  def handle_event("validate_department_settings", %{"department" => params}, socket) do
    changeset =
      socket.assigns.selected_department
      |> Department.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :department_settings_form, to_form(changeset, as: :department))}
  end

  def handle_event("save_department_settings", %{"department" => params}, socket) do
    case Departments.update_department(socket.assigns.selected_department, params) do
      {:ok, department} ->
        department = reload_department_detail(department)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("world", ".flash_department_settings_saved"))
         |> assign_department_detail(department, socket.assigns.selected_department_tab)}

      {:error, changeset} ->
        {:noreply, assign(socket, :department_settings_form, to_form(changeset, as: :department))}
    end
  end

  def handle_event("department_lifecycle", %{"action" => action}, socket)
      when action in ["activate", "drain", "disable", "delete"] do
    department = socket.assigns.selected_department

    case apply_lifecycle_action(department, action) do
      {:ok, deleted_department} when action == "delete" ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("world", ".flash_department_deleted"))
         |> push_patch(to: ~p"/departments?#{%{city: deleted_department.city_id}}")}

      {:ok, department} ->
        department = reload_department_detail(department)

        {:noreply,
         socket
         |> put_flash(:info, lifecycle_flash(action))
         |> assign_department_detail(department, socket.assigns.selected_department_tab)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", ".flash_department_lifecycle_failed"))
         |> assign(:department_settings_form, to_form(changeset, as: :department))}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, Exception.message(error))}
    end
  end

  def handle_event("save_department_secret", %{"secret" => params}, socket) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, _metadata} <-
           SecretBank.upsert_secret(department, params["bank_key"], params["value"]) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_saved"))
       |> assign(:department_secret_form, blank_secret_form())
       |> push_event("secret_form:reset", %{form_id: "department-secret-form"})
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, :invalid_key} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("errors", ".error_invalid_key")
         )
         |> assign(:department_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{
           form_id: "department-secret-form",
           field: "bank_key"
         })}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_value_required"))
         |> assign(:department_secret_form, secret_form_with_key(params["bank_key"]))
         |> push_event("secret_form:focus", %{form_id: "department-secret-form", field: "value"})}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("errors", ".error_secret_save_failed"))
         |> assign(:department_secret_form, secret_form_with_key(params["bank_key"]))}
    end
  end

  def handle_event("delete_department_secret", %{"bank-key" => bank_key}, socket) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, _metadata} <- SecretBank.delete_secret(department, bank_key) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", ".secret_deleted"))
       |> push_event("secret_form:focus", %{form_id: "department-secret-form", field: "bank_key"})
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

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

  def handle_event("edit_department_secret", %{"bank-key" => bank_key}, socket) do
    {:noreply,
     socket
     |> assign(:department_secret_form, secret_form_with_key(bank_key))
     |> push_event("secret_form:focus", %{form_id: "department-secret-form", field: "value"})}
  end

  def handle_event(
        "change_department_connection_create_type",
        %{"connection_create" => %{"type" => type}},
        socket
      ) do
    {:noreply,
     assign(
       socket,
       :department_connection_create_form,
       ConnectionsSurface.create_form(socket.assigns.department_connection_types, %{
         "type" => type
       })
     )}
  end

  def handle_event("open_department_connection_create", _params, socket) do
    {:noreply, assign(socket, :department_connection_create_open, true)}
  end

  def handle_event("close_department_connection_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:department_connection_create_open, false)
     |> assign(
       :department_connection_create_form,
       ConnectionsSurface.create_form(socket.assigns.department_connection_types)
     )}
  end

  def handle_event("create_department_connection", %{"connection_create" => params}, socket) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, attrs} <- ConnectionsSurface.parse_connection_form_params(params),
         {:ok, _connection} <- Connections.create_connection(department, attrs) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_created"))
       |> assign(:department_connection_create_open, false)
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:department_connection_create_open, true)
         |> assign(
           :department_connection_create_form,
           to_form(changeset, as: :connection_create)
         )}

      {:error, :invalid_payload} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_invalid_payload"))}
    end
  end

  def handle_event(
        "start_department_connection_edit",
        %{"connection_id" => connection_id},
        socket
      ) do
    case ConnectionsSurface.find_local_connection_row(
           socket.assigns.department_connection_rows,
           connection_id
         ) do
      {:ok, row} ->
        {:noreply,
         socket
         |> assign(:department_connection_editing_id, connection_id)
         |> assign(:department_connection_edit_form, ConnectionsSurface.edit_form(row.connection))}

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("cancel_department_connection_edit", _params, socket) do
    {:noreply,
     assign(socket, department_connection_editing_id: nil, department_connection_edit_form: nil)}
  end

  def handle_event(
        "change_department_connection_edit_type",
        %{"connection_edit" => %{"connection_id" => connection_id, "type" => type}},
        socket
      ) do
    case ConnectionsSurface.find_local_connection_row(
           socket.assigns.department_connection_rows,
           connection_id
         ) do
      {:ok, row} ->
        config_text =
          ConnectionsSurface.default_config_text(socket.assigns.department_connection_types, type)

        params = %{
          "connection_id" => row.connection.id,
          "type" => type,
          "status" => row.connection.status,
          "config" => config_text
        }

        {:noreply,
         assign(socket, :department_connection_edit_form, ConnectionsSurface.edit_form(params))}

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("change_department_connection_edit_type", _params, socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("layout", ".connections_flash_invalid_payload"))}
  end

  def handle_event("save_department_connection_edit", %{"connection_edit" => params}, socket) do
    connection_id = Map.get(params, "connection_id", "")

    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, row} <-
           ConnectionsSurface.find_local_connection_row(
             socket.assigns.department_connection_rows,
             connection_id
           ),
         {:ok, attrs} <- ConnectionsSurface.parse_connection_form_params(params),
         {:ok, _connection} <- Connections.update_connection(department, row.connection, attrs) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_updated"))
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, :invalid_payload} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_invalid_payload"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("delete_department_connection", %{"connection_id" => connection_id}, socket) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, row} <-
           ConnectionsSurface.find_local_connection_row(
             socket.assigns.department_connection_rows,
             connection_id
           ),
         {:ok, _connection} <- Connections.delete_connection(department, row.connection) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_deleted"))
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event(
        "department_connection_lifecycle",
        %{"connection_id" => connection_id, "action" => action},
        socket
      ) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, row} <-
           ConnectionsSurface.find_local_connection_row(
             socket.assigns.department_connection_rows,
             connection_id
           ),
         {:ok, _connection} <-
           ConnectionsSurface.run_connection_lifecycle(department, row.connection, action) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_status_updated"))
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, dgettext("layout", ".connections_flash_local_only"))}
    end
  end

  def handle_event("test_department_connection", %{"type" => type}, socket) do
    with %Department{} = department <- socket.assigns.selected_department,
         {:ok, _result} <- Connections.test_connection(department, type) do
      department = reload_department_detail(department)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("layout", ".connections_flash_tested"))
       |> assign_department_detail(department, socket.assigns.selected_department_tab)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("errors", ".error_department_unavailable"))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("layout", ".connections_flash_test_failed"))}
    end
  end

  defp build_shell_breadcrumb(nil, nil), do: default_shell_breadcrumb(:departments)

  defp build_shell_breadcrumb(city, nil) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}")
    ]
  end

  defp build_shell_breadcrumb(city, department) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}"),
      shell_item(
        department.name || department.id,
        "/departments?city=#{city.id}&dept=#{department.id}"
      )
    ]
  end

  defp load_page(socket, params) do
    case CitiesPageSnapshot.build(city_id: params["city"]) do
      {:ok, snapshot} ->
        selected_city = snapshot.selected_city
        departments = load_departments(snapshot, selected_city)

        selected_department =
          departments
          |> select_department(params["dept"])
          |> reload_department_detail()

        socket
        |> assign(:world, snapshot.world)
        |> assign(:cities, snapshot.cities)
        |> assign(:city_selector_form, city_selector_form(selected_city))
        |> assign(:selected_city, selected_city)
        |> assign(:departments, departments)
        |> assign_department_detail(selected_department, params["tab"])
        |> put_shell_breadcrumb(build_shell_breadcrumb(selected_city, selected_department))

      {:error, :not_found} ->
        socket
        |> assign(:world, nil)
        |> assign(:cities, [])
        |> assign(:city_selector_form, to_form(%{"city_id" => ""}, as: :city_selector))
        |> assign(:selected_city, nil)
        |> assign(:departments, [])
        |> assign(:selected_department, nil)
        |> assign(:selected_department_tab, "overview")
        |> assign(:department_settings_form, nil)
        |> assign(:department_effective_config, nil)
        |> assign(:department_local_overrides, nil)
        |> assign(:department_lemmings, [])
        |> assign(:department_primary_manager, nil)
        |> assign(:department_secret_metadata, [])
        |> assign(:department_secret_env_policy, [])
        |> assign(:department_secret_activity, [])
        |> assign(:department_connection_rows, [])
        |> assign(
          :department_connection_create_form,
          ConnectionsSurface.create_form(socket.assigns.department_connection_types)
        )
        |> assign(:department_connection_editing_id, nil)
        |> assign(:department_connection_edit_form, nil)
        |> put_shell_breadcrumb(default_shell_breadcrumb(:departments))
    end
  end

  defp load_departments(_snapshot, nil), do: []

  defp load_departments(%{world: %{id: world_id}}, %{id: city_id})
       when is_binary(world_id) and is_binary(city_id) do
    with %World{} = world <- Worlds.get_world(world_id),
         %City{} = city <- Cities.get_city(world, city_id) do
      Departments.list_departments(city, preload: [:city, :world])
    else
      _ -> []
    end
  end

  defp load_departments(_, _), do: []

  defp select_department([], _department_id), do: nil
  defp select_department(_departments, nil), do: nil

  defp select_department(departments, department_id) when is_binary(department_id) do
    Enum.find(departments, &(&1.id == department_id))
  end

  defp select_department(_departments, _department_id), do: nil

  defp reload_department_detail(nil), do: nil

  defp reload_department_detail(%Department{} = department) do
    Departments.get_department(department.id, preload: [:world, :city])
  end

  defp assign_department_detail(socket, nil, _requested_tab) do
    socket
    |> assign(:selected_department, nil)
    |> assign(:selected_department_tab, "overview")
    |> assign(:department_settings_form, nil)
    |> assign(:department_effective_config, nil)
    |> assign(:department_local_overrides, nil)
    |> assign(:department_lemmings, [])
    |> assign(:department_primary_manager, nil)
    |> assign(:department_secret_form, blank_secret_form())
    |> assign(:department_secret_metadata, [])
    |> assign(:department_secret_env_policy, [])
    |> assign(:department_secret_activity, [])
    |> assign(:department_connection_rows, [])
    |> assign(
      :department_connection_create_form,
      ConnectionsSurface.create_form(socket.assigns.department_connection_types)
    )
    |> assign(:department_connection_create_open, false)
    |> assign(:department_connection_editing_id, nil)
    |> assign(:department_connection_edit_form, nil)
  end

  defp assign_department_detail(socket, %Department{} = department, requested_tab) do
    collaboration = DepartmentCollaborationSnapshot.build(department)

    socket
    |> assign(:selected_department, department)
    |> assign(:selected_department_tab, normalize_department_tab(requested_tab))
    |> assign(:department_settings_form, build_department_settings_form(department))
    |> assign(:department_effective_config, Resolver.resolve(department))
    |> assign(:department_local_overrides, department_local_overrides(department))
    |> assign(:department_lemmings, collaboration.lemming_types)
    |> assign(:department_primary_manager, collaboration.primary_manager)
    |> assign(:department_secret_form, blank_secret_form())
    |> assign(:department_secret_metadata, SecretBank.list_effective_metadata(department))
    |> assign(:department_secret_env_policy, SecretBank.list_env_fallback_policy())
    |> assign(:department_secret_activity, SecretBank.list_recent_activity(department, limit: 10))
    |> assign(:department_connection_rows, Connections.list_visible_connections(department))
    |> assign(
      :department_connection_create_form,
      ConnectionsSurface.create_form(socket.assigns.department_connection_types)
    )
    |> assign(:department_connection_create_open, false)
    |> assign(:department_connection_editing_id, nil)
    |> assign(:department_connection_edit_form, nil)
  end

  defp build_department_settings_form(%Department{} = department) do
    department
    |> Department.changeset(%{})
    |> to_form(as: :department)
  end

  defp normalize_department_tab(tab) when tab in @detail_tabs, do: tab
  defp normalize_department_tab(_tab), do: "overview"

  defp detail_params(socket, extra_params) do
    base =
      %{}
      |> maybe_put_param(:city, socket.assigns.selected_city && socket.assigns.selected_city.id)
      |> maybe_put_param(
        :dept,
        socket.assigns.selected_department && socket.assigns.selected_department.id
      )
      |> maybe_put_param(:tab, socket.assigns.selected_department_tab)

    Enum.reduce(extra_params, base, fn
      {_key, nil}, acc -> acc
      {"tab", "overview"}, acc -> Map.delete(acc, :tab)
      {:tab, "overview"}, acc -> Map.delete(acc, :tab)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  defp department_local_overrides(%Department{} = department) do
    %{
      limits_config: prune_local_override(Map.from_struct(department.limits_config || %{})),
      runtime_config: prune_local_override(Map.from_struct(department.runtime_config || %{})),
      costs_config: department_costs_override(department),
      models_config: prune_local_override(Map.from_struct(department.models_config || %{}))
    }
  end

  defp department_costs_override(%Department{costs_config: nil}), do: %{}

  defp department_costs_override(%Department{costs_config: costs_config}) do
    costs_config
    |> Map.from_struct()
    |> Map.update(:budgets, %{}, fn
      nil -> %{}
      budgets -> Map.from_struct(budgets)
    end)
    |> prune_local_override()
  end

  defp prune_local_override(map) when map == %{}, do: %{}

  defp prune_local_override(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        case prune_local_override(value) do
          %{} -> acc
          pruned -> Map.put(acc, key, pruned)
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp apply_lifecycle_action(department, "activate"),
    do: Departments.set_department_status(department, "active")

  defp apply_lifecycle_action(department, "drain"),
    do: Departments.set_department_status(department, "draining")

  defp apply_lifecycle_action(department, "disable"),
    do: Departments.set_department_status(department, "disabled")

  defp apply_lifecycle_action(department, "delete"), do: Departments.delete_department(department)

  defp lifecycle_flash("activate"), do: dgettext("world", ".flash_department_activated")
  defp lifecycle_flash("drain"), do: dgettext("world", ".flash_department_draining")
  defp lifecycle_flash("disable"), do: dgettext("world", ".flash_department_disabled")
  defp lifecycle_flash(_action), do: dgettext("world", ".flash_department_updated")

  defp city_selector_form(selected_city) do
    selected_city_id =
      case selected_city do
        %{id: city_id} -> city_id
        _ -> ""
      end

    to_form(%{"city_id" => selected_city_id}, as: :city_selector)
  end

  defp blank_secret_form, do: to_form(%{"bank_key" => "", "value" => ""}, as: :secret)

  defp secret_form_with_key(bank_key) do
    to_form(%{"bank_key" => String.trim(bank_key || ""), "value" => ""}, as: :secret)
  end
end
