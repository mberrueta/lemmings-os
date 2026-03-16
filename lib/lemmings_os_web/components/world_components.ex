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
      <.content_grid
        id="world-overview-grid"
        columns="default"
        class="lg:grid-cols-[minmax(0,5fr)_minmax(11rem,1fr)] lg:items-start"
      >
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
                    <.badge tone={lemming_status_tone(lemming.status)}>
                      {lemming_status_label(lemming.status)}
                    </.badge>
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
                <span>{status_label(@selected_city.status)}</span>
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
        <.badge class={@compact && "mini-card__status-badge"} tone={status_tone(@city.status)}>
          {status_label(@city.status)}
        </.badge>
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
            <span>{status_label(@city.status)}</span>
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

  defp accent_style(color), do: "background-color: #{color};"
  defp status_tone(:online), do: "success"
  defp status_tone(:degraded), do: "warning"
  defp status_tone(:offline), do: "danger"
  defp status_label(:online), do: dgettext("world", ".status_online")
  defp status_label(:degraded), do: dgettext("world", ".status_degraded")
  defp status_label(:offline), do: dgettext("world", ".status_offline")
  defp lemming_status_tone(:running), do: "success"
  defp lemming_status_tone(:thinking), do: "warning"
  defp lemming_status_tone(:error), do: "danger"
  defp lemming_status_tone(_), do: "default"
  defp lemming_status_label(:running), do: dgettext("lemmings", ".status_running")
  defp lemming_status_label(:thinking), do: dgettext("lemmings", ".status_thinking")
  defp lemming_status_label(:error), do: dgettext("lemmings", ".status_error")
  defp lemming_status_label(:idle), do: dgettext("lemmings", ".status_idle")

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
