defmodule LemmingsOsWeb.HomeComponents do
  @moduledoc """
  Composed sections for the home dashboard.
  """

  use LemmingsOsWeb, :html

  attr :summary, :map, required: true
  attr :cities, :list, required: true
  attr :departments, :list, required: true
  attr :lemmings, :list, required: true
  attr :activity_log, :list, required: true

  def home_page(assigns) do
    active_lemmings = Enum.filter(assigns.lemmings, &(&1.status in [:running, :thinking]))
    city_snapshot = Enum.take(assigns.cities, 3)
    department_snapshot = Enum.take(assigns.departments, 3)

    assigns =
      assigns
      |> assign(:active_lemmings, active_lemmings)
      |> assign(:city_snapshot, city_snapshot)
      |> assign(:department_snapshot, department_snapshot)

    ~H"""
    <.content_container>
      <.content_grid id="home-top-grid" columns="sidebar">
        <.panel id="home-hero" tone="accent">
          <:title>Operations Overview</:title>
          <:subtitle>
            The Phoenix app now mirrors the mock shell and uses reusable components for every major section.
          </:subtitle>
          <:actions>
            <.button navigate={~p"/world"} variant="secondary">Explore world</.button>
          </:actions>

          <div class="hero-copy">
            <p>
              This branch establishes the visual system first: terminal shell, sidebar navigation, pixel panels,
              status badges, stat tiles, and routed mock pages for every major area of the app.
            </p>

            <div class="quick-links">
              <.button navigate={~p"/cities"} variant="ghost">Cities</.button>
              <.button navigate={~p"/departments"} variant="ghost">Departments</.button>
              <.button navigate={~p"/lemmings"} variant="ghost">Lemmings</.button>
              <.button navigate={~p"/tools"} variant="ghost">Tools</.button>
            </div>
          </div>
        </.panel>

        <div class="page-stack">
          <.content_grid columns="two">
            <.stat_item
              label="Active Agents"
              value={to_string(@summary.active_agents_count)}
              detail="running + thinking"
              tone="accent"
            />
            <.stat_item
              label="Online Nodes"
              value={to_string(@summary.online_cities_count)}
              detail="healthy regions"
              tone="info"
            />
            <.stat_item
              label="Departments"
              value={to_string(@summary.departments_count)}
              detail="operational queues"
              tone="warning"
            />
            <.stat_item
              label="Tool Registry"
              value={to_string(@summary.tools_count)}
              detail="available capabilities"
              tone="default"
            />
          </.content_grid>

          <.panel id="home-system-strip">
            <:title>Cluster Signals</:title>
            <div class="inline-metrics">
              <span>CPU {@summary.cpu}</span>
              <span>Memory {@summary.mem}</span>
              <span>Tick {@summary.tick}</span>
            </div>
          </.panel>
        </div>
      </.content_grid>

      <.content_grid id="home-middle-grid" columns="two">
        <.panel id="home-network-snapshot">
          <:title>Network Snapshot</:title>
          <:subtitle>Jump directly into routed city pages.</:subtitle>
          <div class="card-grid">
            <.link
              :for={city <- @city_snapshot}
              navigate={~p"/cities?#{%{city: city.id}}"}
              class="mini-card"
            >
              <div class="mini-card__title">
                <span class="accent-dot" style={accent_style(city.accent)}></span>
                {city.name}
              </div>
              <p class="mini-card__meta">{city.region}</p>
              <p class="mini-card__meta">{city.description}</p>
            </.link>
          </div>
        </.panel>

        <.panel id="home-active-lemmings">
          <:title>Active Lemmings</:title>
          <:subtitle>Use the detailed roster view for full mock records.</:subtitle>
          <div class="stack-list">
            <.link
              :for={lemming <- Enum.take(@active_lemmings, 4)}
              navigate={~p"/lemmings?#{%{lemming: lemming.id}}"}
              class="list-row-card"
            >
              <div>
                <p class="list-row-card__title">{lemming.name}</p>
                <p class="list-row-card__meta">{lemming.role}</p>
              </div>
              <div class="list-row-card__aside">
                <.badge tone={status_tone(lemming.status)}>{status_label(lemming.status)}</.badge>
                <span>{lemming.current_task}</span>
              </div>
            </.link>
          </div>
        </.panel>
      </.content_grid>

      <.content_grid id="home-bottom-grid" columns="two">
        <.panel id="home-department-queues">
          <:title>Department Queues</:title>
          <div class="stack-list">
            <.link
              :for={department <- @department_snapshot}
              navigate={~p"/departments?#{%{dept: department.id}}"}
              class="list-row-card"
            >
              <div>
                <p class="list-row-card__title">{department.name}</p>
                <p class="list-row-card__meta">{department.description}</p>
              </div>
              <div class="list-row-card__aside">
                <span>Next</span>
                <span>{List.first(department.tasks_queue)}</span>
              </div>
            </.link>
          </div>
        </.panel>

        <.panel id="home-activity-feed">
          <:title>Recent Activity</:title>
          <div class="activity-feed">
            <div :for={item <- Enum.take(@activity_log, 6)} class="activity-feed__row">
              <span class="activity-feed__time">[{item.time}]</span>
              <span class={["activity-feed__agent", activity_class(item.type)]}>{item.agent}</span>
              <span>{item.action}</span>
            </div>
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  defp activity_class(:error), do: "activity-feed__agent--danger"
  defp activity_class(:system), do: "activity-feed__agent--warning"
  defp activity_class(_), do: "activity-feed__agent--accent"

  defp accent_style(color), do: "background-color: #{color};"
  defp status_tone(:running), do: "success"
  defp status_tone(:thinking), do: "warning"
  defp status_tone(:error), do: "danger"
  defp status_tone(_), do: "default"
  defp status_label(:running), do: "RUNNING"
  defp status_label(:thinking), do: "THINKING"
  defp status_label(:error), do: "ERROR"
  defp status_label(:idle), do: "IDLE"
end
