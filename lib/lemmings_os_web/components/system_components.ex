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
        <:title>Tools Registry</:title>
        <:subtitle>Capabilities referenced across the mock agent fleet.</:subtitle>
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
              <.badge tone="warning">{tool.agents} agents</.badge>
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
        <:title>Activity Logs</:title>
        <:subtitle>Global event timeline from the mock management environment.</:subtitle>
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
            <span>Waiting for events...</span>
          </div>
        </div>
      </.panel>
    </.content_container>
    """
  end

  attr :form, :any, required: true

  def settings_page(assigns) do
    ~H"""
    <.content_container>
      <.content_grid columns="sidebar">
        <.panel id="settings-page" tone="accent">
          <:title>Settings</:title>
          <:subtitle>Visual-only controls using the final shell primitives.</:subtitle>
          <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
            <div class="page-stack">
              <.input field={@form[:world_name]} label="World Name" />
              <.input field={@form[:max_agents]} type="number" label="Max Agents" />
              <.input
                field={@form[:default_model]}
                type="select"
                label="Default Model"
                options={[
                  {"gpt-4o", "gpt-4o"},
                  {"gpt-4o-mini", "gpt-4o-mini"},
                  {"claude-3.5", "claude-3.5"}
                ]}
              />
              <.input
                field={@form[:log_level]}
                type="select"
                label="Log Level"
                options={[
                  {"verbose", "verbose"},
                  {"info", "info"},
                  {"warn", "warn"},
                  {"error", "error"}
                ]}
              />
              <.button type="submit">Save Config</.button>
            </div>
          </.form>
        </.panel>

        <.panel id="settings-info-panel">
          <:title>Environment Notes</:title>
          <div class="page-stack">
            <.badge tone="warning">Visual mock only</.badge>
            <p>
              These controls now behave like Phoenix forms and use the shared component primitives, but they do
              not persist changes yet. The next tickets can connect them to real LiveView-backed state safely.
            </p>
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  defp activity_class(:error), do: "activity-feed__agent--danger"
  defp activity_class(:system), do: "activity-feed__agent--warning"
  defp activity_class(_), do: "activity-feed__agent--accent"
end
