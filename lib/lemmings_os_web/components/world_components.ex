defmodule LemmingsOsWeb.WorldComponents do
  @moduledoc """
  Components for world, city, and department pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers
  alias LemmingsOs.MockData

  attr :snapshot, :map, default: nil
  attr :import_result, :map, default: nil
  attr :active_tab, :string, default: "overview"
  attr :cities, :list, default: []

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
        snapshot={@snapshot}
        bootstrap_issues={@bootstrap_issues}
        import_issues={@import_issues}
        runtime_checks={@runtime_checks}
        providers={@providers}
        profiles={@profiles}
        declared_limits={@declared_limits}
        declared_runtime={@declared_runtime}
        declared_budget={@declared_budget}
        cities={@cities}
      />
    </.content_container>
    """
  end

  attr :snapshot, :map, required: true
  attr :active_tab, :string, required: true
  attr :bootstrap_issues, :list, required: true
  attr :import_issues, :list, required: true
  attr :runtime_checks, :list, required: true
  attr :providers, :list, required: true
  attr :profiles, :list, required: true
  attr :declared_limits, :map, required: true
  attr :declared_runtime, :map, required: true
  attr :declared_budget, :map, required: true
  attr :cities, :list, default: []

  defp world_snapshot(assigns) do
    ~H"""
    <.panel id="world-status-panel" tone="accent">
      <:title>{dgettext("world", ".title_world_status")}</:title>
      <:actions>
        <.button
          id="world-refresh-button"
          phx-click="refresh_status"
          variant="primary"
          class="ml-auto"
        >
          {dgettext("world", ".button_refresh_world")}
        </.button>
      </:actions>

      <div id="world-status-strip" class="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
        <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-base text-zinc-100">
                {dgettext("world", ".title_world_identity")}
              </div>
              <p class="text-xs uppercase tracking-wider text-zinc-400">{@snapshot.world.name}</p>
            </div>
            <.status id="world-persisted-status" kind={:world} value={@snapshot.world.status} />
          </div>
        </div>

        <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-base text-zinc-100">
                {dgettext("world", ".label_immediate_import")}
              </div>
              <p class="text-xs uppercase tracking-wider text-zinc-400">
                {dgettext("world", ".title_import_state")}
              </p>
            </div>
            <.status
              id="world-immediate-import-status"
              kind={:world}
              value={@snapshot.immediate_import.status}
            />
          </div>
        </div>

        <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-base text-zinc-100">
                {dgettext("world", ".label_last_sync")}
              </div>
              <p class="text-xs uppercase tracking-wider text-zinc-400">
                {Helpers.format_datetime(@snapshot.last_sync.imported_at)}
              </p>
            </div>
            <.status id="world-last-sync-status" kind={:world} value={@snapshot.last_sync.status} />
          </div>
        </div>

        <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-base text-zinc-100">
                {dgettext("world", ".title_bootstrap_config")}
              </div>
              <p class="text-xs uppercase tracking-wider text-zinc-400">
                {Helpers.display_value(@snapshot.bootstrap.source)}
              </p>
            </div>
            <.status id="world-bootstrap-status" kind={:world} value={@snapshot.bootstrap.status} />
          </div>
        </div>

        <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <div class="flex items-center gap-2 text-base text-zinc-100">
                {dgettext("world", ".title_runtime_checks")}
              </div>
              <p class="text-xs uppercase tracking-wider text-zinc-400">
                {to_string(length(@runtime_checks))}
              </p>
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

    <div :if={@active_tab == "overview"} id="world-overview-tab" class="flex flex-col gap-4">
      <.panel id="world-map-panel" tone="accent">
        <MapComponents.world_map id="world-map" cities={Enum.map(@cities, &city_for_map/1)} />
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
            class="rounded-sm border border-zinc-800 p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-xs uppercase tracking-widest text-zinc-400">
                {dgettext("world", ".label_immediate_import")}
              </p>
              <.status kind={:world} value={@snapshot.immediate_import.status} />
            </div>
          </div>

          <div
            id="world-last-sync"
            class="rounded-sm border border-zinc-800 p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <p class="text-xs uppercase tracking-widest text-zinc-400">
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
          class="flex min-h-48 items-center justify-center p-6 text-center"
        >
          <.badge tone="success">{dgettext("world", ".label_no_world_issues")}</.badge>
        </div>
        <div :if={@bootstrap_issues != [] or @import_issues != []} class="flex flex-col gap-3">
          <div
            :for={{issue, index} <- Enum.with_index(@bootstrap_issues ++ @import_issues)}
            id={"world-issue-#{issue.code}-#{index}"}
            class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
          >
            <div>
              <p class="flex items-center gap-2 text-base text-zinc-100">{issue.summary}</p>
              <p class="text-xs uppercase tracking-wider text-zinc-400">{issue.detail}</p>
              <p :if={issue.action_hint} class="text-xs uppercase tracking-wider text-zinc-400">
                {issue.action_hint}
              </p>
            </div>
            <div class="flex items-center justify-between gap-3">
              <.status kind={:issue} value={issue.severity} />
            </div>
          </div>
        </div>
      </.panel>
    </.content_grid>

    <div :if={@active_tab == "bootstrap"} class="flex flex-col gap-4">
      <.panel id="world-bootstrap-panel">
        <:title>{dgettext("world", ".title_bootstrap_config")}</:title>

        <div class="flex flex-col gap-4">
          <div class="grid gap-3 md:grid-cols-2">
            <.stat_item
              id="world-bootstrap-source-field"
              label={dgettext("world", ".label_bootstrap_source")}
              value={Helpers.display_value(@snapshot.bootstrap.source)}
            />
            <.stat_item
              id="world-bootstrap-path-field"
              label={dgettext("world", ".label_bootstrap_path")}
              value={Helpers.truncate_value(@snapshot.bootstrap.path)}
              detail={@snapshot.bootstrap.path}
            />
            <.stat_item
              id="world-bootstrap-postgres-env-field"
              label={runtime_check_label("postgres_connection")}
              value={Helpers.display_value(declared_postgres_url_env(@snapshot))}
            />
            <.stat_item
              id="world-bootstrap-world-field"
              label={dgettext("world", ".title_world_identity")}
              value={Helpers.display_value(bootstrap_world_name(@snapshot))}
              detail={bootstrap_identity_detail(@snapshot)}
            />
          </div>

          <div class="space-y-2">
            <h3 class="text-xs uppercase tracking-wider text-zinc-400">
              {dgettext("world", ".label_providers")}
            </h3>
            <div class="flex flex-col gap-3">
              <div
                :for={provider <- @providers}
                id={"world-provider-#{provider.name}"}
                class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
              >
                <div>
                  <p class="flex items-center gap-2 text-base text-zinc-100">{provider.name}</p>
                  <p class="text-xs uppercase tracking-wider text-zinc-400">
                    {Enum.join(provider.allowed_models, ", ")}
                  </p>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <.badge tone={if(provider.enabled, do: "success", else: "default")}>
                    {provider_enabled_label(provider.enabled)}
                  </.badge>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <h3 class="text-xs uppercase tracking-wider text-zinc-400">
              {dgettext("world", ".label_profiles")}
            </h3>
            <div class="flex flex-col gap-3">
              <div
                :for={profile <- @profiles}
                id={"world-profile-#{profile.name}"}
                class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
              >
                <div>
                  <p class="flex items-center gap-2 text-base text-zinc-100">{profile.name}</p>
                  <p class="text-xs uppercase tracking-wider text-zinc-400">
                    {profile.provider} / {profile.model}
                  </p>
                </div>
                <div class="flex items-center justify-between gap-3">
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
          <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
            <div class="flex items-center gap-2 text-base text-zinc-100">
              <.icon name="hero-building-office-2" class="size-5" />
              {dgettext("world", ".label_placeholder_only")}
            </div>
            <p class="text-xs uppercase tracking-wider text-zinc-400">
              {dgettext("world", ".copy_world_cities_placeholder")}
            </p>
          </div>
        </.panel>

        <.panel id="world-tools-placeholder-panel">
          <:title>{dgettext("world", ".title_world_tools_placeholder")}</:title>
          <div class="border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400">
            <div class="flex items-center gap-2 text-base text-zinc-100">
              <.icon name="hero-wrench-screwdriver" class="size-5" />
              {dgettext("world", ".label_placeholder_only")}
            </div>
            <p class="text-xs uppercase tracking-wider text-zinc-400">
              {dgettext("world", ".copy_world_tools_placeholder")}
            </p>
          </div>
        </.panel>
      </.content_grid>
    </div>

    <.panel :if={@active_tab == "runtime"} id="world-runtime-panel">
      <:title>{dgettext("world", ".title_runtime_checks")}</:title>

      <div class="flex flex-col gap-3">
        <div
          :for={check <- @runtime_checks}
          id={"world-runtime-check-#{check.code}"}
          class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
          data-status={check.status}
        >
          <div>
            <p class="flex items-center gap-2 text-base text-zinc-100">
              {runtime_check_label(check.code)}
            </p>
            <p class="text-xs uppercase tracking-wider text-zinc-400">
              {runtime_check_detail(check)}
            </p>
          </div>
          <div class="flex items-center justify-between gap-3">
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
        <.button
          id="world-refresh-button"
          phx-click="refresh_status"
          variant="primary"
          class="ml-auto"
        >
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

      <div :if={@import_result} id="world-empty-import-result" class="flex flex-col gap-3">
        <div
          :for={issue <- Map.get(@import_result, :issues, [])}
          class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
        >
          <div>
            <p class="flex items-center gap-2 text-base text-zinc-100">{issue.summary}</p>
            <p class="text-xs uppercase tracking-wider text-zinc-400">{issue.detail}</p>
          </div>
          <div class="flex items-center justify-between gap-3">
            <.status kind={:issue} value={issue.severity} />
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  attr :city, :map, required: true

  def city_card(assigns) do
    ~H"""
    <.link
      id={"city-card-link-#{@city.id}"}
      navigate={@city.path}
      class={[
        "block border-2 bg-zinc-950/80 p-4",
        "transition-all duration-150 hover:border-emerald-400 hover:-translate-y-px",
        @city.selected? && "border-emerald-400"
      ]}
      data-selected={@city.selected?}
    >
      <div class="flex items-center gap-2 text-base text-zinc-100">
        <.icon name="hero-building-office-2" class="size-4" />
        <span>{@city.name}</span>
      </div>
      <p class="text-zinc-400 text-xs uppercase tracking-widest">{@city.slug}</p>
      <p class="text-zinc-400 text-xs uppercase tracking-widest">{@city.node_name}</p>
      <p class="text-zinc-400 text-xs uppercase tracking-widest">
        {Helpers.format_datetime(@city.last_seen_at)}
      </p>
      <div class="flex gap-2 items-center flex-wrap mt-2">
        <.status id={"city-card-status-#{@city.id}"} kind={:city} value={@city.status} />
        <.badge
          id={"city-card-liveness-#{@city.id}"}
          tone={@city.liveness_tone}
          data-status={@city.liveness}
        >
          {@city.liveness_label}
        </.badge>
      </div>
    </.link>
    """
  end

  attr :city, :map, required: true

  def city_effective_config_panel(assigns) do
    assigns =
      assign(assigns, :budgets, Map.get(assigns.city.effective_config.costs_config, :budgets))

    ~H"""
    <.panel id="city-effective-config-panel" tone="info">
      <:title>{dgettext("world", ".title_city_effective_config")}</:title>
      <:subtitle>{dgettext("world", ".copy_city_effective_config")}</:subtitle>

      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <.stat_item
          id="city-effective-limits"
          label={dgettext("world", ".label_limits")}
          value={Helpers.display_value(@city.effective_config.limits_config.max_cities)}
          detail={
            "#{Helpers.display_value(@city.effective_config.limits_config.max_departments_per_city)} / #{Helpers.display_value(@city.effective_config.limits_config.max_lemmings_per_department)}"
          }
        />
        <.stat_item
          id="city-effective-runtime"
          label={dgettext("world", ".label_runtime_defaults")}
          value={Helpers.display_value(@city.effective_config.runtime_config.idle_ttl_seconds)}
          detail={
            Helpers.display_value(@city.effective_config.runtime_config.cross_city_communication)
          }
        />
        <.stat_item
          id="city-effective-costs"
          label={dgettext("world", ".label_budgets")}
          value={Helpers.display_value(@budgets && @budgets.monthly_usd)}
          detail={Helpers.display_value(@budgets && @budgets.daily_tokens)}
        />
        <.stat_item
          id="city-effective-models"
          label={dgettext("world", ".label_profiles")}
          value={Helpers.display_value(map_size(@city.effective_config.models_config.providers))}
          detail={Helpers.display_value(map_size(@city.effective_config.models_config.profiles))}
        />
      </div>
    </.panel>
    """
  end

  attr :city, :map, required: true

  def city_departments_panel(assigns) do
    ~H"""
    <.panel id="city-departments-panel">
      <:title>{dgettext("world", ".title_departments")}</:title>
      <:subtitle>{dgettext("world", ".copy_city_departments_summary")}</:subtitle>

      <div :if={@city.departments == []} id="city-departments-empty-state">
        <.empty_state
          id="city-departments-empty-state-card"
          title={dgettext("world", ".empty_no_departments")}
          copy={dgettext("world", ".empty_no_departments_copy")}
        />
      </div>

      <div :if={@city.departments != []} id="city-departments-summary" class="space-y-3 p-6">
        <p id="city-departments-summary-copy" class="text-sm text-zinc-400">
          {dgettext("world", ".city_departments_summary",
            city: @city.name,
            count: @city.department_count
          )}
        </p>

        <ul id="city-departments-list" class="space-y-1 text-sm text-zinc-100">
          <li :for={department <- @city.departments} id={"city-department-item-#{department.id}"}>
            <span id={"city-department-name-#{department.id}"} class="leading-6 text-zinc-100">
              • {department.name}
            </span>
            <span :if={department.notes_preview} class="text-zinc-400">
              {" "}
              <code class="bg-transparent px-0 text-xs text-zinc-400">
                {department.notes_preview}
              </code>
            </span>
          </li>
        </ul>
      </div>

      <div class="mt-6 flex justify-end px-4 pb-4">
        <.button
          id="city-open-departments-button"
          navigate={@city.departments_path}
          variant="secondary"
        >
          {dgettext("world", ".button_open_city_departments")}
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
    <.panel>
      <:title>{@department.name}</:title>
      <:subtitle>{@department.slug}</:subtitle>
      <:actions>
        <.button navigate={~p"/departments?#{%{dept: @department.id}}"} variant="neutral">
          {dgettext("world", ".button_open_dept")}
        </.button>
      </:actions>
      <div class="relative min-h-36 overflow-hidden bg-zinc-950/90 px-4 pt-4 pb-6">
        <div class="absolute right-0 bottom-0 left-0 h-4 bg-emerald-500/10"></div>
        <div class="relative flex flex-wrap justify-center gap-3">
          <LemmingComponents.lemming_sprite
            :for={lemming <- @lemmings}
            lemming={lemming}
            path={~p"/lemmings?#{%{lemming: lemming.id}}"}
          />
        </div>
      </div>
      <div class="border-t border-zinc-800 pt-3 text-sm text-zinc-300">
        {dgettext("world", ".label_queue")}: {List.first(@department.tasks_queue) ||
          dgettext("world", ".label_empty")}
      </div>
    </.panel>
    """
  end

  attr :department, :map, required: true
  attr :selected_city, :map, default: nil
  attr :selected_world, :map, default: nil
  attr :active_tab, :string, default: "overview"
  attr :settings_form, :any, default: nil
  attr :effective_config, :map, default: nil
  attr :local_overrides, :map, default: nil
  attr :lemming_preview, :list, default: []

  def department_detail_page(assigns) do
    ~H"""
    <.panel id="department-detail-panel" tone="accent">
      <:title>{@department.name}</:title>
      <:subtitle>{@department.slug}</:subtitle>
      <:actions>
        <.button
          patch={~p"/departments?#{%{city: @selected_city.id}}"}
          variant="neutral"
        >
          {dgettext("world", ".button_all_departments")}
        </.button>
      </:actions>

      <div id="department-detail-tabs" class="mb-4 flex flex-wrap gap-2">
        <.link
          id="department-tab-overview"
          patch={
            ~p"/departments?#{department_tab_params(@selected_city.id, @department.id, "overview")}"
          }
          class={department_tab_class(@active_tab == "overview")}
        >
          {dgettext("world", ".department_tab_overview")}
        </.link>
        <.link
          id="department-tab-lemmings"
          patch={
            ~p"/departments?#{department_tab_params(@selected_city.id, @department.id, "lemmings")}"
          }
          class={department_tab_class(@active_tab == "lemmings")}
        >
          {dgettext("world", ".department_tab_lemmings")}
        </.link>
        <.link
          id="department-tab-settings"
          patch={
            ~p"/departments?#{department_tab_params(@selected_city.id, @department.id, "settings")}"
          }
          class={department_tab_class(@active_tab == "settings")}
        >
          {dgettext("world", ".department_tab_settings")}
        </.link>
      </div>

      <div :if={@active_tab == "overview"} id="department-overview-tab-panel" class="space-y-4">
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <.stat_item
            id="department-detail-status"
            label={dgettext("world", ".city_form_status_label")}
            value={@department.__struct__.translate_status(@department)}
          />
          <.stat_item
            id="department-detail-city"
            label={dgettext("world", ".title_world_cities")}
            value={Helpers.display_value(@selected_city.name)}
          />
          <.stat_item
            id="department-detail-world"
            label={dgettext("world", ".title_world_identity")}
            value={Helpers.display_value(@selected_world && @selected_world.name)}
          />
          <.stat_item
            id="department-detail-slug"
            label={dgettext("world", ".label_world_slug")}
            value={Helpers.display_value(@department.slug)}
          />
        </div>

        <div class="grid gap-3 lg:grid-cols-2">
          <.panel id="department-overview-metadata-panel">
            <:title>{dgettext("world", ".department_section_metadata")}</:title>
            <div class="grid gap-3 md:grid-cols-2">
              <.stat_item
                id="department-detail-name"
                label={dgettext("world", ".department_field_name")}
                value={Helpers.display_value(@department.name)}
              />
              <.stat_item
                id="department-detail-tags"
                label={dgettext("world", ".department_field_tags")}
                value={Helpers.display_value(Enum.join(@department.tags || [], ", "))}
              />
              <.stat_item
                id="department-detail-notes"
                label={dgettext("world", ".department_field_notes")}
                value={Helpers.display_value(@department.notes)}
              />
            </div>
          </.panel>

          <.panel id="department-lifecycle-panel" tone="info" class="h-full">
            <:title>{dgettext("world", ".department_section_lifecycle")}</:title>
            <:subtitle>{dgettext("world", ".department_section_lifecycle_copy")}</:subtitle>
            <div class="flex h-full flex-1 flex-col">
              <div class="mt-auto flex flex-wrap justify-end gap-2">
                <button
                  id="department-action-activate"
                  type="button"
                  phx-click="department_lifecycle"
                  phx-value-action="activate"
                  class="inline-flex h-11 items-center justify-center gap-2 border-2 border-sky-400/50 bg-sky-400/10 px-4 text-sm font-medium text-sky-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
                >
                  {dgettext("world", ".button_department_activate")}
                </button>
                <button
                  id="department-action-drain"
                  type="button"
                  phx-click="department_lifecycle"
                  phx-value-action="drain"
                  class="inline-flex h-11 items-center justify-center gap-2 border-2 border-emerald-400/50 bg-emerald-400/10 px-4 text-sm font-medium text-emerald-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
                >
                  {dgettext("world", ".button_department_drain")}
                </button>
                <button
                  id="department-action-disable"
                  type="button"
                  phx-click="department_lifecycle"
                  phx-value-action="disable"
                  class="inline-flex h-11 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/80 px-4 text-sm font-medium text-zinc-100 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
                >
                  {dgettext("world", ".button_department_disable")}
                </button>
                <button
                  id="department-action-delete"
                  type="button"
                  phx-click="department_lifecycle"
                  phx-value-action="delete"
                  data-confirm={dgettext("world", ".confirm_department_delete")}
                  class="inline-flex min-h-11 items-center justify-center gap-2 border-2 border-red-400 bg-red-500/10 px-4 py-3 text-sm font-medium text-red-300 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
                >
                  {dgettext("world", ".button_department_delete")}
                </button>
              </div>
            </div>
          </.panel>
        </div>
      </div>

      <div :if={@active_tab == "lemmings"} id="department-lemmings-tab-panel" class="space-y-4">
        <.panel id="department-lemmings-panel">
          <:title>{dgettext("world", ".department_lemmings_title")}</:title>
          <:subtitle>{dgettext("world", ".department_lemmings_mock_copy")}</:subtitle>
          <div
            id="department-lemmings-mock-banner"
            class="mb-4 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
          >
            {dgettext("world", ".label_mock_backed_preview")}
          </div>

          <div :if={@lemming_preview == []} id="department-lemmings-empty-state">
            <.empty_state
              id="department-lemmings-empty-state-card"
              title={dgettext("world", ".department_lemmings_empty")}
              copy={dgettext("world", ".department_lemmings_empty_copy")}
            />
          </div>

          <div :if={@lemming_preview != []} id="department-lemmings-list" class="flex flex-col gap-3">
            <.link
              :for={lemming <- @lemming_preview}
              id={"department-lemming-#{lemming.id}"}
              navigate={~p"/lemmings?#{%{lemming: lemming.id}}"}
              class="flex items-center justify-between gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
            >
              <div>
                <p class="flex items-center gap-2 text-base text-zinc-100">{lemming.name}</p>
                <p class="text-xs uppercase tracking-wider text-zinc-400">
                  {Helpers.display_value(lemming.role)} • {Helpers.display_value(lemming.current_task)}
                </p>
              </div>
              <div class="flex items-center justify-between gap-3">
                <.status kind={:lemming} value={lemming.status} />
              </div>
            </.link>
          </div>
        </.panel>
      </div>

      <div :if={@active_tab == "settings"} id="department-settings-tab-panel" class="space-y-4">
        <div class="grid gap-4 xl:grid-cols-2">
          <.panel id="department-settings-effective-panel">
            <:title>{dgettext("world", ".department_settings_effective_title")}</:title>
            <:subtitle>{dgettext("world", ".department_settings_effective_copy")}</:subtitle>
            <div class="grid gap-3 md:grid-cols-2">
              <.stat_item
                id="department-effective-max-lemmings"
                label={dgettext("world", ".department_setting_max_lemmings")}
                value={display_setting(@effective_config.limits_config.max_lemmings_per_department)}
              />
              <.stat_item
                id="department-effective-idle-ttl"
                label={dgettext("world", ".department_setting_idle_ttl")}
                value={display_setting(@effective_config.runtime_config.idle_ttl_seconds)}
              />
              <.stat_item
                id="department-effective-cross-city"
                label={dgettext("world", ".department_setting_cross_city")}
                value={display_setting(@effective_config.runtime_config.cross_city_communication)}
              />
              <.stat_item
                id="department-effective-daily-tokens"
                label={dgettext("world", ".department_setting_daily_tokens")}
                value={display_setting(@effective_config.costs_config.budgets.daily_tokens)}
              />
            </div>
          </.panel>

          <.panel id="department-settings-local-overrides-panel" tone="info">
            <:title>{dgettext("world", ".department_settings_local_title")}</:title>
            <:subtitle>{dgettext("world", ".department_settings_local_copy")}</:subtitle>
            <div class="grid gap-3 md:grid-cols-2">
              <.stat_item
                id="department-local-max-lemmings"
                label={dgettext("world", ".department_setting_max_lemmings")}
                value={
                  display_setting(
                    get_in(@local_overrides, [:limits_config, :max_lemmings_per_department])
                  )
                }
              />
              <.stat_item
                id="department-local-idle-ttl"
                label={dgettext("world", ".department_setting_idle_ttl")}
                value={
                  display_setting(get_in(@local_overrides, [:runtime_config, :idle_ttl_seconds]))
                }
              />
              <.stat_item
                id="department-local-cross-city"
                label={dgettext("world", ".department_setting_cross_city")}
                value={
                  display_setting(
                    get_in(@local_overrides, [:runtime_config, :cross_city_communication])
                  )
                }
              />
              <.stat_item
                id="department-local-daily-tokens"
                label={dgettext("world", ".department_setting_daily_tokens")}
                value={
                  display_setting(get_in(@local_overrides, [:costs_config, :budgets, :daily_tokens]))
                }
              />
            </div>
          </.panel>
        </div>

        <.panel id="department-settings-v1-panel">
          <:title>{dgettext("world", ".department_settings_v1_title")}</:title>
          <:subtitle>{dgettext("world", ".department_settings_v1_copy")}</:subtitle>

          <.form
            for={@settings_form}
            id="department-settings-form"
            phx-change="validate_department_settings"
            phx-submit="save_department_settings"
          >
            <div class="grid gap-4 lg:grid-cols-2">
              <.inputs_for :let={limits_form} field={@settings_form[:limits_config]}>
                <.input
                  id="department-settings-max-lemmings"
                  field={limits_form[:max_lemmings_per_department]}
                  type="number"
                  label={dgettext("world", ".department_setting_max_lemmings")}
                />
              </.inputs_for>

              <.inputs_for :let={runtime_form} field={@settings_form[:runtime_config]}>
                <.input
                  id="department-settings-idle-ttl"
                  field={runtime_form[:idle_ttl_seconds]}
                  type="number"
                  label={dgettext("world", ".department_setting_idle_ttl")}
                />
                <.input
                  id="department-settings-cross-city"
                  field={runtime_form[:cross_city_communication]}
                  type="select"
                  label={dgettext("world", ".department_setting_cross_city")}
                  options={[
                    {dgettext("world", ".department_setting_inherit"), ""},
                    {dgettext("world", ".department_setting_enabled"), "true"},
                    {dgettext("world", ".department_setting_disabled"), "false"}
                  ]}
                />
              </.inputs_for>

              <.inputs_for :let={costs_form} field={@settings_form[:costs_config]}>
                <.inputs_for :let={budgets_form} field={costs_form[:budgets]}>
                  <.input
                    id="department-settings-daily-tokens"
                    field={budgets_form[:daily_tokens]}
                    type="number"
                    label={dgettext("world", ".department_setting_daily_tokens")}
                  />
                </.inputs_for>
              </.inputs_for>
            </div>

            <div class="mt-4 flex justify-end">
              <.button id="department-settings-save" type="submit">
                {dgettext("world", ".button_department_save_settings")}
              </.button>
            </div>
          </.form>
        </.panel>
      </div>
    </.panel>
    """
  end

  defp department_tab_params(city_id, department_id, "overview"),
    do: %{city: city_id, dept: department_id}

  defp department_tab_params(city_id, department_id, tab),
    do: %{city: city_id, dept: department_id, tab: tab}

  defp department_tab_class(true),
    do:
      "inline-flex h-11 items-center justify-center gap-2 border-2 border-emerald-400/50 bg-emerald-400/10 px-4 text-sm font-medium text-emerald-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"

  defp department_tab_class(false),
    do:
      "inline-flex h-11 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/80 px-4 text-sm font-medium text-zinc-100 transition duration-200 ease-out hover:-translate-y-px"

  defp display_setting(value), do: Helpers.display_value(value)

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
  defp tab_button_variant(_active_tab, _tab), do: "neutral"

  # Maps a real persisted city summary to the canvas format.
  # col/row are synthesized deterministically from the city ID so the same city
  # always lands on the same grid cell without requiring schema changes.
  defp city_for_map(%{id: id} = city) do
    %{
      id: id,
      name: Map.get(city, :name),
      region: Map.get(city, :node_name, "local"),
      color: "#49f28e",
      status: Map.get(city, :status, "unknown"),
      agents: 0,
      depts: 0,
      col: nil,
      row: nil
    }
  end
end
