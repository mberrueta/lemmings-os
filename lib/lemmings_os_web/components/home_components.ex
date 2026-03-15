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
          <:title>{dgettext("layout", ".home_title_operations_overview")}</:title>
          <:subtitle>
            {dgettext("layout", ".home_subtitle_operations_overview")}
          </:subtitle>
          <:actions>
            <.button navigate={~p"/world"} variant="secondary">
              {dgettext("layout", ".button_explore_world")}
            </.button>
          </:actions>

          <div class="hero-copy">
            <p>
              {dgettext("layout", ".home_hero_copy")}
            </p>

            <div class="quick-links">
              <.button navigate={~p"/cities"} variant="ghost">
                {dgettext("layout", ".nav_cities")}
              </.button>
              <.button navigate={~p"/departments"} variant="ghost">
                {dgettext("layout", ".nav_departments")}
              </.button>
              <.button navigate={~p"/lemmings"} variant="ghost">
                {dgettext("layout", ".nav_lemmings")}
              </.button>
              <.button navigate={~p"/tools"} variant="ghost">
                {dgettext("layout", ".nav_tools")}
              </.button>
            </div>
          </div>
        </.panel>

        <div class="page-stack">
          <.content_grid columns="two">
            <.stat_item
              label={dgettext("layout", ".stat_active_agents")}
              value={to_string(@summary.active_agents_count)}
              detail={dgettext("layout", ".stat_active_agents_detail")}
              tone="accent"
            />
            <.stat_item
              label={dgettext("layout", ".stat_online_nodes")}
              value={to_string(@summary.online_cities_count)}
              detail={dgettext("layout", ".stat_online_nodes_detail")}
              tone="info"
            />
            <.stat_item
              label={dgettext("layout", ".stat_departments")}
              value={to_string(@summary.departments_count)}
              detail={dgettext("layout", ".stat_departments_detail")}
              tone="warning"
            />
            <.stat_item
              label={dgettext("layout", ".stat_tool_registry")}
              value={to_string(@summary.tools_count)}
              detail={dgettext("layout", ".stat_tool_registry_detail")}
              tone="default"
            />
          </.content_grid>

          <.panel id="home-system-strip">
            <:title>{dgettext("layout", ".home_title_cluster_signals")}</:title>
            <div class="inline-metrics">
              <span>{dgettext("layout", ".metric_cpu")} {@summary.cpu}</span>
              <span>{dgettext("layout", ".metric_memory")} {@summary.mem}</span>
              <span>{dgettext("layout", ".metric_tick")} {@summary.tick}</span>
            </div>
          </.panel>
        </div>
      </.content_grid>

      <.content_grid id="home-middle-grid" columns="two">
        <.panel id="home-network-snapshot">
          <:title>{dgettext("layout", ".home_title_network_snapshot")}</:title>
          <:subtitle>{dgettext("layout", ".home_subtitle_network_snapshot")}</:subtitle>
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
          <:title>{dgettext("lemmings", ".title_active_lemmings")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_active_lemmings")}</:subtitle>
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
          <:title>{dgettext("world", ".title_department_queues")}</:title>
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
                <span>{dgettext("world", ".label_next")}</span>
                <span>{List.first(department.tasks_queue)}</span>
              </div>
            </.link>
          </div>
        </.panel>

        <.panel id="home-activity-feed">
          <:title>{dgettext("layout", ".home_title_recent_activity")}</:title>
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
  defp status_label(:running), do: dgettext("lemmings", ".status_running")
  defp status_label(:thinking), do: dgettext("lemmings", ".status_thinking")
  defp status_label(:error), do: dgettext("lemmings", ".status_error")
  defp status_label(:idle), do: dgettext("lemmings", ".status_idle")
  defp status_label(status), do: status |> Atom.to_string() |> String.upcase()
end
