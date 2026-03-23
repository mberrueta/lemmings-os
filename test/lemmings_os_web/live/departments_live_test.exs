defmodule LemmingsOsWeb.DepartmentsLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "index flow" do
    test "S01: defaults to the first city when no city param is present", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      world = insert(:world, name: "Ops World", slug: "ops-world", status: "ok")

      first_city =
        insert(:city,
          world: world,
          name: "Alpha City",
          slug: "alpha-city",
          status: "active",
          inserted_at: DateTime.add(now, -60, :second),
          updated_at: DateTime.add(now, -60, :second)
        )

      _second_city =
        insert(:city,
          world: world,
          name: "Beta City",
          slug: "beta-city",
          status: "disabled",
          inserted_at: now,
          updated_at: now
        )

      department =
        insert(:department, world: world, city: first_city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments")

      assert has_element?(view, "#departments-layout")
      assert has_element?(view, "#departments-city-selector-panel")
      assert has_element?(view, "#departments-city-select-form")
      assert has_element?(view, "#departments-city-select")
      assert has_element?(view, "#department-link-#{department.id}")
      assert has_element?(view, "#departments-list-panel", "Alpha City")
      assert has_element?(view, "#departments-city-map")
      refute has_element?(view, "#departments-cities-panel")
    end

    test "S02: page scopes departments to the selected city only", %{conn: conn} do
      world = insert(:world)

      city_a =
        insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      city_b = insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")

      department_a =
        insert(:department,
          world: world,
          city: city_a,
          name: "Support",
          slug: "support",
          tags: ["customer-care"]
        )

      department_b =
        insert(:department,
          world: world,
          city: city_b,
          name: "Platform",
          slug: "platform",
          tags: ["platform"]
        )

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city_b.id}")

      assert has_element?(view, "#departments-city-selector-panel")
      assert has_element?(view, "#department-link-#{department_b.id}")
      assert has_element?(view, "#departments-list-panel", "Beta City")
      assert has_element?(view, "#departments-city-map")
      refute has_element?(view, "#department-link-#{department_a.id}")
    end

    test "S03: changing the city selector patches to the chosen city", %{conn: conn} do
      world = insert(:world)

      city_a =
        insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      city_b = insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")
      insert(:department, world: world, city: city_b, name: "Platform", slug: "platform")

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city_a.id}")

      view
      |> element("#departments-city-select-form")
      |> render_change(%{"city_selector" => %{"city_id" => city_b.id}})

      assert_patch(view, ~p"/departments?#{%{city: city_b.id}}")
      assert has_element?(view, "#departments-list-panel", "Beta City")
    end

    test "S04: clicking a department enters detail route state", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          notes: "Handles escalations"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city.id}")

      view |> element("#department-link-#{department.id}") |> render_click()

      assert_patch(view, ~p"/departments?#{%{city: city.id, dept: department.id}}")
      assert has_element?(view, "#department-detail-panel")
      assert has_element?(view, "#department-overview-tab-panel")
      assert has_element?(view, "#department-detail-city", "Alpha City")
      assert has_element?(view, "#department-lifecycle-panel")
    end

    test "S05: renders an empty page state when there are no cities", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/departments")

      assert has_element?(view, "#departments-page-empty-state")
    end

    test "S06: department detail supports tab patching and settings form", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-settings") |> render_click()

      assert_patch(
        view,
        ~p"/departments?#{%{city: city.id, dept: department.id, tab: "settings"}}"
      )

      assert has_element?(view, "#department-settings-tab-panel")
      assert has_element?(view, "#department-settings-form")
      assert has_element?(view, "#department-settings-effective-panel")
      assert has_element?(view, "#department-settings-local-overrides-panel")
    end

    test "S07: department settings save updates the persisted local overrides", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 90},
          costs_config: %CostsConfig{budgets: %Budgets{daily_tokens: 1_000}}
        )

      department = insert(:department, world: world, city: city, slug: "support", name: "Support")

      {:ok, view, _html} =
        live(conn, ~p"/departments?#{%{city: city.id, dept: department.id, tab: "settings"}}")

      view
      |> element("#department-settings-form")
      |> render_submit(%{
        "department" => %{
          "limits_config" => %{"max_lemmings_per_department" => "12"},
          "runtime_config" => %{
            "idle_ttl_seconds" => "180",
            "cross_city_communication" => "true"
          },
          "costs_config" => %{"budgets" => %{"daily_tokens" => "2500"}}
        }
      })

      updated = Repo.get!(Department, department.id)

      assert updated.limits_config.max_lemmings_per_department == 12
      assert updated.runtime_config.idle_ttl_seconds == 180
      assert updated.runtime_config.cross_city_communication == true
      assert updated.costs_config.budgets.daily_tokens == 2500
      assert has_element?(view, "#department-settings-tab-panel")
    end
  end
end
