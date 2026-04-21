defmodule LemmingsOsWeb.ToolsLiveTest do
  use LemmingsOsWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias LemmingsOs.Tools.MockPolicyFetcher
  alias LemmingsOs.Tools.MockRuntimeFetcher

  setup :verify_on_exit!

  setup do
    stub(MockPolicyFetcher, :fetch, fn -> :deferred end)
    :ok
  end

  test "renders the fixed runtime catalog on the happy path", %{conn: conn} do
    expect(MockRuntimeFetcher, :fetch, 0, fn -> {:error, :timeout} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-page")
    assert has_element?(view, "#tools-runtime-status[data-status='ok']")
    assert has_element?(view, "#tools-policy-status[data-status='unknown']")
    assert has_element?(view, "#tools-page-status[data-status='ok']")
    assert has_element?(view, "#tools-issues-panel")
    refute has_element?(view, "#tools-empty-state")
    assert has_element?(view, "#tools-grouped-list")
    assert has_element?(view, "#tool-group-filesystem")
    assert has_element?(view, "#tool-group-web")
    assert has_element?(view, ~s([id="tool-list-item-fs.read_text_file"]))
    assert has_element?(view, ~s([id="tool-list-item-fs.write_text_file"]))
    assert has_element?(view, ~s([id="tool-list-item-web.search"]))
    assert has_element?(view, ~s([id="tool-list-item-web.fetch"]))
  end

  test "filters runtime tools locally without reloading the page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/tools")

    view
    |> element("#tools-filter-form")
    |> render_change(%{"filter" => %{"query" => "web.fetch"}})

    assert has_element?(view, ~s([id="tool-list-item-web.fetch"]))
    refute has_element?(view, ~s([id="tool-list-item-web.search"]))
    refute has_element?(view, ~s([id="tool-list-item-fs.read_text_file"]))
    refute has_element?(view, ~s([id="tool-list-item-fs.write_text_file"]))
  end

  test "renders partial policy reconciliation explicitly", %{conn: conn} do
    stub(MockPolicyFetcher, :fetch, fn -> {:ok, %{"fs.read_text_file" => "ok"}} end)

    {:ok, view, _html} = live(conn, ~p"/tools")

    assert has_element?(view, "#tools-policy-status[data-status='degraded']")
    assert has_element?(view, "#tools-page-status[data-status='degraded']")
    assert has_element?(view, "#tools-issue-tools_policy_partial")
  end
end
