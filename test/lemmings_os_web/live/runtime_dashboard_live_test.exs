defmodule LemmingsOsWeb.RuntimeDashboardLiveTest do
  use LemmingsOsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LemmingsOs.LemmingInstances.DepartmentScheduler
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.Runtime.ActivityLog

  setup do
    ActivityLog.clear()
    ensure_runtime_registry!(LemmingsOs.LemmingInstances.ExecutorRegistry)
    ensure_runtime_registry!(LemmingsOs.LemmingInstances.SchedulerRegistry)
    ensure_runtime_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_runtime_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)
    :ok
  end

  test "renders runtime module sections and live runtime rows", %{conn: conn} do
    suffix = System.unique_integer([:positive]) |> Integer.to_string()
    department_id = "dept-dashboard-#{suffix}"
    instance_id = "instance-dashboard-#{suffix}"
    resource_key = "ollama:dashboard-#{suffix}"

    instance = %LemmingInstance{
      id: instance_id,
      world_id: "world-dashboard-#{suffix}",
      city_id: "city-dashboard-#{suffix}",
      department_id: department_id,
      lemming_id: "lemming-dashboard-#{suffix}",
      status: "created",
      config_snapshot: %{}
    }

    {:ok, _scheduler_pid} =
      start_supervised(
        {DepartmentScheduler,
         department_id: department_id,
         admission_mode: :manual,
         context_mod: nil,
         pool_mod: ResourcePool}
      )

    {:ok, _pool_pid} =
      start_supervised(
        {ResourcePool,
         resource_key: resource_key, pubsub_mod: Phoenix.PubSub, pubsub_name: LemmingsOs.PubSub}
      )

    {:ok, _executor_pid} =
      start_supervised(
        {Executor,
         instance: instance,
         context_mod: nil,
         ets_mod: LemmingsOs.LemmingInstances.EtsStore,
         dets_mod: nil,
         model_mod: nil,
         pool_mod: ResourcePool,
         pubsub_mod: Phoenix.PubSub,
         pubsub_name: LemmingsOs.PubSub}
      )

    {:ok, view, _html} = live(conn, ~p"/dev/runtime")

    assert has_element?(view, "#runtime-dashboard-overview")
    assert has_element?(view, "#runtime-dashboard-services")
    assert has_element?(view, "#runtime-dashboard-schedulers-panel")
    assert has_element?(view, "#runtime-dashboard-pools-panel")
    assert has_element?(view, "#runtime-dashboard-executors-panel")
    assert has_element?(view, "#runtime-dashboard-runtime-entries-panel")
    assert has_element?(view, "#runtime-dashboard-scheduler-#{department_id}", department_id)
    assert has_element?(view, "#runtime-dashboard-executor-#{instance_id}", instance_id)
  end

  defp ensure_runtime_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({Registry, keys: :unique, name: name})
        :ok
    end
  end

  defp ensure_runtime_supervisor!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({DynamicSupervisor, name: name, strategy: :one_for_one})
        :ok
    end
  end
end
