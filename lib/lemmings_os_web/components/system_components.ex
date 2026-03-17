defmodule LemmingsOsWeb.SystemComponents do
  @moduledoc """
  Small components for tools and logs pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  attr :tool, :map, required: true

  def tool_runtime_card(assigns) do
    ~H"""
    <article id={"tool-card-#{@tool.id}"} class="mini-card h-full">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="mini-card__title">
            <.icon name={@tool.icon || "hero-wrench-screwdriver"} class="size-5" />
            {@tool.name}
          </div>
          <p class="mini-card__meta">
            {Helpers.display_value(@tool.description,
              default: dgettext("layout", ".tools_description_unavailable")
            )}
          </p>
        </div>

        <div class="flex shrink-0 flex-col items-end gap-2">
          <.status
            id={"tool-runtime-status-#{@tool.id}"}
            kind={:world}
            value={@tool.runtime.status}
          />
          <.status
            id={"tool-policy-status-#{@tool.id}"}
            kind={:world}
            value={@tool.policy.status}
          />
        </div>
      </div>

      <div class="mt-3 grid gap-3 md:grid-cols-2">
        <.stat_item
          label={dgettext("layout", ".tools_card_category_label")}
          value={Helpers.display_value(@tool.category)}
        />
        <.stat_item
          label={dgettext("layout", ".tools_card_risk_label")}
          value={Helpers.display_value(@tool.risk)}
        />
        <.stat_item
          label={dgettext("layout", ".tools_card_usage_label")}
          value={tool_usage_value(@tool.usage_count)}
        />
        <.stat_item
          label={dgettext("layout", ".tools_card_policy_mode_label")}
          value={tool_policy_mode_label(@tool.policy.mode)}
        />
      </div>
    </article>
    """
  end

  defp tool_usage_value(nil), do: dgettext("layout", ".tools_usage_unknown")
  defp tool_usage_value(value), do: to_string(value)

  defp tool_policy_mode_label("deferred"),
    do: dgettext("layout", ".tools_policy_mode_deferred")

  defp tool_policy_mode_label("partial"),
    do: dgettext("layout", ".tools_policy_mode_partial")

  defp tool_policy_mode_label("known"),
    do: dgettext("layout", ".tools_policy_mode_known")

  defp tool_policy_mode_label(_mode), do: Helpers.display_value(nil)

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
