defmodule LemmingsOsWeb.LemmingsLiveRuntimeTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(Message)
    Repo.delete_all(LemmingInstance)
    Repo.delete_all(Lemming)
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_default_world()
    :ok
  end

  test "S01: detail page shows spawned instances and the spawn modal", %{conn: conn} do
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
        status: "active",
        description: "Classifies inbound incidents.",
        instructions: "Review the report.\nRoute to the right team."
      )

    {:ok, instance} =
      LemmingsOs.LemmingInstances.spawn_instance(lemming, "Investigate the outage")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(view, "#lemming-instances-panel")
    assert has_element?(view, "#lemming-spawn-button")
    assert has_element?(view, "#lemming-instance-#{instance.id}")
    assert has_element?(view, "#lemming-instance-#{instance.id}", "Investigate the outage")

    view
    |> element("#lemming-spawn-button")
    |> render_click()

    assert has_element?(view, "#lemming-spawn-modal")
    assert has_element?(view, "#lemming-spawn-form")
  end

  test "S02: spawn modal stays open on invalid submission", %{conn: conn} do
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
        status: "active"
      )

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    view
    |> element("#lemming-spawn-button")
    |> render_click()

    view
    |> element("#lemming-spawn-form")
    |> render_submit(%{"spawn" => %{"request_text" => ""}})

    assert has_element?(view, "#lemming-spawn-modal")
    assert has_element?(view, "#lemming-spawn-form")
  end
end
