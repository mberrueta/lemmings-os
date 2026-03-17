defmodule LemmingsOsWeb.SystemComponents do
  @moduledoc """
  Components for tools, logs, and settings pages.
  """

  use LemmingsOsWeb, :html

  attr :tools, :list, required: true

  def tools_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="tools-page" tone="accent">
        <:title>{dgettext("layout", ".title_tools_registry")}</:title>
        <:subtitle>{dgettext("layout", ".subtitle_tools_registry")}</:subtitle>
      </.panel>

      <.panel id="tools-grid-panel">
        <div class="card-grid">
          <div :for={tool <- @tools} class="mini-card">
            <div class="mini-card__title">
              <.icon name={tool.icon} class="size-5" />
              {tool.name}
            </div>
            <p class="mini-card__meta">{tool.description}</p>
            <div class="mini-card__footer">
              <.badge tone="warning">
                {dgettext("layout", ".badge_agents_count", count: tool.agents)}
              </.badge>
            </div>
          </div>
        </div>
      </.panel>
    </.content_container>
    """
  end

  attr :activity_log, :list, required: true

  def logs_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="logs-page" tone="accent">
        <:title>{dgettext("layout", ".title_activity_logs")}</:title>
        <:subtitle>{dgettext("layout", ".subtitle_activity_logs")}</:subtitle>
      </.panel>

      <.panel id="logs-feed-panel">
        <div class="activity-feed">
          <div :for={item <- @activity_log} class="activity-feed__row">
            <span class="activity-feed__time">[{item.time}]</span>
            <span class={["activity-feed__agent", activity_class(item.type)]}>{item.agent}</span>
            <span>{item.action}</span>
          </div>
          <div class="activity-feed__row">
            <span class="terminal-bar__cursor">█</span>
            <span>{dgettext("layout", ".logs_waiting_for_events")}</span>
          </div>
        </div>
      </.panel>
    </.content_container>
    """
  end

  defp activity_class(:error), do: "activity-feed__agent--danger"
  defp activity_class(:system), do: "activity-feed__agent--warning"
  defp activity_class(_), do: "activity-feed__agent--accent"
end
