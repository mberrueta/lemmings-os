defmodule LemmingsOs.LemmingInstances.ExecutorTest do
  use LemmingsOs.DataCase, async: false
  import ExUnit.CaptureLog
  require Logger

  @moduletag capture_log: true

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.ModelRuntime.Response
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Worlds.World

  defmodule FakeModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:model_run, self(), config_snapshot, context_messages, current_item})
      end

      {:ok,
       Response.new(
         action: :reply,
         reply: "processed",
         provider: "fake",
         model: Map.get(config_snapshot, :model, "fake-model"),
         raw: %{current_item: current_item, context_messages: context_messages}
       )}
    end
  end

  defmodule CrashingModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      raise "boom"
    end
  end

  defmodule HangingModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      receive do
      after
        60_000 -> :ok
      end
    end
  end

  defmodule ProviderHttpErrorModelRuntime do
    def run(_config_snapshot, _context_messages, _current_item) do
      {:error, {:provider_http_error, %{provider: "ollama", status: 500, detail: "boom"}}}
    end
  end

  defmodule InvalidStructuredOutputModelRuntime do
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

  defmodule ToolLoopModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:tool_loop_model_run, context_messages, current_item})
      end

      if Enum.any?(
           context_messages,
           &String.contains?(&1.content, "As response to your previous tool request")
         ) do
        {:ok,
         Response.new(
           action: :reply,
           reply: "final response with tool context",
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

  defmodule LemmingCallLoopModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(
          observer_pid,
          {:lemming_call_model_run, config_snapshot, context_messages, current_item}
        )
      end

      if Enum.any?(context_messages, &String.contains?(&1.content, "Lemming call result:")) do
        {:ok,
         Response.new(
           action: :reply,
           reply: "Delegated to child call.",
           provider: "fake",
           model: "lemming-call-loop-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :lemming_call,
           lemming_target: "ops-worker",
           lemming_request: "Draft child notes",
           continue_call_id: nil,
           provider: "fake",
           model: "lemming-call-loop-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule FakeLemmingCalls do
    def available_targets(_instance) do
      [
        %{
          slug: "ops-worker",
          capability: "ops/ops-worker",
          role: "worker",
          department_slug: "ops",
          description: "Drafts notes"
        }
      ]
    end

    def request_call(instance, attrs, _opts) do
      {:ok,
       %LemmingsOs.LemmingCalls.LemmingCall{
         id: Ecto.UUID.generate(),
         world_id: instance.world_id,
         city_id: instance.city_id,
         caller_instance_id: instance.id,
         callee_instance_id: Ecto.UUID.generate(),
         request_text: attrs.request,
         status: "running"
       }}
    end

    def sync_child_instance_terminal(_instance, _status, _attrs), do: :ok
  end

  defmodule FinalizationAwareModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:finalization_model_run, context_messages, current_item})
      end

      if String.contains?(current_item.content, "Finalization Phase:") do
        {:ok,
         Response.new(
           action: :reply,
           reply: "Created sample.md with mock budget data for your boss.",
           provider: "fake",
           model: "finalization-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "fs.write_text_file",
           tool_args: %{"path" => "sample.md", "content" => "# Sample budget"},
           provider: "fake",
           model: "finalization-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule RepairOnceModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:repair_model_run, context_messages, current_item})
      end

      cond do
        String.contains?(current_item.content, "Repair Notice:") ->
          {:ok,
           Response.new(
             action: :reply,
             reply: "Created sample.md successfully. It now contains mock budget data.",
             provider: "fake",
             model: "repair-model",
             raw: %{current_item: current_item, context_messages: context_messages}
           )}

        String.contains?(current_item.content, "Finalization Phase:") ->
          {:error,
           {:invalid_structured_output,
            %{
              provider: "fake",
              model: "repair-model",
              content: "",
              raw: %{content: "", provider: "fake", model: "repair-model"}
            }}}

        true ->
          {:ok,
           Response.new(
             action: :tool_call,
             tool_name: "fs.write_text_file",
             tool_args: %{"path" => "sample.md", "content" => "# Sample budget"},
             provider: "fake",
             model: "repair-model",
             raw: %{current_item: current_item, context_messages: context_messages}
           )}
      end
    end
  end

  defmodule RepairFailsModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:repair_fails_model_run, context_messages, current_item})
      end

      if String.contains?(current_item.content, "Finalization Phase:") do
        {:error,
         {:invalid_structured_output,
          %{
            provider: "fake",
            model: "repair-fails-model",
            content: "",
            raw: %{content: "", provider: "fake", model: "repair-fails-model"}
          }}}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "fs.write_text_file",
           tool_args: %{"path" => "sample.md", "content" => "# Sample budget"},
           provider: "fake",
           model: "repair-fails-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule MoreWorkFinalizationModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:more_work_model_run, context_messages, current_item})
      end

      if String.contains?(current_item.content, "Finalization Phase:") do
        {:ok,
         Response.new(
           action: :reply,
           reply:
             "sample.md is ready. The next step is to review the figures and adjust them to your real budget before presenting.",
           provider: "fake",
           model: "more-work-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "fs.write_text_file",
           tool_args: %{"path" => "sample.md", "content" => "# Sample budget"},
           provider: "fake",
           model: "more-work-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule ToolLoopErrorModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:tool_loop_error_model_run, context_messages, current_item})
      end

      if Enum.any?(context_messages, &String.contains?(&1.content, "status=error")) do
        {:ok,
         Response.new(
           action: :reply,
           reply: "final response after tool error",
           provider: "fake",
           model: "tool-loop-error-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "web.fetch",
           tool_args: %{"url" => "https://broken.example.invalid"},
           provider: "fake",
           model: "tool-loop-error-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule UnsupportedToolLoopModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:unsupported_tool_model_run, context_messages, current_item})
      end

      if Enum.any?(
           context_messages,
           &String.contains?(&1.content, "\"code\":\"tool.unsupported\"")
         ) do
        {:ok,
         Response.new(
           action: :reply,
           reply: "final response after unsupported tool",
           provider: "fake",
           model: "unsupported-tool-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      else
        {:ok,
         Response.new(
           action: :tool_call,
           tool_name: "exec.run",
           tool_args: %{},
           provider: "fake",
           model: "unsupported-tool-model",
           raw: %{current_item: current_item, context_messages: context_messages}
         )}
      end
    end
  end

  defmodule SuccessToolRuntime do
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

    def execute(_world, _instance, "fs.write_text_file", %{
          "path" => "sample.md",
          "content" => content
        }) do
      {:ok,
       %{
         tool_name: "fs.write_text_file",
         args: %{"path" => "sample.md", "content" => content},
         summary: "Wrote file sample.md",
         preview: String.slice(content, 0, 80),
         result: %{
           path: "sample.md",
           workspace_path: "/workspace/test/sample.md",
           root_path: "/workspace/test",
           bytes: byte_size(content)
         }
       }}
    end
  end

  defmodule ErrorToolRuntime do
    def execute(_world, _instance, "web.fetch", _args) do
      {:error,
       %{
         tool_name: "web.fetch",
         code: "tool.web.request_failed",
         message: "Web fetch request failed",
         details: %{reason: "dns"}
       }}
    end
  end

  defmodule RejectingMessagePersistor do
    def insert(_attrs), do: {:error, :forced_persist_failure}
  end

  defmodule BlockingAsyncDetsStore do
    def snapshot_async(instance_id, runtime_state) do
      test_pid = runtime_state.config_snapshot.observer_pid

      Task.start(fn ->
        send(test_pid, {:snapshot_started, instance_id, self()})

        receive do
          :release_snapshot -> :ok
        end
      end)

      :ok
    end
  end

  setup do
    start_supervised!(RuntimeTableOwner)
    ensure_process_started!(ActivityLog)
    ActivityLog.clear()
    ensure_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    ensure_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_dynamic_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)

    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Initial request")

    if :ets.whereis(:lemming_instance_runtime) != :undefined do
      :ets.delete_all_objects(:lemming_instance_runtime)
    end

    on_exit(fn ->
      if :ets.whereis(:lemming_instance_runtime) != :undefined do
        :ets.delete_all_objects(:lemming_instance_runtime)
      end
    end)

    {:ok, instance: instance, department_id: department.id}
  end

  test "S01: via_name and child_spec build the expected registry wiring", %{instance: instance} do
    assert Executor.via_name(instance.id) ==
             {:via, Registry, {LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id}}

    spec = Executor.child_spec(instance: instance, name: nil)
    assert spec.id == {Executor, instance.id}
    assert spec.start == {Executor, :start_link, [[instance: instance, name: nil]]}
  end

  test "S01b: enqueue_work/2 returns executor_unavailable when the target process is gone" do
    dead_pid = spawn(fn -> :ok end)
    monitor_ref = Process.monitor(dead_pid)

    assert_receive {:DOWN, ^monitor_ref, :process, ^dead_pid, _reason}
    assert {:error, :executor_unavailable} = Executor.enqueue_work(dead_pid, "Investigate")
  end

  test "S01c: enqueue_work/2 returns executor_unavailable when the registry name is unresolved",
       %{
         instance: instance
       } do
    assert {:error, :executor_unavailable} = Executor.enqueue_work(instance.id, "Investigate")
  end

  test "S01d: resume_pending/2 returns executor_unavailable when the target process is gone" do
    dead_pid = spawn(fn -> :ok end)
    monitor_ref = Process.monitor(dead_pid)

    assert_receive {:DOWN, ^monitor_ref, :process, ^dead_pid, _reason}
    assert {:error, :executor_unavailable} = Executor.resume_pending(dead_pid, "Investigate")
  end

  test "S01e: enqueue_work/2 returns executor_unavailable when the registered executor dies during admission",
       %{instance: instance} do
    parent = self()

    race_pid =
      spawn(fn ->
        {:ok, _} =
          Registry.register(LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id, :race)

        send(parent, {:executor_registered, self()})

        receive do
          {:"$gen_call", _from, {:enqueue_work, _content}} ->
            exit(:boom)
        end
      end)

    monitor_ref = Process.monitor(race_pid)

    assert_receive {:executor_registered, ^race_pid}
    assert {:error, :executor_unavailable} = Executor.enqueue_work(instance.id, "Investigate")
    assert_receive {:DOWN, ^monitor_ref, :process, ^race_pid, :boom}
  end

  test "S01f: terminal executors reject synchronous enqueue and resume calls", %{
    instance: instance
  } do
    assert {:ok, failed_instance} = LemmingInstances.update_status(instance, "failed", %{})

    pid =
      start_supervised!(
        {Executor,
         instance: failed_instance,
         config_snapshot: %{},
         context_mod: LemmingInstances,
         model_mod: FakeModelRuntime,
         pool_mod: ResourcePool,
         pubsub_mod: Phoenix.PubSub,
         dets_mod: nil,
         ets_mod: LemmingsOs.LemmingInstances.EtsStore,
         name: nil}
      )

    assert {:error, :terminal_instance} = Executor.enqueue_work(pid, "Retry me")
    assert {:error, :terminal_instance} = Executor.resume_pending(pid, "Retry me")
  end

  test "S02: successful execution persists the assistant reply and returns to idle", %{
    instance: instance
  } do
    resource_key = "ollama:fake-model"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "fake-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "fake-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: FakeModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert ResourcePool.status(resource_key) == {1, 1}

    assert :ok = Executor.enqueue_work(pid, "Investigate the outage")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fake-model"}, _context_messages,
                    %{content: "Investigate the outage"}}

    assert_receive {:status_changed, %{status: "idle"}}
    assert ResourcePool.status(resource_key) == {0, 1}

    assert Executor.status(pid).status == "idle"

    messages = LemmingInstances.list_messages(instance)
    assert Enum.any?(messages, &(&1.role == "assistant" and &1.content == "processed"))

    GenServer.stop(pid)
  end

  test "S02a: idle snapshotting does not block follow-up admission", %{instance: instance} do
    resource_key = "ollama:idle-snapshot-async"
    instance_id = instance.id

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "fake-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "fake-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: FakeModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: BlockingAsyncDetsStore,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Initial request")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, _config_snapshot, _context_messages,
                    %{content: "Initial request"}}

    assert_receive {:status_changed, %{status: "idle"}}
    assert_receive {:snapshot_started, ^instance_id, snapshot_pid}

    assert :ok = Executor.enqueue_work(pid, "Follow-up while snapshot is pending")
    assert_receive {:status_changed, %{status: "queued"}}
    assert Executor.status(pid).queue_depth == 1

    send(snapshot_pid, :release_snapshot)

    GenServer.stop(pid)
  end

  test "S02b: lemming_call responses route through LemmingCalls and continue model loop", %{
    instance: instance
  } do
    resource_key = "ollama:lemming-call-loop-model"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "lemming-call-loop-model",
          observer_pid: self(),
          models_config: %{
            profiles: %{default: %{provider: "ollama", model: "lemming-call-loop-model"}}
          }
        },
        context_mod: LemmingInstances,
        model_mod: LemmingCallLoopModelRuntime,
        lemming_calls_mod: FakeLemmingCalls,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Delegate this")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:lemming_call_model_run, %{lemming_call_targets: targets}, _messages,
                    %{content: "Delegate this"}}

    assert [%{slug: "ops-worker"}] = targets
    assert_receive {:status_changed, %{status: "idle"}}

    assert :ok =
             Executor.resume_after_lemming_call(pid, %LemmingsOs.LemmingCalls.LemmingCall{
               id: Ecto.UUID.generate(),
               status: "completed",
               result_summary: "Draft child notes complete."
             })

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:lemming_call_model_run, _config_snapshot, context_messages,
                    %{content: "Delegate this"}}

    assert Enum.any?(context_messages, &String.contains?(&1.content, "Lemming call result:"))
    assert_receive {:status_changed, %{status: "idle"}}

    messages = LemmingInstances.list_messages(instance)

    assert Enum.any?(
             messages,
             &(&1.role == "assistant" and &1.content == "Delegated to child call.")
           )

    GenServer.stop(pid)
  end

  test "S03: model crashes transition the executor to failed and release the pool token", %{
    instance: instance
  } do
    assert capture_log(fn ->
             resource_key = "ollama:fake-model"

             assert :ok = PubSub.subscribe_instance(instance.id)

             {:ok, pid} =
               Executor.start_link(
                 instance: instance,
                 config_snapshot: %{
                   runtime_config: %{max_retries: 1},
                   models_config: %{
                     profiles: %{default: %{provider: "ollama", model: "fake-model"}}
                   }
                 },
                 context_mod: LemmingInstances,
                 model_mod: CrashingModelRuntime,
                 pool_mod: ResourcePool,
                 pubsub_mod: Phoenix.PubSub,
                 dets_mod: nil,
                 ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                 name: nil
               )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert ResourcePool.status(resource_key) == {1, 1}

             assert :ok = Executor.enqueue_work(pid, "Crash please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}
             assert ResourcePool.status(resource_key) == {0, 1}

             assert Executor.status(pid).status == "failed"

             GenServer.stop(pid)
           end) =~ "executor model task crashed"
  end

  test "S04: hanging model execution times out and fails the executor", %{instance: instance} do
    assert capture_log(fn ->
             resource_key = "ollama:hanging-model"

             assert :ok = PubSub.subscribe_instance(instance.id)

             {:ok, pid} =
               Executor.start_link(
                 instance: instance,
                 config_snapshot: %{
                   runtime_config: %{max_retries: 1, model_timeout_ms: 10},
                   models_config: %{
                     profiles: %{default: %{provider: "ollama", model: "hanging-model"}}
                   }
                 },
                 context_mod: LemmingInstances,
                 model_mod: HangingModelRuntime,
                 pool_mod: ResourcePool,
                 pubsub_mod: Phoenix.PubSub,
                 dets_mod: nil,
                 ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                 name: nil
               )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert ResourcePool.status(resource_key) == {1, 1}

             assert :ok = Executor.enqueue_work(pid, "Hang please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}

             assert ResourcePool.status(resource_key) == {0, 1}

             assert %{status: "failed", last_error: "Executor model task timed out."} =
                      Executor.status(pid)

             GenServer.stop(pid)
           end) =~ "Executor model task timed out."
  end

  test "S04a: provider failure keeps raw diagnostics internal while exposing sanitized copy", %{
    instance: instance
  } do
    assert capture_log(fn ->
             resource_key = "ollama:provider-http-error"

             assert :ok = PubSub.subscribe_instance(instance.id)

             {:ok, pid} =
               Executor.start_link(
                 instance: instance,
                 config_snapshot: %{
                   runtime_config: %{max_retries: 1},
                   models_config: %{
                     profiles: %{default: %{provider: "ollama", model: "provider-http-error"}}
                   }
                 },
                 context_mod: LemmingInstances,
                 model_mod: ProviderHttpErrorModelRuntime,
                 pool_mod: ResourcePool,
                 pubsub_mod: Phoenix.PubSub,
                 dets_mod: nil,
                 ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                 name: nil
               )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert :ok = Executor.enqueue_work(pid, "Trigger provider failure")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}

             assert %{
                      status: "failed",
                      last_error: "ollama request failed (HTTP 500). Retry or inspect logs.",
                      internal_error_details: %{
                        kind: :provider_http_error,
                        provider: "ollama",
                        status: 500,
                        detail: "boom"
                      }
                    } = Executor.status(pid)

             assert %{
                      last_error: "ollama request failed (HTTP 500). Retry or inspect logs.",
                      internal_error_details: %{detail: "boom"}
                    } = Executor.snapshot(pid)

             GenServer.stop(pid)
           end) =~ "executor status transitioned"
  end

  test "S04b: retry/1 requeues failed work on a live executor", %{instance: instance} do
    capture_log(fn ->
      resource_key = "ollama:retry-live"

      assert :ok = PubSub.subscribe_instance(instance.id)

      {:ok, pid} =
        Executor.start_link(
          instance: instance,
          config_snapshot: %{
            runtime_config: %{max_retries: 1},
            models_config: %{profiles: %{default: %{provider: "ollama", model: "retry-live"}}}
          },
          context_mod: LemmingInstances,
          model_mod: CrashingModelRuntime,
          pool_mod: ResourcePool,
          pubsub_mod: Phoenix.PubSub,
          dets_mod: nil,
          ets_mod: LemmingsOs.LemmingInstances.EtsStore,
          name: nil
        )

      {:ok, _pool_pid} =
        start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

      assert :ok = ResourcePool.checkout(resource_key, holder: pid)
      assert :ok = Executor.enqueue_work(pid, "Retry me")
      assert_receive {:status_changed, %{status: "queued"}}

      send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

      assert_receive {:status_changed, %{status: "processing"}}
      assert_receive {:status_changed, %{status: "failed"}}

      assert :ok = Executor.retry(pid)
      assert_receive {:status_changed, %{status: "queued"}}

      send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

      assert_receive {:status_changed, %{status: "processing"}}
      assert_receive {:status_changed, %{status: "failed"}}

      GenServer.stop(pid)
    end)
  end

  test "S04c: assistant message persistence failure does not count as successful completion", %{
    instance: instance
  } do
    assert capture_log(fn ->
             resource_key = "ollama:persist-failure"

             assert :ok = PubSub.subscribe_instance(instance.id)

             {:ok, pid} =
               Executor.start_link(
                 instance: instance,
                 config_snapshot: %{
                   runtime_config: %{max_retries: 1},
                   model: "persist-failure",
                   observer_pid: self(),
                   models_config: %{
                     profiles: %{default: %{provider: "ollama", model: "persist-failure"}}
                   }
                 },
                 context_mod: LemmingInstances,
                 model_mod: FakeModelRuntime,
                 message_persist_mod: RejectingMessagePersistor,
                 pool_mod: ResourcePool,
                 pubsub_mod: Phoenix.PubSub,
                 dets_mod: nil,
                 ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                 name: nil
               )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert :ok = Executor.enqueue_work(pid, "Persist the assistant reply")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}

             assert_receive {:model_run, _task_pid, %{model: "persist-failure"},
                             _context_messages, %{content: "Persist the assistant reply"}}

             assert_receive {:status_changed, %{status: "failed"}}
             assert ResourcePool.status(resource_key) == {0, 1}

             assert %{
                      status: "failed",
                      last_error:
                        "Assistant response could not be persisted. Retry or inspect logs.",
                      internal_error_details: %{
                        kind: :assistant_message_persist_failed,
                        reason: ":forced_persist_failure"
                      }
                    } = Executor.status(pid)

             refute Enum.any?(
                      LemmingInstances.list_messages(instance),
                      &(&1.role == "assistant" and &1.content == "processed")
                    )

             GenServer.stop(pid)
           end) =~ "executor failed to persist assistant message"
  end

  test "S05: failed executions clear persisted DETS snapshots", %{instance: instance} do
    resource_key = "ollama:failed-snapshot"
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    assert capture_log(fn ->
             assert :ok = PubSub.subscribe_instance(instance.id)

             assert :ok =
                      DetsStore.snapshot(instance.id, %{
                        department_id: instance.department_id,
                        queue: :queue.new(),
                        current_item: nil,
                        retry_count: 0,
                        max_retries: 1,
                        context_messages: [],
                        status: :idle,
                        started_at: started_at,
                        last_activity_at: started_at
                      })

             assert {:ok, pid} =
                      Executor.start_link(
                        instance: instance,
                        config_snapshot: %{
                          runtime_config: %{max_retries: 1},
                          models_config: %{
                            profiles: %{default: %{provider: "ollama", model: "fake-model"}}
                          }
                        },
                        context_mod: LemmingInstances,
                        model_mod: CrashingModelRuntime,
                        pool_mod: ResourcePool,
                        pubsub_mod: Phoenix.PubSub,
                        dets_mod: DetsStore,
                        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
                        name: nil
                      )

             {:ok, _pool_pid} =
               start_supervised(
                 {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
               )

             assert :ok = ResourcePool.checkout(resource_key, holder: pid)
             assert :ok = Executor.enqueue_work(pid, "Crash please")
             assert_receive {:status_changed, %{status: "queued"}}

             send(
               pid,
               {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}}
             )

             assert_receive {:status_changed, %{status: "processing"}}
             assert_receive {:status_changed, %{status: "failed"}}
             assert {:error, :not_found} = DetsStore.read(instance.id)

             GenServer.stop(pid)
           end) =~ "executor model task crashed"
  end

  test "S06: idle_timeout_ms option expires an idle executor deterministically", %{
    instance: instance
  } do
    resource_key = "ollama:idle-timeout"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "fake-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "fake-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: FakeModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        idle_timeout_ms: 20,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Expire after idle")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fake-model"}, _context_messages,
                    %{content: "Expire after idle"}}

    assert_receive {:status_changed, %{status: "idle"}}
    assert_receive {:status_changed, %{status: "expired"}}

    assert Repo.get!(LemmingsOs.LemmingInstances.LemmingInstance, instance.id).status == "expired"
  end

  test "S06a: recovered idle executors start the idle timer during boot", %{instance: instance} do
    assert :ok = PubSub.subscribe_instance(instance.id)
    assert {:ok, idle_instance} = LemmingInstances.update_status(instance, "idle", %{})

    assert {:ok, pid} =
             Executor.start_link(
               instance: idle_instance,
               config_snapshot: %{},
               context_mod: LemmingInstances,
               model_mod: FakeModelRuntime,
               pool_mod: ResourcePool,
               pubsub_mod: Phoenix.PubSub,
               dets_mod: nil,
               ets_mod: LemmingsOs.LemmingInstances.EtsStore,
               idle_timeout_ms: 20,
               name: nil
             )

    monitor_ref = Process.monitor(pid)

    assert_receive {:status_changed, %{status: "expired"}}
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, :normal}

    assert Repo.get!(LemmingsOs.LemmingInstances.LemmingInstance, instance.id).status == "expired"
  end

  test "S07: multiple queued items are processed in FIFO order", %{instance: instance} do
    resource_key = "ollama:fifo-model"

    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "fifo-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "fifo-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: FakeModelRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "First queued item")
    assert :ok = Executor.enqueue_work(pid, "Second queued item")

    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fifo-model"}, _context_messages,
                    %{content: "First queued item"}}

    assert_receive {:status_changed, %{status: "queued"}}

    wait_for_pool_status(resource_key, {0, 1})
    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}

    assert_receive {:model_run, _task_pid, %{model: "fifo-model"}, _context_messages,
                    %{content: "Second queued item"}}

    assert_receive {:status_changed, %{status: "idle"}}

    GenServer.stop(pid)
  end

  test "S08: tool_call loop executes tool runtime and continues until final reply", %{
    instance: instance
  } do
    started_ref = attach([:lemmings_os, :runtime, :tool_execution, :started])
    completed_ref = attach([:lemmings_os, :runtime, :tool_execution, :completed])

    resource_key = "ollama:tool-loop-model"
    assert :ok = PubSub.subscribe_instance(instance.id)
    assert :ok = PubSub.subscribe_instance_messages(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{
          model: "tool-loop-model",
          observer_pid: self(),
          models_config: %{profiles: %{default: %{provider: "ollama", model: "tool-loop-model"}}}
        },
        context_mod: LemmingInstances,
        model_mod: ToolLoopModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: LemmingsOs.LemmingInstances.EtsStore,
        name: nil
      )

    {:ok, _pool_pid} =
      start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Use a tool then reply")
    assert_receive {:status_changed, %{status: "queued"}}

    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert_receive {:status_changed, %{status: "processing"}}
    assert_receive {:tool_execution_upserted, %{status: "running"}}
    assert_receive {:tool_execution_upserted, %{status: "ok"}}

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :started],
                    %{count: 1}, started_metadata}

    assert started_metadata.instance_id == instance.id
    assert started_metadata.world_id == instance.world_id
    assert started_metadata.city_id == instance.city_id
    assert started_metadata.department_id == instance.department_id
    assert started_metadata.lemming_id == instance.lemming_id
    assert started_metadata.tool_name == "web.fetch"

    assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :completed],
                    %{count: 1, duration_ms: duration_ms}, completed_metadata}

    assert duration_ms >= 0
    assert completed_metadata.instance_id == instance.id
    assert completed_metadata.tool_name == "web.fetch"
    assert completed_metadata.tool_status == "ok"

    assert_receive {:status_changed, %{status: "idle"}}

    assert_receive {:tool_loop_model_run, first_context_messages,
                    %{content: "Use a tool then reply"}}

    assert_receive {:tool_loop_model_run, second_context_messages, second_current_item}

    assert String.contains?(second_current_item.content, "Finalization Phase:")
    assert String.contains?(second_current_item.content, "Original user goal:")
    assert String.contains?(second_current_item.content, "Use a tool then reply")
    assert String.contains?(second_current_item.content, "Return action=reply")

    assert Enum.count(
             first_context_messages,
             &(&1.role == "user" and &1.content == "Use a tool then reply")
           ) == 1

    assert Enum.count(
             second_context_messages,
             &(&1.role == "user" and &1.content == "Use a tool then reply")
           ) == 1

    assert Enum.any?(
             second_context_messages,
             &String.contains?(&1.content, "Assistant requested tool web.fetch with arguments:")
           )

    assert Enum.any?(
             second_context_messages,
             &String.contains?(&1.content, "As response to your previous tool request")
           )

    messages = LemmingInstances.list_messages(instance)

    assert Enum.any?(
             messages,
             &(&1.role == "assistant" and &1.content == "final response with tool context")
           )

    executions =
      LemmingTools.list_tool_executions(%World{id: instance.world_id}, instance)
      |> Enum.filter(&(&1.tool_name == "web.fetch"))

    assert [%{status: "ok", summary: "Fetched https://example.com", result: result}] = executions
    assert result["status"] == 200

    model_steps = Executor.snapshot(pid).model_steps

    assert [
             %{
               step_index: 1,
               status: "ok",
               parsed_output: %{"action" => "tool_call", "tool_name" => "web.fetch"},
               tool_execution_id: tool_execution_id
             },
             %{
               step_index: 2,
               status: "ok",
               parsed_output: %{
                 "action" => "reply",
                 "reply" => "final response with tool context"
               }
             }
           ] = model_steps

    assert is_binary(tool_execution_id)

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "tool_execution" and &1.action == "Tool started" and
                 &1.metadata[:tool_name] == "web.fetch")
           )

    assert Enum.any?(
             ActivityLog.recent_events(),
             &(&1.agent == "tool_execution" and &1.action == "Tool completed" and
                 &1.metadata[:tool_name] == "web.fetch")
           )

    detach(started_ref)
    detach(completed_ref)
    GenServer.stop(pid)
  end

  test "S08b: tool success enters finalization phase and returns normal final response", %{
    instance: instance
  } do
    resource_key = "ollama:finalization-model"
    assert :ok = PubSub.subscribe_instance(instance.id)

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{observer_pid: self(), model: "finalization-model"},
        context_mod: LemmingInstances,
        model_mod: FinalizationAwareModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: nil,
        name: nil
      )

    start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Create sample.md for my boss")
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert eventually_status(pid, "idle")

    assert_receive {:finalization_model_run, _first_context_messages,
                    %{content: "Create sample.md for my boss"}}

    assert_receive {:finalization_model_run, _second_context_messages, finalization_item}
    assert String.contains?(finalization_item.content, "Finalization Phase:")
    assert String.contains?(finalization_item.content, "Artifacts created:")
    assert String.contains?(finalization_item.content, "- sample.md")

    assert Enum.any?(
             LemmingInstances.list_messages(instance),
             &(&1.role == "assistant" and
                 &1.content == "Created sample.md with mock budget data for your boss.")
           )

    GenServer.stop(pid)
  end

  test "S08c: tool success empty final response triggers one repair retry", %{instance: instance} do
    resource_key = "ollama:repair-model"

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{observer_pid: self(), model: "repair-model"},
        context_mod: LemmingInstances,
        model_mod: RepairOnceModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: nil,
        name: nil
      )

    start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Create sample.md for my boss")
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert eventually_status(pid, "idle")

    assert_receive {:repair_model_run, _context_messages,
                    %{content: "Create sample.md for my boss"}}

    assert_receive {:repair_model_run, _context_messages, finalization_item}
    assert String.contains?(finalization_item.content, "Finalization Phase:")
    refute String.contains?(finalization_item.content, "Repair Notice:")

    assert_receive {:repair_model_run, _context_messages, repaired_item}
    assert String.contains?(repaired_item.content, "Repair Notice:")

    assert Enum.any?(
             LemmingInstances.list_messages(instance),
             &(&1.role == "assistant" and
                 &1.content == "Created sample.md successfully. It now contains mock budget data.")
           )

    model_steps = Executor.snapshot(pid).model_steps
    assert length(model_steps) == 3
    assert Enum.at(model_steps, 1).status == "error"
    assert Enum.at(model_steps, 2).status == "ok"

    GenServer.stop(pid)
  end

  test "S08d: final response can communicate next step after tool success", %{instance: instance} do
    resource_key = "ollama:more-work-model"

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{observer_pid: self(), model: "more-work-model"},
        context_mod: LemmingInstances,
        model_mod: MoreWorkFinalizationModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: nil,
        name: nil
      )

    start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Create sample.md for my boss")
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert eventually_status(pid, "idle")

    assert Enum.any?(
             LemmingInstances.list_messages(instance),
             &(&1.role == "assistant" and
                 String.contains?(&1.content, "The next step is to review the figures"))
           )

    GenServer.stop(pid)
  end

  test "S09: tool_call errors are persisted and reasoning can continue", %{instance: instance} do
    capture_log(fn ->
      started_ref = attach([:lemmings_os, :runtime, :tool_execution, :started])
      failed_ref = attach([:lemmings_os, :runtime, :tool_execution, :failed])

      resource_key = "ollama:tool-loop-error-model"
      assert :ok = PubSub.subscribe_instance(instance.id)
      assert :ok = PubSub.subscribe_instance_messages(instance.id)

      {:ok, pid} =
        Executor.start_link(
          instance: instance,
          config_snapshot: %{
            model: "tool-loop-error-model",
            observer_pid: self(),
            models_config: %{
              profiles: %{default: %{provider: "ollama", model: "tool-loop-error-model"}}
            }
          },
          context_mod: LemmingInstances,
          model_mod: ToolLoopErrorModelRuntime,
          tools_context_mod: LemmingTools,
          tool_runtime_mod: ErrorToolRuntime,
          pool_mod: ResourcePool,
          pubsub_mod: Phoenix.PubSub,
          dets_mod: nil,
          ets_mod: LemmingsOs.LemmingInstances.EtsStore,
          name: nil
        )

      {:ok, _pool_pid} =
        start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

      assert :ok = ResourcePool.checkout(resource_key, holder: pid)
      assert :ok = Executor.enqueue_work(pid, "Use a failing tool then reply")
      assert_receive {:status_changed, %{status: "queued"}}

      send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

      assert_receive {:status_changed, %{status: "processing"}}
      assert_receive {:tool_execution_upserted, %{status: "running"}}
      assert_receive {:tool_execution_upserted, %{status: "error"}}

      assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :started],
                      %{count: 1}, _started_metadata}

      assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :failed],
                      %{count: 1, duration_ms: duration_ms}, failed_metadata}

      assert duration_ms >= 0
      assert failed_metadata.instance_id == instance.id
      assert failed_metadata.tool_name == "web.fetch"
      assert failed_metadata.tool_status == "error"
      assert failed_metadata.reason == "tool.web.request_failed"

      assert_receive {:status_changed, %{status: "idle"}}

      messages = LemmingInstances.list_messages(instance)

      assert Enum.any?(
               messages,
               &(&1.role == "assistant" and &1.content == "final response after tool error")
             )

      executions =
        LemmingTools.list_tool_executions(%World{id: instance.world_id}, instance)
        |> Enum.filter(&(&1.tool_name == "web.fetch"))

      assert [%{status: "error", error: %{"code" => "tool.web.request_failed"}}] = executions

      assert Enum.any?(
               ActivityLog.recent_events(),
               &(&1.agent == "tool_execution" and &1.action == "Tool failed" and
                   &1.metadata[:reason] == "tool.web.request_failed")
             )

      detach(started_ref)
      detach(failed_ref)
      GenServer.stop(pid)
    end)
  end

  test "S10: invalid structured output keeps raw provider content in model steps", %{
    instance: instance
  } do
    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{observer_pid: self(), model: "broken-model"},
        context_mod: LemmingInstances,
        model_mod: InvalidStructuredOutputModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: nil,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: nil
      )

    assert :ok = Executor.enqueue_work(pid, "Break structured output")
    Executor.admit(pid)
    assert eventually_status(pid, "failed")

    assert %{
             status: "failed",
             last_error: "Model returned invalid structured output."
           } = Executor.snapshot(pid)

    assert [
             %{
               step_index: 1,
               status: "error",
               response_payload: %{"content" => "not-json"},
               error: %{"kind" => "invalid_structured_output", "content" => "not-json"}
             },
             %{
               step_index: 2,
               status: "error",
               response_payload: %{"content" => "not-json"},
               error: %{"kind" => "invalid_structured_output", "content" => "not-json"}
             },
             %{
               step_index: 3,
               status: "error",
               response_payload: %{"content" => "not-json"},
               error: %{"kind" => "invalid_structured_output", "content" => "not-json"}
             }
           ] = Executor.snapshot(pid).model_steps

    GenServer.stop(pid)
  end

  test "S10b: finalization repair runs only once and does not loop forever", %{instance: instance} do
    resource_key = "ollama:repair-fails-model"

    {:ok, pid} =
      Executor.start_link(
        instance: instance,
        config_snapshot: %{observer_pid: self(), model: "repair-fails-model"},
        context_mod: LemmingInstances,
        model_mod: RepairFailsModelRuntime,
        tools_context_mod: LemmingTools,
        tool_runtime_mod: SuccessToolRuntime,
        pool_mod: ResourcePool,
        pubsub_mod: Phoenix.PubSub,
        dets_mod: nil,
        ets_mod: nil,
        name: nil
      )

    start_supervised({ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil})

    assert :ok = ResourcePool.checkout(resource_key, holder: pid)
    assert :ok = Executor.enqueue_work(pid, "Create sample.md for my boss")
    send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

    assert eventually_status(pid, "failed")

    assert_receive {:repair_fails_model_run, _context_messages,
                    %{content: "Create sample.md for my boss"}}

    assert_receive {:repair_fails_model_run, _context_messages, finalization_item}
    assert String.contains?(finalization_item.content, "Finalization Phase:")
    refute String.contains?(finalization_item.content, "Repair Notice:")

    assert_receive {:repair_fails_model_run, _context_messages, repaired_item}
    assert String.contains?(repaired_item.content, "Repair Notice:")

    refute_receive {:repair_fails_model_run, _context_messages, _current_item}, 100

    model_steps = Executor.snapshot(pid).model_steps
    assert length(model_steps) == 3
    assert Enum.at(model_steps, 0).status == "ok"
    assert Enum.at(model_steps, 1).status == "error"
    assert Enum.at(model_steps, 2).status == "error"

    GenServer.stop(pid)
  end

  test "S10: tool_call success emits structured started/completed lifecycle logs", %{
    instance: instance
  } do
    log =
      capture_info_log(fn ->
        resource_key = "ollama:tool-loop-log-success"
        assert :ok = PubSub.subscribe_instance(instance.id)
        assert :ok = PubSub.subscribe_instance_messages(instance.id)

        {:ok, pid} =
          Executor.start_link(
            instance: instance,
            config_snapshot: %{
              model: "tool-loop-log-success",
              observer_pid: self(),
              models_config: %{
                profiles: %{default: %{provider: "ollama", model: "tool-loop-log-success"}}
              }
            },
            context_mod: LemmingInstances,
            model_mod: ToolLoopModelRuntime,
            tools_context_mod: LemmingTools,
            tool_runtime_mod: SuccessToolRuntime,
            pool_mod: ResourcePool,
            pubsub_mod: Phoenix.PubSub,
            dets_mod: nil,
            ets_mod: LemmingsOs.LemmingInstances.EtsStore,
            name: nil
          )

        {:ok, _pool_pid} =
          start_supervised(
            {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
          )

        assert :ok = ResourcePool.checkout(resource_key, holder: pid)
        assert :ok = Executor.enqueue_work(pid, "Use a tool and log success")
        assert_receive {:status_changed, %{status: "queued"}}

        send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

        assert_receive {:status_changed, %{status: "processing"}}
        assert_receive {:tool_execution_upserted, %{status: "running"}}
        assert_receive {:tool_execution_upserted, %{status: "ok"}}
        assert_receive {:status_changed, %{status: "idle"}}

        GenServer.stop(pid)
      end)

    assert log =~ "event=instance.executor.tool_execution.started"
    assert log =~ "event=instance.executor.tool_execution.completed"
    assert log =~ "operation=web.fetch"
    assert log =~ "status=running"
    assert log =~ "status=ok"
  end

  test "S11: unsupported tool requests persist error and emit failed lifecycle logs", %{
    instance: instance
  } do
    log =
      capture_info_log(fn ->
        started_ref = attach([:lemmings_os, :runtime, :tool_execution, :started])
        failed_ref = attach([:lemmings_os, :runtime, :tool_execution, :failed])

        resource_key = "ollama:unsupported-tool-model"
        assert :ok = PubSub.subscribe_instance(instance.id)
        assert :ok = PubSub.subscribe_instance_messages(instance.id)

        {:ok, pid} =
          Executor.start_link(
            instance: instance,
            config_snapshot: %{
              model: "unsupported-tool-model",
              observer_pid: self(),
              models_config: %{
                profiles: %{default: %{provider: "ollama", model: "unsupported-tool-model"}}
              }
            },
            context_mod: LemmingInstances,
            model_mod: UnsupportedToolLoopModelRuntime,
            tools_context_mod: LemmingTools,
            tool_runtime_mod: LemmingsOs.Tools.Runtime,
            pool_mod: ResourcePool,
            pubsub_mod: Phoenix.PubSub,
            dets_mod: nil,
            ets_mod: LemmingsOs.LemmingInstances.EtsStore,
            name: nil
          )

        {:ok, _pool_pid} =
          start_supervised(
            {ResourcePool, resource_key: resource_key, gate: :open, pubsub_mod: nil}
          )

        assert :ok = ResourcePool.checkout(resource_key, holder: pid)
        assert :ok = Executor.enqueue_work(pid, "Use unsupported tool then recover")
        assert_receive {:status_changed, %{status: "queued"}}

        send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

        assert_receive {:status_changed, %{status: "processing"}}
        assert_receive {:tool_execution_upserted, %{status: "running"}}
        assert_receive {:tool_execution_upserted, %{status: "error"}}

        assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :started],
                        %{count: 1}, started_metadata}

        assert started_metadata.tool_name == "exec.run"
        assert started_metadata.instance_id == instance.id

        assert_receive {:telemetry_event, [:lemmings_os, :runtime, :tool_execution, :failed],
                        %{count: 1, duration_ms: duration_ms}, failed_metadata}

        assert duration_ms >= 0
        assert failed_metadata.tool_name == "exec.run"
        assert failed_metadata.tool_status == "error"
        assert failed_metadata.reason == "tool.unsupported"

        assert_receive {:status_changed, %{status: "idle"}}

        messages = LemmingInstances.list_messages(instance)

        assert Enum.any?(
                 messages,
                 &(&1.role == "assistant" and
                     &1.content == "final response after unsupported tool")
               )

        executions =
          LemmingTools.list_tool_executions(%World{id: instance.world_id}, instance)
          |> Enum.filter(&(&1.tool_name == "exec.run"))

        assert [%{status: "error", error: %{"code" => "tool.unsupported"}}] = executions

        detach(started_ref)
        detach(failed_ref)
        GenServer.stop(pid)
      end)

    assert log =~ "event=instance.executor.tool_execution.started"
    assert log =~ "event=instance.executor.tool_execution.failed"
    assert log =~ "operation=exec.run"
    assert log =~ "reason=tool.unsupported"
    assert log =~ "status=error"
  end

  defp ensure_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({Registry, keys: :unique, name: name})
        :ok
    end
  end

  defp ensure_dynamic_supervisor!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({DynamicSupervisor, name: name, strategy: :one_for_one})
        :ok
    end
  end

  defp ensure_process_started!(child) do
    case Process.whereis(child) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!(child)
        :ok
    end
  end

  defp attach(event) do
    ref = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        "executor-telemetry-test-#{inspect(ref)}",
        event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

    ref
  end

  defp detach(ref) do
    :telemetry.detach("executor-telemetry-test-#{inspect(ref)}")
  end

  defp wait_for_pool_status(resource_key, expected_status, attempts \\ 20)

  defp wait_for_pool_status(resource_key, expected_status, attempts)
       when attempts > 0 do
    case ResourcePool.status(resource_key) do
      ^expected_status ->
        :ok

      _other ->
        Process.sleep(10)
        wait_for_pool_status(resource_key, expected_status, attempts - 1)
    end
  end

  defp wait_for_pool_status(resource_key, expected_status, 0) do
    assert ResourcePool.status(resource_key) == expected_status
  end

  defp eventually_status(pid, expected_status, attempts \\ 20)

  defp eventually_status(pid, expected_status, attempts) when attempts > 0 do
    if Executor.status(pid).status == expected_status do
      true
    else
      Process.sleep(10)
      eventually_status(pid, expected_status, attempts - 1)
    end
  end

  defp eventually_status(pid, expected_status, 0) do
    assert Executor.status(pid).status == expected_status
  end

  defp capture_info_log(fun) when is_function(fun, 0) do
    previous_level = Logger.level()

    try do
      Logger.configure(level: :info)

      capture_log([level: :info], fn ->
        fun.()
      end)
    after
      Logger.configure(level: previous_level)
    end
  end
end
