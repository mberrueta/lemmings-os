defmodule LemmingsOsWeb.InstanceRawSnapshotControllerTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.ModelRuntime.Response
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime.ActivityLog
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

  test "returns live markdown trace export", %{conn: conn} do
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

    conn = get(conn, ~p"/lemmings/instances/#{instance.id}/raw.md?#{%{world: world.id}}")
    body = response(conn, 200)

    assert Enum.any?(
             get_resp_header(conn, "content-type"),
             &String.starts_with?(&1, "text/markdown")
           )

    assert body =~ "# Instance Raw Context"
    assert body =~ "Source: live executor trace"
    assert body =~ "2. App -> LLM"
    assert body =~ "LLM requested tool web.fetch"
    assert body =~ "File created successfully!"

    GenServer.stop(pid)
  end

  test "requires explicit world scope", %{conn: conn} do
    %{instance: instance} = spawn_runtime_session()

    conn = get(conn, ~p"/lemmings/instances/#{instance.id}/raw.md")

    assert response(conn, 404) == "World not found"
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
        name: "Ops Department #{unique}",
        slug: "ops-department-#{unique}"
      )

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active",
        name: "Trace Agent #{unique}"
      )

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Use a tool then reply")

    %{world: world, instance: instance}
  end

  defp eventually_executor_status(pid, expected_status, attempts \\ 40)

  defp eventually_executor_status(_pid, _expected_status, 0), do: false

  defp eventually_executor_status(pid, expected_status, attempts) do
    case Executor.snapshot(pid) do
      %{status: ^expected_status} ->
        true

      _other ->
        Process.sleep(20)
        eventually_executor_status(pid, expected_status, attempts - 1)
    end
  end
end
