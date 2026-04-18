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

    start_supervised!(
      {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.ExecutorRegistry}
    )

    start_supervised!(
      {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.SchedulerRegistry}
    )

    start_supervised!({Registry, keys: :unique, name: LemmingsOs.LemmingInstances.PoolRegistry})

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.PoolSupervisor, strategy: :one_for_one}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.ExecutorSupervisor, strategy: :one_for_one}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: LemmingsOs.LemmingInstances.SchedulerSupervisor, strategy: :one_for_one}
    )

    start_supervised!(LemmingsOs.LemmingInstances.RuntimeTableOwner)
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

  test "S03: spawn button is disabled for non-active lemmings", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")

    draft_lemming =
      insert(:lemming, world: world, city: city, department: department, status: "draft")

    archived_lemming =
      insert(:lemming, world: world, city: city, department: department, status: "archived")

    {:ok, draft_view, _html} =
      live(conn, ~p"/lemmings/#{draft_lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(draft_view, "#lemming-spawn-button[disabled]")
    refute has_element?(draft_view, "#lemming-spawn-modal")

    {:ok, archived_view, _html} =
      live(conn, ~p"/lemmings/#{archived_lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(archived_view, "#lemming-spawn-button[disabled]")
    refute has_element?(archived_view, "#lemming-spawn-modal")
  end

  test "S04: spawn modal cancel closes without creating an instance", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    view
    |> element("#lemming-spawn-button")
    |> render_click()

    assert has_element?(view, "#lemming-spawn-modal")

    view
    |> element("#lemming-spawn-cancel")
    |> render_click()

    refute has_element?(view, "#lemming-spawn-modal")
    assert LemmingsOs.LemmingInstances.list_instances(world, lemming_id: lemming.id) == []
    assert has_element?(view, "#lemming-instances-empty-list", "No active instances")
  end

  test "S05: successful spawn creates an instance and navigates to the session page", %{
    conn: conn
  } do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    view
    |> element("#lemming-spawn-button")
    |> render_click()

    assert has_element?(view, "#lemming-spawn-submit[disabled]")

    view
    |> element("#lemming-spawn-form")
    |> render_change(%{"spawn" => %{"request_text" => "Investigate runtime regressions"}})

    refute has_element?(view, "#lemming-spawn-submit[disabled]")

    view
    |> element("#lemming-spawn-form")
    |> render_submit(%{"spawn" => %{"request_text" => "Investigate runtime regressions"}})

    {redirected_to, _flash} = assert_redirect(view)
    assert redirected_to =~ "/lemmings/instances/"
    assert redirected_to =~ "world=#{world.id}"

    [_, instance_id] = Regex.run(~r|/lemmings/instances/([^?]+)|, redirected_to)

    assert {:ok, %LemmingInstance{id: ^instance_id} = instance} =
             LemmingsOs.LemmingInstances.get_instance(instance_id, world: world)

    assert instance.status == "queued"

    assert Enum.map(LemmingsOs.LemmingInstances.list_messages(instance), &{&1.role, &1.content}) ==
             [
               {"user", "Investigate runtime regressions"}
             ]
  end

  test "S06: active instance list renders empty and populated states from transcript messages", %{
    conn: conn
  } do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, empty_view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(empty_view, "#lemming-instances-empty-list", "No active instances")

    {:ok, instance} =
      LemmingsOs.LemmingInstances.spawn_instance(lemming, "Earliest request preview")

    _assistant_message =
      Repo.insert!(%Message{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "assistant",
        content: "Assistant reply",
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, populated_view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(populated_view, "#lemming-instance-#{instance.id}")

    assert has_element?(
             populated_view,
             "#lemming-instance-#{instance.id}",
             "Earliest request preview"
           )

    assert has_element?(
             populated_view,
             "#lemming-instance-#{instance.id} [data-status='created']"
           )
  end

  test "S07: recent terminal sessions are listed separately from active instances", %{conn: conn} do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city, status: "active")
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, active_instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Still running")

    {:ok, failed_instance} =
      LemmingsOs.LemmingInstances.spawn_instance(lemming, "Earlier failure")

    {:ok, expired_instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Expired run")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _} =
             LemmingsOs.LemmingInstances.update_status(failed_instance, "failed", %{
               stopped_at: now
             })

    assert {:ok, _} =
             LemmingsOs.LemmingInstances.update_status(expired_instance, "expired", %{
               stopped_at: now
             })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/#{lemming.id}?#{%{city: city.id, dept: department.id}}")

    assert has_element?(view, "#lemming-instance-#{active_instance.id}", "Still running")
    refute has_element?(view, "#lemming-instance-#{failed_instance.id}")
    refute has_element?(view, "#lemming-instance-#{expired_instance.id}")

    assert has_element?(view, "#lemming-recent-instances-list")
    assert has_element?(view, "#lemming-recent-instance-#{failed_instance.id}", "Earlier failure")
    assert has_element?(view, "#lemming-recent-instance-#{expired_instance.id}", "Expired run")

    assert has_element?(
             view,
             "#lemming-recent-instance-#{failed_instance.id} [data-status='failed']"
           )

    assert has_element?(
             view,
             "#lemming-recent-instance-#{expired_instance.id} [data-status='expired']"
           )
  end
end
