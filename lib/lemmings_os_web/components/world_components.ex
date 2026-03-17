defmodule LemmingsOsWeb.WorldComponents do
  @moduledoc """
  Components for world, city, and department pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers
  alias LemmingsOs.MockData

  @map_cols 45
  @map_rows 26

  attr :snapshot, :map, default: nil
  attr :import_result, :map, default: nil
  attr :map_cities, :list, default: []
  attr :active_tab, :string, default: "overview"

  def world_page(assigns) do
    assigns =
      assigns
      |> assign(:bootstrap_issues, snapshot_issues(assigns.snapshot, :bootstrap))
      |> assign(:import_issues, import_issues(assigns.snapshot, assigns.import_result))
      |> assign(:runtime_checks, runtime_checks(assigns.snapshot))
      |> assign(:providers, providers(assigns.snapshot))
      |> assign(:profiles, profiles(assigns.snapshot))
      |> assign(:declared_limits, declared_limits(assigns.snapshot))
      |> assign(:declared_runtime, declared_runtime(assigns.snapshot))
      |> assign(:declared_budget, declared_budget(assigns.snapshot))

    ~H"""
    <.content_container>
      <.world_empty_state :if={is_nil(@snapshot)} import_result={@import_result} />
      <.world_snapshot
        :if={@snapshot}
        active_tab={@active_tab}
        map_cities={@map_cities}
        snapshot={@snapshot}
        bootstrap_issues={@bootstrap_issues}
        import_issues={@import_issues}
        runtime_checks={@runtime_checks}
        providers={@providers}
        profiles={@profiles}
        declared_limits={@declared_limits}
        declared_runtime={@declared_runtime}
        declared_budget={@declared_budget}
      />
    </.content_container>
    """
  end

  attr :snapshot, :map, required: true
  attr :active_tab, :string, required: true
  attr :map_cities, :list, required: true
  attr :bootstrap_issues, :list, required: true
  attr :import_issues, :list, required: true
  attr :runtime_checks, :list, required: true
  attr :providers, :list, required: true
  attr :profiles, :list, required: true
  attr :declared_limits, :map, required: true
  attr :declared_runtime, :map, required: true
  attr :declared_budget, :map, required: true

  defp world_snapshot(assigns) do
    ~H"""
    <.panel id="world-status-panel" tone="accent">
      <:title>{dgettext("world", ".title_world_status")}</:title>
      <:actions>
        <.button id="world-refresh-button" phx-click="refresh_status" variant="ghost" class="ml-auto">
          {dgettext("world", ".button_refresh_world")}
        </.button>
      </:actions>

      <div id="world-status-strip" class="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
        <div class="mini-card">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mini-card__title">{dgettext("world", ".title_world_identity")}</div>
              <p class="mini-card__meta">{@snapshot.world.name}</p>
            </div>
            <.status id="world-persisted-status" kind={:world} value={@snapshot.world.status} />
          </div>
        </div>

        <div class="mini-card">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mini-card__title">{dgettext("world", ".label_immediate_import")}</div>
              <p class="mini-card__meta">{dgettext("world", ".title_import_state")}</p>
            </div>
            <.status
              id="world-immediate-import-status"
              kind={:world}
              value={@snapshot.immediate_import.status}
            />
          </div>
        </div>

        <div class="mini-card">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mini-card__title">{dgettext("world", ".label_last_sync")}</div>
              <p class="mini-card__meta">
                {Helpers.format_datetime(@snapshot.last_sync.imported_at)}
              </p>
            </div>
            <.status id="world-last-sync-status" kind={:world} value={@snapshot.last_sync.status} />
          </div>
        </div>

        <div class="mini-card">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mini-card__title">{dgettext("world", ".title_bootstrap_config")}</div>
              <p class="mini-card__meta">{Helpers.display_value(@snapshot.bootstrap.source)}</p>
            </div>
            <.status id="world-bootstrap-status" kind={:world} value={@snapshot.bootstrap.status} />
          </div>
        </div>

        <div class="mini-card">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="mini-card__title">{dgettext("world", ".title_runtime_checks")}</div>
              <p class="mini-card__meta">{to_string(length(@runtime_checks))}</p>
            </div>
            <.status id="world-runtime-status" kind={:world} value={@snapshot.runtime.status} />
          </div>
        </div>
      </div>
    </.panel>

    <div id="world-tabs" class="flex flex-wrap gap-2">
      <.button
        id="world-tab-overview"
        phx-click="select_tab"
        phx-value-tab="overview"
        variant={tab_button_variant(@active_tab, "overview")}
      >
        {dgettext("world", ".tab_overview")}
      </.button>
      <.button
        id="world-tab-import"
        phx-click="select_tab"
        phx-value-tab="import"
        variant={tab_button_variant(@active_tab, "import")}
      >
        {dgettext("world", ".tab_import")}
      </.button>
      <.button
        id="world-tab-bootstrap"
        phx-click="select_tab"
        phx-value-tab="bootstrap"
        variant={tab_button_variant(@active_tab, "bootstrap")}
      >
        {dgettext("world", ".tab_bootstrap")}
      </.button>
      <.button
        id="world-tab-runtime"
        phx-click="select_tab"
        phx-value-tab="runtime"
        variant={tab_button_variant(@active_tab, "runtime")}
      >
        {dgettext("world", ".tab_runtime")}
      </.button>
    </div>

    <div :if={@active_tab == "overview"} id="world-overview-tab" class="page-stack">
      <.panel id="world-map-panel" tone="accent">
        <%!-- TODO(task 07 follow-up): the world topology still uses mock city data
          until the Cities slice exposes real world-scoped topology. --%>
        <MapComponents.world_map id="world-map" cities={@map_cities} />
      </.panel>
    </div>

    <.content_grid :if={@active_tab == "import"} id="world-import-grid" columns="two">
      <.panel id="world-import-panel">
        <:title>{dgettext("world", ".title_import_state")}</:title>
        <:actions>
          <.button
            id="world-import-button"
            phx-click="import_bootstrap"
            variant="secondary"
            class="ml-auto"
          >
            {dgettext("world", ".button_import_bootstrap")}
          </.button>
        </:actions>
        <div class="space-y-4">
          <div
            id="world-immediate-import"
            class="rounded-[var(--radius-sm)] border border-[var(--border-soft)] p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
                {dgettext("world", ".label_immediate_import")}
              </p>
              <.status kind={:world} value={@snapshot.immediate_import.status} />
            </div>
          </div>

          <div
            id="world-last-sync"
            class="rounded-[var(--radius-sm)] border border-[var(--border-soft)] p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
                {dgettext("world", ".label_last_sync")}
              </p>
              <.status kind={:world} value={@snapshot.last_sync.status} />
            </div>
          </div>

          <div class="grid gap-3">
            <.stat_item
              label={dgettext("world", ".label_last_imported_at")}
              value={Helpers.format_datetime(@snapshot.last_sync.imported_at)}
            />
            <.stat_item
              label={dgettext("world", ".label_last_bootstrap_hash")}
              value={Helpers.truncate_value(@snapshot.last_sync.bootstrap_hash)}
              detail={@snapshot.last_sync.bootstrap_hash}
            />
          </div>
        </div>
      </.panel>

      <.panel id="world-issues-panel">
        <:title>{dgettext("world", ".title_world_issues")}</:title>
        <div
          :if={@bootstrap_issues == [] and @import_issues == []}
          class="flex min-h-[12rem] items-center justify-center p-6 text-center"
        >
          <.badge tone="success">{dgettext("world", ".label_no_world_issues")}</.badge>
        </div>
        <div :if={@bootstrap_issues != [] or @import_issues != []} class="stack-list">
          <div :for={issue <- @bootstrap_issues ++ @import_issues} class="list-row-card">
            <div>
              <p class="list-row-card__title">{issue.summary}</p>
              <p class="list-row-card__meta">{issue.detail}</p>
              <p :if={issue.action_hint} class="list-row-card__meta">{issue.action_hint}</p>
            </div>
            <div class="list-row-card__aside">
              <.status kind={:issue} value={issue.severity} />
            </div>
          </div>
        </div>
      </.panel>
    </.content_grid>

    <div :if={@active_tab == "bootstrap"} class="page-stack">
      <.panel id="world-bootstrap-panel">
        <:title>{dgettext("world", ".title_bootstrap_config")}</:title>

        <div class="page-stack">
          <div class="grid gap-3 md:grid-cols-2">
            <.stat_item
              label={dgettext("world", ".label_bootstrap_source")}
              value={Helpers.display_value(@snapshot.bootstrap.source)}
            />
            <.stat_item
              label={dgettext("world", ".label_bootstrap_path")}
              value={Helpers.truncate_value(@snapshot.bootstrap.path)}
              detail={@snapshot.bootstrap.path}
            />
            <.stat_item
              label={runtime_check_label("postgres_connection")}
              value={Helpers.display_value(declared_postgres_url_env(@snapshot))}
            />
            <.stat_item
              label={dgettext("world", ".title_world_identity")}
              value={Helpers.display_value(bootstrap_world_name(@snapshot))}
              detail={bootstrap_identity_detail(@snapshot)}
            />
          </div>

          <div class="space-y-2">
            <h3 class="text-[0.76rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("world", ".label_providers")}
            </h3>
            <div class="stack-list">
              <div :for={provider <- @providers} class="list-row-card">
                <div>
                  <p class="list-row-card__title">{provider.name}</p>
                  <p class="list-row-card__meta">
                    {Enum.join(provider.allowed_models, ", ")}
                  </p>
                </div>
                <div class="list-row-card__aside">
                  <.badge tone={if(provider.enabled, do: "success", else: "default")}>
                    {provider_enabled_label(provider.enabled)}
                  </.badge>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <h3 class="text-[0.76rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("world", ".label_profiles")}
            </h3>
            <div class="stack-list">
              <div :for={profile <- @profiles} class="list-row-card">
                <div>
                  <p class="list-row-card__title">{profile.name}</p>
                  <p class="list-row-card__meta">{profile.provider} / {profile.model}</p>
                </div>
                <div class="list-row-card__aside">
                  <span>{fallback_summary(profile.fallbacks)}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="grid gap-3 md:grid-cols-2">
            <.stat_item
              label={dgettext("world", ".label_limits")}
              value={Helpers.display_value(Map.get(@declared_limits, :max_cities))}
              detail={limits_detail(@declared_limits)}
            />
            <.stat_item
              label={dgettext("world", ".label_budgets")}
              value={Helpers.display_value(Map.get(@declared_budget, :monthly_usd))}
              detail={budget_detail(@declared_budget)}
            />
            <.stat_item
              label={dgettext("world", ".label_runtime_defaults")}
              value={Helpers.display_value(Map.get(@declared_runtime, :idle_ttl_seconds))}
              detail={runtime_detail(@declared_runtime)}
            />
            <.stat_item
              label={dgettext("world", ".label_placeholder_sections")}
              value={placeholder_value(snapshot_placeholders(@snapshot))}
            />
          </div>
        </div>
      </.panel>

      <.content_grid id="world-placeholders-grid" columns="two">
        <.panel id="world-cities-placeholder-panel">
          <:title>{dgettext("world", ".title_world_cities_placeholder")}</:title>
          <div class="mini-card">
            <div class="mini-card__title">
              <.icon name="hero-building-office-2" class="size-5" />
              {dgettext("world", ".label_placeholder_only")}
            </div>
            <p class="mini-card__meta">{dgettext("world", ".copy_world_cities_placeholder")}</p>
          </div>
        </.panel>

        <.panel id="world-tools-placeholder-panel">
          <:title>{dgettext("world", ".title_world_tools_placeholder")}</:title>
          <div class="mini-card">
            <div class="mini-card__title">
              <.icon name="hero-wrench-screwdriver" class="size-5" />
              {dgettext("world", ".label_placeholder_only")}
            </div>
            <p class="mini-card__meta">{dgettext("world", ".copy_world_tools_placeholder")}</p>
          </div>
        </.panel>
      </.content_grid>
    </div>

    <.panel :if={@active_tab == "runtime"} id="world-runtime-panel">
      <:title>{dgettext("world", ".title_runtime_checks")}</:title>

      <div class="stack-list">
        <div
          :for={check <- @runtime_checks}
          id={"world-runtime-check-#{check.code}"}
          class="list-row-card"
          data-status={check.status}
        >
          <div>
            <p class="list-row-card__title">{runtime_check_label(check.code)}</p>
            <p class="list-row-card__meta">{runtime_check_detail(check)}</p>
          </div>
          <div class="list-row-card__aside">
            <.status
              id={"world-runtime-check-status-#{check.code}"}
              kind={:world}
              value={check.status}
            />
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  attr :import_result, :map, default: nil

  defp world_empty_state(assigns) do
    ~H"""
    <.panel id="world-empty-panel" tone="warning">
      <:title>{dgettext("world", ".title_world_identity")}</:title>
      <:actions>
        <.button id="world-refresh-button" phx-click="refresh_status" variant="ghost" class="ml-auto">
          {dgettext("world", ".button_refresh_world")}
        </.button>
        <.button id="world-import-button" phx-click="import_bootstrap" variant="secondary">
          {dgettext("world", ".button_import_bootstrap")}
        </.button>
      </:actions>
      <.empty_state
        id="world-page-empty-state"
        title={dgettext("world", ".empty_world_snapshot")}
        copy={dgettext("world", ".empty_world_snapshot_copy")}
      />

      <div :if={@import_result} id="world-empty-import-result" class="stack-list">
        <div :for={issue <- Map.get(@import_result, :issues, [])} class="list-row-card">
          <div>
            <p class="list-row-card__title">{issue.summary}</p>
            <p class="list-row-card__meta">{issue.detail}</p>
          </div>
          <div class="list-row-card__aside">
            <.status kind={:issue} value={issue.severity} />
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  attr :cities, :list, required: true
  attr :selected_city, :map, default: nil

  def cities_page(assigns) do
    selected_city = assigns.selected_city || List.first(assigns.cities)
    city_departments = selected_city && MockData.departments_for_city(selected_city.id)
    city_lemmings = selected_city && MockData.lemmings_for_city(selected_city.id)

    assigns =
      assigns
      |> assign(:selected_city, selected_city)
      |> assign(:city_departments, city_departments || [])
      |> assign(:city_lemmings, city_lemmings || [])

    ~H"""
    <.content_container>
      <.content_grid id="cities-dashboard-grid" columns="sidebar">
        <.panel id="cities-list-panel">
          <:title>{dgettext("world", ".title_all_cities")}</:title>
          <:subtitle>{dgettext("world", ".subtitle_all_cities")}</:subtitle>
          <div class="stack-list">
            <.city_card :for={city <- @cities} city={city} />
          </div>
        </.panel>

        <div class="page-stack">
          <.city_detail_page
            :if={@selected_city}
            city={@selected_city}
            cities={@cities}
            show_selector={false}
          />

          <.content_grid :if={@selected_city} columns="two">
            <.panel id="city-departments-panel">
              <:title>{dgettext("world", ".title_departments")}</:title>
              <div class="stack-list">
                <.link
                  :for={department <- @city_departments}
                  navigate={~p"/departments?#{%{city: @selected_city.id, dept: department.id}}"}
                  class="list-row-card"
                >
                  <div>
                    <p class="list-row-card__title">{department.name}</p>
                    <p class="list-row-card__meta">{department.description}</p>
                  </div>
                  <div class="list-row-card__aside">
                    <span>
                      {dgettext("world", ".count_agents",
                        count: length(MockData.lemmings_for_department(department.id))
                      )}
                    </span>
                  </div>
                </.link>
              </div>
            </.panel>

            <.panel id="city-active-lemmings-panel">
              <:title>{dgettext("world", ".title_assigned_agents")}</:title>
              <div class="stack-list">
                <.link
                  :for={lemming <- Enum.take(@city_lemmings, 4)}
                  navigate={~p"/lemmings?#{%{lemming: lemming.id}}"}
                  class="list-row-card"
                >
                  <div>
                    <p class="list-row-card__title">{lemming.name}</p>
                    <p class="list-row-card__meta">{lemming.role}</p>
                  </div>
                  <div class="list-row-card__aside">
                    <.status kind={:lemming} value={lemming.status} />
                    <span>{lemming.current_task}</span>
                  </div>
                </.link>
              </div>
            </.panel>
          </.content_grid>
        </div>
      </.content_grid>
    </.content_container>
    """
  end

  attr :cities, :list, required: true
  attr :selected_city, :map, default: nil
  attr :departments, :list, required: true
  attr :selected_department, :map, default: nil

  def departments_page(assigns) do
    assigns = assign(assigns, :selected_city, assigns.selected_city || List.first(assigns.cities))

    ~H"""
    <.content_container>
      <.department_detail_page
        :if={@selected_department}
        department={@selected_department}
        selected_city={@selected_city}
      />

      <.panel :if={!@selected_department} id="departments-list">
        <:title>{dgettext("world", ".title_departments")}</:title>
        <:actions>
          <div :if={@selected_city} class="departments-toolbar">
            <div class="departments-toolbar__visual">
              <MapComponents.city_node
                city={to_map_city(@selected_city)}
                id="departments-selected-city-node"
                size={60}
              />
            </div>
            <div class="departments-toolbar__copy">
              <div class="departments-toolbar__title-row">
                <span class="departments-toolbar__city-name">{@selected_city.name}</span>
                <span class="departments-toolbar__region">{@selected_city.region}</span>
              </div>
              <div class="inline-metrics">
                <.status kind={:city} value={@selected_city.status} />
                <span>{dgettext("world", ".count_departments", count: length(@departments))}</span>
                <span>
                  {dgettext("world", ".count_agents",
                    count: MockData.lemmings_for_city(@selected_city.id) |> length()
                  )}
                </span>
              </div>
            </div>
          </div>
        </:actions>
        <p class="departments-list__hint">
          {dgettext("world", ".copy_departments_browser")}
        </p>
        <div id="departments-links" class="departments-fallback-list">
          <.link
            :for={department <- @departments}
            id={"department-link-#{department.id}"}
            patch={~p"/departments?#{%{city: @selected_city.id, dept: department.id}}"}
            class="list-row-card"
          >
            <div>
              <p class="list-row-card__title">{department.name}</p>
              <p class="list-row-card__meta">{department.description}</p>
            </div>
            <div class="list-row-card__aside">
              <span>
                {dgettext("world", ".count_agents",
                  count: length(MockData.lemmings_for_department(department.id))
                )}
              </span>
              <span>
                {dgettext("world", ".count_queued_tasks", count: length(department.tasks_queue))}
              </span>
            </div>
          </.link>
        </div>
      </.panel>

      <.panel :if={!@selected_department && @selected_city} id="departments-map-panel">
        <CityMapComponents.city_map
          city={to_map_city(@selected_city)}
          departments={Enum.map(@departments, &to_map_department/1)}
          id="departments-city-map"
        />
      </.panel>

      <.empty_state
        :if={!@selected_department && @departments == []}
        id="departments-empty-state"
        title={dgettext("world", ".empty_no_departments")}
        copy={dgettext("world", ".empty_no_departments_copy")}
      />
    </.content_container>
    """
  end

  attr :city, :map, required: true
  attr :compact, :boolean, default: false

  def city_card(assigns) do
    city_departments = MockData.departments_for_city(assigns.city.id)
    city_lemmings = MockData.lemmings_for_city(assigns.city.id)

    assigns =
      assigns
      |> assign(:city_departments, city_departments)
      |> assign(:city_lemmings, city_lemmings)

    ~H"""
    <.link
      navigate={~p"/cities?#{%{city: @city.id}}"}
      class={["mini-card", @compact && "mini-card--compact"]}
    >
      <div class="mini-card__title">
        <span class="accent-dot" style={accent_style(@city.accent)}></span>
        {@city.name}
      </div>
      <p class="mini-card__meta">{@city.region}</p>
      <p class="mini-card__meta">{@city.description}</p>
      <div class={["mini-card__footer", @compact && "mini-card__footer--compact"]}>
        <span>{dgettext("world", ".count_depts", count: length(@city_departments))}</span>
        <span>{dgettext("world", ".count_agents", count: length(@city_lemmings))}</span>
        <.status
          kind={:city}
          value={@city.status}
          class={@compact && "mini-card__status-badge"}
        />
      </div>
    </.link>
    """
  end

  attr :city, :map, required: true
  attr :cities, :list, required: true
  attr :show_selector, :boolean, default: true

  def city_detail_page(assigns) do
    departments = MockData.departments_for_city(assigns.city.id)
    city_lemmings = MockData.lemmings_for_city(assigns.city.id)

    assigns =
      assigns
      |> assign(:departments, departments)
      |> assign(:city_lemmings, city_lemmings)
      |> assign(:map_city, to_map_city(assigns.city))

    ~H"""
    <.panel id="city-detail-panel" tone="accent">
      <:title>{@city.name}</:title>
      <:subtitle>{@city.description}</:subtitle>
      <:actions>
        <.button navigate={~p"/departments?#{%{city: @city.id}}"} variant="secondary">
          {dgettext("layout", ".nav_departments")}
        </.button>
      </:actions>
      <div class="city-detail-hero">
        <div class="city-detail-hero__visual">
          <MapComponents.city_node city={@map_city} id="city-detail-node" size={96} />
        </div>
        <div class="city-detail-hero__copy">
          <div class="inline-metrics">
            <span>{@city.region}</span>
            <.status kind={:city} value={@city.status} />
            <span>{dgettext("world", ".count_departments", count: length(@departments))}</span>
            <span>{dgettext("world", ".count_agents", count: length(@city_lemmings))}</span>
          </div>
          <p class="city-detail-hero__summary">
            {dgettext("world", ".copy_city_detail_hero")}
          </p>
        </div>
      </div>

      <div :if={@show_selector} id="cities-selector" class="city-selector">
        <.button
          :for={city <- @cities}
          id={"city-selector-#{city.id}"}
          navigate={~p"/cities?#{%{city: city.id}}"}
          variant={if(city.id == @city.id, do: "secondary", else: "ghost")}
          class="city-selector__button"
        >
          <span class="city-selector__label">
            <span class="accent-dot" style={accent_style(city.accent)}></span>
            <span>{city.name}</span>
          </span>
          <span class="city-selector__region">{city.region}</span>
        </.button>
      </div>
    </.panel>
    """
  end

  attr :department, :map, required: true

  def department_room(assigns) do
    lemmings = MockData.lemmings_for_department(assigns.department.id)
    assigns = assign(assigns, :lemmings, lemmings)

    ~H"""
    <.panel class="department-room">
      <:title>{@department.name}</:title>
      <:subtitle>{@department.description}</:subtitle>
      <:actions>
        <.button navigate={~p"/departments?#{%{dept: @department.id}}"} variant="ghost">
          {dgettext("world", ".button_open_dept")}
        </.button>
      </:actions>
      <div class="department-room__stage">
        <div class="department-room__floor"></div>
        <div class="department-room__lemmings">
          <LemmingComponents.lemming_sprite
            :for={lemming <- @lemmings}
            lemming={lemming}
            path={~p"/lemmings?#{%{lemming: lemming.id}}"}
          />
        </div>
      </div>
      <div class="department-room__queue">
        {dgettext("world", ".label_queue")}: {List.first(@department.tasks_queue) ||
          dgettext("world", ".label_empty")}
      </div>
    </.panel>
    """
  end

  attr :department, :map, required: true
  attr :selected_city, :map, default: nil

  def department_detail_page(assigns) do
    lemmings = MockData.lemmings_for_department(assigns.department.id)
    city = MockData.city_for_department(assigns.department.id)

    assigns =
      assigns
      |> assign(:lemmings, lemmings)
      |> assign(:city, city)

    ~H"""
    <.panel id="department-detail-panel" tone="accent">
      <:title>{@department.name}</:title>
      <:subtitle>{@department.description}</:subtitle>
      <:actions>
        <.button
          navigate={~p"/departments?#{%{city: (@selected_city || @city).id}}"}
          variant="ghost"
        >
          {dgettext("world", ".button_all_departments")}
        </.button>
      </:actions>
      <div class="inline-metrics">
        <span>{dgettext("world", ".label_node")} {@city.name}</span>
        <span>{dgettext("world", ".count_agents", count: length(@lemmings))}</span>
        <span>
          {dgettext("world", ".count_queued_tasks", count: length(@department.tasks_queue))}
        </span>
      </div>
    </.panel>

    <.content_grid columns="two">
      <.panel id="department-agents-panel">
        <:title>{dgettext("world", ".title_assigned_agents")}</:title>
        <div class="sprite-grid">
          <LemmingComponents.lemming_sprite
            :for={lemming <- @lemmings}
            lemming={lemming}
            size="md"
            path={~p"/lemmings?#{%{lemming: lemming.id}}"}
          />
        </div>
      </.panel>

      <.panel id="department-queue-panel">
        <:title>{dgettext("world", ".title_task_queue")}</:title>
        <div class="queue-list">
          <div
            :for={{task, index} <- Enum.with_index(@department.tasks_queue, 1)}
            class="queue-list__row"
          >
            <span class="queue-list__index">[{index}]</span>
            <span>{task}</span>
          </div>
        </div>
      </.panel>
    </.content_grid>
    """
  end

  defp snapshot_issues(nil, _section), do: []
  defp snapshot_issues(snapshot, :bootstrap), do: snapshot.bootstrap.issues

  defp import_issues(nil, nil), do: []
  defp import_issues(nil, import_result), do: Map.get(import_result, :issues, [])
  defp import_issues(snapshot, _import_result), do: snapshot.immediate_import.issues

  defp runtime_checks(nil), do: []
  defp runtime_checks(snapshot), do: snapshot.runtime.checks

  defp declared_postgres_url_env(%{
         bootstrap: %{declared_config: %{infrastructure: %{postgres: %{url_env: url_env}}}}
       }),
       do: url_env

  defp declared_postgres_url_env(_snapshot), do: nil

  defp providers(nil), do: []

  defp providers(%{bootstrap: %{declared_config: %{models: %{providers: providers}}}}),
    do: providers

  defp providers(_snapshot), do: []

  defp profiles(nil), do: []
  defp profiles(%{bootstrap: %{declared_config: %{models: %{profiles: profiles}}}}), do: profiles
  defp profiles(_snapshot), do: []

  defp declared_limits(nil), do: %{}
  defp declared_limits(%{bootstrap: %{declared_config: %{limits: limits}}}), do: limits
  defp declared_limits(_snapshot), do: %{}

  defp declared_runtime(nil), do: %{}
  defp declared_runtime(%{bootstrap: %{declared_config: %{runtime: runtime}}}), do: runtime
  defp declared_runtime(_snapshot), do: %{}

  defp declared_budget(nil), do: %{}
  defp declared_budget(%{bootstrap: %{declared_config: %{costs: %{budgets: budget}}}}), do: budget
  defp declared_budget(_snapshot), do: %{}

  defp snapshot_placeholders(%{bootstrap: %{declared_config: %{placeholders: placeholders}}}),
    do: placeholders

  defp snapshot_placeholders(_snapshot), do: nil

  defp provider_enabled_label(true), do: dgettext("world", ".label_provider_enabled")
  defp provider_enabled_label(false), do: dgettext("world", ".label_provider_disabled")
  defp provider_enabled_label(_value), do: dgettext("world", ".label_not_available")

  defp fallback_summary([]), do: dgettext("world", ".label_no_fallbacks")

  defp fallback_summary(fallbacks) do
    Enum.map_join(fallbacks, " | ", fn fallback ->
      "#{fallback.provider} / #{fallback.model}"
    end)
  end

  defp limits_detail(limits) do
    [
      "#{Helpers.display_value(Map.get(limits, :max_departments_per_city))} #{dgettext("world", ".label_departments_short")}",
      "#{Helpers.display_value(Map.get(limits, :max_lemmings_per_department))} #{dgettext("world", ".label_lemmings_short")}"
    ]
    |> Enum.join(" / ")
  end

  defp budget_detail(budget) do
    "#{Helpers.display_value(Map.get(budget, :daily_tokens))} #{dgettext("world", ".label_daily_tokens")}"
  end

  defp runtime_detail(runtime) do
    "#{Helpers.display_value(Map.get(runtime, :cross_city_communication))} #{dgettext("world", ".label_cross_city_communication")}"
  end

  defp placeholder_value(placeholders) do
    if placeholders && placeholders.cities_declared? && placeholders.tools_declared? do
      dgettext("world", ".label_declared")
    else
      dgettext("world", ".label_not_available")
    end
  end

  defp bootstrap_world_name(%{bootstrap: %{declared_config: %{world: %{name: name}}}}), do: name
  defp bootstrap_world_name(_snapshot), do: nil

  defp bootstrap_identity_detail(%{
         bootstrap: %{declared_config: %{world: %{bootstrap_id: bootstrap_id, slug: slug}}}
       }) do
    [
      "#{dgettext("world", ".label_world_id")}: #{Helpers.display_value(bootstrap_id)}",
      "#{dgettext("world", ".label_world_slug")}: #{Helpers.display_value(slug)}"
    ]
    |> Enum.join(" / ")
  end

  defp bootstrap_identity_detail(_snapshot), do: dgettext("world", ".label_not_available")

  defp runtime_check_label("bootstrap_file"),
    do: dgettext("world", ".runtime_check_bootstrap_file")

  defp runtime_check_label("postgres_connection"),
    do: dgettext("world", ".runtime_check_postgres_connection")

  defp runtime_check_label("provider_credentials"),
    do: dgettext("world", ".runtime_check_provider_credentials")

  defp runtime_check_label("provider_reachability"),
    do: dgettext("world", ".runtime_check_provider_reachability")

  defp runtime_check_label(code), do: code

  defp runtime_check_detail(%{code: "bootstrap_file", detail: detail}),
    do: Map.get(detail, :path) || dgettext("world", ".label_not_available")

  defp runtime_check_detail(%{code: "postgres_connection", detail: detail}) do
    Map.get(detail, :reason) || Map.get(detail, :url_env) ||
      dgettext("world", ".label_not_available")
  end

  defp runtime_check_detail(%{code: "provider_credentials", detail: detail}) do
    missing_envs = Map.get(detail, :missing_envs, [])

    case missing_envs do
      [] -> dgettext("world", ".label_provider_credentials_ready")
      envs -> Enum.join(envs, ", ")
    end
  end

  defp runtime_check_detail(%{code: "provider_reachability", detail: detail}) do
    providers = Map.get(detail, :providers, [])

    case providers do
      [] -> dgettext("world", ".label_runtime_deferred")
      _providers -> dgettext("world", ".label_runtime_deferred")
    end
  end

  defp runtime_check_detail(_check), do: dgettext("world", ".label_not_available")

  defp tab_button_variant(active_tab, active_tab), do: "secondary"
  defp tab_button_variant(_active_tab, _tab), do: "ghost"

  defp accent_style(color), do: "background-color: #{color};"

  defp to_map_city(city) do
    %{
      id: city.id,
      name: city.name,
      region: city.region,
      color: city.accent,
      status: city.status,
      agents: city.id |> MockData.lemmings_for_city() |> length(),
      depts: city.id |> MockData.departments_for_city() |> length(),
      col: grid_coordinate(city.x, @map_cols - 1),
      row: grid_coordinate(city.y, @map_rows - 1)
    }
  end

  defp to_map_department(department) do
    %{
      id: department.id,
      name: department.name,
      color: department.accent,
      lemmings:
        department.id
        |> MockData.lemmings_for_department()
        |> Enum.map(fn lemming ->
          %{
            id: lemming.id,
            name: lemming.name,
            status: lemming.status
          }
        end)
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
