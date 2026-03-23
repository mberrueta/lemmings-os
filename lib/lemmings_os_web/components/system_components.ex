defmodule LemmingsOsWeb.SystemComponents do
  @moduledoc """
  Small components for tools and logs pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  attr :tool, :map, required: true

  def tool_runtime_card(assigns) do
    ~H"""
    <article id={"tool-card-#{@tool.id}"} class={mini_card_class()}>
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class={mini_card_title_class()}>
            <.icon name={@tool.icon || "hero-wrench-screwdriver"} class="size-5" />
            {@tool.name}
          </div>
          <p id={"tool-card-description-#{@tool.id}"} class={mini_card_meta_class()}>
            {Helpers.display_value(@tool.description,
              unavailable_label: dgettext("layout", ".tools_description_unavailable")
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

  defp mini_card_class do
    "h-full border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
  end

  defp mini_card_title_class do
    "flex items-center gap-2 text-base font-medium text-zinc-100"
  end

  defp mini_card_meta_class do
    "text-xs uppercase tracking-widest text-zinc-400"
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
        <div class="flex flex-col gap-3 font-mono">
          <div :for={item <- @activity_log} class="flex flex-wrap items-start gap-3 text-sm">
            <span class="text-xs tracking-widest text-zinc-400">[{item.time}]</span>
            <span class={["font-medium", activity_class(item.type)]}>{item.agent}</span>
            <span class="text-zinc-200">{item.action}</span>
          </div>
          <div class="flex flex-wrap items-start gap-3 text-sm">
            <span class="animate-pulse">█</span>
            <span class="text-zinc-400">{dgettext("layout", ".logs_waiting_for_events")}</span>
          </div>
        </div>
      </.panel>
    </.content_container>
    """
  end

  defp activity_class(:error), do: "text-red-400"
  defp activity_class(:system), do: "text-amber-400"
  defp activity_class(_), do: "text-emerald-400"
end
