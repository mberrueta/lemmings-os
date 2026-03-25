defmodule LemmingsOsWeb.CreateLemmingLiveTest do
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

  test "shows city and department selectors when no department context is provided", %{conn: conn} do
    world = insert(:world, name: "Ops World")
    city = insert(:city, world: world, name: "Alpha City")
    insert(:department, world: world, city: city, name: "Support")

    {:ok, view, _html} = live(conn, ~p"/lemmings/new")

    assert has_element?(view, "#create-lemming-missing-context")
    assert has_element?(view, "#create-lemming-scope-form")
    assert has_element?(view, "#create-lemming-selected-world", "Ops World")
    assert has_element?(view, "#create-lemming-scope-city")
    assert has_element?(view, "#create-lemming-scope-department")
    refute has_element?(view, "#create-lemming-form")
  end

  test "selecting city and department patches into create scope", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, name: "Alpha City")
    department = insert(:department, world: world, city: city, name: "Support")

    {:ok, view, _html} = live(conn, ~p"/lemmings/new")

    view
    |> element("#create-lemming-scope-form")
    |> render_change(%{"scope" => %{"city_id" => city.id, "department_id" => ""}})

    assert_patch(view, ~p"/lemmings/new?#{%{city: city.id}}")

    view
    |> element("#create-lemming-scope-form")
    |> render_change(%{"scope" => %{"city_id" => city.id, "department_id" => department.id}})

    assert_patch(view, ~p"/lemmings/new?#{%{dept: department.id}}")
  end

  test "renders the real create form in department scope", %{conn: conn} do
    world = insert(:world, name: "Ops World")
    city = insert(:city, world: world, name: "Alpha City")
    department = insert(:department, world: world, city: city, name: "Support")

    {:ok, view, _html} = live(conn, ~p"/lemmings/new?#{%{dept: department.id}}")

    assert has_element?(view, "#create-lemming-form")
    assert has_element?(view, "#create-lemming-world", "Ops World")
    assert has_element?(view, "#create-lemming-city", "Alpha City")
    assert has_element?(view, "#create-lemming-department", "Support")
    assert has_element?(view, "#lemming_name")
    assert has_element?(view, "#lemming_slug")
    assert has_element?(view, "#lemming_description")
    assert has_element?(view, "#lemming_instructions")
    assert has_element?(view, "#lemming_status")
    refute render(view) =~ "system_prompt"
    refute render(view) =~ "tool-toggle-"
  end

  test "auto-generates the slug from the name until manually overridden", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    {:ok, view, _html} = live(conn, ~p"/lemmings/new?#{%{dept: department.id}}")

    html =
      view
      |> element("#create-lemming-form")
      |> render_change(%{
        "_target" => ["lemming", "name"],
        "lemming" => %{
          "name" => "Regression Tracker",
          "slug" => "",
          "description" => "",
          "instructions" => "",
          "status" => "draft"
        }
      })

    assert html =~ ~s(value="regression-tracker")

    html =
      view
      |> element("#create-lemming-form")
      |> render_change(%{
        "_target" => ["lemming", "slug"],
        "lemming" => %{
          "name" => "Regression Tracker",
          "slug" => "custom-slug",
          "description" => "",
          "instructions" => "",
          "status" => "draft"
        }
      })

    assert html =~ ~s(value="custom-slug")

    html =
      view
      |> element("#create-lemming-form")
      |> render_change(%{
        "_target" => ["lemming", "name"],
        "lemming" => %{
          "name" => "Regression Tracker Updated",
          "slug" => "custom-slug",
          "description" => "",
          "instructions" => "",
          "status" => "draft"
        }
      })

    assert html =~ ~s(value="custom-slug")
  end

  test "creates a persisted lemming and redirects to detail", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    {:ok, view, _html} = live(conn, ~p"/lemmings/new?#{%{dept: department.id}}")

    view
    |> element("#create-lemming-form")
    |> render_submit(%{
      "lemming" => %{
        "name" => "Regression Tracker",
        "slug" => "",
        "description" => "Tracks recurring regressions.",
        "instructions" => "Look for repeating failures.",
        "status" => "draft"
      }
    })

    lemming = Repo.get_by!(Lemming, name: "Regression Tracker")

    assert_redirect(
      view,
      ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}"
    )
  end

  test "shows duplicate slug validation inline", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    insert(:lemming, world: world, city: city, department: department, slug: "regression-tracker")

    {:ok, view, _html} = live(conn, ~p"/lemmings/new?#{%{dept: department.id}}")

    html =
      view
      |> element("#create-lemming-form")
      |> render_submit(%{
        "lemming" => %{
          "name" => "Regression Tracker",
          "slug" => "regression-tracker",
          "description" => "",
          "instructions" => "",
          "status" => "draft"
        }
      })

    assert html =~ "has already been taken"
    assert has_element?(view, "#create-lemming-form")
  end
end
