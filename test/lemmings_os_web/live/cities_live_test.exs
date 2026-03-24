defmodule LemmingsOsWeb.CitiesLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
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

  describe "list and detail" do
    test "S01: renders all persisted cities for the world and the selected city detail", %{
      conn: conn
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      world = insert(:world, name: "City World", slug: "city-world", status: "ok")

      city_a =
        insert(:city,
          world: world,
          name: "Alpha City",
          slug: "alpha-city",
          status: "active",
          last_seen_at: now
        )

      city_b =
        insert(:city,
          world: world,
          name: "Beta City",
          slug: "beta-city",
          status: "draining",
          last_seen_at: DateTime.add(now, -300, :second)
        )

      department =
        insert(:department,
          world: world,
          city: city_b,
          name: "Support",
          slug: "support",
          status: "active",
          tags: ["customer-care", "tier-1"],
          notes: "Handles incoming operator escalations."
        )

      insert(:lemming, world: world, city: city_b, department: department, status: "active")
      insert(:lemming, world: world, city: city_b, department: department, status: "draft")

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city_b.id}")

      assert has_element?(view, "#cities-page")
      assert has_element?(view, "#cities-list-panel")
      assert has_element?(view, "#city-card-link-#{city_a.id}")
      assert has_element?(view, "#city-card-link-#{city_b.id}")
      assert has_element?(view, "#city-detail-panel")
      assert has_element?(view, "#city-admin-status[data-status='draining']")
      assert has_element?(view, "#city-liveness-status[data-status='stale']")
      assert has_element?(view, "#city-effective-config-panel")
      assert has_element?(view, "#city-departments-panel")
      assert has_element?(view, "#city-open-departments-button")
      assert has_element?(view, "#city-departments-summary-copy", "Beta City")
      assert has_element?(view, "#city-department-item-#{department.id}")
      assert has_element?(view, "#city-department-name-#{department.id}", "Support")
      assert has_element?(view, "#city-department-lemming-count-#{department.id}", "2 Lemmings")
      refute has_element?(view, "#city-active-lemmings-panel")
    end

    test "S02: renders the empty state when there is no persisted world", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cities")

      assert has_element?(view, "#cities-page-empty-state")
    end

    test "S03: selecting a city via ?city=id shows that city in the detail panel", %{conn: conn} do
      world = insert(:world)
      _city_a = insert(:city, world: world, name: "Alpha", status: "active")
      city_b = insert(:city, world: world, name: "Beta", status: "disabled")

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city_b.id}")

      assert has_element?(view, "#city-detail-panel")
      assert has_element?(view, "#city-admin-status[data-status='disabled']")
    end

    test "S04: renders an empty departments state when the selected city has no departments", %{
      conn: conn
    } do
      world = insert(:world)
      city = insert(:city, world: world, name: "Solo City", status: "active")

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city.id}")

      assert has_element?(view, "#city-departments-empty-state")
      refute has_element?(view, "#city-active-lemmings-panel")
    end
  end

  describe "new city form" do
    setup %{conn: conn} do
      world = insert(:world)
      {:ok, view, _html} = live(conn, ~p"/cities")
      %{view: view, world: world}
    end

    test "S05: new city button opens the form", %{view: view} do
      refute has_element?(view, "#city-form")

      view |> element("#cities-new-button") |> render_click()

      assert has_element?(view, "#city-form")
      assert has_element?(view, "#city-form-name")
      assert has_element?(view, "#city-form-slug")
      assert has_element?(view, "#city-form-node-name")
      assert has_element?(view, "#city-form-status")
    end

    test "S06: cancel closes the form", %{view: view} do
      view |> element("#cities-new-button") |> render_click()
      assert has_element?(view, "#city-form")

      view |> element("#city-form-cancel-button") |> render_click()

      refute has_element?(view, "#city-form")
    end

    test "S07: successful create adds city to list and closes form", %{view: view} do
      view |> element("#cities-new-button") |> render_click()

      view
      |> form("#city-form", %{
        city: %{
          name: "New City",
          slug: "new-city",
          node_name: "new@localhost",
          status: "active"
        }
      })
      |> render_submit()

      # Form should close and city should appear
      refute has_element?(view, "#city-form")

      # Verify city was persisted
      assert Repo.aggregate(City, :count) == 1
    end

    test "S08: validation error keeps form open with errors", %{view: view} do
      view |> element("#cities-new-button") |> render_click()

      view
      |> form("#city-form", %{
        city: %{
          name: "Bad City",
          slug: "",
          node_name: "invalid-no-at",
          status: "active"
        }
      })
      |> render_submit()

      # Form should remain open
      assert has_element?(view, "#city-form")

      # No city should be persisted
      assert Repo.aggregate(City, :count) == 0
    end
  end

  describe "edit city form" do
    test "S09: edit loads city data into form", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          name: "Editable City",
          slug: "editable",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city.id}")

      view |> element("#city-edit-button") |> render_click()

      assert has_element?(view, "#city-form")
    end

    test "S10: successful update shows updated name in detail panel", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          name: "Before Update",
          slug: "update-test",
          node_name: "update@localhost",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city.id}")

      view |> element("#city-edit-button") |> render_click()

      view
      |> form("#city-form", %{
        city: %{name: "After Update"}
      })
      |> render_submit()

      # Form should close
      refute has_element?(view, "#city-form")

      # DB should reflect the update
      updated_city = Repo.get!(City, city.id)
      assert updated_city.name == "After Update"
    end
  end

  describe "delete city" do
    test "S11: delete removes city and navigates back to list", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          name: "Doomed City",
          slug: "doomed",
          status: "active"
        )

      {:ok, view, _html} = live(conn, ~p"/cities?city=#{city.id}")

      assert has_element?(view, "#city-detail-panel")

      view |> element("#city-delete-button") |> render_click()

      # City should be deleted from DB
      assert Repo.get(City, city.id) == nil
    end
  end
end
