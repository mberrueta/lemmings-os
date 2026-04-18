defmodule LemmingsOsWeb.NavigationLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Mox
  import Phoenix.LiveViewTest

  alias LemmingsOs.Repo
  alias LemmingsOs.Tools.MockPolicyFetcher
  alias LemmingsOs.Tools.MockRuntimeFetcher
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds.Cache

  setup :verify_on_exit!

  setup do
    Repo.delete_all(Lemming)
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    stub(MockRuntimeFetcher, :fetch, fn -> {:error, :not_implemented} end)
    stub(MockPolicyFetcher, :fetch, fn -> :deferred end)
    :ok
  end

  test "home page is the default route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, "#brand-wordmark-os")
    assert has_element?(view, "#sidebar-nav-home")
  end

  test "world page renders the world empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-page-empty-state")
    assert has_element?(view, "#world-import-button")
  end

  test "departments page renders the city department map", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, slug: "city-alpha", name: "City Alpha")
    department = insert(:department, world: world, city: city, slug: "eng", name: "Engineering")

    {:ok, view, _html} = live(conn, ~p"/departments?city=#{city.id}")

    assert has_element?(view, "#departments-links")
    assert has_element?(view, "#department-link-#{department.id}")
    assert has_element?(view, "#departments-map-panel")
    assert has_element?(view, "#departments-city-map[phx-update='ignore']")
  end

  test "departments page supports a selected department view", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, slug: "city-alpha", name: "City Alpha")
    department = insert(:department, world: world, city: city, slug: "eng", name: "Engineering")

    {:ok, view, _html} = live(conn, ~p"/departments?city=#{city.id}&dept=#{department.id}")

    assert has_element?(view, "#department-detail-panel")
    assert has_element?(view, "#department-overview-tab-panel")
  end

  test "lemmings page links into dedicated detail view", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, slug: "city-alpha", name: "City Alpha")
    department = insert(:department, world: world, city: city, slug: "eng", name: "Engineering")
    lemming = insert(:lemming, world: world, city: city, department: department, name: "Triage")

    {:ok, view, _html} = live(conn, ~p"/lemmings")

    assert has_element?(view, "#lemming-card-#{lemming.id}")

    {:ok, detail_view, _html} = live(conn, ~p"/lemmings/#{lemming.id}")

    assert has_element?(detail_view, "#lemming-detail-panel")
    assert has_element?(detail_view, "#lemming-hero-name", "Triage")
  end

  test "tools, logs, settings, and create lemming pages render", %{conn: conn} do
    {:ok, tools_view, _tools_html} = live(conn, ~p"/tools")
    {:ok, logs_view, _logs_html} = live(conn, ~p"/logs")
    {:ok, settings_view, _settings_html} = live(conn, ~p"/settings")
    {:ok, create_view, _create_html} = live(conn, ~p"/lemmings/new")

    assert has_element?(tools_view, "#tools-page")
    assert has_element?(logs_view, "#logs-runtime-page")
    assert has_element?(settings_view, "#settings-page")
    assert has_element?(create_view, "#create-lemming-missing-context")
  end

  test "departments live view patches when a department is selected", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, slug: "city-alpha", name: "City Alpha")
    insert(:department, world: world, city: city, slug: "eng", name: "Engineering")

    {:ok, view, _html} = live(conn, ~p"/departments?city=#{city.id}")

    render_hook(view, "navigate_department", %{"department_id" => "eng"})

    assert_patch(view, ~p"/departments?city=#{city.id}&dept=eng")
  end
end
