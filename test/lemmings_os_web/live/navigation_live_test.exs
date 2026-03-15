defmodule LemmingsOsWeb.NavigationLiveTest do
  use LemmingsOsWeb.ConnCase

  import Phoenix.LiveViewTest

  test "home page is the default route", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Operations Overview"
    assert html =~ "brand-wordmark__os"
    assert html =~ "sidebar-nav-home"
  end

  test "world page renders the world map", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-map-panel")
    assert has_element?(view, "#world-network-map")
  end

  test "cities page supports a selected city view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cities?city=city-alpha")

    assert has_element?(view, "#city-detail-panel")
    assert has_element?(view, "#city-detail-node")
    assert has_element?(view, "#city-departments-grid")
  end

  test "departments page supports a selected department view", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/departments?dept=eng")

    assert html =~ "department-detail-panel"
    assert html =~ "Assigned Agents"
  end

  test "lemmings page supports a selected detail panel", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/lemmings?lemming=lem-1")

    assert html =~ "lemming-detail-panel"
    assert html =~ "Fix auth bug"
  end

  test "tools, logs, settings, and create lemming pages render", %{conn: conn} do
    {:ok, _tools_view, tools_html} = live(conn, ~p"/tools")
    {:ok, _logs_view, logs_html} = live(conn, ~p"/logs")
    {:ok, _settings_view, settings_html} = live(conn, ~p"/settings")
    {:ok, _create_view, create_html} = live(conn, ~p"/lemmings/new")

    assert tools_html =~ "tools-page"
    assert logs_html =~ "logs-page"
    assert settings_html =~ "settings-form"
    assert create_html =~ "create-lemming-form"
  end
end
