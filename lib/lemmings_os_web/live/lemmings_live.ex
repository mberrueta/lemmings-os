defmodule LemmingsOsWeb.LemmingsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.ImportExport
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Runtime
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("layout", ".page_title_lemmings"))
     |> assign(
       world: nil,
       cities: [],
       departments: [],
       selected_city: nil,
       selected_department: nil,
       filters_form: filters_form(nil, nil),
       lemmings: [],
       selected_lemming: nil,
       selected_lemming_effective_config: nil,
       selected_lemming_inheriting?: false,
       lemming_not_found?: false,
       active_detail_tab: "overview",
       settings_form: nil,
       spawn_form: nil,
       spawn_modal_open?: false,
       spawn_enabled?: false,
       spawn_disabled_reason: nil,
       lemming_instances: [],
       recent_lemming_instances: [],
       overview_path: nil,
       edit_path: nil,
       secrets_path: nil,
       lemming_secret_form: blank_secret_form(),
       lemming_secret_metadata: [],
       lemming_secret_activity: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_page(socket, params)}
  end

  @impl true
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

  def handle_event("save_lemming_secret", %{"secret" => params}, socket) do
    with %Lemming{} = lemming <- socket.assigns.selected_lemming,
         {:ok, _metadata} <-
           SecretBank.upsert_secret(lemming, params["bank_key"], params["value"]) do
      lemming = load_selected_lemming(lemming.id)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", "Secret saved"))
       |> assign(:lemming_secret_form, secret_form_with_key(params["bank_key"]))
       |> assign_selected_lemming(lemming)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("world", "Lemming is unavailable"))}

      {:error, :invalid_key} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", "Secret key is required"))
         |> assign(:lemming_secret_form, secret_form_with_key(params["bank_key"]))}

      {:error, :invalid_value} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", "Secret value is required"))
         |> assign(:lemming_secret_form, secret_form_with_key(params["bank_key"]))}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("world", "Failed to save secret"))
         |> assign(:lemming_secret_form, secret_form_with_key(params["bank_key"]))}
    end
  end

  def handle_event("delete_lemming_secret", %{"bank-key" => bank_key}, socket) do
    with %Lemming{} = lemming <- socket.assigns.selected_lemming,
         {:ok, _metadata} <- SecretBank.delete_secret(lemming, bank_key) do
      lemming = load_selected_lemming(lemming.id)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("world", "Local secret deleted"))
       |> assign_selected_lemming(lemming)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("world", "Lemming is unavailable"))}

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

  def handle_event("open_spawn_modal", _params, socket) do
    if socket.assigns.spawn_enabled? do
      {:noreply,
       socket
       |> assign(spawn_modal_open?: true, spawn_form: blank_spawn_form())}
    else
      {:noreply, put_flash(socket, :error, spawn_error_message(:lemming_not_active))}
    end
  end

  def handle_event("close_spawn_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(spawn_modal_open?: false, spawn_form: blank_spawn_form())}
  end

  def handle_event("validate_spawn", %{"spawn" => params}, socket) do
    {:noreply,
     socket
     |> assign(spawn_modal_open?: true, spawn_form: spawn_form(params))}
  end

  def handle_event("submit_spawn", %{"spawn" => params}, socket) do
    changeset = spawn_changeset(params)

    if changeset.valid? and socket.assigns.spawn_enabled? do
      request_text = Ecto.Changeset.get_field(changeset, :request_text)

      case Runtime.spawn_session(socket.assigns.selected_lemming, request_text,
             world: socket.assigns.world
           ) do
        {:ok, instance} ->
          {:noreply,
           push_navigate(socket, to: instance_session_path(instance, socket.assigns.world.id))}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(spawn_modal_open?: true, spawn_form: spawn_form(params))
           |> put_flash(:error, spawn_error_message(reason))}
      end
    else
      {:noreply,
       socket
       |> assign(spawn_modal_open?: true, spawn_form: to_form(changeset, as: :spawn))}
    end
  end

  @impl true
  def handle_info({:status_changed, _payload}, socket) do
    {:noreply, refresh_lemming_instances(socket)}
  end

  defp load_page(socket, params) do
    case Worlds.get_default_world() do
      %World{} = world ->
        selected_lemming = load_selected_lemming(lemming_id_param(socket, params))
        cities = Cities.list_cities(world)
        selected_city = selected_city(cities, params["city"], selected_lemming)
        departments = load_departments(world, selected_city)
        selected_department = selected_department(departments, params["dept"], selected_lemming)
        lemmings = load_lemmings(world, selected_city, selected_department)
        selected_lemming = selected_lemming(socket, lemmings, selected_lemming, params)

        socket
        |> assign(
          world: world,
          cities: cities,
          departments: departments,
          selected_city: selected_city,
          selected_department: selected_department,
          filters_form: filters_form(selected_city, selected_department),
          lemmings: lemmings,
          lemming_not_found?: lemming_not_found?(socket, params, selected_lemming),
          active_detail_tab: active_detail_tab(socket, params)
        )
        |> assign_selected_lemming(selected_lemming)
        |> put_shell_breadcrumb(
          build_shell_breadcrumb(world, selected_city, selected_department, selected_lemming)
        )

      nil ->
        socket
        |> assign(
          world: nil,
          cities: [],
          departments: [],
          selected_city: nil,
          selected_department: nil,
          filters_form: filters_form(nil, nil),
          lemmings: [],
          selected_lemming: nil,
          selected_lemming_effective_config: nil,
          selected_lemming_inheriting?: false,
          lemming_not_found?: false,
          active_detail_tab: "overview",
          settings_form: nil,
          spawn_form: nil,
          spawn_modal_open?: false,
          spawn_enabled?: false,
          spawn_disabled_reason: nil,
          lemming_instances: [],
          recent_lemming_instances: [],
          overview_path: nil,
          edit_path: nil,
          secrets_path: nil,
          lemming_secret_form: blank_secret_form(),
          lemming_secret_metadata: [],
          lemming_secret_activity: []
        )
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
    |> assign(
      selected_lemming: nil,
      selected_lemming_effective_config: nil,
      selected_lemming_inheriting?: false,
      settings_form: nil,
      spawn_form: nil,
      spawn_modal_open?: false,
      spawn_enabled?: false,
      spawn_disabled_reason: nil,
      lemming_instances: [],
      recent_lemming_instances: [],
      overview_path: nil,
      edit_path: nil,
      secrets_path: nil,
      lemming_secret_form: blank_secret_form(),
      lemming_secret_metadata: [],
      lemming_secret_activity: []
    )
  end

  defp assign_selected_lemming(socket, %Lemming{} = lemming) do
    lemming = hydrate_resolver_chain(lemming, socket.assigns.world)

    changeset =
      lemming
      |> Lemming.changeset(%{})
      |> build_settings_changeset(nil)

    socket
    |> assign(
      selected_lemming: lemming,
      selected_lemming_effective_config: Resolver.resolve(lemming),
      selected_lemming_inheriting?: inheriting_all_configuration?(lemming),
      settings_form: to_form(changeset, as: :lemming),
      lemming_secret_form: blank_secret_form(),
      spawn_form: blank_spawn_form(),
      spawn_modal_open?: false
    )
    |> assign_spawn_state(lemming)
    |> assign(
      lemming_instances: load_lemming_instances(socket.assigns.world, lemming),
      recent_lemming_instances: load_recent_lemming_instances(socket.assigns.world, lemming),
      overview_path: detail_path(lemming, socket, "overview"),
      edit_path: detail_path(lemming, socket, "edit"),
      secrets_path: detail_path(lemming, socket, "secrets"),
      lemming_secret_metadata: SecretBank.list_effective_metadata(lemming),
      lemming_secret_activity: SecretBank.list_recent_activity(lemming, limit: 10)
    )
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

  defp load_departments(%World{}, %City{} = city) do
    Departments.list_departments(city, preload: [:city, :world])
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

  defp build_shell_breadcrumb(_world, nil, nil, %Lemming{} = lemming) do
    [
      shell_item(:cities, "/cities"),
      shell_item(:lemmings, "/lemmings"),
      shell_item(lemming.name || lemming.id, "/lemmings/#{lemming.id}")
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
  defp active_detail_tab(%{assigns: %{live_action: :show}}, %{"tab" => "secrets"}), do: "secrets"
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

  defp refresh_lemming_instances(
         %{assigns: %{world: %World{} = world, selected_lemming: %Lemming{} = lemming}} = socket
       ) do
    socket
    |> assign(:lemming_instances, load_lemming_instances(world, lemming))
    |> assign(:recent_lemming_instances, load_recent_lemming_instances(world, lemming))
  end

  defp refresh_lemming_instances(socket), do: socket

  defp load_lemming_instances(%World{} = world, %Lemming{} = lemming) do
    world
    |> LemmingInstances.list_instances(lemming_id: lemming.id)
    |> Enum.reject(&terminal_instance?/1)
    |> Enum.map(&instance_view_model/1)
    |> tap(&subscribe_instance_topics/1)
  end

  defp load_lemming_instances(_world, _lemming), do: []

  defp load_recent_lemming_instances(%World{} = world, %Lemming{} = lemming) do
    world
    |> LemmingInstances.list_instances(lemming_id: lemming.id, statuses: ["failed", "expired"])
    |> Enum.take(10)
    |> Enum.map(&instance_view_model/1)
  end

  defp load_recent_lemming_instances(_world, _lemming), do: []

  defp subscribe_instance_topics(instances) when is_list(instances) do
    Enum.each(instances, fn %{id: instance_id} ->
      _ = PubSub.subscribe_instance(instance_id)
    end)
  end

  defp instance_view_model(instance) do
    %{
      id: instance.id,
      status: instance.status,
      inserted_at: instance.inserted_at,
      preview: first_user_message_preview(instance)
    }
  end

  defp first_user_message_preview(instance) do
    instance
    |> LemmingsOs.LemmingInstances.list_messages([])
    |> Enum.find(&(&1.role == "user"))
    |> case do
      nil ->
        "No message yet"

      message ->
        Helpers.truncate_value(message.content,
          max_length: 120,
          unavailable_label: "No message yet"
        )
    end
  end

  defp terminal_instance?(%{status: status}), do: status in ["failed", "expired"]

  defp spawn_form(params) when is_map(params), do: to_form(spawn_changeset(params), as: :spawn)
  defp blank_spawn_form, do: spawn_form(%{})

  defp spawn_changeset(params) when is_map(params) do
    {%{}, %{request_text: :string}}
    |> Ecto.Changeset.cast(params, [:request_text])
    |> Ecto.Changeset.validate_required([:request_text])
  end

  defp spawn_error_message(:lemming_not_active), do: "The lemming must be active before spawning."
  defp spawn_error_message(:empty_request_text), do: "Enter a request before spawning."
  defp spawn_error_message(_reason), do: "Failed to create instance."

  defp assign_spawn_state(socket, %Lemming{status: "active"}) do
    socket
    |> assign(:spawn_enabled?, true)
    |> assign(:spawn_disabled_reason, nil)
  end

  defp assign_spawn_state(socket, %Lemming{} = lemming) do
    socket
    |> assign(:spawn_enabled?, false)
    |> assign(
      :spawn_disabled_reason,
      "Spawn is available when this lemming is active. Current status: #{lemming.status}."
    )
  end

  defp instance_session_path(%{id: instance_id}, world_id) do
    ~p"/lemmings/instances/#{instance_id}?#{%{world: world_id}}"
  end

  defp blank_secret_form, do: to_form(%{"bank_key" => "", "value" => ""}, as: :secret)

  defp secret_form_with_key(bank_key) do
    to_form(%{"bank_key" => String.trim(bank_key || ""), "value" => ""}, as: :secret)
  end
end
