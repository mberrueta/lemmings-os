defmodule Mix.Tasks.Lemmings.InstanceTraceTest do
  use LemmingsOs.DataCase, async: false

  import ExUnit.CaptureIO
  import LemmingsOs.Factory

  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Repo
  alias LemmingsOsWeb.PageData.InstanceRawSnapshot

  setup do
    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    start_or_lookup!(RuntimeTableOwner)

    if :ets.whereis(:lemming_instance_runtime) != :undefined do
      :ets.delete_all_objects(:lemming_instance_runtime)
    end

    on_exit(fn ->
      if :ets.whereis(:lemming_instance_runtime) != :undefined do
        :ets.delete_all_objects(:lemming_instance_runtime)
      end
    end)

    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        name: "Trace Agent"
      )

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Use a tool then reply")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _state} =
             EtsStore.put(instance.id, %{
               department_id: instance.department_id,
               world_id: world.id,
               queue: :queue.new(),
               current_item: %{id: "current-1", content: "Use a tool then reply"},
               config_snapshot: instance.config_snapshot,
               resource_key: nil,
               retry_count: 0,
               max_retries: 3,
               context_messages: [
                 %{role: "user", content: "Use a tool then reply"},
                 %{
                   role: "assistant",
                   content:
                     "As response to your previous tool request, the runtime executed web.fetch. Tool result for web.fetch: status=ok payload={\"summary\":\"Fetched https://example.com\"}. Decide what to do next."
                 }
               ],
               last_error: nil,
               internal_error_details: nil,
               status: :idle,
               started_at: now,
               last_activity_at: now
             })

    Repo.insert!(%Message{
      lemming_instance_id: instance.id,
      world_id: world.id,
      role: "assistant",
      content: "File created successfully!",
      provider: "fake",
      model: "tool-loop-model"
    })

    Repo.insert!(%ToolExecution{
      lemming_instance_id: instance.id,
      world_id: world.id,
      tool_name: "web.fetch",
      status: "ok",
      args: %{"url" => "https://example.com"},
      result: %{url: "https://example.com", status: 200},
      error: nil,
      summary: "Fetched https://example.com",
      preview: "example preview",
      started_at: now,
      completed_at: now,
      duration_ms: 12
    })

    %{world: world, instance: instance}
  end

  test "build/1 infers world from instance id and renders markdown", %{instance: instance} do
    assert {:ok, snapshot} = InstanceRawSnapshot.build(instance_id: instance.id)

    markdown = InstanceRawSnapshot.to_markdown(snapshot)

    assert markdown =~ "# Instance Raw Context"
    assert markdown =~ "## Execution Summary"
    assert markdown =~ "Instance: #{instance.id}"
    assert markdown =~ "## Why this trace is trustworthy / partial / reconstructed"
    assert markdown =~ "## Timeline"
    assert markdown =~ "## Model Input Summary"
    assert markdown =~ "## Runtime State Summary"
    assert markdown =~ "## Why it likely succeeded / failed"
    assert markdown =~ "## Raw Details"
    assert markdown =~ "Persisted tool execution"
    assert markdown =~ "File created successfully!"
    assert markdown =~ "Source: persisted transcript/tool history only"
    assert markdown =~ "Current item: Use a tool then reply"

    {raw_details_index, _} = :binary.match(markdown, "## Raw Details")
    {raw_json_index, _} = :binary.match(markdown, "```json")

    assert raw_details_index < raw_json_index
  end

  test "mix lemmings.instance_trace prints markdown for instance id only", %{instance: instance} do
    Mix.Task.reenable("lemmings.instance_trace")

    output =
      capture_io(fn ->
        Mix.Tasks.Lemmings.InstanceTrace.run([instance.id])
      end)

    assert output =~ "# Instance Raw Context"
    assert output =~ instance.id
    assert output =~ "## Execution Summary"
    assert output =~ "## Timeline"
    assert output =~ "## Raw Details"
  end

  test "mix lemmings.instance_trace prefers live markdown export when endpoint responds", %{
    instance: instance
  } do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/lemmings/instances/#{instance.id}/raw.md", fn conn ->
      Plug.Conn.resp(conn, 200, "# Instance Raw Context\n\nlive-export-marker")
    end)

    Mix.Task.reenable("lemmings.instance_trace")

    output =
      capture_io(fn ->
        Mix.Tasks.Lemmings.InstanceTrace.run([
          instance.id,
          "--base-url",
          "http://localhost:#{bypass.port}"
        ])
      end)

    assert output =~ "live-export-marker"
  end

  test "to_markdown renders escaped newlines and empty current item clearly", %{
    world: world,
    instance: instance
  } do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    snapshot = %InstanceRawSnapshot{
      world: world,
      instance: instance,
      runtime_state: %{
        status: :failed,
        queue: :queue.new(),
        current_item: nil,
        retry_count: 2,
        max_retries: 3,
        context_messages: [
          %{role: "assistant", content: "Line one\\nLine two"}
        ],
        last_error: "Model returned invalid structured output.",
        internal_error_details: %{kind: "invalid_structured_output"},
        started_at: now,
        last_activity_at: now
      },
      model_steps: [],
      interaction_timeline: [
        %{
          id: "step-1",
          kind: :final_reply,
          title: "1. LLM -> App",
          summary: "Final reply stored in transcript",
          body: "Line one\\nLine two",
          timestamp: now,
          meta: [],
          status: "ok",
          raw_sections: []
        }
      ],
      interaction_timeline_source: :persisted_history_only,
      model_request: %{
        "request" => %{
          "messages" => [
            %{"role" => "system", "content" => "Prompt header\\nPrompt detail"},
            %{"role" => "user", "content" => "Use it"}
          ],
          "model" => "qwen3.5:latest"
        }
      },
      model_request_source: :transcript_reconstruction
    }

    markdown = InstanceRawSnapshot.to_markdown(snapshot)

    assert markdown =~ "- Current item: none"
    assert markdown =~ "> Prompt header\n> Prompt detail"
    assert markdown =~ "Preview:\n\n> Line one\n> Line two"
    refute markdown =~ "Preview:\n\n> Line one\\nLine two"
    assert markdown =~ "Likely issue: prompt ambiguity / structured-output mismatch"
    assert markdown =~ "Source: reconstructed from persisted transcript"
  end

  test "to_markdown keeps full timeline body instead of six-line preview", %{
    world: world,
    instance: instance
  } do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    snapshot = %InstanceRawSnapshot{
      world: world,
      instance: instance,
      runtime_state: %{},
      model_steps: [],
      interaction_timeline: [
        %{
          id: "step-1",
          kind: :llm_request,
          title: "1. App -> LLM",
          summary: "Long body",
          body: Enum.join(for(line <- 1..8, do: "Line #{line}"), "\n"),
          timestamp: now,
          meta: [],
          status: "ok",
          raw_sections: []
        }
      ],
      interaction_timeline_source: :live_executor_trace,
      model_request: %{},
      model_request_source: :live_executor_trace
    }

    markdown = InstanceRawSnapshot.to_markdown(snapshot)

    assert markdown =~ "> Line 1"
    assert markdown =~ "> Line 6"
    assert markdown =~ "> Line 7"
    assert markdown =~ "> Line 8"
  end

  test "to_markdown explains manager waiting on delegated child without callback context", %{
    world: world
  } do
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        name: "Manager Trace"
      )

    worker_department = insert(:department, world: world, city: city)

    worker =
      insert(:lemming,
        world: world,
        city: city,
        department: worker_department,
        status: "active",
        name: "Worker Trace"
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Delegate investigation")
    {:ok, worker_instance} = LemmingInstances.spawn_instance(worker, "Investigate outage")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    call =
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
      |> Repo.preload([:caller_lemming, :callee_lemming])

    snapshot = %InstanceRawSnapshot{
      world: world,
      instance: manager_instance,
      runtime_state: %{
        status: :idle,
        current_item: %{content: "Delegate investigation"},
        context_messages: [
          %{role: "user", content: "Delegate investigation"},
          %{
            role: "assistant",
            content:
              "Assistant requested lemming_call with arguments: {\"target\":\"worker-trace\",\"request\":\"Investigate outage\"}"
          }
        ]
      },
      model_steps: [],
      lemming_calls: [call],
      interaction_timeline: [],
      interaction_timeline_source: :live_executor_trace,
      model_request: %{},
      model_request_source: :live_executor_trace
    }

    markdown = InstanceRawSnapshot.to_markdown(snapshot)

    assert markdown =~ "## Delegation State"
    assert markdown =~ "Manager received callback context: no"
    assert markdown =~ "Manager waiting state: idle waiting on child"

    assert markdown =~
             "Manager delegated work and is still waiting. No delegated-result callback has been appended yet."
  end

  test "build/1 renders readable provider messages and lemming delegation timeline", %{
    world: world
  } do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    manager =
      insert(:manager_lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        name: "Manager Trace"
      )

    worker_department = insert(:department, world: world, city: city)

    worker =
      insert(:lemming,
        world: world,
        city: city,
        department: worker_department,
        status: "active",
        name: "Worker Trace"
      )

    {:ok, manager_instance} = LemmingInstances.spawn_instance(manager, "Delegate investigation")
    {:ok, worker_instance} = LemmingInstances.spawn_instance(worker, "Investigate outage")

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
      status: "completed",
      result_summary: "Worker found root cause.",
      started_at: now,
      completed_at: now
    })

    {:ok, pid} =
      Executor.start_link(
        instance: manager_instance,
        context_mod: nil,
        model_mod: nil,
        pubsub_mod: nil,
        dets_mod: nil,
        ets_mod: nil
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)

    request_payload = %{
      "provider" => "ollama",
      "model" => "trace-model",
      "request" => %{
        "messages" => [
          %{"role" => "system", "content" => "System line one\\nSystem line two"},
          %{"role" => "user", "content" => "Delegate investigation"},
          %{
            "role" => "assistant",
            "content" =>
              "Assistant requested lemming_call with arguments: {\"target\":\"worker-trace\",\"request\":\"Investigate outage\"}"
          }
        ]
      }
    }

    :sys.replace_state(pid, fn state ->
      Map.put(state, :model_steps, [
        %{
          step_index: 1,
          status: "ok",
          started_at: now,
          completed_at: now,
          provider: "ollama",
          model: "trace-model",
          request_payload: request_payload,
          parsed_output: %{
            "action" => "lemming_call",
            "target" => "worker-trace",
            "request" => "Investigate outage"
          },
          response_payload: %{"content" => "{\"action\":\"lemming_call\"}"},
          error: nil,
          tool_execution_id: nil
        }
      ])
    end)

    assert {:ok, snapshot} =
             InstanceRawSnapshot.build(instance_id: manager_instance.id, world: world)

    markdown = InstanceRawSnapshot.to_markdown(snapshot)

    assert markdown =~ "App -> Lemming"
    assert markdown =~ "Lemming -> App"
    assert markdown =~ "Delegate to Worker Trace"
    assert markdown =~ "Worker found root cause."
    assert markdown =~ "Message 1 - SYSTEM"
    assert markdown =~ "> System line one\n> System line two"
    refute markdown =~ "\"messages\": ["
  end

  defp ensure_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> pid
      nil -> start_supervised!({Registry, keys: :unique, name: name})
    end
  end

  defp start_or_lookup!(child) do
    case Process.whereis(child) do
      pid when is_pid(pid) -> pid
      nil -> start_supervised!(child)
    end
  end
end
