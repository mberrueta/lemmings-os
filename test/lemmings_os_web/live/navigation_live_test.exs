defmodule LemmingsOsWeb.NavigationLiveTest do
  use LemmingsOsWeb.ConnCase

  import Mox
  import Phoenix.LiveViewTest

  alias LemmingsOs.Repo
  alias LemmingsOs.Tools.MockPolicyFetcher
  alias LemmingsOs.Tools.MockRuntimeFetcher
  alias LemmingsOs.World
  alias LemmingsOs.WorldCache

  setup :verify_on_exit!

  setup do
    Repo.delete_all(World)
    WorldCache.invalidate_all()
    stub(MockRuntimeFetcher, :fetch, fn -> {:error, :not_implemented} end)
    stub(MockPolicyFetcher, :fetch, fn -> :deferred end)
    :ok
  end

  test "home page is the default route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, ".brand-wordmark__os")
    assert has_element?(view, "#sidebar-nav-home")
  end

  test "world page renders the world empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-page-empty-state")
    assert has_element?(view, "#world-import-button")
  end

  test "cities page supports a selected city view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cities?city=city-alpha")

    assert has_element?(view, "#cities-list-panel")
    assert has_element?(view, "#city-detail-panel")
    assert has_element?(view, "#city-detail-node")
    assert has_element?(view, "#city-departments-panel")
    assert has_element?(view, "#city-active-lemmings-panel")
    refute has_element?(view, "#cities-selector")
    refute has_element?(view, "#city-map-panel")
    refute has_element?(view, "#city-network-map")
  end

  test "cities page renders the default city detail", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cities")

    assert has_element?(view, "#cities-list-panel")
    assert has_element?(view, "#city-detail-panel")
    assert has_element?(view, "#city-departments-panel")
    refute has_element?(view, "#city-network-map")
  end

  test "departments page renders the city department map", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/departments?city=city-alpha")

    assert has_element?(view, "#departments-links")
    assert has_element?(view, "#department-link-eng")
    assert has_element?(view, "#departments-selected-city-node")
    assert has_element?(view, "#departments-map-panel")
    assert has_element?(view, "#departments-city-map[phx-update='ignore']")
  end

  test "departments page supports a selected department view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/departments?city=city-alpha&dept=eng")

    assert has_element?(view, "#department-detail-panel")
    assert has_element?(view, "#department-agents-panel")
  end

  test "lemmings page supports a selected detail panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lemmings?lemming=lem-1")

    assert has_element?(view, "#lemming-detail-panel")
    assert has_element?(view, "#lemming-link-lem-1.data-table__row--active")
  end

  test "tools, logs, settings, and create lemming pages render", %{conn: conn} do
    {:ok, tools_view, _tools_html} = live(conn, ~p"/tools")
    {:ok, logs_view, _logs_html} = live(conn, ~p"/logs")
    {:ok, settings_view, _settings_html} = live(conn, ~p"/settings")
    {:ok, create_view, _create_html} = live(conn, ~p"/lemmings/new")

    assert has_element?(tools_view, "#tools-page")
    assert has_element?(logs_view, "#logs-page")
    assert has_element?(settings_view, "#settings-page")
    assert has_element?(create_view, "#create-lemming-form")
  end

  test "departments live view patches when a department is selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/departments?city=city-alpha")

    render_hook(view, "navigate_department", %{"department_id" => "eng"})

    assert_patch(view, ~p"/departments?city=city-alpha&dept=eng")
  end
end
