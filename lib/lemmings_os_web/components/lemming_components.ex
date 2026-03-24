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

  def lemmings_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="lemmings-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_all_lemmings")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_all_lemmings")}</:subtitle>
      </.panel>

      <.panel id="lemmings-filters-panel" tone="info">
        <:title>{dgettext("lemmings", ".title_filters")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_filters")}</:subtitle>

        <.form for={@filters_form} id="lemmings-filters-form" phx-change="change_filters">
          <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(0,1fr)]">
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

      <.panel id="lemmings-cards-panel">
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
            class={[
              "flex min-h-40 flex-col gap-4 border-2 border-zinc-800 bg-zinc-950/80 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400 hover:bg-emerald-400/5"
            ]}
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

  def lemming_detail_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="lemming-detail-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_lemming_detail")}</:title>

        <div :if={@selected_lemming} class="flex items-start gap-4">
          <LemmingImageComponents.lemming_type_avatar
            slug={@selected_lemming.slug}
            class="border-emerald-400/30 bg-emerald-400/5"
          />
          <div class="min-w-0 flex-1">
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
            <.status kind={:lemming} value={@selected_lemming.status} />

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
        />

        <.lemming_instances_workspace lemming={@selected_lemming} />
      </.content_grid>
    </.content_container>
    """
  end

  attr :lemming, :map, required: true
  attr :effective_config, :map, required: true
  attr :inheriting?, :boolean, default: false

  def lemming_detail_workspace(assigns) do
    assigns = assign(assigns, :budgets, Map.get(assigns.effective_config.costs_config, :budgets))

    ~H"""
    <.panel
      id="lemming-detail-panel"
      tone={if(@lemming.status == "archived", do: "warning", else: "default")}
    >
      <:actions>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div id="lemming-detail-tabs" class="flex flex-wrap gap-2">
            <.badge id="lemming-tab-overview" tone="accent">
              {dgettext("lemmings", ".tab_overview")}
            </.badge>
            <.badge id="lemming-tab_edit_placeholder" tone="default">
              {dgettext("lemmings", ".tab_edit_coming_soon")}
            </.badge>
          </div>

          <p
            id="lemming-detail-slug"
            class="font-mono text-xs uppercase tracking-widest text-zinc-500"
          >
            {@lemming.slug}
          </p>
        </div>
      </:actions>

      <div class="space-y-6">
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
    </.panel>
    """
  end

  attr :lemming, :map, default: nil

  def lemming_instances_workspace(assigns) do
    ~H"""
    <.panel id="lemming-instances-panel" tone="warning">
      <:title>{dgettext("lemmings", ".title_instances_workspace")}</:title>
      <:subtitle>{dgettext("lemmings", ".subtitle_instances_workspace")}</:subtitle>

      <div class="space-y-4">
        <div class="grid gap-3 md:grid-cols-2">
          <.stat_item
            id="lemming-instances-running-count"
            label={dgettext("lemmings", ".detail_running_instances")}
            value={dgettext("lemmings", ".value_instances_unknown")}
          />
          <.stat_item
            id="lemming-instances-spawn-capability"
            label={dgettext("lemmings", ".detail_spawn_requests")}
            value={dgettext("lemmings", ".value_future_capability")}
          />
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

        <div :if={@lemming} id="lemming-instances-placeholder-stack" class="grid gap-4">
          <div class="border-2 border-zinc-800 bg-zinc-950/70 p-4">
            <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".title_instance_console_placeholder")}
            </p>
            <p class="mt-2 text-sm text-zinc-400">
              {dgettext("lemmings", ".copy_instance_console_placeholder")}
            </p>
          </div>

          <div class="border-2 border-zinc-800 bg-zinc-950/70 p-4">
            <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", ".title_spawn_request_placeholder")}
            </p>
            <p class="mt-2 text-sm text-zinc-400">
              {dgettext("lemmings", ".copy_spawn_request_placeholder")}
            </p>
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
  attr :selected_tools, :list, required: true
  attr :available_tools, :list, required: true

  def create_lemming_page(assigns) do
    ~H"""
    <.content_container>
      <.content_grid columns="sidebar">
        <.panel id="create-lemming-panel" tone="accent">
          <:title>{dgettext("lemmings", ".title_create_lemming")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_create_lemming")}</:subtitle>
          <.form for={@form} id="create-lemming-form" phx-change="validate" phx-submit="save">
            <div class="flex flex-col gap-6">
              <.input
                field={@form[:name]}
                label={dgettext("lemmings", ".label_name")}
                placeholder={dgettext("lemmings", ".placeholder_name")}
              />
              <.input
                field={@form[:role]}
                label={dgettext("lemmings", ".label_role")}
                placeholder={dgettext("lemmings", ".placeholder_role")}
              />
              <.input
                field={@form[:model]}
                type="select"
                label={dgettext("lemmings", ".label_model")}
                options={[
                  {"gpt-4o", "gpt-4o"},
                  {"gpt-4o-mini", "gpt-4o-mini"},
                  {"claude-3.5", "claude-3.5"},
                  {"claude-3-opus", "claude-3-opus"},
                  {"llama-3", "llama-3"}
                ]}
              />
              <.input
                field={@form[:system_prompt]}
                type="textarea"
                label={dgettext("lemmings", ".label_system_prompt")}
                rows="5"
              />

              <div class="flex flex-col gap-2">
                <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                  {dgettext("lemmings", ".detail_tools_allowed")}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button
                    :for={tool <- @available_tools}
                    id={"tool-toggle-#{tool}"}
                    type="button"
                    phx-click="toggle_tool"
                    phx-value-tool={tool}
                    class={[
                      "border-2 px-3 py-1.5 text-xs font-medium transition-all duration-150",
                      tool in @selected_tools &&
                        "border-emerald-400/60 bg-emerald-400/10 text-emerald-400 shadow-md",
                      tool not in @selected_tools &&
                        "border-zinc-700 bg-zinc-950/80 text-zinc-400 hover:border-zinc-600 hover:text-zinc-200"
                    ]}
                  >
                    {tool}
                  </button>
                </div>
              </div>

              <.button type="submit" class="w-full sm:w-fit">
                {dgettext("lemmings", ".button_deploy_lemming")}
              </.button>
            </div>
          </.form>
        </.panel>

        <.panel id="create-lemming-preview">
          <:title>{dgettext("lemmings", ".title_deployment_preview")}</:title>
          <div class="flex flex-col gap-6">
            <div class="flex flex-col gap-2">
              <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_selected_tooling")}
              </p>
              <div class="flex flex-wrap gap-2">
                <.badge :for={tool <- @selected_tools} tone="accent">{tool}</.badge>
                <.badge :if={@selected_tools == []} tone="default">
                  {dgettext("lemmings", ".empty_no_tools_selected")}
                </.badge>
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_expected_outcome")}
              </p>
              <p class="text-sm text-zinc-400 leading-relaxed">
                {dgettext("lemmings", ".copy_expected_outcome")}
              </p>
            </div>
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  defp card_params(selected_city, selected_department) do
    %{}
    |> maybe_put(:city, selected_city && selected_city.id)
    |> maybe_put(:dept, selected_department && selected_department.id)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp accent_style(color), do: "background-color: #{color};"
  defp sprite_size("sm"), do: nil
  defp sprite_size("md"), do: "sprite-card--md"
end
