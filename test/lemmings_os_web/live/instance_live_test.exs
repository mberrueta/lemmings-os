defmodule LemmingsOsWeb.InstanceLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Repo
  alias LemmingsOsWeb.InstanceComponents
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(Message)
    Repo.delete_all(LemmingInstance)
    Repo.delete_all(Lemming)
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()

    if :ets.whereis(:lemming_instance_runtime) != :undefined do
      :ets.delete_all_objects(:lemming_instance_runtime)
    end

    ActivityLog.clear()

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

  test "S01: shows the runtime session shell and waiting state", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-session-page")
    assert has_element?(view, "#instance-status-badge")
    assert has_element?(view, "#instance-session-follow-up")
    assert has_element?(view, "#instance-follow-up-request-text[disabled]")
    assert has_element?(view, "#instance-follow-up-copy", "Starting...")
    refute has_element?(view, "#instance-session-not-found")
  end

  test "S02: renders assistant metadata in the transcript bubble" do
    assistant_message = %Message{
      role: "assistant",
      content: "The outage has been contained.",
      provider: "openai",
      model: "gpt-4.1-mini",
      input_tokens: 12,
      output_tokens: 8,
      total_tokens: 20,
      usage: %{"cache_read" => 3, "reasoning_tokens" => 5},
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    html =
      render_component(&InstanceComponents.message_bubble/1, %{
        id: "assistant-message",
        message: assistant_message
      })

    assert html =~ ~s(data-role="assistant")
    assert html =~ "The outage has been contained."
    assert html =~ "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"
    assert html =~ "Input 12 tokens"
    assert html =~ "Output 8 tokens"
    assert html =~ "Total 20 tokens"
    refute html =~ "openai"
    refute html =~ "gpt-4.1-mini"
    refute html =~ "cache_read"
    refute html =~ "reasoning_tokens"
  end

  test "S03: renders a not found state for missing instances", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops-world")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{Ecto.UUID.generate()}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-session-page")
    assert has_element?(view, "#instance-session-not-found")
    assert has_element?(view, "#instance-session-not-found", "Instance not found")
    refute has_element?(view, "#instance-session-transcript")
  end

  test "S03b: respects the explicit world scope instead of forcing the default world", %{
    conn: conn
  } do
    default_world = insert(:world, name: "Default World", slug: "default-world")
    other_world = insert(:world, name: "Other World", slug: "other-world")
    city = insert(:city, world: other_world, status: "active")
    department = insert(:department, world: other_world, city: city, status: "active")

    lemming =
      insert(:lemming,
        world: other_world,
        city: city,
        department: department,
        status: "active"
      )

    {:ok, instance} =
      LemmingsOs.LemmingInstances.spawn_instance(lemming, "Investigate the outage")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: other_world.id}}")

    assert has_element?(view, "#instance-session-page")
    refute has_element?(view, "#instance-session-not-found")
    assert has_element?(view, "#instance-session-page", other_world.name)
    refute has_element?(view, "#instance-session-page", default_world.name)
  end

  test "S04: renders the reusable status banner component" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    html =
      render_component(&InstanceComponents.status_banner/1, %{
        id: "instance-status-panel",
        status: "created",
        runtime_state: %{
          status: "created",
          started_at: now,
          last_activity_at: now,
          current_item: %{content: "Investigate the outage"},
          queue_depth: 0,
          retry_count: 0,
          max_retries: 3
        },
        status_now: now
      })

    assert html =~ "instance-status-panel"
    assert html =~ "Current item"
    assert html =~ "Investigate the outage"
    assert html =~ "Starting..."
  end

  test "S04b: renders failure detail in the status banner" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    html =
      render_component(&InstanceComponents.status_banner/1, %{
        id: "instance-status-panel",
        status: "failed",
        runtime_state: %{
          status: "failed",
          started_at: now,
          last_activity_at: now,
          queue_depth: 0,
          retry_count: 3,
          max_retries: 3,
          last_error: "ollama provider returned a non-success response (HTTP 500): boom."
        },
        status_now: now
      })

    assert html =~ "Failure detail"
    assert html =~ "ollama provider returned a non-success response (HTTP 500): boom."
  end

  test "S05: submits a follow-up request on an idle instance", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-session-page")
    assert has_element?(view, "#instance-follow-up-form")
    assert has_element?(view, "#instance-follow-up-request-text")
    refute has_element?(view, "#instance-follow-up-request-text[disabled]")

    view
    |> element("#instance-follow-up-form")
    |> render_submit(%{
      "follow_up_request" => %{"request_text" => "Continue with the outage analysis"}
    })

    assert eventually_has_element?(
             view,
             "#instance-session-transcript",
             "Continue with the outage analysis"
           )

    assert eventually_has_element?(view, "#instance-follow-up-request-text[disabled]")
    assert eventually_has_element?(view, "#instance-follow-up-copy", "Waiting for capacity...")
    assert eventually_has_element?(view, "#instance-status-badge", "Queued")
  end

  test "S05b: rejects forged follow-up submits when the instance is not idle", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-follow-up-request-text[disabled]")

    view
    |> element("#instance-follow-up-form")
    |> render_submit(%{
      "follow_up_request" => %{"request_text" => "Force a second request while starting"}
    })

    assert has_element?(view, "#instance-follow-up-error", "Starting...")

    refute has_element?(
             view,
             "#instance-session-transcript-stream",
             "Force a second request while starting"
           )
  end

  test "S05c: follow-up input toggles as PubSub status changes arrive", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    refute has_element?(view, "#instance-follow-up-request-text[disabled]")
    assert has_element?(view, "#instance-follow-up-copy", "Ready for another request.")

    {:ok, _instance} = LemmingsOs.LemmingInstances.update_status(instance, "queued", %{})
    assert :ok = PubSub.broadcast_status_change(instance.id, "queued")

    assert eventually_has_element?(view, "#instance-follow-up-request-text[disabled]")
    assert eventually_has_element?(view, "#instance-follow-up-copy", "Waiting for capacity...")

    {:ok, _instance} = LemmingsOs.LemmingInstances.update_status(instance, "idle", %{})
    assert :ok = PubSub.broadcast_status_change(instance.id, "idle")

    assert eventually_lacks_element?(view, "#instance-follow-up-request-text[disabled]")

    {:ok, _instance} = LemmingsOs.LemmingInstances.update_status(instance, "failed", %{})
    assert :ok = PubSub.broadcast_status_change(instance.id, "failed")

    assert eventually_has_element?(
             view,
             "#instance-follow-up-terminal-message",
             "Instance has failed"
           )

    refute has_element?(view, "#instance-follow-up-form")
  end

  test "S05d: failed instances render a retry action and requeue when clicked", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()
    {:ok, failed_instance} = LemmingsOs.LemmingInstances.update_status(instance, "failed", %{})

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{failed_instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-retry-button", "Retry")

    view
    |> element("#instance-retry-button")
    |> render_click()

    assert eventually_has_element?(view, "#instance-status-badge", "Queued")
    assert eventually_lacks_element?(view, "#instance-retry-button")
    assert eventually_has_element?(view, "#instance-follow-up-copy", "Waiting for capacity...")
  end

  defp spawn_runtime_session do
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

    {:ok, instance} =
      LemmingsOs.LemmingInstances.spawn_instance(lemming, "Investigate the outage")

    %{world: world, lemming: lemming, instance: instance}
  end

  defp spawn_idle_runtime_session do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, instance} =
      LemmingsOs.LemmingInstances.update_status(instance, "idle", %{
        started_at: now,
        last_activity_at: now
      })

    _pid =
      start_supervised!(
        {Executor,
         [
           instance: instance,
           context_mod: LemmingsOs.LemmingInstances,
           ets_mod: EtsStore,
           dets_mod: nil,
           pool_mod: nil,
           model_mod: nil
         ]}
      )

    %{world: world, instance: instance}
  end

  defp eventually_has_element?(view, selector, text \\ nil, attempts \\ 10)

  defp eventually_has_element?(view, selector, text, 0),
    do: has_element?(view, selector, text)

  defp eventually_has_element?(view, selector, text, attempts) do
    if has_element?(view, selector, text) do
      true
    else
      Process.sleep(50)
      eventually_has_element?(view, selector, text, attempts - 1)
    end
  end

  defp eventually_lacks_element?(view, selector, attempts \\ 10)

  defp eventually_lacks_element?(_view, _selector, 0), do: true

  defp eventually_lacks_element?(view, selector, attempts) do
    if has_element?(view, selector) do
      Process.sleep(50)
      eventually_lacks_element?(view, selector, attempts - 1)
    else
      true
    end
  end
end
