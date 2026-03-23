defmodule LemmingsOsWeb.DepartmentsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.MockData
  alias LemmingsOs.Repo
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  @detail_tabs ~w(overview lemmings settings)

  def mount(_params, _session, socket) do
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
     |> assign(:department_lemming_preview, [])}
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
        department = preload_department_detail(department)

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
        department = preload_department_detail(department)

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
          |> preload_department_detail()

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
        |> assign(:department_lemming_preview, [])
        |> put_shell_breadcrumb(default_shell_breadcrumb(:departments))
    end
  end

  defp load_departments(_snapshot, nil), do: []

  defp load_departments(snapshot, selected_city) do
    Departments.list_departments(snapshot.world.id, selected_city.id, preload: [:city, :world])
  end

  defp select_department([], _department_id), do: nil
  defp select_department(_departments, nil), do: nil

  defp select_department(departments, department_id) when is_binary(department_id) do
    Enum.find(departments, &(&1.id == department_id))
  end

  defp select_department(_departments, _department_id), do: nil

  defp preload_department_detail(nil), do: nil

  defp preload_department_detail(%Department{} = department) do
    Repo.preload(department, [:world, city: [:world]])
  end

  defp assign_department_detail(socket, nil, _requested_tab) do
    socket
    |> assign(:selected_department, nil)
    |> assign(:selected_department_tab, "overview")
    |> assign(:department_settings_form, nil)
    |> assign(:department_effective_config, nil)
    |> assign(:department_local_overrides, nil)
    |> assign(:department_lemming_preview, [])
  end

  defp assign_department_detail(socket, %Department{} = department, requested_tab) do
    socket
    |> assign(:selected_department, department)
    |> assign(:selected_department_tab, normalize_department_tab(requested_tab))
    |> assign(:department_settings_form, build_department_settings_form(department))
    |> assign(:department_effective_config, Resolver.resolve(department))
    |> assign(:department_local_overrides, department_local_overrides(department))
    |> assign(:department_lemming_preview, department_lemming_preview(department))
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

  defp department_lemming_preview(%Department{} = department) do
    direct_preview = MockData.lemmings_for_department(department.slug)

    if direct_preview == [] do
      department.id
      |> :erlang.phash2()
      |> rem(max(length(MockData.lemmings()), 1))
      |> rotated_mock_lemmings()
    else
      direct_preview
    end
  end

  defp rotated_mock_lemmings(seed) do
    lemmings = MockData.lemmings()
    {head, tail} = Enum.split(lemmings, seed)
    Enum.take(tail ++ head, 4)
  end

  defp apply_lifecycle_action(department, "activate"),
    do: Departments.activate_department(department)

  defp apply_lifecycle_action(department, "drain"), do: Departments.drain_department(department)

  defp apply_lifecycle_action(department, "disable"),
    do: Departments.disable_department(department)

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
end
