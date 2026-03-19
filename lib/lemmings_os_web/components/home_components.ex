defmodule LemmingsOsWeb.HomeComponents do
  @moduledoc """
  Small components for the Home dashboard.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  @doc """
  Renders a trustworthy dashboard card from the Home snapshot.
  """
  attr :card, :map, required: true

  def dashboard_card(assigns) do
    assigns = assign(assigns, :display, card_display(assigns.card))

    ~H"""
    <article id={"home-card-#{@card.id}"} class="mini-card h-full" data-status={@card.status}>
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="mini-card__title">{@display.title}</div>
          <p class="mini-card__meta">{@display.subtitle}</p>
        </div>
        <.status kind={:world} value={@card.status} />
      </div>

      <div class="mt-3 grid gap-3 md:grid-cols-2">
        <.stat_item
          :for={item <- @display.items}
          label={item.label}
          value={item.value}
          detail={item[:detail]}
        />
      </div>
    </article>
    """
  end

  @doc """
  Renders a localized Home alert.
  """
  attr :alert, :map, required: true

  def dashboard_alert(assigns) do
    assigns =
      assign(assigns,
        summary: alert_summary(assigns.alert),
        detail: alert_detail(assigns.alert),
        action: alert_action(assigns.alert)
      )

    ~H"""
    <article id={"home-alert-#{@alert.code}"} class="mini-card">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <div class="mini-card__title">{@summary}</div>
          <p class="mini-card__meta">{@detail}</p>
        </div>
        <.status kind={:issue} value={@alert.severity} />
      </div>
      <p :if={@action} class="mt-3 text-sm text-[var(--muted)]">{@action}</p>
    </article>
    """
  end

  @doc """
  Renders a navigation action for the Home dashboard.
  """
  attr :action, :map, required: true

  def navigation_action(assigns) do
    ~H"""
    <.button
      id={"home-link-#{@action.id}"}
      navigate={@action.to}
      variant="ghost"
    >
      {navigation_action_label(@action.id)}
    </.button>
    """
  end

  @doc """
  Renders an intentionally omitted Home section entry.
  """
  attr :section_id, :string, required: true

  def omitted_section(assigns) do
    ~H"""
    <div id={"home-omitted-#{@section_id}"} class="list-row-card">
      <div>
        <p class="list-row-card__title">{omitted_section_title(@section_id)}</p>
        <p class="list-row-card__meta">{dgettext("layout", ".home_omitted_item_copy")}</p>
      </div>
    </div>
    """
  end

  defp card_display(%{id: "world_identity", source: "persisted_world", meta: meta}) do
    %{
      title: dgettext("layout", ".home_card_world_identity_title"),
      subtitle: source_label("persisted_world"),
      items: [
        %{
          label: dgettext("layout", ".home_card_world_name_label"),
          value:
            Helpers.display_value(meta.name,
              unavailable_label: dgettext("layout", ".home_card_world_name_missing")
            )
        },
        %{
          label: dgettext("layout", ".home_card_world_slug_label"),
          value: Helpers.display_value(meta.slug)
        }
      ]
    }
  end

  defp card_display(%{id: "bootstrap_health", source: "bootstrap_config", meta: meta}) do
    %{
      title: dgettext("layout", ".home_card_bootstrap_health_title"),
      subtitle: source_label("bootstrap_config"),
      items: [
        %{
          label: dgettext("layout", ".home_card_bootstrap_path_label"),
          value: Helpers.truncate_value(meta.path, max_length: 36)
        },
        %{
          label: dgettext("layout", ".home_card_bootstrap_issues_label"),
          value: to_string(meta.issue_count)
        }
      ]
    }
  end

  defp card_display(%{id: "runtime_health", source: "runtime_checks", meta: meta}) do
    %{
      title: dgettext("layout", ".home_card_runtime_health_title"),
      subtitle: source_label("runtime_checks"),
      items: [
        %{
          label: dgettext("layout", ".home_card_runtime_checks_label"),
          value: to_string(meta.check_count)
        },
        %{
          label: dgettext("layout", ".home_card_runtime_deferred_label"),
          value: to_string(length(meta.deferred_sources))
        }
      ]
    }
  end

  defp card_display(%{id: "tools_health", source: "tools_snapshot", meta: meta}) do
    %{
      title: dgettext("layout", ".home_card_tools_health_title"),
      subtitle: source_label("tools_snapshot"),
      items: [
        %{
          label: dgettext("layout", ".home_card_tools_count_label"),
          value: to_string(meta.tool_count)
        },
        %{
          label: dgettext("layout", ".home_card_tools_policy_mode_label"),
          value: policy_mode_label(meta.policy_mode)
        },
        %{
          label: dgettext("layout", ".home_card_tools_issues_label"),
          value: to_string(meta.issue_count)
        }
      ]
    }
  end

  defp card_display(%{id: "city_health", source: "persisted_cities", meta: meta}) do
    %{
      title: dgettext("layout", ".home_card_city_health_title"),
      subtitle: source_label("persisted_cities"),
      items: [
        %{
          label: dgettext("layout", ".home_card_city_count_label"),
          value: to_string(meta.city_count)
        }
      ]
    }
  end

  defp source_label("persisted_world"), do: dgettext("layout", ".home_source_persisted_world")
  defp source_label("bootstrap_config"), do: dgettext("layout", ".home_source_bootstrap_config")
  defp source_label("runtime_checks"), do: dgettext("layout", ".home_source_runtime_checks")
  defp source_label("tools_snapshot"), do: dgettext("layout", ".home_source_tools_snapshot")
  defp source_label("persisted_cities"), do: dgettext("layout", ".home_source_persisted_cities")
  defp source_label(_source), do: dgettext("layout", ".home_source_runtime_checks")

  defp navigation_action_label("world"), do: dgettext("layout", ".nav_world")
  defp navigation_action_label("tools"), do: dgettext("layout", ".nav_tools")
  defp navigation_action_label("logs"), do: dgettext("layout", ".nav_logs")
  defp navigation_action_label("settings"), do: dgettext("layout", ".nav_settings")
  defp navigation_action_label(_action_id), do: dgettext("layout", ".nav_world")

  defp policy_mode_label("deferred"), do: dgettext("layout", ".tools_policy_mode_deferred")
  defp policy_mode_label("partial"), do: dgettext("layout", ".tools_policy_mode_partial")
  defp policy_mode_label("known"), do: dgettext("layout", ".tools_policy_mode_known")
  defp policy_mode_label(_policy_mode), do: Helpers.display_value(nil)

  defp alert_summary(%{code: "home_world_unavailable"}),
    do: dgettext("layout", ".home_world_unavailable_summary")

  defp alert_summary(%{code: "tools_policy_partial"}),
    do: dgettext("layout", ".home_alert_tools_policy_partial_summary")

  defp alert_summary(%{code: "tools_policy_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_policy_unavailable_summary")

  defp alert_summary(%{code: "tools_runtime_source_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_runtime_source_unavailable_summary")

  defp alert_summary(alert), do: alert.summary

  defp alert_detail(%{code: "home_world_unavailable"}),
    do: dgettext("layout", ".home_world_unavailable_detail")

  defp alert_detail(%{code: "tools_policy_partial"}),
    do: dgettext("layout", ".home_alert_tools_policy_partial_detail")

  defp alert_detail(%{code: "tools_policy_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_policy_unavailable_detail")

  defp alert_detail(%{code: "tools_runtime_source_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_runtime_source_unavailable_detail")

  defp alert_detail(alert), do: alert.detail

  defp alert_action(%{code: "home_world_unavailable"}),
    do: dgettext("layout", ".home_world_unavailable_action")

  defp alert_action(%{code: "tools_policy_partial"}),
    do: dgettext("layout", ".home_alert_tools_policy_partial_action")

  defp alert_action(%{code: "tools_policy_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_policy_unavailable_action")

  defp alert_action(%{code: "tools_runtime_source_unavailable"}),
    do: dgettext("layout", ".home_alert_tools_runtime_source_unavailable_action")

  defp alert_action(alert), do: alert.action_hint

  defp omitted_section_title("hierarchy_counts"),
    do: dgettext("layout", ".home_omitted_hierarchy_counts_title")

  defp omitted_section_title("city_network"),
    do: dgettext("layout", ".home_omitted_city_network_title")

  defp omitted_section_title("department_queues"),
    do: dgettext("layout", ".home_omitted_department_queues_title")

  defp omitted_section_title("active_lemmings"),
    do: dgettext("layout", ".home_omitted_active_lemmings_title")

  defp omitted_section_title("recent_activity"),
    do: dgettext("layout", ".home_omitted_recent_activity_title")

  defp omitted_section_title("bootstrap_health"),
    do: dgettext("layout", ".home_card_bootstrap_health_title")

  defp omitted_section_title("runtime_health"),
    do: dgettext("layout", ".home_card_runtime_health_title")

  defp omitted_section_title("tools_health"),
    do: dgettext("layout", ".home_card_tools_health_title")

  defp omitted_section_title(_section_id),
    do: dgettext("layout", ".home_omitted_hierarchy_counts_title")
end
