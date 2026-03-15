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

  attr :form, :any, required: true

  def settings_page(assigns) do
    ~H"""
    <.content_container>
      <.content_grid columns="sidebar">
        <.panel id="settings-page" tone="accent">
          <:title>{dgettext("layout", ".title_settings")}</:title>
          <:subtitle>{dgettext("layout", ".subtitle_settings")}</:subtitle>
          <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
            <div class="page-stack">
              <.input field={@form[:world_name]} label={dgettext("layout", ".label_world_name")} />
              <.input
                field={@form[:max_agents]}
                type="number"
                label={dgettext("layout", ".label_max_agents")}
              />
              <.input
                field={@form[:default_model]}
                type="select"
                label={dgettext("layout", ".label_default_model")}
                options={[
                  {"gpt-4o", "gpt-4o"},
                  {"gpt-4o-mini", "gpt-4o-mini"},
                  {"claude-3.5", "claude-3.5"}
                ]}
              />
              <.input
                field={@form[:log_level]}
                type="select"
                label={dgettext("layout", ".label_log_level")}
                options={[
                  {"verbose", "verbose"},
                  {"info", "info"},
                  {"warn", "warn"},
                  {"error", "error"}
                ]}
              />
              <.button type="submit">{dgettext("layout", ".button_save_config")}</.button>
            </div>
          </.form>
        </.panel>

        <.panel id="settings-info-panel">
          <:title>{dgettext("layout", ".title_environment_notes")}</:title>
          <div class="page-stack">
            <.badge tone="warning">{dgettext("layout", ".badge_visual_mock_only")}</.badge>
            <p>
              {dgettext("layout", ".copy_settings_mock_note")}
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
