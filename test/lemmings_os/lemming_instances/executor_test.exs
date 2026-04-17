defmodule LemmingsOs.LemmingInstances.ExecutorTest do
  use LemmingsOs.DataCase, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner
  alias LemmingsOs.ModelRuntime.Response

  defmodule FakeModelRuntime do
    def run(config_snapshot, context_messages, current_item) do
      observer_pid = Map.get(config_snapshot, :observer_pid)

      if is_pid(observer_pid) do
        send(observer_pid, {:model_run, self(), config_snapshot, context_messages, current_item})
      end

      {:ok,
       Response.new(
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

             send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

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

             send(pid, {:scheduler_admit, %{instance_id: instance.id, resource_key: resource_key}})

             assert_receive {:status_changed, %{status: "processing"}}

             assert_receive {:model_run, _task_pid, %{model: "persist-failure"}, _context_messages,
                             %{content: "Persist the assistant reply"}}

             assert_receive {:status_changed, %{status: "failed"}}
             assert ResourcePool.status(resource_key) == {0, 1}

             assert %{
                      status: "failed",
                      last_error: "Assistant response could not be persisted. Retry or inspect logs.",
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
end
