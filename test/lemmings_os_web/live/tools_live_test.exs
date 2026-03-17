defmodule LemmingsOsWeb.ToolsLiveTest do
  use LemmingsOsWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    Application.delete_env(:lemmings_os, :tools_runtime_fetcher)
    Application.delete_env(:lemmings_os, :tools_policy_fetcher)

    on_exit(fn ->
      Application.delete_env(:lemmings_os, :tools_runtime_fetcher)
      Application.delete_env(:lemmings_os, :tools_policy_fetcher)
    end)

    :ok
  end

  test "renders unknown runtime state honestly when runtime data is unavailable", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-page")
    assert has_element?(view, "#tools-runtime-status[data-status='unknown']")
    assert has_element?(view, "#tools-policy-status[data-status='unknown']")
    assert has_element?(view, "#tools-page-status[data-status='unknown']")
    assert has_element?(view, "#tools-issues-panel")
    assert has_element?(view, "#tools-issue-tools_runtime_source_unavailable")
    assert has_element?(view, "#tools-empty-state")
    refute has_element?(view, "#tool-card-terminal")
  end

  test "renders runtime tools with deferred policy reconciliation", %{conn: conn} do
    put_tools_fetchers(policy_fetcher: fn -> :deferred end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-runtime-status[data-status='ok']")
    assert has_element?(view, "#tools-policy-status[data-status='unknown']")
    assert has_element?(view, "#tools-page-status[data-status='ok']")
    assert has_element?(view, "#tool-card-terminal")
    assert has_element?(view, "#tool-card-git")
    assert has_element?(view, "#tool-policy-status-terminal[data-status='unknown']")
    assert has_element?(view, "#tool-policy-status-git[data-status='unknown']")
  end

  test "renders unavailable runtime state explicitly when the runtime source times out", %{
    conn: conn
  } do
    put_tools_fetchers(
      runtime_fetcher: fn -> {:error, :timeout} end,
      policy_fetcher: fn -> :deferred end
    )

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-runtime-status[data-status='unavailable']")
    assert has_element?(view, "#tools-page-status[data-status='unavailable']")
    assert has_element?(view, "#tools-issue-tools_runtime_source_unavailable")
    assert has_element?(view, "#tools-empty-state")
    refute has_element?(view, "#tool-card-terminal")
  end

  test "filters runtime tools locally without reloading the page", %{conn: conn} do
    put_tools_fetchers(policy_fetcher: fn -> :deferred end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    view
    |> element("#tools-filter-form")
    |> render_change(%{"filter" => %{"query" => "git"}})

    assert has_element?(view, "#tool-card-git")
    refute has_element?(view, "#tool-card-terminal")
  end

  test "renders partial policy reconciliation explicitly", %{conn: conn} do
    put_tools_fetchers(policy_fetcher: fn -> {:ok, %{"terminal" => "ok"}} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-policy-status[data-status='degraded']")
    assert has_element?(view, "#tools-page-status[data-status='degraded']")
    assert has_element?(view, "#tools-issue-tools_policy_partial")
    assert has_element?(view, "#tool-policy-status-terminal[data-status='ok']")
    assert has_element?(view, "#tool-policy-status-git[data-status='unknown']")
  end

  defp put_tools_fetchers(opts) do
    runtime_fetcher = Keyword.get(opts, :runtime_fetcher, fn -> {:ok, runtime_tools()} end)
    policy_fetcher = Keyword.fetch!(opts, :policy_fetcher)

    Application.put_env(:lemmings_os, :tools_runtime_fetcher, runtime_fetcher)
    Application.put_env(:lemmings_os, :tools_policy_fetcher, policy_fetcher)
  end

  defp runtime_tools do
    [
      %{
        id: "terminal",
        name: "Terminal",
        description: "Execute shell commands inside the runtime boundary.",
        icon: "hero-command-line",
        category: "operations",
        risk: "high",
        usage_count: 3
      },
      %{
        id: "git",
        name: "Git",
        description: "Inspect repository history and local diffs.",
        icon: "hero-code-bracket-square",
        category: "development",
        risk: "medium",
        usage_count: 1
      }
    ]
  end
end
