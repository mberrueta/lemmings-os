defmodule LemmingsOsWeb.WorldComponents do
  @moduledoc """
  Components for world, city, and department pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.MockData

  @map_cols 45
  @map_rows 26

  attr :summary, :map, required: true
  attr :cities, :list, required: true
  attr :departments, :list, required: true
  attr :lemmings, :list, required: true

  def world_page(assigns) do
    assigns = assign(assigns, :map_cities, Enum.map(assigns.cities, &to_map_city/1))

    ~H"""
    <.content_container>
      <.content_grid id="world-overview-grid" columns="two" class="content-grid--world-overview">
        <.panel id="world-map-panel">
          <:title>{dgettext("world", ".title_network_map")}</:title>
          <:subtitle>{dgettext("world", ".subtitle_network_map")}</:subtitle>
          <MapComponents.world_map cities={@map_cities} id="world-network-map" />
        </.panel>

        <.panel id="world-cities-snapshot">
          <:title>{dgettext("world", ".title_node_summary")}</:title>
          <div class="stack-list world-node-summary-list">
            <.city_card :for={city <- @cities} city={city} compact />
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  attr :cities, :list, required: true
  attr :selected_city, :map, default: nil

  def cities_page(assigns) do
    ~H"""
    <.content_container>
      <.city_detail_page :if={@selected_city} city={@selected_city} />

      <.panel :if={!@selected_city} id="cities-list-panel">
        <:title>{dgettext("world", ".title_all_cities")}</:title>
        <:subtitle>{dgettext("world", ".subtitle_all_cities")}</:subtitle>
        <div id="cities-grid" class="card-grid">
          <.city_card :for={city <- @cities} city={city} />
        </div>
      </.panel>
    </.content_container>
    """
  end

  attr :departments, :list, required: true
  attr :selected_department, :map, default: nil

  def departments_page(assigns) do
    ~H"""
    <.content_container>
      <.department_detail_page :if={@selected_department} department={@selected_department} />

      <.panel :if={!@selected_department} id="departments-list">
        <:title>{dgettext("world", ".title_departments")}</:title>
        <:subtitle>{dgettext("world", ".subtitle_departments")}</:subtitle>
        <div class="stack-list">
          <div :for={department <- @departments} class="list-row-card">
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
              <.button navigate={~p"/departments?#{%{dept: department.id}}"} variant="ghost">
                {dgettext("world", ".button_inspect")}
              </.button>
            </div>
          </div>
        </div>
      </.panel>
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
        <.badge class={@compact && "mini-card__status-badge"} tone={status_tone(@city.status)}>
          {status_label(@city.status)}
        </.badge>
      </div>
    </.link>
    """
  end

  attr :city, :map, required: true

  def city_detail_page(assigns) do
    departments = MockData.departments_for_city(assigns.city.id)

    assigns =
      assigns
      |> assign(:departments, departments)
      |> assign(:map_city, to_map_city(assigns.city))

    ~H"""
    <.panel id="city-detail-panel" tone="accent">
      <:title>{@city.name}</:title>
      <:subtitle>{@city.description}</:subtitle>
      <:actions>
        <.button navigate={~p"/cities"} variant="ghost">
          {dgettext("world", ".button_all_cities")}
        </.button>
      </:actions>
      <div class="city-detail-hero">
        <div class="city-detail-hero__visual">
          <MapComponents.city_node city={@map_city} id="city-detail-node" size={132} />
        </div>
        <div class="city-detail-hero__copy">
          <div class="inline-metrics">
            <span>{@city.region}</span>
            <span>{status_label(@city.status)}</span>
            <span>{dgettext("world", ".count_departments", count: length(@departments))}</span>
            <span>{dgettext("world", ".count_agents", count: Map.get(@map_city, :agents, 0))}</span>
          </div>
          <p class="city-detail-hero__summary">
            {dgettext("world", ".copy_city_detail_hero")}
          </p>
        </div>
      </div>
    </.panel>

    <div id="city-departments-grid" class="content-grid content-grid--two">
      <.department_room :for={department <- @departments} department={department} />
    </div>

    <.empty_state
      :if={@departments == []}
      id="city-empty-state"
      title={dgettext("world", ".empty_no_departments")}
      copy={dgettext("world", ".empty_no_departments_copy")}
    />
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
        <.button navigate={~p"/departments"} variant="ghost">
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

  defp accent_style(color), do: "background-color: #{color};"
  defp status_tone(:online), do: "success"
  defp status_tone(:degraded), do: "warning"
  defp status_tone(:offline), do: "danger"
  defp status_label(:online), do: dgettext("world", ".status_online")
  defp status_label(:degraded), do: dgettext("world", ".status_degraded")
  defp status_label(:offline), do: dgettext("world", ".status_offline")

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
