defmodule LemmingsOsWeb.LemmingsLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(Lemming)
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  test "renders filters and browse cards", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "draft",
        description: "Classifies inbound incidents.",
        instructions: "Review the report.\nRoute to the right team.",
        tools_config: %{allowed_tools: ["search"], denied_tools: ["delete"]}
      )

    {:ok, view, _html} = live(conn, ~p"/lemmings")

    assert has_element?(view, "#lemmings-filters-panel")
    assert has_element?(view, "#lemmings-selected-world", "Ops World")
    assert has_element?(view, "#lemmings-filter-city")
    assert has_element?(view, "#lemmings-filter-department")
    assert has_element?(view, "#lemmings-cards-grid")
    assert has_element?(view, "#lemming-card-#{lemming.id}")
    assert has_element?(view, "#lemming-card-#{lemming.id}", "Incident Triage")
    assert has_element?(view, "#lemming-card-#{lemming.id}", "Classifies inbound incidents.")
    refute has_element?(view, "#lemming-card-#{lemming.id}", "incident-triage")
    refute has_element?(view, "#lemming-card-#{lemming.id}", "Support")
    refute has_element?(view, "#lemming-card-#{lemming.id}", "Alpha City")
    refute has_element?(view, "#lemming-detail-panel")
  end

  test "changing filters scopes the cards", %{conn: conn} do
    world = insert(:world)
    city_a = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    city_b = insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")

    department_a =
      insert(:department, world: world, city: city_a, name: "Support", slug: "support")

    department_b =
      insert(:department, world: world, city: city_b, name: "Research", slug: "research")

    lemming_a =
      insert(:lemming,
        world: world,
        city: city_a,
        department: department_a,
        name: "Incident Triage"
      )

    lemming_b =
      insert(:lemming,
        world: world,
        city: city_b,
        department: department_b,
        name: "Release Notes"
      )

    {:ok, view, _html} = live(conn, ~p"/lemmings")

    view
    |> element("#lemmings-filters-form")
    |> render_change(%{"filters" => %{"city_id" => city_b.id, "department_id" => ""}})

    assert_patch(view, ~p"/lemmings?#{%{city: city_b.id}}")
    assert has_element?(view, "#lemming-card-#{lemming_b.id}")
    refute has_element?(view, "#lemming-card-#{lemming_a.id}")
  end

  test "card navigates to dedicated detail page", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "draft",
        description: "Classifies inbound incidents.",
        instructions: "Review the report.\nRoute to the right team.",
        tools_config: %{allowed_tools: ["search"], denied_tools: ["delete"]}
      )

    {:ok, view, _html} = live(conn, ~p"/lemmings?#{%{city: city.id, dept: department.id}}")

    view
    |> element("#lemming-card-#{lemming.id}")
    |> render_click()

    assert_redirected(view, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")
  end

  test "dedicated detail page renders workspace", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "draft",
        description: "Classifies inbound incidents.",
        instructions: "Review the report.\nRoute to the right team.",
        tools_config: %{allowed_tools: ["search"], denied_tools: ["delete"]}
      )

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(view, "#lemming-detail-header-panel")
    assert has_element?(view, "#lemming-type-avatar")
    assert has_element?(view, "#lemming-hero-name", "Incident Triage")
    assert has_element?(view, "#lemming-hero-purpose", "Classifies inbound incidents.")
    assert has_element?(view, "#lemming-hero-action-activate")
    assert has_element?(view, "#lemming-detail-panel")
    assert has_element?(view, "#lemming-detail-slug", "incident-triage")
    assert has_element?(view, "#lemming-effective-config-panel")
    assert has_element?(view, "#lemming-instances-panel")
    assert has_element?(view, "#lemming-allowed-tools", "search")
    assert has_element?(view, "#lemming-denied-tools", "delete")
    refute has_element?(view, "#lemming-action-activate")
    refute has_element?(view, "#lemming-action-archive")
  end

  test "activate succeeds when instructions are present", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "draft")

    {:ok, view, _html} = live(conn, ~p"/lemmings/#{lemming.id}")

    view
    |> element("#lemming-hero-action-activate")
    |> render_click()

    assert has_element?(view, "#flash-info")
    assert has_element?(view, "#lemming-context-status", "Active")
    refute has_element?(view, "#lemming-hero-action-activate")
    assert has_element?(view, "#lemming-hero-action-archive")
  end

  test "activate fails when instructions are blank", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "draft",
        instructions: "   "
      )

    {:ok, view, _html} = live(conn, ~p"/lemmings/#{lemming.id}")

    view
    |> element("#lemming-hero-action-activate")
    |> render_click()

    assert has_element?(view, "#flash-error")
    assert has_element?(view, "#lemming-context-status", "Draft")
  end

  test "archive succeeds for active lemmings", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, view, _html} = live(conn, ~p"/lemmings/#{lemming.id}")

    view
    |> element("#lemming-hero-action-archive")
    |> render_click()

    assert has_element?(view, "#flash-info")
    assert has_element?(view, "#lemming-context-status", "Archived")
    assert has_element?(view, "#lemming-hero-action-activate")
    refute has_element?(view, "#lemming-hero-action-archive")
  end

  test "shows not found state for invalid lemming id", %{conn: conn} do
    insert(:world)

    {:ok, view, _html} = live(conn, ~p"/lemmings/#{Ecto.UUID.generate()}")

    assert has_element?(view, "#lemming-detail-not-found")
    assert has_element?(view, "#lemming-not-found-state")
    refute has_element?(view, "#lemming-detail-panel")
  end
end
