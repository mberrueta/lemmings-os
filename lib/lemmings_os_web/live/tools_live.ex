defmodule LemmingsOsWeb.ToolsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Helpers
  alias LemmingsOsWeb.PageData.ToolsPageSnapshot

  def mount(_params, _session, socket) do
    snapshot = build_snapshot()

    {:ok,
     socket
     |> assign_shell(:tools, dgettext("layout", ".page_title_tools"))
     |> assign_tools_snapshot(snapshot, "")}
  end

  def handle_event("filter_tools", %{"filter" => %{"query" => query}}, socket) do
    {:noreply, assign_tools_snapshot(socket, socket.assigns.snapshot, query)}
  end

  defp assign_tools_snapshot(socket, snapshot, query) do
    filtered_tools = filter_tools(snapshot.tools, query)

    assign(socket,
      snapshot: snapshot,
      filter: query,
      filter_form: build_filter_form(query),
      filtered_tools: filtered_tools,
      grouped_tools: group_tools(filtered_tools)
    )
  end

  defp build_snapshot do
    ToolsPageSnapshot.build(
      runtime_fetcher: LemmingsOs.Tools.DefaultRuntimeFetcher,
      policy_fetcher: policy_fetcher()
    )
  end

  defp policy_fetcher do
    Application.get_env(
      :lemmings_os,
      :tools_policy_fetcher,
      LemmingsOs.Tools.DefaultPolicyFetcher
    )
  end

  defp build_filter_form(query), do: to_form(%{"query" => query}, as: :filter)

  defp filter_tools(tools, query) when query in [nil, ""], do: tools

  defp filter_tools(tools, query) do
    normalized_query = String.downcase(String.trim(query))

    Enum.filter(tools, fn tool ->
      searchable_text =
        [tool.name, tool.id, tool.description, tool.category, tool.risk]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> String.downcase()

      String.contains?(searchable_text, normalized_query)
    end)
  end

  defp group_tools(tools) do
    tools
    |> Enum.group_by(&Helpers.display_value(&1.category, unavailable_label: "uncategorized"))
    |> Enum.sort_by(fn {category, _tools} -> category end)
    |> Enum.map(fn {category, grouped_tools} ->
      %{category: String.capitalize(category), tools: Enum.sort_by(grouped_tools, & &1.name)}
    end)
  end

  defp page_status_copy(%{issues: issues}) do
    issues
    |> length()
    |> issues_count_label()
  end

  defp policy_status_copy(%{mode: "deferred"}),
    do: dgettext("layout", ".tools_policy_copy_deferred")

  defp policy_status_copy(%{mode: "partial"}),
    do: dgettext("layout", ".tools_policy_copy_partial")

  defp policy_status_copy(%{mode: "known"}), do: dgettext("layout", ".tools_policy_copy_known")
  defp policy_status_copy(_policy), do: dgettext("layout", ".tools_policy_copy_unknown")

  defp runtime_count_label(%{status: "ok", tool_count: 0}),
    do: dgettext("layout", ".tools_runtime_count_zero")

  defp runtime_count_label(%{status: "ok", tool_count: tool_count}),
    do: dgettext("layout", ".tools_runtime_count_many", count: tool_count)

  defp runtime_count_label(%{status: "unknown"}),
    do: dgettext("layout", ".tools_runtime_count_unknown")

  defp runtime_count_label(%{status: "unavailable"}),
    do: dgettext("layout", ".tools_runtime_count_unavailable")

  defp runtime_count_label(_runtime), do: dgettext("layout", ".tools_runtime_count_unknown")

  defp empty_state_title("", "unknown"), do: dgettext("layout", ".tools_empty_runtime_title")
  defp empty_state_title("", "unavailable"), do: dgettext("layout", ".tools_empty_runtime_title")
  defp empty_state_title("", _status), do: dgettext("layout", ".tools_empty_title")
  defp empty_state_title(_query, _status), do: dgettext("layout", ".tools_empty_filtered_title")

  defp empty_state_copy("", "unknown"), do: dgettext("layout", ".tools_empty_runtime_copy")
  defp empty_state_copy("", "unavailable"), do: dgettext("layout", ".tools_empty_runtime_copy")
  defp empty_state_copy("", _status), do: dgettext("layout", ".tools_empty_copy")
  defp empty_state_copy(_query, _status), do: dgettext("layout", ".tools_empty_filtered_copy")

  defp issues_count_label(0), do: dgettext("layout", ".tools_issues_zero")
  defp issues_count_label(1), do: dgettext("layout", ".tools_issues_one")
  defp issues_count_label(count), do: dgettext("layout", ".tools_issues_many", count: count)

  defp issue_summary(%{code: "tools_runtime_source_unavailable"}),
    do: dgettext("layout", ".tools_issue_runtime_source_unavailable_summary")

  defp issue_summary(%{code: "tools_policy_partial"}),
    do: dgettext("layout", ".tools_issue_policy_partial_summary")

  defp issue_summary(%{code: "tools_policy_unavailable"}),
    do: dgettext("layout", ".tools_issue_policy_unavailable_summary")

  defp issue_summary(issue), do: issue.summary

  defp issue_detail(%{code: "tools_runtime_source_unavailable"}, _snapshot),
    do: dgettext("layout", ".tools_issue_runtime_source_unavailable_detail")

  defp issue_detail(%{code: "tools_policy_partial"}, snapshot) do
    dgettext("layout", ".tools_issue_policy_partial_detail",
      count: Enum.count(snapshot.tools, &(&1.policy.status == "unknown"))
    )
  end

  defp issue_detail(%{code: "tools_policy_unavailable"}, _snapshot),
    do: dgettext("layout", ".tools_issue_policy_unavailable_detail")

  defp issue_detail(issue, _snapshot), do: issue.detail

  defp issue_action(%{code: "tools_runtime_source_unavailable"}),
    do: dgettext("layout", ".tools_issue_runtime_source_unavailable_action")

  defp issue_action(%{code: "tools_policy_partial"}),
    do: dgettext("layout", ".tools_issue_policy_partial_action")

  defp issue_action(%{code: "tools_policy_unavailable"}),
    do: dgettext("layout", ".tools_issue_policy_unavailable_action")

  defp issue_action(issue), do: issue.action_hint || issue.source

  defp mini_card_class do
    "h-full border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
  end

  defp mini_card_title_class do
    "flex items-center gap-2 text-base font-medium text-zinc-100"
  end

  defp mini_card_meta_class do
    "text-xs uppercase tracking-widest text-zinc-400"
  end

  defp tool_list_item_copy(tool_name, risk) do
    dgettext("layout", ".tools_list_item_copy", name: tool_name, risk: risk_label(risk))
  end

  defp risk_label("high"), do: dgettext("layout", ".tools_risk_high")
  defp risk_label("medium"), do: dgettext("layout", ".tools_risk_medium")
  defp risk_label("low"), do: dgettext("layout", ".tools_risk_low")
  defp risk_label(_risk), do: dgettext("layout", ".tools_risk_unknown")
end
