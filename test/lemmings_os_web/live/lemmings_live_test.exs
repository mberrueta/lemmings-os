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
    assert has_element?(view, "#lemming-card-department-#{lemming.id}", "Support")
    assert has_element?(view, "#lemming-card-city-#{lemming.id}", "Alpha City")
    refute has_element?(view, "#lemming-card-#{lemming.id}", "incident-triage")
    refute has_element?(view, "#lemming-detail-panel")
  end

  test "shows world unavailable state when there is no persisted world", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lemmings")

    assert has_element?(view, "#lemmings-world-missing-state")
    refute has_element?(view, "#lemmings-filters-panel")
    refute has_element?(view, "#lemmings-cards-panel")
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

  test "shows an empty state when the selected department has no lemmings", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops-world")
    city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
    department = insert(:department, world: world, city: city, name: "Support", slug: "support")

    {:ok, view, _html} = live(conn, ~p"/lemmings?#{%{city: city.id, dept: department.id}}")

    assert has_element?(view, "#lemmings-cards-panel")
    assert has_element?(view, "#lemmings-list-empty-state")
    assert has_element?(view, "#lemmings-list-empty-state-card")
    refute has_element?(view, "#lemmings-cards-grid")
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

  test "edit tab renders a real settings form", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "draft")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
      )

    assert has_element?(view, "#lemming-settings-tab-panel")
    assert has_element?(view, "#lemming-settings-form")
    assert has_element?(view, "#lemming-settings-name")
    assert has_element?(view, "#lemming-edit-limit")
    assert has_element?(view, "#lemming-edit-runtime")
  end

  test "settings save persists mutable fields and local overrides", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "draft")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
      )

    view
    |> element("#lemming-settings-form")
    |> render_submit(%{
      "lemming" => %{
        "name" => "Regression Tracker",
        "slug" => "regression-tracker",
        "description" => "Tracks recurring regressions.",
        "instructions" => "You review failures and summarize what changed.",
        "status" => "active",
        "limits_config" => %{"max_lemmings_per_department" => "12"},
        "runtime_config" => %{"idle_ttl_seconds" => "180", "cross_city_communication" => "true"},
        "costs_config" => %{"budgets" => %{"monthly_usd" => "25.5", "daily_tokens" => "2500"}},
        "models_providers_json" => ~s({"openai":{"enabled":true}}),
        "models_profiles_json" => ~s({"fast":{"provider":"openai","model":"gpt-5"}}),
        "allowed_tools_csv" => "github, filesystem",
        "denied_tools_csv" => "shell"
      }
    })

    updated = Repo.get!(Lemming, lemming.id)

    assert updated.name == "Regression Tracker"
    assert updated.slug == "regression-tracker"
    assert updated.status == "active"
    assert updated.name == "Regression Tracker"
    assert updated.slug == "regression-tracker"
    assert updated.status == "active"
    assert has_element?(view, "#flash-info")
    assert has_element?(view, "#lemming-hero-name", "Regression Tracker")
  end

  test "validate event provides inline feedback without persisting", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "draft")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
      )

    html =
      view
      |> element("#lemming-settings-form")
      |> render_change(%{
        "lemming" => %{
          "name" => "Regression Tracker Edited",
          "slug" => lemming.slug,
          "description" => lemming.description || "",
          "instructions" => lemming.instructions || "",
          "status" => lemming.status,
          "limits_config" => %{"max_lemmings_per_department" => ""},
          "runtime_config" => %{"idle_ttl_seconds" => "", "cross_city_communication" => ""},
          "costs_config" => %{"budgets" => %{"monthly_usd" => "", "daily_tokens" => ""}},
          "models_providers_json" => "{}",
          "models_profiles_json" => "{}",
          "allowed_tools_csv" => "",
          "denied_tools_csv" => ""
        }
      })

    assert html =~ ~s(value="Regression Tracker Edited")

    unchanged = Repo.get!(Lemming, lemming.id)

    assert unchanged.name == lemming.name
    assert has_element?(view, "#lemming-settings-tab-panel")
  end

  test "settings save keeps activation guard when instructions are blank", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "draft")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
      )

    view
    |> element("#lemming-settings-form")
    |> render_submit(%{
      "lemming" => %{
        "name" => lemming.name,
        "slug" => lemming.slug,
        "description" => lemming.description || "",
        "instructions" => "   ",
        "status" => "active",
        "limits_config" => %{"max_lemmings_per_department" => ""},
        "runtime_config" => %{"idle_ttl_seconds" => "", "cross_city_communication" => ""},
        "costs_config" => %{"budgets" => %{"monthly_usd" => "", "daily_tokens" => ""}},
        "models_providers_json" => "{}",
        "models_profiles_json" => "{}",
        "allowed_tools_csv" => "",
        "denied_tools_csv" => ""
      }
    })

    unchanged = Repo.get!(Lemming, lemming.id)

    assert unchanged.status == "draft"
    assert has_element?(view, "#flash-error")
    assert has_element?(view, "#lemming-settings-tab-panel")
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

  describe "export" do
    test "export button is visible on the edit tab", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, status: "active")
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
        )

      assert has_element?(view, "#lemming-export-button")
      assert has_element?(view, "#lemming-export-hook")
    end

    test "export_lemming event triggers a download_json push event", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, status: "active")
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft"
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id, tab: "edit"}}"
        )

      view |> element("#lemming-export-button") |> render_click()

      assert_push_event(view, "download_json", %{filename: filename, content: content})
      assert filename == "lemming-code-reviewer.json"
      assert {:ok, decoded} = Jason.decode(content)
      assert decoded["name"] == "Code Reviewer"
      assert decoded["slug"] == "code-reviewer"
      assert decoded["schema_version"] == 1
    end
  end
end
