defmodule LemmingsOsWeb.WorldComponents do
  @moduledoc """
  Components for world, city, and department pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.MockData

  attr :summary, :map, required: true
  attr :cities, :list, required: true
  attr :departments, :list, required: true
  attr :lemmings, :list, required: true

  def world_page(assigns) do
    city_connections =
      for {city, index} <- Enum.with_index(assigns.cities),
          other <- Enum.drop(assigns.cities, index + 1) do
        {city, other}
      end

    assigns = assign(assigns, :city_connections, city_connections)

    ~H"""
    <.content_container>
      <.panel id="world-summary-panel" tone="accent">
        <:title>World Map</:title>
        <:subtitle>Mock regions, departments, and agent density wired into the new shell.</:subtitle>
        <div class="inline-metrics">
          <span>Nodes {@summary.cities_count}</span>
          <span>Online {@summary.online_cities_count}</span>
          <span>Agents {@summary.agents_count}</span>
        </div>
      </.panel>

      <.panel id="world-map-panel">
        <:title>Network Map</:title>
        <:subtitle>Select any node to open its city page.</:subtitle>
        <div class="world-map">
          <div class="world-map__grid"></div>
          <div class="world-map__scanlines"></div>

          <svg class="world-map__connections" viewBox="0 0 100 100" preserveAspectRatio="none">
            <line
              :for={{city, other} <- @city_connections}
              x1={city.x}
              y1={city.y}
              x2={other.x}
              y2={other.y}
              vector-effect="non-scaling-stroke"
            />
          </svg>

          <.link
            :for={city <- @cities}
            id={"world-city-#{city.id}"}
            navigate={~p"/cities?#{%{city: city.id}}"}
            class="world-map__node"
            style={node_style(city)}
          >
            <div class="world-map__node-card">
              <div
                :for={department <- MockData.departments_for_city(city.id)}
                class="world-map__tower"
                style={accent_style(department.accent)}
              >
              </div>
            </div>
            <div class="world-map__node-copy">
              <span>{city.name}</span>
              <small>{city.region}</small>
            </div>
          </.link>
        </div>
      </.panel>

      <.content_grid columns="two">
        <.panel id="world-cities-snapshot">
          <:title>Node Summary</:title>
          <div class="card-grid">
            <.city_card :for={city <- @cities} city={city} />
          </div>
        </.panel>

        <.panel id="world-departments-snapshot">
          <:title>Departments by Node</:title>
          <div class="stack-list">
            <div :for={city <- @cities} class="list-row-card">
              <div>
                <p class="list-row-card__title">{city.name}</p>
                <p class="list-row-card__meta">
                  {length(MockData.departments_for_city(city.id))} departments deployed
                </p>
              </div>
              <div class="list-row-card__aside">
                <span>{length(MockData.lemmings_for_city(city.id))} agents</span>
                <.button navigate={~p"/cities?#{%{city: city.id}}"} variant="ghost">Open</.button>
              </div>
            </div>
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
        <:title>All Cities</:title>
        <:subtitle>Select a node to explore its departments.</:subtitle>
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
        <:title>Departments</:title>
        <:subtitle>Mock queues and agent rosters ready for real data later.</:subtitle>
        <div class="stack-list">
          <div :for={department <- @departments} class="list-row-card">
            <div>
              <p class="list-row-card__title">{department.name}</p>
              <p class="list-row-card__meta">{department.description}</p>
            </div>
            <div class="list-row-card__aside">
              <span>{length(MockData.lemmings_for_department(department.id))} agents</span>
              <.button navigate={~p"/departments?#{%{dept: department.id}}"} variant="ghost">
                Inspect
              </.button>
            </div>
          </div>
        </div>
      </.panel>
    </.content_container>
    """
  end

  attr :city, :map, required: true

  def city_card(assigns) do
    city_departments = MockData.departments_for_city(assigns.city.id)
    city_lemmings = MockData.lemmings_for_city(assigns.city.id)

    assigns =
      assigns
      |> assign(:city_departments, city_departments)
      |> assign(:city_lemmings, city_lemmings)

    ~H"""
    <.link navigate={~p"/cities?#{%{city: @city.id}}"} class="mini-card">
      <div class="mini-card__title">
        <span class="accent-dot" style={accent_style(@city.accent)}></span>
        {@city.name}
      </div>
      <p class="mini-card__meta">{@city.region}</p>
      <p class="mini-card__meta">{@city.description}</p>
      <div class="mini-card__footer">
        <.badge tone={status_tone(@city.status)}>{status_label(@city.status)}</.badge>
        <span>{length(@city_departments)} depts · {length(@city_lemmings)} agents</span>
      </div>
    </.link>
    """
  end

  attr :city, :map, required: true

  def city_detail_page(assigns) do
    departments = MockData.departments_for_city(assigns.city.id)

    assigns = assign(assigns, :departments, departments)

    ~H"""
    <.panel id="city-detail-panel" tone="accent">
      <:title>{@city.name}</:title>
      <:subtitle>{@city.description}</:subtitle>
      <:actions>
        <.button navigate={~p"/cities"} variant="ghost">All cities</.button>
      </:actions>
      <div class="inline-metrics">
        <span>{@city.region}</span>
        <span>{status_label(@city.status)}</span>
        <span>{length(@departments)} departments</span>
      </div>
    </.panel>

    <div id="city-departments-grid" class="content-grid content-grid--two">
      <.department_room :for={department <- @departments} department={department} />
    </div>

    <.empty_state
      :if={@departments == []}
      id="city-empty-state"
      title="No departments deployed"
      copy="This node is ready to receive its first department."
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
          Open dept
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
        Queue: {List.first(@department.tasks_queue) || "empty"}
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
        <.button navigate={~p"/departments"} variant="ghost">All departments</.button>
      </:actions>
      <div class="inline-metrics">
        <span>Node {@city.name}</span>
        <span>{length(@lemmings)} agents</span>
        <span>{length(@department.tasks_queue)} queued tasks</span>
      </div>
    </.panel>

    <.content_grid columns="two">
      <.panel id="department-agents-panel">
        <:title>Assigned Agents</:title>
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
        <:title>Task Queue</:title>
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

  defp node_style(city),
    do: "left: #{city.x}%; top: #{city.y}%; --node-accent: #{city.accent};"

  defp accent_style(color), do: "background-color: #{color};"
  defp status_tone(:online), do: "success"
  defp status_tone(:degraded), do: "warning"
  defp status_tone(:offline), do: "danger"
  defp status_label(:online), do: "ONLINE"
  defp status_label(:degraded), do: "DEGRADED"
  defp status_label(:offline), do: "OFFLINE"
end
