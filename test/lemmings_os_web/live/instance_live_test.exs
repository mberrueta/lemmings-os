defmodule LemmingsOsWeb.InstanceLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  @moduletag capture_log: true

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.ModelRuntime.Response
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Repo
  alias LemmingsOsWeb.InstanceComponents
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  defmodule RawTraceToolLoopModelRuntime do
    def run(_config_snapshot, context_messages, current_item) do
      if Enum.any?(
           context_messages,
           &String.contains?(&1.content, "As response to your previous tool request")
         ) do
        {:ok,
         Response.new(
           action: :reply,
           reply: "File created successfully!",
           provider: "fake",
           model: "tool-loop-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "web.fetch",
           tool_args: %{"url" => "https://example.com"},
           provider: "fake",
           model: "tool-loop-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule RawTraceSuccessToolRuntime do
    def execute(_world, _instance, "web.fetch", %{"url" => "https://example.com"}) do
      {:ok,
       %{
         tool_name: "web.fetch",
         args: %{"url" => "https://example.com"},
         summary: "Fetched https://example.com",
         preview: "example preview",
         result: %{url: "https://example.com", status: 200, body: "example body"}
       }}
    end
  end

  defmodule RawTraceInvalidOutputModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      {:error,
       {:invalid_structured_output,
        %{
          provider: "fake",
          model: "broken-model",
          content: "not-json",
          raw: %{content: "not-json", provider: "fake", model: "broken-model"}
        }}}
    end
  end

  setup do
    Repo.delete_all(ToolExecution)
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
    refute html =~ "Usage"
    refute html =~ "cache_read"
    refute html =~ "reasoning_tokens"
    refute html =~ "openai"
    refute html =~ "gpt-4.1-mini"
  end

  test "S02b: omits nullable assistant metadata fields cleanly" do
    assistant_message = %Message{
      role: "assistant",
      content: "The outage has been contained.",
      provider: nil,
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      usage: nil,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    html =
      render_component(&InstanceComponents.message_bubble/1, %{
        id: "assistant-message",
        message: assistant_message
      })

    refute html =~ "openai"
    refute html =~ "gpt-4.1-mini"
    refute html =~ "Input "
    refute html =~ "Output "
    refute html =~ "Total "
    refute html =~ "Usage"
    refute html =~ "null"
  end

  test "S02c: assistant transcript bubble accepts speaker overrides" do
    assistant_message = %Message{
      role: "assistant",
      content: "Deployment investigation complete.",
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    html =
      render_component(&InstanceComponents.message_bubble/1, %{
        id: "assistant-message",
        message: assistant_message,
        speaker_name: "Research Worker",
        speaker_avatar_label: "R"
      })

    assert html =~ "RESEARCH WORKER"
    refute html =~ ">AI<"
    refute html =~ ">Assistant<"
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
          last_error: "ollama request failed (HTTP 500). Retry or inspect logs.",
          internal_error_details: %{detail: "boom"}
        },
        status_now: now
      })

    assert html =~ "Failure detail"
    assert html =~ "ollama request failed (HTTP 500). Retry or inspect logs."
    refute html =~ "boom"
  end

  test "S04c: truncates long current item copy in the status banner" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    html =
      render_component(&InstanceComponents.status_banner/1, %{
        id: "instance-status-panel",
        status: "processing",
        runtime_state: %{
          status: "processing",
          started_at: now,
          last_activity_at: now,
          current_item: %{
            content:
              "I mean from the beggning of the chat, what are all the things that we discuss ? omit the typo"
          },
          queue_depth: 0,
          retry_count: 0,
          max_retries: 3
        },
        status_now: now
      })

    assert html =~ "I mean from the beggning of ..."
    refute html =~ "what are all the things"
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

  test "S06: session page renders every runtime status state", %{conn: conn} do
    for status <- ~w(created queued processing retrying idle failed expired) do
      %{world: world, instance: instance} = spawn_runtime_session()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, _instance} =
               LemmingsOs.LemmingInstances.update_status(instance, status, %{
                 started_at: now,
                 last_activity_at: now
               })

      if status == "retrying" do
        assert {:ok, _state} =
                 EtsStore.put(instance.id, %{
                   department_id: instance.department_id,
                   retry_count: 2,
                   max_retries: 3,
                   queue: :queue.new(),
                   current_item: %{content: "Retry current item"},
                   context_messages: [],
                   last_error: "provider timeout",
                   status: :retrying,
                   started_at: now,
                   last_activity_at: now
                 })
      end

      {:ok, view, _html} =
        live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

      assert has_element?(view, "#instance-status-badge[data-status='#{status}']")

      if status == "retrying" do
        assert has_element?(view, "#instance-status-panel", "Retry attempt 2 of 3")
        assert has_element?(view, "#instance-started-at")
        assert has_element?(view, "#instance-last-activity-at")
      end
    end
  end

  test "S07: transcript renders chronological messages and parent navigation", %{conn: conn} do
    %{world: world, lemming: lemming, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    _old_assistant =
      Repo.insert!(%Message{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "assistant",
        content: "First assistant reply",
        provider: "ollama",
        model: "llama3.2",
        inserted_at: DateTime.add(now, 1, :second)
      })

    _new_user =
      Repo.insert!(%Message{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "user",
        content: "Second user request",
        inserted_at: DateTime.add(now, 2, :second)
      })

    {:ok, view, html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-parent-lemming-link")
    assert html =~ ~s(href="/lemmings/#{lemming.id}")

    assert text_position(html, "Investigate the outage") <
             text_position(html, "First assistant reply")

    assert text_position(html, "First assistant reply") <
             text_position(html, "Second user request")

    assert has_element?(view, "#instance-session-transcript-stream", "First assistant reply")
  end

  test "S07b: manager sessions render delegated work states and child links", %{conn: conn} do
    %{world: world, manager_instance: manager_instance, calls: calls} = manager_call_fixture()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{manager_instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-transcript-collaboration-strip")
    assert has_element?(view, "#instance-delegated-work-copy", "inline with the conversation")
    assert has_element?(view, "#instance-delegated-work-targets")
    assert has_element?(view, "#instance-session-transcript-stream")

    assert has_element?(
             view,
             "#card-delegation-intent-#{calls.running.id}[data-role='delegation-intent']"
           )

    assert has_element?(
             view,
             "#delegation-intent-copy-#{calls.running.id}",
             "Dispatch Manager is delegating to Running Worker"
           )

    assert has_element?(view, "#card-delegated-call-#{calls.running.id}[data-role='delegated']")
    assert has_element?(view, "#delegated-call-state-#{calls.queued.id}", "Queued")
    assert has_element?(view, "#delegated-call-state-#{calls.running.id}", "Running")
    assert has_element?(view, "#delegated-call-state-#{calls.retry_source.id}", "Retrying")
    assert has_element?(view, "#delegated-call-state-#{calls.completed.id}", "Completed")
    assert has_element?(view, "#delegated-call-state-#{calls.failed.id}", "Failed")
    assert has_element?(view, "#delegated-call-state-#{calls.dead.id}", "Dead")
    assert has_element?(view, "#delegated-call-state-#{calls.recovery.id}", "Recovery pending")
    assert has_element?(view, "#delegated-call-open-child-#{calls.running.id}")
  end

  test "S07c: manager delegated work refreshes when child input changes a call", %{conn: conn} do
    %{
      world: world,
      manager_instance: manager_instance,
      recovery_child: recovery_child,
      calls: calls
    } =
      manager_call_fixture()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{manager_instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#delegated-call-state-#{calls.recovery.id}", "Recovery pending")

    assert :ok = LemmingCalls.note_child_user_input(recovery_child, "Need more context")

    assert eventually_has_element?(
             view,
             "#delegated-call-state-copy-#{calls.recovery.id}",
             "Direct child input changed this delegated work."
           )
  end

  test "S07d: child sessions show the parent manager relationship", %{conn: conn} do
    %{world: world, child_instance: child_instance, call: call} = child_call_fixture()

    Repo.insert!(%Message{
      lemming_instance_id: child_instance.id,
      world_id: world.id,
      role: "assistant",
      content: "Deployment investigation complete."
    })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{child_instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-transcript-collaboration-strip")
    assert has_element?(view, "#instance-delegated-work-copy", "opened through a manager")
    assert has_element?(view, "#instance-delegated-open-parent")
    assert has_element?(view, "#card-manager-request-#{call.id}[data-role='manager-request']")

    assert has_element?(
             view,
             "#manager-request-copy-#{call.id}",
             "Investigate the failed deployment"
           )

    refute has_element?(view, "#card-delegated-call-#{call.id}")

    assert has_element?(
             view,
             "#instance-session-transcript-stream [data-role='assistant']",
             "Deployment investigation complete."
           )

    assert render(view) =~ "RESEARCH WORKER"

    refute has_element?(
             view,
             "#instance-session-transcript-stream [data-role='user']",
             "Investigate the failed deployment"
           )
  end

  test "S08: message broadcasts append new transcript entries without remount", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    message =
      Repo.insert!(%Message{
        lemming_instance_id: instance.id,
        world_id: world.id,
        role: "assistant",
        content: "Broadcast transcript update",
        provider: "ollama",
        model: "llama3.2"
      })

    assert :ok = PubSub.broadcast_message_appended(instance.id, message.id, message.role)

    assert eventually_has_element?(
             view,
             "#instance-session-transcript-stream",
             "Broadcast transcript update"
           )
  end

  test "S08b: historical transcript renders compact tool cards in chronological order", %{
    conn: conn
  } do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "Initial assistant reply",
      inserted_at: DateTime.add(now, 1, :second)
    })

    {:ok, tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "fs.write_text_file",
        status: "ok",
        args: %{"path" => "notes/output.md", "content" => "artifact"},
        summary: "Wrote artifact to workspace.",
        preview: "notes/output.md",
        result: %{"path" => "notes/output.md", "bytes" => 32},
        started_at: DateTime.add(now, 2, :second),
        completed_at: DateTime.add(now, 2, :second),
        duration_ms: 18
      })

    Repo.update!(
      Ecto.Changeset.change(tool_execution, inserted_at: DateTime.add(now, 2, :second))
    )

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "user",
      content: "Follow-up question",
      inserted_at: DateTime.add(now, 3, :second)
    })

    {:ok, view, html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#card-tool-execution-#{tool_execution.id}")
    assert has_element?(view, "#tool-execution-summary-#{tool_execution.id}", "notes/output.md")
    assert has_element?(view, "#tool-execution-preview-#{tool_execution.id}", "notes/output.md")
    assert has_element?(view, "#tool-execution-details-#{tool_execution.id}")

    assert has_element?(
             view,
             "#tool-execution-args-#{tool_execution.id}",
             "\"path\": \"notes/output.md\""
           )

    assert has_element?(view, "#tool-execution-result-#{tool_execution.id}", "\"bytes\": 32")

    assert html =~
             ~s(/lemmings/instances/#{instance.id}/artifacts/notes/output.md?world=#{world.id})

    assert text_position(html, "Initial assistant reply") <
             text_position(html, "notes/output.md")

    assert text_position(html, "notes/output.md") <
             text_position(html, "Follow-up question")
  end

  test "S08d: tool execution artifact link opens workspace file content", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, %{absolute_path: absolute_path}} =
      LemmingInstances.artifact_absolute_path(instance, "sample.md")

    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, "# Sample artifact\n")

    {:ok, _tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "fs.write_text_file",
        status: "ok",
        args: %{"path" => "sample.md", "content" => "# Sample artifact\n"},
        summary: "Wrote file sample.md",
        preview: "# Sample artifact",
        result: %{"path" => "sample.md", "bytes" => 18}
      })

    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["sample.md"]}?#{%{world: world.id}}"
      )

    assert response.status == 200
    assert response.resp_body == "# Sample artifact\n"
    assert get_resp_header(response, "content-type") == ["application/octet-stream"]

    assert get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="sample.md")
           ]

    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
  end

  test "S08j: workspace action copies the workspace path", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    html =
      view
      |> element("#instance-workspace-copy-button")
      |> render()

    assert html =~ ~s(type="button")
    assert html =~ ~s(data-workspace-path=)
    assert html =~ "Copy workspace path"
    assert html =~ "navigator.clipboard.writeText(this.dataset.workspacePath)"

    refute html =~ ~s(target="_blank")
    refute html =~ ~s(href=)
    refute html =~ "Open workspace"
  end

  test "S08k: clicking copy workspace path shows a copied flash", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    html =
      view
      |> element("#instance-workspace-copy-button")
      |> render_click()

    assert html =~ "Workspace path copied."
  end

  test "S08g: artifact download rejects symlink targets outside workspace", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, %{absolute_path: safe_path}} =
      LemmingInstances.artifact_absolute_path(instance, "safe.md")

    work_area = Path.dirname(safe_path)
    outside_path = Path.join(Path.dirname(work_area), "outside-artifact.md")
    File.mkdir_p!(work_area)
    File.mkdir_p!(Path.dirname(outside_path))
    File.write!(outside_path, "# Secret artifact\n")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "artifact-link.md"))

    assert {:error, :path_outside_workspace} =
             LemmingInstances.artifact_absolute_path(instance, "artifact-link.md")

    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["artifact-link.md"]}?#{%{world: world.id}}"
      )

    assert response.status == 404
    assert response.resp_body == "Artifact not found"
  end

  test "S08c: tool execution broadcasts update transcript cards without remount", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    {:ok, tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "web.fetch",
        status: "running",
        args: %{"url" => "https://example.com"},
        summary: "Fetching source page.",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    assert :ok =
             PubSub.broadcast_tool_execution_upserted(
               instance.id,
               tool_execution.id,
               tool_execution.status
             )

    assert eventually_has_element?(
             view,
             "#card-tool-execution-#{tool_execution.id}[data-status='running']"
           )

    {:ok, _updated_tool_execution} =
      LemmingTools.update_tool_execution(world, instance, tool_execution, %{
        status: "ok",
        summary: "Fetched source page.",
        preview: "https://example.com",
        result: %{"url" => "https://example.com", "status" => 200},
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        duration_ms: 45
      })

    assert :ok = PubSub.broadcast_tool_execution_upserted(instance.id, tool_execution.id, "ok")

    assert eventually_has_element?(
             view,
             "#card-tool-execution-#{tool_execution.id}[data-status='ok']"
           )

    assert eventually_has_element?(
             view,
             "#tool-execution-summary-#{tool_execution.id}",
             "Fetched source page."
           )

    assert eventually_has_element?(
             view,
             "#tool-execution-preview-#{tool_execution.id}",
             "https://example.com"
           )
  end

  test "S08e: tool execution broadcasts failed lifecycle updates without remount", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    {:ok, tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "web.fetch",
        status: "running",
        args: %{"url" => "https://example.invalid"},
        summary: "Fetching source page.",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    assert :ok =
             PubSub.broadcast_tool_execution_upserted(
               instance.id,
               tool_execution.id,
               tool_execution.status
             )

    assert eventually_has_element?(
             view,
             "#card-tool-execution-#{tool_execution.id}[data-status='running']"
           )

    {:ok, _updated_tool_execution} =
      LemmingTools.update_tool_execution(world, instance, tool_execution, %{
        status: "error",
        summary: "Failed to fetch source page.",
        error: %{
          "code" => "tool.runtime_timeout",
          "message" => "Request timed out while fetching URL"
        },
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        duration_ms: 75
      })

    assert :ok =
             PubSub.broadcast_tool_execution_upserted(
               instance.id,
               tool_execution.id,
               "error"
             )

    assert eventually_has_element?(
             view,
             "#card-tool-execution-#{tool_execution.id}[data-status='error']"
           )

    assert eventually_has_element?(
             view,
             "#tool-execution-summary-#{tool_execution.id}",
             "Failed to fetch source page."
           )

    assert eventually_has_element?(
             view,
             "#tool-execution-preview-#{tool_execution.id}",
             "Request timed out while fetching URL"
           )

    assert eventually_has_element?(
             view,
             "#tool-execution-error-#{tool_execution.id}",
             "\"code\": \"tool.runtime_timeout\""
           )
  end

  test "S08f: persisted failed tool execution details render after page reload", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, tool_execution} =
      LemmingTools.create_tool_execution(world, instance, %{
        tool_name: "web.fetch",
        status: "error",
        args: %{"url" => "https://example.invalid"},
        summary: "Unable to fetch source page.",
        error: %{
          "code" => "tool.runtime_timeout",
          "message" => "Request timed out while fetching URL"
        },
        started_at: now,
        completed_at: DateTime.add(now, 1, :second),
        duration_ms: 1000
      })

    Repo.update!(
      Ecto.Changeset.change(tool_execution, inserted_at: DateTime.add(now, 2, :second))
    )

    {:ok, _initial_view, _initial_html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    {:ok, reloaded_view, _reloaded_html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(
             reloaded_view,
             "#card-tool-execution-#{tool_execution.id}[data-status='error']"
           )

    assert has_element?(
             reloaded_view,
             "#tool-execution-summary-#{tool_execution.id}",
             "Unable to fetch source page."
           )

    assert has_element?(
             reloaded_view,
             "#tool-execution-details-#{tool_execution.id}"
           )

    assert has_element?(
             reloaded_view,
             "#tool-execution-args-#{tool_execution.id}",
             "\"url\": \"https://example.invalid\""
           )

    assert has_element?(
             reloaded_view,
             "#tool-execution-error-#{tool_execution.id}",
             "\"message\": \"Request timed out while fetching URL\""
           )
  end

  test "S09: session header shows aggregate total tokens across transcript", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "First tokenized response",
      total_tokens: 250,
      inserted_at: DateTime.add(now, 1, :second)
    })

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "Second tokenized response",
      total_tokens: 180,
      inserted_at: DateTime.add(now, 2, :second)
    })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-total-tokens", "430")
    assert has_element?(view, "#instance-total-tokens", "Across transcript")
  end

  test "S10: session header shows provider and model from the latest assistant reply", %{
    conn: conn
  } do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "First assistant reply",
      provider: "ollama",
      model: "qwen2.5:latest",
      inserted_at: DateTime.add(now, 1, :second)
    })

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "Second assistant reply",
      provider: "openai",
      model: "gpt-4.1-mini",
      inserted_at: DateTime.add(now, 2, :second)
    })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-session-page", "openai")
    assert has_element?(view, "#instance-session-page", "gpt-4.1-mini")
    refute has_element?(view, "#bubble-message-2", "openai")
  end

  test "S11: session page links to raw context view", %{conn: conn} do
    %{world: world, instance: instance} = spawn_idle_runtime_session()

    {:ok, view, html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}")

    assert has_element?(view, "#instance-raw-context-link", "Raw context")
    assert html =~ ~s(/lemmings/instances/#{instance.id}/raw?world=#{world.id})
  end

  test "S12: raw context view renders persisted runtime context and config snapshot", %{
    conn: conn
  } do
    %{world: world, instance: instance} = spawn_runtime_session()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _state} =
             EtsStore.put(instance.id, %{
               department_id: instance.department_id,
               queue: :queue.new(),
               current_item: %{id: "msg-current", content: "Create budget file"},
               retry_count: 0,
               tool_iteration_count: 2,
               max_retries: 3,
               context_messages: [
                 %{role: "user", content: "Create a budget file"},
                 %{
                   role: "assistant",
                   content:
                     "As response to your previous tool request, the runtime executed fs.write_text_file. Tool result for fs.write_text_file: status=ok payload={}. Decide what to do next."
                 }
               ],
               last_error: nil,
               internal_error_details: nil,
               status: :idle,
               started_at: now,
               last_activity_at: now
             })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}/raw?#{%{world: world.id}}")

    assert has_element?(view, "#instance-raw-page")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline-source",
             "persisted transcript/tool history only"
           )

    assert has_element?(view, "#instance-raw-model-request", "\"format\": \"json\"")
    assert has_element?(view, "#instance-raw-model-request", "fs.write_text_file")
    assert has_element?(view, "#instance-raw-model-request-source", "live executor snapshot")

    assert has_element?(
             view,
             "#instance-raw-model-request",
             "\"content\": \"Create budget file\""
           )

    assert has_element?(view, "#instance-raw-context-messages", "Create a budget file")
    assert has_element?(view, "#instance-raw-runtime-state", "\"tool_iteration_count\": 2")
    assert has_element?(view, "#instance-raw-current-item", "Create budget file")
    assert has_element?(view, "#instance-raw-config-snapshot", "\"tools_config\"")
    assert has_element?(view, "#instance-raw-session-link", "Back to session")
  end

  test "S12b: raw context view reconstructs the provider request from persisted transcript", %{
    conn: conn
  } do
    %{world: world, instance: instance} = spawn_runtime_session()

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "I can help with that."
    })

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "user",
      content: "Create a file at notes/budget_brief_example.md"
    })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}/raw?#{%{world: world.id}}")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline-source",
             "persisted transcript/tool history only"
           )

    assert has_element?(view, "#instance-raw-model-request-source", "persisted transcript")

    assert has_element?(
             view,
             "#instance-raw-model-request",
             "\"content\": \"Create a file at notes/budget_brief_example.md\""
           )

    refute has_element?(view, "#instance-raw-model-request", ":invalid_request")
  end

  test "S12c: raw context view renders live model interaction timeline", %{conn: conn} do
    %{world: world, instance: instance} = spawn_runtime_session()
    resource_key = "ollama:tool-loop-model"

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          name: "Incident Triage",
          description: "Handles incident follow-up and operator requests.",
          instructions: "Stay concise and use tools when needed.",
          model: "tool-loop-model",
          models_config: %{profiles: %{default: %{provider: "ollama", model: "tool-loop-model"}}}
        },
        context_mod: LemmingsOs.LemmingInstances,
        model_mod: RawTraceToolLoopModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: RawTraceSuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: EtsStore
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Use a tool then reply")
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert eventually_executor_status(pid, "idle")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}/raw?#{%{world: world.id}}")

    assert has_element?(view, "#instance-raw-interaction-timeline-source", "live executor trace")
    assert has_element?(view, "#instance-raw-model-request-source", "exact latest live request")
    assert has_element?(view, "#instance-raw-model-request", "\"model\": \"tool-loop-model\"")
    assert has_element?(view, "#instance-raw-interaction-timeline", "1. User -> App")
    assert has_element?(view, "#instance-raw-interaction-timeline", "2. App -> LLM")
    assert has_element?(view, "#instance-raw-interaction-timeline", "SYSTEM")
    assert has_element?(view, "#instance-raw-interaction-timeline", "Platform Runtime Context")
    assert has_element?(view, "#instance-raw-interaction-timeline", "Configured Lemming Identity")
    assert has_element?(view, "#instance-raw-interaction-timeline", "Name: Incident Triage")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "Description: Handles incident follow-up and operator requests."
           )

    assert has_element?(view, "#instance-raw-interaction-timeline", "Instructions:")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "Stay concise and use tools when needed."
           )

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "Available Tools"
           )

    assert has_element?(view, "#instance-raw-interaction-timeline", "USER")
    assert has_element?(view, "#instance-raw-interaction-timeline", "Use a tool then reply")
    assert has_element?(view, "#instance-raw-interaction-timeline", "Loop State Semantics")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "Immediate Response Instruction"
           )

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "LLM requested tool web.fetch"
           )

    assert has_element?(view, "#instance-raw-interaction-timeline", "Execute web.fetch")
    assert has_element?(view, "#instance-raw-interaction-timeline", "web.fetch completed")
    assert has_element?(view, "#instance-raw-interaction-timeline", "File created successfully!")

    GenServer.stop(pid)
  end

  test "S12d: raw context view shows malformed provider content on invalid structured output", %{
    conn: conn
  } do
    %{world: world, instance: instance} = spawn_runtime_session()

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{model: "broken-model"},
        context_mod: LemmingsOs.LemmingInstances,
        model_mod: RawTraceInvalidOutputModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: RawTraceSuccessToolRuntime,
        pool_mod: nil,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: EtsStore
      )

    assert :ok = Executor.enqueue_work(pid, "Trigger malformed output")
    Executor.admit(pid)
    assert eventually_executor_status(pid, "failed")

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{instance.id}/raw?#{%{world: world.id}}")

    assert has_element?(
             view,
             "#instance-raw-interaction-timeline",
             "LLM returned an unexpected payload"
           )

    assert has_element?(view, "#instance-raw-interaction-timeline", "not-json")

    GenServer.stop(pid)
  end

  test "S12e: raw context view renders delegation state for waiting manager", %{conn: conn} do
    unique = System.unique_integer([:positive])
    world = insert(:world, name: "Ops World #{unique}", slug: "ops-world-#{unique}")
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        name: "Manager Trace #{unique}"
      )

    worker_department = insert(:department, world: world, city: city)

    worker =
      insert(:lemming,
        world: world,
        city: city,
        department: worker_department,
        status: "active",
        name: "Worker Trace #{unique}"
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Delegate investigation")
    {:ok, worker_instance} = LemmingInstances.spawn_instance(worker, "Investigate outage")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%LemmingCall{
      world_id: world.id,
      city_id: city.id,
      caller_department_id: department.id,
      callee_department_id: worker_department.id,
      caller_lemming_id: manager.id,
      callee_lemming_id: worker.id,
      caller_instance_id: manager_instance.id,
      callee_instance_id: worker_instance.id,
      request_text: "Investigate outage",
      status: "running",
      started_at: now
    })

    assert {:ok, _state} =
             EtsStore.put(manager_instance.id, %{
               department_id: manager_instance.department_id,
               queue: :queue.new(),
               current_item: %{id: "msg-current", content: "Delegate investigation"},
               retry_count: 0,
               tool_iteration_count: 0,
               max_retries: 3,
               context_messages: [
                 %{role: "user", content: "Delegate investigation"},
                 %{
                   role: "assistant",
                   content:
                     "Assistant requested lemming_call with arguments: {\"target\":\"worker-trace\",\"request\":\"Investigate outage\"}"
                 }
               ],
               last_error: nil,
               internal_error_details: nil,
               status: :idle,
               started_at: now,
               last_activity_at: now
             })

    {:ok, view, _html} =
      live(conn, ~p"/lemmings/instances/#{manager_instance.id}/raw?#{%{world: world.id}}")

    assert has_element?(view, "#instance-raw-delegation-state", "Delegation state")
    assert has_element?(view, "#instance-raw-delegation-state", "running")
    assert has_element?(view, "#instance-raw-delegation-state", "no")
    assert has_element?(view, "#instance-raw-delegation-state", "idle waiting on child")
    assert has_element?(view, "#instance-raw-delegation-state", worker_instance.id)
  end

  defp spawn_runtime_session do
    unique = System.unique_integer([:positive])
    world = insert(:world, name: "Ops World #{unique}", slug: "ops-world-#{unique}")

    city =
      insert(:city,
        world: world,
        name: "Alpha City #{unique}",
        slug: "alpha-city-#{unique}",
        status: "active"
      )

    department =
      insert(:department,
        world: world,
        city: city,
        name: "Support #{unique}",
        slug: "support-#{unique}"
      )

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage #{unique}",
        description: "Handles incident follow-up and operator requests.",
        instructions: "Stay concise and use tools when needed.",
        slug: "incident-triage-#{unique}",
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

  defp manager_call_fixture do
    world = insert(:world, slug: "manager-world")
    city = insert(:city, world: world, slug: "manager-city", status: "active")

    manager_department =
      insert(:department,
        world: world,
        city: city,
        slug: "operations",
        name: "Operations"
      )

    worker_department =
      insert(:department,
        world: world,
        city: city,
        slug: "research",
        name: "Research"
      )

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: manager_department,
        status: "active",
        slug: "dispatch-manager",
        name: "Dispatch Manager",
        tools_config: %{allowed_tools: ["lemming.call"]}
      )

    manager_instance =
      insert(:lemming_instance,
        lemming: manager,
        world: world,
        city: city,
        department: manager_department,
        status: "idle",
        config_snapshot: %{
          tools_config: %{allowed_tools: ["lemming.call"], denied_tools: []}
        }
      )

    _local_worker =
      insert(:lemming,
        world: world,
        city: city,
        department: manager_department,
        status: "active",
        collaboration_role: "worker",
        slug: "incident-triage",
        name: "Incident Triage"
      )

    queued =
      persist_manager_call(manager_instance, worker_department, "queued", "accepted")

    running =
      persist_manager_call(manager_instance, worker_department, "running", "running")

    completed =
      persist_manager_call(manager_instance, worker_department, "completed", "completed")

    failed =
      persist_manager_call(manager_instance, worker_department, "failed", "failed")

    dead =
      persist_manager_call(manager_instance, worker_department, "dead", "failed",
        recovery_status: "expired"
      )

    recovery =
      persist_manager_call(manager_instance, worker_department, "recovery", "running",
        recovery_status: "direct_child_input"
      )

    retry_source =
      persist_manager_call(
        manager_instance,
        worker_department,
        "retry-source",
        "failed",
        recovery_status: "expired"
      )

    _retry_successor =
      persist_manager_call(
        manager_instance,
        worker_department,
        "retry-successor",
        "running",
        previous_call_id: retry_source.id
      )

    recovery_child =
      LemmingCalls.list_manager_calls(manager_instance, preload: [:callee_instance])
      |> Enum.find(&(&1.id == recovery.id))
      |> Map.fetch!(:callee_instance)

    %{
      world: world,
      manager_instance: manager_instance,
      recovery_child: recovery_child,
      calls: %{
        queued: queued,
        running: running,
        completed: completed,
        failed: failed,
        dead: dead,
        recovery: recovery,
        retry_source: retry_source
      }
    }
  end

  defp child_call_fixture do
    world = insert(:world, slug: "child-world")
    city = insert(:city, world: world, slug: "child-city", status: "active")

    manager_department =
      insert(:department,
        world: world,
        city: city,
        slug: "ops",
        name: "Ops"
      )

    worker_department =
      insert(:department,
        world: world,
        city: city,
        slug: "analysis",
        name: "Analysis"
      )

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: manager_department,
        status: "active",
        slug: "dispatch-manager",
        name: "Dispatch Manager"
      )

    manager_instance =
      insert(:lemming_instance,
        lemming: manager,
        world: world,
        city: city,
        department: manager_department,
        status: "idle"
      )

    child =
      insert(:lemming,
        world: world,
        city: city,
        department: worker_department,
        status: "active",
        collaboration_role: "worker",
        slug: "researcher",
        name: "Research Worker"
      )

    child_instance =
      insert(:lemming_instance,
        lemming: child,
        world: world,
        city: city,
        department: worker_department,
        status: "queued"
      )

    call =
      Repo.insert!(%LemmingCall{
        world_id: world.id,
        city_id: city.id,
        caller_department_id: manager_department.id,
        callee_department_id: worker_department.id,
        caller_lemming_id: manager.id,
        callee_lemming_id: child.id,
        caller_instance_id: manager_instance.id,
        callee_instance_id: child_instance.id,
        request_text: "Investigate the failed deployment",
        status: "running",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{world: world, child_instance: child_instance, call: call}
  end

  defp persist_manager_call(manager_instance, worker_department, label, status, opts \\ []) do
    child =
      insert(:lemming,
        world: manager_instance.world,
        city: manager_instance.city,
        department: worker_department,
        status: "active",
        collaboration_role: "worker",
        slug: "#{label}-worker",
        name: "#{String.capitalize(String.replace(label, "-", " "))} Worker"
      )

    child_instance =
      insert(:lemming_instance,
        lemming: child,
        world: manager_instance.world,
        city: manager_instance.city,
        department: worker_department,
        status: if(status == "completed", do: "idle", else: "queued")
      )

    Repo.insert!(%LemmingCall{
      world_id: manager_instance.world_id,
      city_id: manager_instance.city_id,
      caller_department_id: manager_instance.department_id,
      callee_department_id: worker_department.id,
      caller_lemming_id: manager_instance.lemming_id,
      callee_lemming_id: child.id,
      caller_instance_id: manager_instance.id,
      callee_instance_id: child_instance.id,
      previous_call_id: Keyword.get(opts, :previous_call_id),
      request_text: "Delegated request for #{label}",
      status: status,
      recovery_status: Keyword.get(opts, :recovery_status),
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      completed_at: completed_at(status)
    })
  end

  defp completed_at(status) when status in ["completed", "failed"],
    do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp completed_at(_status), do: nil

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

  defp eventually_executor_status(pid, expected_status, attempts \\ 20)

  defp eventually_executor_status(pid, expected_status, 0) do
    Executor.status(pid).status == expected_status
  end

  defp eventually_executor_status(pid, expected_status, attempts) do
    if Executor.status(pid).status == expected_status do
      true
    else
      Process.sleep(50)
      eventually_executor_status(pid, expected_status, attempts - 1)
    end
  end

  defp text_position(html, text) when is_binary(html) and is_binary(text) do
    case :binary.match(html, text) do
      {position, _length} -> position
      :nomatch -> nil
    end
  end
end
