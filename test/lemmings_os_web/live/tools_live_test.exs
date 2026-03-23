defmodule LemmingsOsWeb.ToolsLiveTest do
  use LemmingsOsWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias LemmingsOs.Tools.MockPolicyFetcher
  alias LemmingsOs.Tools.MockRuntimeFetcher

  setup :verify_on_exit!

  setup do
    stub(MockRuntimeFetcher, :fetch, fn -> {:error, :not_implemented} end)
    stub(MockPolicyFetcher, :fetch, fn -> :deferred end)
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
    stub(MockRuntimeFetcher, :fetch, fn -> {:ok, runtime_tools()} end)

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
    stub(MockRuntimeFetcher, :fetch, fn -> {:error, :timeout} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-runtime-status[data-status='unavailable']")
    assert has_element?(view, "#tools-page-status[data-status='unavailable']")
    assert has_element?(view, "#tools-issue-tools_runtime_source_unavailable")
    assert has_element?(view, "#tools-empty-state")
    refute has_element?(view, "#tool-card-terminal")
  end

  test "filters runtime tools locally without reloading the page", %{conn: conn} do
    stub(MockRuntimeFetcher, :fetch, fn -> {:ok, runtime_tools()} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    view
    |> element("#tools-filter-form")
    |> render_change(%{"filter" => %{"query" => "git"}})

    assert has_element?(view, "#tool-card-git")
    refute has_element?(view, "#tool-card-terminal")
  end

  test "renders partial policy reconciliation explicitly", %{conn: conn} do
    stub(MockRuntimeFetcher, :fetch, fn -> {:ok, runtime_tools()} end)
    stub(MockPolicyFetcher, :fetch, fn -> {:ok, %{"terminal" => "ok"}} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-policy-status[data-status='degraded']")
    assert has_element?(view, "#tools-page-status[data-status='degraded']")
    assert has_element?(view, "#tools-issue-tools_policy_partial")
    assert has_element?(view, "#tool-policy-status-terminal[data-status='ok']")
    assert has_element?(view, "#tool-policy-status-git[data-status='unknown']")
  end

  test "renders the explicit unavailable description label for tools without description", %{
    conn: conn
  } do
    stub(MockRuntimeFetcher, :fetch, fn ->
      {:ok,
       [
         %{
           id: "terminal",
           name: "Terminal",
           description: nil,
           icon: "hero-command-line",
           category: "operations",
           risk: "high",
           usage_count: 3
         }
       ]}
    end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(
             view,
             "#tool-card-description-terminal",
             "No runtime description available."
           )
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
