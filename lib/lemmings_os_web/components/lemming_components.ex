defmodule LemmingsOsWeb.LemmingComponents do
  @moduledoc """
  Components for lemming lists, detail panels, and creation flows.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  attr :world, :map, default: nil
  attr :cities, :list, default: []
  attr :departments, :list, default: []
  attr :filters_form, :any, required: true
  attr :selected_city, :map, default: nil
  attr :selected_department, :map, default: nil
  attr :lemmings, :list, required: true
  attr :selected_lemming, :map, default: nil
  attr :selected_lemming_effective_config, :map, default: nil
  attr :selected_lemming_inheriting?, :boolean, default: false
  attr :lemming_not_found?, :boolean, default: false
  attr :active_detail_tab, :string, default: "overview"
  attr :settings_form, :any, default: nil
  attr :overview_path, :string, default: nil
  attr :edit_path, :string, default: nil

  def lemmings_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="lemmings-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_all_lemmings")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_all_lemmings")}</:subtitle>
      </.panel>

      <.panel :if={!@world} id="lemmings-world-missing-state" tone="warning">
        <:title>{dgettext("lemmings", ".title_all_lemmings")}</:title>
        <.empty_state
          id="lemmings-world-missing-state-card"
          title={dgettext("lemmings", ".empty_world_unavailable")}
          copy={dgettext("lemmings", ".empty_world_unavailable_copy")}
        />
      </.panel>

      <.panel :if={@world} id="lemmings-filters-panel" tone="info">
        <:title>{dgettext("lemmings", ".title_filters")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_filters")}</:subtitle>

        <.form for={@filters_form} id="lemmings-filters-form" phx-change="change_filters">
          <div class="grid gap-4 lg:grid-cols-3">
            <div
              id="lemmings-selected-world"
              class="flex flex-col gap-1.5 border-2 border-zinc-800 bg-zinc-950/70 px-3 py-2.5"
            >
              <span class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".filter_world")}
              </span>
              <span class="font-mono text-sm text-zinc-100">
                {Helpers.display_value(@world && @world.name)}
              </span>
            </div>

            <.input
              id="lemmings-filter-city"
              field={@filters_form[:city_id]}
              type="select"
              label={dgettext("lemmings", ".filter_city")}
              options={Enum.map(@cities, fn city -> {city.name, city.id} end)}
              prompt={dgettext("lemmings", ".filter_city_prompt")}
            />

            <.input
              id="lemmings-filter-department"
              field={@filters_form[:department_id]}
              type="select"
              label={dgettext("lemmings", ".filter_department")}
              options={Enum.map(@departments, fn department -> {department.name, department.id} end)}
              prompt={dgettext("lemmings", ".filter_department_prompt")}
            />
          </div>
        </.form>
      </.panel>

      <.panel :if={@world} id="lemmings-cards-panel">
        <:title>{dgettext("lemmings", ".title_lemming_types")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_lemming_types")}</:subtitle>

        <div :if={@lemmings == []} id="lemmings-list-empty-state">
          <.empty_state
            id="lemmings-list-empty-state-card"
            title={dgettext("lemmings", ".empty_no_lemmings")}
            copy={dgettext("lemmings", ".empty_no_lemmings_copy")}
          />
        </div>

        <div
          :if={@lemmings != []}
          id="lemmings-cards-grid"
          class="grid gap-4 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4"
        >
          <.link
            :for={lemming <- @lemmings}
            id={"lemming-card-#{lemming.id}"}
            navigate={
              ~p"/lemmings/#{lemming.id}?#{card_params(@selected_city, @selected_department)}"
            }
            class="flex min-h-40 flex-col gap-4 border-2 border-zinc-800 bg-zinc-950/80 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400 hover:bg-emerald-400/5"
          >
            <div class="flex items-start justify-between gap-4">
              <p class="min-w-0 text-base leading-tight text-zinc-100">{lemming.name}</p>
              <.icon name="hero-arrow-top-right-on-square" class="size-4 shrink-0 text-zinc-500" />
            </div>

            <p class="text-sm leading-relaxed text-zinc-400">
              {Helpers.truncate_value(lemming.description,
                max_length: 120,
                unavailable_label: dgettext("lemmings", ".empty_no_description")
              )}
            </p>

            <div class="grid gap-2 text-xs uppercase tracking-widest text-zinc-500">
              <div id={"lemming-card-department-#{lemming.id}"} class="flex items-center gap-2">
                <span>{dgettext("lemmings", ".filter_department")}</span>
                <span class="font-mono text-zinc-300">
                  {Helpers.display_value(lemming.department && lemming.department.name)}
                </span>
              </div>

              <div id={"lemming-card-city-#{lemming.id}"} class="flex items-center gap-2">
                <span>{dgettext("lemmings", ".filter_city")}</span>
                <span class="font-mono text-zinc-300">
                  {Helpers.display_value(
                    lemming.department && lemming.department.city && lemming.department.city.name
                  )}
                </span>
              </div>
            </div>

            <div class="mt-auto flex items-center justify-between gap-3 border-t border-zinc-800 pt-3">
              <span class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".label_open_detail")}
              </span>
              <.status kind={:lemming} value={lemming.status} />
            </div>
          </.link>
        </div>
      </.panel>
    </.content_container>
    """
  end

  attr :world, :map, default: nil
  attr :selected_city, :map, default: nil
  attr :selected_department, :map, default: nil
  attr :selected_lemming, :map, default: nil
  attr :selected_lemming_effective_config, :map, default: nil
  attr :selected_lemming_inheriting?, :boolean, default: false
  attr :lemming_not_found?, :boolean, default: false
  attr :active_detail_tab, :string, default: "overview"
  attr :settings_form, :any, default: nil
  attr :overview_path, :string, default: nil
  attr :edit_path, :string, default: nil
  attr :secrets_path, :string, default: nil
  attr :secret_form, :any, default: nil
  attr :secret_metadata, :list, default: []
  attr :secret_activity, :list, default: []
  attr :lemming_instances, :list, default: []
  attr :recent_lemming_instances, :list, default: []
  attr :spawn_form, :any, default: nil
  attr :spawn_modal_open?, :boolean, default: false
  attr :spawn_enabled?, :boolean, default: false
  attr :spawn_disabled_reason, :string, default: nil

  def lemming_detail_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="lemming-detail-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_lemming_detail")}</:title>

        <div :if={@selected_lemming} class="flex items-start gap-4">
          <LemmingImageComponents.lemming_type_avatar
            slug={@selected_lemming.slug}
            class={
              if @selected_lemming.status == "archived",
                do: "border-emerald-400/30 bg-emerald-400/5 opacity-40 grayscale",
                else: "border-emerald-400/30 bg-emerald-400/5"
            }
          />
          <div class={[
            "min-w-0 flex-1",
            @selected_lemming.status == "archived" && "opacity-50"
          ]}>
            <p id="lemming-hero-name" class="text-left text-lg text-zinc-100">
              {@selected_lemming.name}
            </p>
            <p
              id="lemming-hero-purpose"
              class="text-left text-sm font-normal tracking-normal text-zinc-400"
            >
              {Helpers.display_value(@selected_lemming.description)}
            </p>
          </div>
          <div class="ml-auto flex shrink-0 flex-wrap items-center justify-end gap-2 self-start">
            <span id="lemming-export-hook" phx-hook="DownloadJsonHook" class="hidden" />
            <span class={[
              @selected_lemming.status == "archived" &&
                "border-2 border-amber-400/50 bg-amber-400/5 px-2 py-1"
            ]}>
              <.status kind={:lemming} value={@selected_lemming.status} />
            </span>

            <button
              id="lemming-export-button"
              type="button"
              phx-click="export_lemming"
              class="inline-flex h-9 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/80 px-3 text-xs font-medium text-zinc-100 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
            >
              {dgettext("lemmings", ".button_export_json")}
            </button>

            <.link
              id="lemming-action-edit"
              patch={@edit_path}
              class="inline-flex h-9 items-center justify-center gap-2 border-2 border-sky-400/50 bg-sky-400/10 px-3 text-xs font-medium text-sky-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
            >
              {dgettext("lemmings", ".tab_edit")}
            </.link>

            <button
              :if={@selected_lemming.status in ["draft", "archived"]}
              id="lemming-hero-action-activate"
              type="button"
              phx-click="lemming_lifecycle"
              phx-value-action="activate"
              class="inline-flex h-9 items-center justify-center gap-2 border-2 border-sky-400/50 bg-sky-400/10 px-3 text-xs font-medium text-sky-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
            >
              {dgettext("lemmings", ".button_lemming_activate")}
            </button>

            <button
              :if={@selected_lemming.status == "active"}
              id="lemming-hero-action-archive"
              type="button"
              phx-click="lemming_lifecycle"
              phx-value-action="archive"
              class="inline-flex h-9 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/80 px-3 text-xs font-medium text-zinc-100 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
            >
              {dgettext("lemmings", ".button_lemming_archive")}
            </button>
          </div>
        </div>
        <div
          :if={@selected_lemming}
          id="lemming-detail-context"
          class="grid gap-3 md:grid-cols-3"
        >
          <.stat_item
            id="lemming-context-city"
            label={dgettext("lemmings", ".filter_city")}
            value={Helpers.display_value(@selected_city && @selected_city.name)}
          />
          <.stat_item
            id="lemming-context-department"
            label={dgettext("lemmings", ".filter_department")}
            value={Helpers.display_value(@selected_department && @selected_department.name)}
          />
          <.stat_item
            id="lemming-context-status"
            label={dgettext("lemmings", ".detail_status")}
            value={
              @selected_lemming && @selected_lemming.__struct__.translate_status(@selected_lemming)
            }
          />
        </div>
      </.panel>

      <.panel :if={@lemming_not_found?} id="lemming-detail-not-found" tone="warning">
        <:title>{dgettext("lemmings", ".title_lemming_detail")}</:title>
        <.empty_state
          id="lemming-not-found-state"
          title={dgettext("lemmings", ".empty_lemming_not_found")}
          copy={dgettext("lemmings", ".empty_lemming_not_found_copy")}
        />
      </.panel>

      <.content_grid :if={@selected_lemming} id="lemmings-workspace-grid" columns="two">
        <.lemming_detail_workspace
          lemming={@selected_lemming}
          effective_config={@selected_lemming_effective_config}
          inheriting?={@selected_lemming_inheriting?}
          active_tab={@active_detail_tab}
          settings_form={@settings_form}
          overview_path={@overview_path}
          edit_path={@edit_path}
          secrets_path={@secrets_path}
          secret_form={@secret_form}
          secret_metadata={@secret_metadata}
          secret_activity={@secret_activity}
        />

        <.lemming_instances_workspace
          lemming={@selected_lemming}
          instances={@lemming_instances}
          recent_instances={@recent_lemming_instances}
          spawn_form={@spawn_form}
          spawn_modal_open?={@spawn_modal_open?}
          spawn_enabled?={@spawn_enabled?}
          spawn_disabled_reason={@spawn_disabled_reason}
        />
      </.content_grid>
    </.content_container>
    """
  end

  attr :lemming, :map, required: true
  attr :effective_config, :map, required: true
  attr :inheriting?, :boolean, default: false
  attr :active_tab, :string, default: "overview"
  attr :settings_form, :any, default: nil
  attr :overview_path, :string, default: nil
  attr :edit_path, :string, default: nil
  attr :secrets_path, :string, default: nil
  attr :secret_form, :any, default: nil
  attr :secret_metadata, :list, default: []
  attr :secret_activity, :list, default: []

  def lemming_detail_workspace(assigns) do
    assigns = assign(assigns, :budgets, Map.get(assigns.effective_config.costs_config, :budgets))

    ~H"""
    <.panel
      id="lemming-detail-panel"
      tone={if(@lemming.status == "archived", do: "warning", else: "default")}
    >
      <div id="lemming-detail-mode" class="flex flex-col gap-0.5">
        <span class="text-sm font-medium text-zinc-100">
          {detail_mode_label(@active_tab)}
        </span>
        <span
          id="lemming-detail-slug"
          class="font-mono text-xs uppercase tracking-widest text-zinc-500"
        >
          {@lemming.slug}
        </span>
      </div>

      <div id="lemming-detail-tabs" class="mb-4 flex flex-wrap gap-2">
        <.link
          id="lemming-tab-overview"
          patch={@overview_path}
          class={detail_tab_class(@active_tab == "overview")}
        >
          {dgettext("lemmings", ".tab_overview")}
        </.link>
        <.link
          id="lemming-tab-edit"
          patch={@edit_path}
          class={detail_tab_class(@active_tab == "edit")}
        >
          {dgettext("lemmings", ".tab_edit")}
        </.link>
        <.link
          id="lemming-tab-secrets"
          patch={@secrets_path}
          class={detail_tab_class(@active_tab == "secrets")}
        >
          {dgettext("world", "Secrets")}
        </.link>
      </div>

      <div :if={@active_tab == "overview"} class="space-y-6">
        <div class="flex flex-col gap-2">
          <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_instructions")}
          </p>
          <pre class="overflow-x-auto whitespace-pre-wrap border-2 border-zinc-800 bg-zinc-950/70 p-4 text-sm leading-relaxed text-zinc-300">{Helpers.display_value(@lemming.instructions)}</pre>
        </div>

        <.panel id="lemming-effective-config-panel" tone="info">
          <:title>{dgettext("lemmings", ".title_effective_config")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_effective_config")}</:subtitle>

          <p
            :if={@inheriting?}
            id="lemming-inheriting-config-note"
            class="text-sm text-zinc-400"
          >
            {dgettext("lemmings", ".copy_inheriting_all_config")}
          </p>

          <div class="grid gap-3 md:grid-cols-2">
            <.stat_item
              id="lemming-effective-max-lemmings"
              label={dgettext("lemmings", ".detail_effective_max_lemmings")}
              value={
                Helpers.display_value(@effective_config.limits_config.max_lemmings_per_department)
              }
            />
            <.stat_item
              id="lemming-effective-idle-ttl"
              label={dgettext("lemmings", ".detail_effective_idle_ttl")}
              value={Helpers.display_value(@effective_config.runtime_config.idle_ttl_seconds)}
            />
            <.stat_item
              id="lemming-effective-cross-city"
              label={dgettext("lemmings", ".detail_effective_cross_city")}
              value={Helpers.display_value(@effective_config.runtime_config.cross_city_communication)}
            />
            <.stat_item
              id="lemming-effective-daily-tokens"
              label={dgettext("lemmings", ".detail_effective_daily_tokens")}
              value={Helpers.display_value(@budgets && @budgets.daily_tokens)}
            />
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <div class="flex flex-col gap-2">
              <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_allowed_tools")}
              </p>
              <div id="lemming-allowed-tools" class="flex flex-wrap gap-2">
                <.badge :for={tool <- @effective_config.tools_config.allowed_tools} tone="info">
                  {tool}
                </.badge>
                <.badge :if={@effective_config.tools_config.allowed_tools == []} tone="default">
                  {dgettext("lemmings", ".empty_no_allowed_tools")}
                </.badge>
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_denied_tools")}
              </p>
              <div id="lemming-denied-tools" class="flex flex-wrap gap-2">
                <.badge :for={tool <- @effective_config.tools_config.denied_tools} tone="warning">
                  {tool}
                </.badge>
                <.badge :if={@effective_config.tools_config.denied_tools == []} tone="default">
                  {dgettext("lemmings", ".empty_no_denied_tools")}
                </.badge>
              </div>
            </div>
          </div>
        </.panel>
      </div>

      <div :if={@active_tab == "edit"} id="lemming-settings-tab-panel" class="space-y-6">
        <.panel id="lemming-settings-form-panel" tone="info">
          <:title>{dgettext("lemmings", ".title_lemming_settings")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_lemming_settings")}</:subtitle>

          <.form
            :if={@settings_form}
            for={@settings_form}
            id="lemming-settings-form"
            phx-change="validate_lemming_settings"
            phx-submit="save_lemming_settings"
          >
            <div class="space-y-6">
              <div class="grid gap-4 lg:grid-cols-2">
                <.form_field_with_info
                  field_id="lemming-settings-name"
                  label={dgettext("lemmings", ".label_name")}
                  tooltip={dgettext("lemmings", ".tooltip_create_name")}
                >
                  <.input id="lemming-settings-name" field={@settings_form[:name]} />
                </.form_field_with_info>

                <.form_field_with_info
                  field_id="lemming-settings-slug"
                  label={dgettext("lemmings", ".label_slug")}
                  tooltip={dgettext("lemmings", ".tooltip_create_slug")}
                >
                  <.input id="lemming-settings-slug" field={@settings_form[:slug]} />
                </.form_field_with_info>
              </div>

              <.form_field_with_info
                field_id="lemming-settings-description"
                label={dgettext("lemmings", ".label_description")}
                tooltip={dgettext("lemmings", ".tooltip_create_description")}
              >
                <.input
                  id="lemming-settings-description"
                  field={@settings_form[:description]}
                  type="textarea"
                  rows="3"
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming-settings-instructions"
                label={dgettext("lemmings", ".label_instructions")}
                tooltip={dgettext("lemmings", ".tooltip_create_instructions")}
              >
                <.input
                  id="lemming-settings-instructions"
                  field={@settings_form[:instructions]}
                  type="textarea"
                  rows="6"
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming-settings-status"
                label={dgettext("lemmings", ".label_status")}
                tooltip={dgettext("lemmings", ".tooltip_create_status")}
              >
                <.input
                  id="lemming-settings-status"
                  field={@settings_form[:status]}
                  type="select"
                  options={LemmingsOs.Lemmings.Lemming.status_options()}
                />
              </.form_field_with_info>

              <div class="grid gap-3 md:grid-cols-2">
                <.button id="lemming-edit-limit" variant="ghost" type="button">
                  {dgettext("lemmings", ".button_edit_limit")}
                </.button>
                <.button id="lemming-edit-runtime" variant="ghost" type="button">
                  {dgettext("lemmings", ".button_edit_runtime")}
                </.button>
                <.button id="lemming-edit-costs" variant="ghost" type="button">
                  {dgettext("lemmings", ".button_edit_costs")}
                </.button>
                <.button id="lemming-edit-tools" variant="ghost" type="button">
                  {dgettext("lemmings", ".button_edit_tools")}
                </.button>
              </div>

              <div class="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-end">
                <.button id="lemming-settings-cancel" patch={@overview_path} variant="primary">
                  {dgettext("lemmings", ".button_cancel_edit")}
                </.button>
                <.button
                  id="lemming-settings-save"
                  type="submit"
                  variant="secondary"
                  phx-disable-with={dgettext("lemmings", ".button_saving_lemming")}
                >
                  {dgettext("lemmings", ".button_save_lemming")}
                </.button>
              </div>
            </div>
          </.form>
        </.panel>
      </div>

      <SecretBankComponents.secret_surface
        :if={@active_tab == "secrets"}
        id_prefix="lemming"
        form={@secret_form}
        metadata={@secret_metadata}
        activity={@secret_activity}
        save_event="save_lemming_secret"
        edit_event="edit_lemming_secret"
        delete_event="delete_lemming_secret"
        subtitle={dgettext("world", "Write-only Secret Bank values scoped to this lemming.")}
      />
    </.panel>
    """
  end

  attr :lemming, :map, required: true
  attr :instances, :list, default: []
  attr :recent_instances, :list, default: []
  attr :spawn_form, :any, default: nil
  attr :spawn_modal_open?, :boolean, default: false
  attr :spawn_enabled?, :boolean, default: false
  attr :spawn_disabled_reason, :string, default: nil

  def lemming_instances_workspace(assigns) do
    ~H"""
    <.panel id="lemming-instances-panel" tone="warning">
      <:title>{dgettext("lemmings", ".title_instances_workspace")}</:title>
      <:subtitle>{dgettext("lemmings", ".subtitle_instances_workspace")}</:subtitle>

      <div class="space-y-5">
        <div class="flex flex-col gap-3 border-b border-zinc-800 pb-4 md:flex-row md:items-start md:justify-between">
          <div class="space-y-1">
            <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".detail_spawn_requests")}
            </p>
            <p class="text-sm text-zinc-400">
              {if @spawn_enabled?,
                do: dgettext("lemmings", ".spawn_enabled_copy"),
                else: @spawn_disabled_reason}
            </p>
          </div>

          <div class="flex shrink-0 items-center">
            <.button
              :if={@spawn_enabled?}
              id="lemming-spawn-button"
              type="button"
              variant="secondary"
              phx-click="open_spawn_modal"
            >
              {dgettext("lemmings", ".button_spawn")}
            </.button>

            <button
              :if={!@spawn_enabled?}
              id="lemming-spawn-button"
              type="button"
              disabled
              title={@spawn_disabled_reason}
              class="inline-flex min-h-11 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/70 px-4 py-2 text-sm font-medium text-zinc-500"
            >
              {dgettext("lemmings", ".button_spawn")}
            </button>
          </div>
        </div>

        <div :if={@lemming} id="lemming-instances-selected-copy" class="text-sm text-zinc-400">
          {dgettext("lemmings", ".copy_instances_workspace_selected", name: @lemming.name)}
        </div>

        <div :if={!@lemming} id="lemming-instances-empty-state">
          <.empty_state
            id="lemming-instances-empty-state-card"
            title={dgettext("lemmings", ".empty_instances_workspace")}
            copy={dgettext("lemmings", ".empty_instances_workspace_copy")}
          />
        </div>

        <div :if={@spawn_modal_open?} id="lemming-spawn-modal" class="fixed inset-0 z-50">
          <div class="absolute inset-0 bg-black/70" />
          <div class="relative flex min-h-full items-center justify-center p-4">
            <div class="w-full max-w-2xl border-2 border-emerald-400/40 bg-zinc-950 p-5 shadow-2xl">
              <div class="flex items-start justify-between gap-4 border-b border-zinc-800 pb-4">
                <div>
                  <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                    {dgettext("lemmings", ".title_spawn_instance")}
                  </p>
                  <p class="mt-1 text-sm text-zinc-400">
                    {dgettext("lemmings", ".copy_spawn_instance")}
                  </p>
                </div>

                <button
                  id="lemming-spawn-modal-close"
                  type="button"
                  class="text-zinc-400 hover:text-zinc-100"
                  phx-click="close_spawn_modal"
                >
                  <.icon name="hero-x-mark" class="size-5" />
                </button>
              </div>

              <.form
                for={@spawn_form}
                id="lemming-spawn-form"
                class="mt-4 space-y-4"
                phx-change="validate_spawn"
                phx-submit="submit_spawn"
              >
                <.input
                  id="lemming-spawn-request-text"
                  field={@spawn_form[:request_text]}
                  type="textarea"
                  rows="5"
                  label={dgettext("lemmings", ".label_initial_request")}
                  placeholder={dgettext("lemmings", ".placeholder_spawn_request")}
                />

                <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
                  <.button
                    id="lemming-spawn-cancel"
                    type="button"
                    variant="ghost"
                    phx-click="close_spawn_modal"
                  >
                    {dgettext("lemmings", ".button_cancel")}
                  </.button>

                  <.button
                    id="lemming-spawn-submit"
                    type="submit"
                    variant="secondary"
                    disabled={Helpers.blank?(@spawn_form[:request_text].value)}
                    phx-disable-with={dgettext("lemmings", ".button_spawning")}
                  >
                    {dgettext("lemmings", ".button_confirm_spawn")}
                  </.button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <div class="space-y-3">
          <div class="flex items-center justify-between gap-3">
            <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".title_active_instances")}
            </p>
            <p class="text-xs uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".count_total", count: length(@instances))}
            </p>
          </div>

          <div :if={@instances == []} id="lemming-instances-empty-list">
            <.empty_state
              id="lemming-instances-empty-state-card"
              title={dgettext("lemmings", ".empty_no_active_instances")}
              copy={dgettext("lemmings", ".empty_no_active_instances_copy")}
            />
          </div>

          <div :if={@instances != []} id="lemming-instances-list" class="grid gap-3">
            <.link
              :for={instance <- @instances}
              id={"lemming-instance-#{instance.id}"}
              navigate={instance_path(@lemming.world_id, instance.id)}
              class="flex items-start justify-between gap-4 border-2 border-zinc-800 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
            >
              <div class="min-w-0 space-y-2">
                <div class="flex items-center gap-2">
                  <.status kind={:instance} value={instance.status} />
                  <span class="text-xs uppercase tracking-widest text-zinc-500">
                    {Helpers.format_datetime(instance.inserted_at,
                      nil_label: dgettext("lemmings", ".label_unknown")
                    )}
                  </span>
                </div>

                <p class="truncate text-sm text-zinc-100">
                  {instance.preview}
                </p>
              </div>

              <div class="shrink-0 pt-0.5">
                <.icon name="hero-arrow-top-right-on-square" class="size-4 text-zinc-500" />
              </div>
            </.link>
          </div>
        </div>

        <div :if={@recent_instances != []} class="space-y-3 border-t border-zinc-800 pt-4">
          <div class="flex items-center justify-between gap-3">
            <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".title_recent_sessions")}
            </p>
            <p class="text-xs uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".count_shown", count: length(@recent_instances))}
            </p>
          </div>

          <div id="lemming-recent-instances-list" class="grid gap-3">
            <.link
              :for={instance <- @recent_instances}
              id={"lemming-recent-instance-#{instance.id}"}
              navigate={instance_path(@lemming.world_id, instance.id)}
              class="flex items-start justify-between gap-4 border border-zinc-800 bg-zinc-950/60 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-zinc-600"
            >
              <div class="min-w-0 space-y-2">
                <div class="flex items-center gap-2">
                  <.status kind={:instance} value={instance.status} />
                  <span class="text-xs uppercase tracking-widest text-zinc-500">
                    {Helpers.format_datetime(instance.inserted_at,
                      nil_label: dgettext("lemmings", ".label_unknown")
                    )}
                  </span>
                </div>

                <p class="truncate text-sm text-zinc-200">
                  {instance.preview}
                </p>
              </div>

              <div class="shrink-0 pt-0.5">
                <.icon name="hero-arrow-top-right-on-square" class="size-4 text-zinc-500" />
              </div>
            </.link>
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  attr :lemming, :map, required: true
  attr :size, :string, default: "sm", values: ~w(sm md)
  attr :path, :string, default: nil

  def lemming_sprite(assigns) do
    ~H"""
    <.link
      :if={@path}
      navigate={@path}
      class={[
        "inline-flex flex-col items-center gap-2 text-zinc-300 transition-all hover:-translate-y-px hover:text-emerald-400",
        sprite_size(@size)
      ]}
    >
      <div
        class={[
          "shrink-0 border-2 border-zinc-700 bg-zinc-900",
          if(@size == "md", do: "size-12", else: "size-10")
        ]}
        style={accent_style(@lemming.accent)}
      >
      </div>
      <span class="text-xs font-medium">{@lemming.name}</span>
    </.link>
    <div
      :if={!@path}
      class={["inline-flex flex-col items-center gap-2 text-zinc-300", sprite_size(@size)]}
    >
      <div
        class={[
          "shrink-0 border-2 border-zinc-700 bg-zinc-900",
          if(@size == "md", do: "size-12", else: "size-10")
        ]}
        style={accent_style(@lemming.accent)}
      >
      </div>
      <span class="text-xs font-medium">{@lemming.name}</span>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :scope_form, :any, required: true
  attr :world, :map, default: nil
  attr :city, :map, default: nil
  attr :department, :map, default: nil
  attr :cities, :list, default: []
  attr :departments, :list, default: []

  def create_lemming_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="create-lemming-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_create_lemming")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_create_lemming_real")}</:subtitle>
      </.panel>

      <.content_grid columns="sidebar">
        <.panel :if={!@department} id="create-lemming-missing-context" tone="warning">
          <:title>{dgettext("lemmings", ".title_create_scope")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_create_scope")}</:subtitle>

          <div class="flex flex-col gap-6">
            <.empty_state
              id="create-lemming-missing-context-card"
              title={dgettext("lemmings", ".empty_create_missing_department")}
              copy={dgettext("lemmings", ".empty_create_missing_department_copy")}
            />

            <.form for={@scope_form} id="create-lemming-scope-form" phx-change="change_scope">
              <div class="grid gap-4 lg:grid-cols-3">
                <div
                  id="create-lemming-selected-world"
                  class="flex flex-col gap-1.5 border-2 border-zinc-800 bg-zinc-950/70 px-3 py-2.5"
                >
                  <span class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                    {dgettext("lemmings", ".filter_world")}
                  </span>
                  <span class="font-mono text-sm text-zinc-100">
                    {Helpers.display_value(@world && @world.name)}
                  </span>
                </div>

                <.input
                  id="create-lemming-scope-city"
                  field={@scope_form[:city_id]}
                  type="select"
                  label={dgettext("lemmings", ".filter_city")}
                  options={Enum.map(@cities, fn city -> {city.name, city.id} end)}
                  prompt={dgettext("lemmings", ".filter_city_prompt")}
                />

                <.input
                  id="create-lemming-scope-department"
                  field={@scope_form[:department_id]}
                  type="select"
                  label={dgettext("lemmings", ".filter_department")}
                  options={
                    Enum.map(@departments, fn department -> {department.name, department.id} end)
                  }
                  prompt={dgettext("lemmings", ".filter_department_prompt")}
                  disabled={@departments == []}
                />
              </div>
            </.form>
          </div>
        </.panel>

        <.panel :if={@department} id="create-lemming-panel" tone="accent">
          <:title>{dgettext("lemmings", ".title_create_lemming")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_create_lemming_form")}</:subtitle>
          <.form for={@form} id="create-lemming-form" phx-change="validate" phx-submit="save">
            <div class="flex flex-col gap-6">
              <.form_field_with_info
                field_id="lemming_name"
                label={dgettext("lemmings", ".label_name")}
                tooltip={dgettext("lemmings", ".tooltip_create_name")}
              >
                <.input
                  field={@form[:name]}
                  placeholder={dgettext("lemmings", ".placeholder_name")}
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming_slug"
                label={dgettext("lemmings", ".label_slug")}
                tooltip={dgettext("lemmings", ".tooltip_create_slug")}
              >
                <.input
                  field={@form[:slug]}
                  placeholder={dgettext("lemmings", ".placeholder_slug")}
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming_description"
                label={dgettext("lemmings", ".label_description")}
                tooltip={dgettext("lemmings", ".tooltip_create_description")}
              >
                <.input
                  field={@form[:description]}
                  type="textarea"
                  rows="3"
                  placeholder={dgettext("lemmings", ".placeholder_description")}
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming_instructions"
                label={dgettext("lemmings", ".label_instructions")}
                tooltip={dgettext("lemmings", ".tooltip_create_instructions")}
              >
                <.input
                  field={@form[:instructions]}
                  type="textarea"
                  rows="5"
                  placeholder={dgettext("lemmings", ".placeholder_instructions")}
                />
              </.form_field_with_info>

              <.form_field_with_info
                field_id="lemming_status"
                label={dgettext("lemmings", ".label_status")}
                tooltip={dgettext("lemmings", ".tooltip_create_status")}
              >
                <.input
                  field={@form[:status]}
                  type="select"
                  options={LemmingsOs.Lemmings.Lemming.status_options()}
                />
              </.form_field_with_info>

              <div class="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-end">
                <.button
                  id="create-lemming-cancel"
                  navigate={
                    ~p"/departments?#{%{city: @city.id, dept: @department.id, tab: "lemmings"}}"
                  }
                  variant="primary"
                  class="w-full sm:w-fit"
                >
                  {dgettext("lemmings", ".button_cancel_create")}
                </.button>

                <.button
                  type="submit"
                  id="create-lemming-submit"
                  variant="secondary"
                  phx-disable-with={dgettext("lemmings", ".button_creating_lemming")}
                  class="w-full sm:w-fit"
                >
                  {dgettext("lemmings", ".button_create_lemming")}
                </.button>
              </div>
            </div>
          </.form>
        </.panel>

        <.panel :if={@department} id="create-lemming-context-panel">
          <:title>{dgettext("lemmings", ".title_create_scope")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_create_scope")}</:subtitle>
          <div class="flex flex-col gap-6">
            <.stat_item
              id="create-lemming-world"
              label={dgettext("lemmings", ".filter_world")}
              value={Helpers.display_value(@world && @world.name)}
            />
            <.stat_item
              id="create-lemming-city"
              label={dgettext("lemmings", ".filter_city")}
              value={Helpers.display_value(@city && @city.name)}
            />
            <.stat_item
              id="create-lemming-department"
              label={dgettext("lemmings", ".filter_department")}
              value={Helpers.display_value(@department && @department.name)}
            />
            <p class="text-sm leading-relaxed text-zinc-400">
              {dgettext("lemmings", ".copy_create_scope")}
            </p>
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  attr :field_id, :string, required: true
  attr :label, :string, required: true
  attr :tooltip, :string, required: true

  slot :inner_block, required: true

  def form_field_with_info(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <div class="flex items-center gap-2">
        <label for={@field_id} class="text-xs font-bold uppercase tracking-widest text-zinc-500">
          {@label}
        </label>
        <span
          class="inline-flex size-5 items-center justify-center rounded-full border border-zinc-700
     bg-zinc-950/80 text-zinc-400"
          title={@tooltip}
          aria-label={@tooltip}
        >
          <.icon name="hero-information-circle" class="size-3.5" />
        </span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp card_params(selected_city, selected_department) do
    %{}
    |> maybe_put(:city, selected_city && selected_city.id)
    |> maybe_put(:dept, selected_department && selected_department.id)
  end

  defp detail_mode_label("edit"), do: dgettext("lemmings", ".tab_edit")
  defp detail_mode_label("secrets"), do: dgettext("world", "Secrets")
  defp detail_mode_label(_tab), do: dgettext("lemmings", ".tab_overview")

  defp detail_tab_class(true),
    do:
      "inline-flex h-10 items-center justify-center gap-2 border-2 border-emerald-400/50 bg-emerald-400/10 px-3 text-sm font-medium text-emerald-400 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"

  defp detail_tab_class(false),
    do:
      "inline-flex h-10 items-center justify-center gap-2 border-2 border-zinc-700 bg-zinc-950/80 px-3 text-sm font-medium text-zinc-100 transition duration-200 ease-out hover:-translate-y-px"

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp accent_style(color), do: "background-color: #{color};"
  defp sprite_size("sm"), do: nil
  defp sprite_size("md"), do: "sprite-card--md"

  defp instance_path(world_id, instance_id) do
    ~p"/lemmings/instances/#{instance_id}?#{%{world: world_id}}"
  end
end
