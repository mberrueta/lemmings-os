defmodule LemmingsOsWeb.LemmingsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.ImportExport
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("layout", ".page_title_lemmings"))
     |> assign(:world, nil)
     |> assign(:cities, [])
     |> assign(:departments, [])
     |> assign(:selected_city, nil)
     |> assign(:selected_department, nil)
     |> assign(:filters_form, filters_form(nil, nil))
     |> assign(:lemmings, [])
     |> assign(:selected_lemming, nil)
     |> assign(:selected_lemming_effective_config, nil)
     |> assign(:selected_lemming_inheriting?, false)
     |> assign(:lemming_not_found?, false)
     |> assign(:active_detail_tab, "overview")
     |> assign(:settings_form, nil)
     |> assign(:overview_path, nil)
     |> assign(:edit_path, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  def handle_event("change_filters", %{"filters" => filters}, socket) do
    params =
      %{}
      |> maybe_put_param(:city, filters["city_id"])
      |> maybe_put_param(:dept, filters["department_id"])

    {:noreply, push_patch(socket, to: ~p"/lemmings?#{params}")}
  end

  def handle_event("validate_lemming_settings", %{"lemming" => params}, socket) do
    {:noreply, assign_settings_form(socket, socket.assigns.selected_lemming, params, :validate)}
  end

  def handle_event("save_lemming_settings", %{"lemming" => params}, socket) do
    attrs = Map.take(params, ["name", "slug", "description", "instructions", "status"])

    if active_without_instructions?(socket.assigns.selected_lemming, attrs) do
      {:noreply,
       socket
       |> assign_settings_form(socket.assigns.selected_lemming, params, :validate)
       |> put_flash(:error, dgettext("lemmings", ".flash_instructions_required"))}
    else
      case Lemmings.update_lemming(socket.assigns.selected_lemming, attrs) do
        {:ok, lemming} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("lemmings", ".flash_lemming_saved"))
           |> load_page(stringify_keys(overview_tab_params(socket, lemming)))}

        {:error, %Ecto.Changeset{} = _changeset} ->
          {:noreply,
           assign_settings_form(socket, socket.assigns.selected_lemming, params, :validate)}
      end
    end
  end

  def handle_event("lemming_lifecycle", %{"action" => action}, socket)
      when action in ["activate", "archive"] do
    case apply_lifecycle_action(socket.assigns.selected_lemming, action) do
      {:ok, lemming} ->
        params =
          socket
          |> current_scope_params()
          |> Map.put(:lemming, lemming.id)

        {:noreply,
         socket
         |> put_flash(:info, lifecycle_flash(action))
         |> load_page(stringify_keys(params))}

      {:error, :instructions_required} ->
        {:noreply,
         put_flash(socket, :error, dgettext("lemmings", ".flash_instructions_required"))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(socket, :error, dgettext("lemmings", ".flash_lemming_update_failed"))}
    end
  end

  def handle_event("export_lemming", _params, %{assigns: %{selected_lemming: lemming}} = socket)
      when not is_nil(lemming) do
    export_map = ImportExport.export_lemming(lemming)
    json_string = Jason.encode!(export_map, pretty: true)
    filename = "lemming-#{lemming.slug}.json"

    {:noreply, push_event(socket, "download_json", %{filename: filename, content: json_string})}
  end

  def handle_event("export_lemming", _params, socket) do
    {:noreply, put_flash(socket, :error, dgettext("lemmings", ".flash_export_no_lemming"))}
  end

  defp load_page(socket, params) do
    case Worlds.get_default_world() do
      {:ok, world} ->
        selected_lemming = load_selected_lemming(lemming_id_param(socket, params))
        cities = Cities.list_cities(world)
        selected_city = selected_city(cities, params["city"], selected_lemming)
        departments = load_departments(world, selected_city)
        selected_department = selected_department(departments, params["dept"], selected_lemming)
        lemmings = load_lemmings(world, selected_city, selected_department)
        selected_lemming = selected_lemming(socket, lemmings, selected_lemming, params)

        socket
        |> assign(:world, world)
        |> assign(:cities, cities)
        |> assign(:departments, departments)
        |> assign(:selected_city, selected_city)
        |> assign(:selected_department, selected_department)
        |> assign(:filters_form, filters_form(selected_city, selected_department))
        |> assign(:lemmings, lemmings)
        |> assign(:lemming_not_found?, lemming_not_found?(socket, params, selected_lemming))
        |> assign(:active_detail_tab, active_detail_tab(socket, params))
        |> assign_selected_lemming(selected_lemming)
        |> put_shell_breadcrumb(
          build_shell_breadcrumb(world, selected_city, selected_department, selected_lemming)
        )

      {:error, :not_found} ->
        socket
        |> assign(:world, nil)
        |> assign(:cities, [])
        |> assign(:departments, [])
        |> assign(:selected_city, nil)
        |> assign(:selected_department, nil)
        |> assign(:filters_form, filters_form(nil, nil))
        |> assign(:lemmings, [])
        |> assign(:selected_lemming, nil)
        |> assign(:selected_lemming_effective_config, nil)
        |> assign(:selected_lemming_inheriting?, false)
        |> assign(:lemming_not_found?, false)
        |> assign(:active_detail_tab, "overview")
        |> assign(:settings_form, nil)
        |> assign(:overview_path, nil)
        |> assign(:edit_path, nil)
        |> put_shell_breadcrumb(default_shell_breadcrumb(:lemmings))
    end
  end

  defp filters_form(selected_city, selected_department) do
    to_form(
      %{
        "city_id" => (selected_city && selected_city.id) || "",
        "department_id" => (selected_department && selected_department.id) || ""
      },
      as: :filters
    )
  end

  defp assign_selected_lemming(socket, nil) do
    socket
    |> assign(:selected_lemming, nil)
    |> assign(:selected_lemming_effective_config, nil)
    |> assign(:selected_lemming_inheriting?, false)
    |> assign(:settings_form, nil)
    |> assign(:overview_path, nil)
    |> assign(:edit_path, nil)
  end

  defp assign_selected_lemming(socket, %Lemming{} = lemming) do
    lemming = hydrate_resolver_chain(lemming, socket.assigns.world)

    changeset =
      lemming
      |> Lemming.changeset(%{})
      |> build_settings_changeset(nil)

    socket
    |> assign(:selected_lemming, lemming)
    |> assign(:selected_lemming_effective_config, Resolver.resolve(lemming))
    |> assign(:selected_lemming_inheriting?, inheriting_all_configuration?(lemming))
    |> assign(:settings_form, to_form(changeset, as: :lemming))
    |> assign(:overview_path, detail_path(lemming, socket, "overview"))
    |> assign(:edit_path, detail_path(lemming, socket, "edit"))
  end

  defp load_selected_lemming(nil), do: nil

  defp load_selected_lemming(lemming_id) when is_binary(lemming_id) do
    Lemmings.get_lemming(lemming_id, preload: [:world, city: :world, department: [city: :world]])
  end

  defp selected_city([], _city_param, _selected_lemming), do: nil

  defp selected_city(cities, city_param, %Lemming{} = selected_lemming) do
    Enum.find(cities, &(&1.id == resolve_city_id(city_param, selected_lemming))) ||
      List.first(cities)
  end

  defp selected_city(cities, city_param, nil) do
    Enum.find(cities, &(&1.id == city_param)) || List.first(cities)
  end

  defp selected_department([], _dept_param, _selected_lemming), do: nil

  defp selected_department(departments, dept_param, %Lemming{} = selected_lemming) do
    Enum.find(departments, &(&1.id == resolve_department_id(dept_param, selected_lemming)))
  end

  defp selected_department(departments, dept_param, nil) when is_binary(dept_param) do
    Enum.find(departments, &(&1.id == dept_param))
  end

  defp selected_department(_departments, _dept_param, nil), do: nil

  defp load_departments(_world, nil), do: []

  defp load_departments(%World{} = world, %City{} = city) do
    Departments.list_departments(world, city, preload: [:city, :world])
  end

  defp load_lemmings(_world, _city, %Department{} = department) do
    Lemmings.list_lemmings(department, preload: [department: [:city]])
  end

  defp load_lemmings(_world, %City{} = city, nil) do
    Lemmings.list_lemmings(city, preload: [department: [:city]])
  end

  defp load_lemmings(%World{} = world, nil, nil) do
    Lemmings.list_lemmings(world, preload: [department: [:city]])
  end

  defp selected_lemming(%{assigns: %{live_action: :index}}, _lemmings, _fallback, _params),
    do: nil

  defp selected_lemming(_socket, lemmings, nil, _params), do: List.first(lemmings)

  defp selected_lemming(_socket, lemmings, %Lemming{id: id} = fallback, _params) do
    Enum.find(lemmings, &(&1.id == id)) || fallback
  end

  defp lemming_id_param(%{assigns: %{live_action: :show}}, %{"id" => id}), do: id
  defp lemming_id_param(_socket, %{"lemming" => id}) when is_binary(id), do: id
  defp lemming_id_param(_socket, _params), do: nil

  defp lemming_not_found?(%{assigns: %{live_action: :show}}, %{"id" => id}, nil)
       when is_binary(id),
       do: true

  defp lemming_not_found?(_socket, _params, _selected_lemming), do: false

  defp build_shell_breadcrumb(world, nil, nil, nil) do
    [
      shell_item(:cities, "/cities"),
      shell_item(world.name || world.id, "/lemmings")
    ]
  end

  defp build_shell_breadcrumb(_world, %City{} = city, nil, nil) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:lemmings, "/lemmings?city=#{city.id}")
    ]
  end

  defp build_shell_breadcrumb(_world, %City{} = city, %Department{} = department, nil) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}"),
      shell_item(
        department.name || department.id,
        "/lemmings?city=#{city.id}&dept=#{department.id}"
      )
    ]
  end

  defp build_shell_breadcrumb(
         _world,
         %City{} = city,
         %Department{} = department,
         %Lemming{} = lemming
       ) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:departments, "/departments?city=#{city.id}"),
      shell_item(
        department.name || department.id,
        "/departments?city=#{city.id}&dept=#{department.id}"
      ),
      shell_item(
        lemming.name || lemming.id,
        "/lemmings/#{lemming.id}?city=#{city.id}&dept=#{department.id}"
      )
    ]
  end

  defp build_shell_breadcrumb(_world, %City{} = city, nil, %Lemming{} = lemming) do
    [
      shell_item(:cities, "/cities"),
      shell_item(city.name || city.id, "/cities?city=#{city.id}"),
      shell_item(:lemmings, "/lemmings?city=#{city.id}"),
      shell_item(lemming.name || lemming.id, "/lemmings/#{lemming.id}?city=#{city.id}")
    ]
  end

  defp apply_lifecycle_action(lemming, "activate"),
    do: Lemmings.set_lemming_status(lemming, "active")

  defp apply_lifecycle_action(lemming, "archive"),
    do: Lemmings.set_lemming_status(lemming, "archived")

  defp lifecycle_flash("activate"), do: dgettext("lemmings", ".flash_lemming_activated")
  defp lifecycle_flash("archive"), do: dgettext("lemmings", ".flash_lemming_archived")

  defp inheriting_all_configuration?(%Lemming{} = lemming) do
    lemming
    |> local_override_buckets()
    |> Enum.all?(&(&1 == %{}))
  end

  defp local_override_buckets(%Lemming{} = lemming) do
    [
      prune_override(Map.from_struct(lemming.limits_config || %{})),
      prune_override(Map.from_struct(lemming.runtime_config || %{})),
      prune_override(lemming_costs_override(lemming)),
      prune_override(Map.from_struct(lemming.models_config || %{})),
      prune_override(Map.from_struct(lemming.tools_config || %{}))
    ]
  end

  defp lemming_costs_override(%Lemming{costs_config: nil}), do: %{}

  defp lemming_costs_override(%Lemming{costs_config: costs_config}) do
    costs_config
    |> Map.from_struct()
    |> Map.update(:budgets, %{}, fn
      nil -> %{}
      budgets -> Map.from_struct(budgets)
    end)
  end

  defp prune_override(map) when map == %{}, do: %{}

  defp prune_override(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {_key, []}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        case prune_override(value) do
          %{} -> acc
          pruned -> Map.put(acc, key, pruned)
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp resolve_city_id(city_param, %Lemming{}) when is_binary(city_param), do: city_param

  defp resolve_city_id(_city_param, %Lemming{city_id: city_id}), do: city_id

  defp resolve_department_id(dept_param, %Lemming{}) when is_binary(dept_param), do: dept_param

  defp resolve_department_id(_dept_param, %Lemming{department_id: department_id}),
    do: department_id

  defp current_scope_params(socket) do
    %{}
    |> maybe_put_param(:city, socket.assigns.selected_city && socket.assigns.selected_city.id)
    |> maybe_put_param(
      :dept,
      socket.assigns.selected_department && socket.assigns.selected_department.id
    )
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, _key, ""), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  defp stringify_keys(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp active_detail_tab(%{assigns: %{live_action: :show}}, %{"tab" => "edit"}), do: "edit"
  defp active_detail_tab(%{assigns: %{live_action: :show}}, _params), do: "overview"
  defp active_detail_tab(_socket, _params), do: "overview"

  defp detail_path(%Lemming{} = lemming, socket, tab) do
    params =
      socket
      |> current_scope_params()
      |> maybe_put_param(:tab, normalize_overview_tab(tab))

    ~p"/lemmings/#{lemming.id}?#{params}"
  end

  defp normalize_overview_tab("overview"), do: nil
  defp normalize_overview_tab(tab), do: tab

  defp overview_tab_params(socket, %Lemming{} = lemming) do
    socket
    |> current_scope_params()
    |> Map.put(:id, lemming.id)
  end

  defp assign_settings_form(socket, %Lemming{} = lemming, params, action) do
    attrs = Map.take(params, ["name", "slug", "description", "instructions", "status"])

    changeset =
      lemming
      |> Lemming.changeset(attrs)
      |> build_settings_changeset(action)

    assign(socket, :settings_form, to_form(changeset, as: :lemming))
  end

  defp build_settings_changeset(changeset, nil), do: changeset
  defp build_settings_changeset(changeset, action), do: Map.put(changeset, :action, action)

  defp active_without_instructions?(%Lemming{} = lemming, attrs) do
    desired_status = Map.get(attrs, "status", lemming.status)
    desired_instructions = Map.get(attrs, "instructions", lemming.instructions)

    desired_status == "active" and Helpers.blank?(desired_instructions)
  end

  defp hydrate_resolver_chain(
         %Lemming{department: %Department{city: %City{} = department_city} = department} =
           lemming,
         %World{} = world
       ) do
    %{
      lemming
      | world: world,
        city: %{department_city | world: world},
        department: %{department | world: world, city: %{department_city | world: world}}
    }
  end

  defp hydrate_resolver_chain(%Lemming{} = lemming, _world), do: lemming
end
