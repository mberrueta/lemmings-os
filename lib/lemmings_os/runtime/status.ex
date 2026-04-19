defmodule LemmingsOs.Runtime.Status do
  @moduledoc """
  Runtime operations snapshot for dashboards and logs.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.DepartmentScheduler
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.Repo

  @recoverable_statuses ~w(created queued processing retrying idle)
  @statuses @recoverable_statuses ++ ~w(failed expired)

  @spec snapshot() :: map()
  def snapshot do
    engine_enabled? = Application.get_env(:lemmings_os, :runtime_engine_on_startup, true)
    services = service_statuses()
    persisted_instances = persisted_instance_counts()
    active_processes = active_process_counts()
    alerts = alerts(engine_enabled?, services, persisted_instances, active_processes)

    %{
      engine_enabled?: engine_enabled?,
      services: services,
      persisted_instances: persisted_instances,
      active_processes: active_processes,
      recoverable_statuses: @recoverable_statuses,
      pending_instances:
        persisted_instances.created + persisted_instances.queued + persisted_instances.processing +
          persisted_instances.retrying,
      attention_required?: alerts != [],
      alerts: alerts
    }
  end

  @spec dashboard_snapshot(keyword()) :: map()
  def dashboard_snapshot(opts \\ []) do
    overview = snapshot()
    executors = executor_snapshots()
    runtime_entries = runtime_entries(executors)
    labels = runtime_labels(executors, runtime_entries)
    schedulers = scheduler_snapshots(labels.department_labels)
    pools = pool_snapshots()
    recent_limit = Keyword.get(opts, :recent_limit)

    executors =
      executors
      |> attach_executor_labels(labels.instance_labels)
      |> latest_first()
      |> maybe_take(recent_limit)

    runtime_entries =
      runtime_entries
      |> attach_runtime_entry_labels(labels.instance_labels)
      |> latest_first()
      |> maybe_take(recent_limit)

    tool_executions =
      recent_tool_executions(recent_limit)
      |> attach_tool_execution_labels(labels.instance_labels)

    %{
      overview: overview,
      services: service_rows(overview.services),
      executors: executors,
      schedulers: schedulers,
      pools: pools,
      runtime_entries: runtime_entries,
      tool_executions: tool_executions
    }
  end

  defp service_statuses do
    %{
      activity_log: alive?(LemmingsOs.Runtime.ActivityLog),
      runtime_table_owner: alive?(LemmingsOs.LemmingInstances.RuntimeTableOwner),
      executor_supervisor: alive?(LemmingsOs.LemmingInstances.ExecutorSupervisor),
      pool_supervisor: alive?(LemmingsOs.LemmingInstances.PoolSupervisor),
      scheduler_supervisor: alive?(LemmingsOs.LemmingInstances.SchedulerSupervisor),
      executor_registry: registry_alive?(LemmingsOs.LemmingInstances.ExecutorRegistry),
      scheduler_registry: registry_alive?(LemmingsOs.LemmingInstances.SchedulerRegistry),
      pool_registry: registry_alive?(LemmingsOs.LemmingInstances.PoolRegistry)
    }
  end

  defp persisted_instance_counts do
    counts =
      try do
        LemmingInstance
        |> group_by([instance], instance.status)
        |> select([instance], {instance.status, count(instance.id)})
        |> Repo.all()
        |> Map.new()
      rescue
        _ -> %{}
      end

    Enum.reduce(@statuses, %{total: 0}, fn status, acc ->
      count = Map.get(counts, status, 0)
      acc |> Map.put(String.to_atom(status), count) |> Map.update!(:total, &(&1 + count))
    end)
  end

  defp active_process_counts do
    %{
      executors: registry_count(LemmingsOs.LemmingInstances.ExecutorRegistry),
      schedulers: registry_count(LemmingsOs.LemmingInstances.SchedulerRegistry),
      pools: registry_count(LemmingsOs.LemmingInstances.PoolRegistry)
    }
  end

  defp alerts(false, _services, _persisted_instances, _active_processes) do
    [
      %{
        severity: "error",
        code: "runtime_engine_disabled",
        summary: "Runtime engine startup is disabled.",
        detail: "Executors and schedulers are not attached automatically on boot.",
        action_hint: "Enable :runtime_engine_on_startup or start the runtime children manually."
      }
    ]
  end

  defp alerts(true, services, persisted_instances, active_processes) do
    []
    |> maybe_add_missing_service_alert(services)
    |> maybe_add_orphaned_runtime_alert(persisted_instances, active_processes)
    |> maybe_add_failed_instances_alert(persisted_instances)
  end

  defp maybe_add_missing_service_alert(alerts, services) do
    missing =
      services
      |> Enum.filter(fn {_service, alive?} -> alive? == false end)
      |> Enum.map(fn {service, _alive?} -> service end)

    if missing == [] do
      alerts
    else
      [
        %{
          severity: "error",
          code: "runtime_services_missing",
          summary: "Runtime infrastructure is incomplete.",
          detail: "Missing services: #{Enum.map_join(missing, ", ", &to_string/1)}",
          action_hint: "Check the runtime supervisors and registries."
        }
        | alerts
      ]
    end
  end

  defp maybe_add_orphaned_runtime_alert(alerts, persisted_instances, active_processes) do
    expected =
      persisted_instances.created + persisted_instances.queued + persisted_instances.processing +
        persisted_instances.retrying + persisted_instances.idle

    if expected > 0 and active_processes.executors < expected do
      [
        %{
          severity: "warning",
          code: "runtime_executor_gap",
          summary: "Some persisted instances are not attached to executors.",
          detail:
            "Recoverable instances: #{expected}. Running executors: #{active_processes.executors}.",
          action_hint: "Check recovery logs and restart the runtime engine if needed."
        }
        | alerts
      ]
    else
      alerts
    end
  end

  defp maybe_add_failed_instances_alert(alerts, %{failed: failed}) when failed > 0 do
    [
      %{
        severity: "warning",
        code: "runtime_failed_instances",
        summary: "There are failed runtime instances.",
        detail: "#{failed} instance(s) are in failed state.",
        action_hint: "Inspect the logs feed and affected instance pages."
      }
      | alerts
    ]
  end

  defp maybe_add_failed_instances_alert(alerts, _persisted_instances), do: alerts

  defp service_rows(services) do
    services
    |> Enum.map(fn {service, up?} ->
      %{
        id: service,
        label: service |> Atom.to_string() |> String.replace("_", " "),
        up?: up?,
        pid: named_pid_string(service_name(service))
      }
    end)
    |> Enum.sort_by(&Atom.to_string(&1.id))
  end

  defp executor_snapshots do
    registry_entries(LemmingsOs.LemmingInstances.ExecutorRegistry)
    |> Enum.map(fn {instance_id, pid} ->
      pid
      |> safe_runtime_call(&Executor.snapshot/1, %{})
      |> Map.merge(%{
        instance_id: instance_id,
        pid: inspect(pid),
        alive?: Process.alive?(pid)
      })
    end)
    |> Enum.sort_by(& &1.instance_id)
  end

  defp scheduler_snapshots(department_labels) do
    registry_entries(LemmingsOs.LemmingInstances.SchedulerRegistry)
    |> Enum.map(fn {department_id, pid} ->
      pid
      |> safe_runtime_call(&DepartmentScheduler.snapshot/1, %{})
      |> Map.merge(%{
        department_id: department_id,
        department_label: Map.get(department_labels, department_id, department_id),
        pid: inspect(pid),
        alive?: Process.alive?(pid)
      })
    end)
    |> Enum.sort_by(& &1.department_id)
  end

  defp pool_snapshots do
    registry_entries(LemmingsOs.LemmingInstances.PoolRegistry)
    |> Enum.map(fn {resource_key, pid} ->
      pid
      |> safe_runtime_call(&ResourcePool.snapshot/1, %{})
      |> Map.merge(%{
        resource_key: resource_key,
        pid: inspect(pid),
        alive?: Process.alive?(pid)
      })
    end)
    |> Enum.sort_by(& &1.resource_key)
  end

  defp runtime_entries(executors) do
    executor_index = Map.new(executors, &{&1.instance_id, &1})

    EtsStore.list_all()
    |> Enum.map(fn {instance_id, state} ->
      executor = Map.get(executor_index, instance_id)
      queue_depth = queue_depth(state.queue)

      %{
        instance_id: instance_id,
        department_id: state.department_id,
        status: state.status |> to_string(),
        queue_depth: queue_depth,
        current_item_id: current_item_id(state.current_item),
        resource_key: state.resource_key,
        retry_count: state.retry_count,
        max_retries: state.max_retries,
        last_error: state.last_error,
        internal_error_details: Map.get(state, :internal_error_details),
        started_at: state.started_at,
        last_activity_at: state.last_activity_at,
        executor_alive?: not is_nil(executor),
        executor_pid: executor && executor.pid
      }
    end)
    |> Enum.sort_by(fn entry -> {entry.department_id || "", entry.instance_id} end)
  rescue
    _ -> []
  end

  defp attach_executor_labels(executors, instance_labels) do
    Enum.map(executors, fn executor ->
      labels = Map.get(instance_labels, executor.instance_id, %{})

      executor
      |> Map.put(:display_label, Map.get(labels, :display_label, executor.instance_id))
      |> Map.put(:department_label, Map.get(labels, :department_label, executor.department_id))
    end)
  end

  defp attach_runtime_entry_labels(runtime_entries, instance_labels) do
    Enum.map(runtime_entries, fn entry ->
      labels = Map.get(instance_labels, entry.instance_id, %{})

      entry
      |> Map.put(:display_label, Map.get(labels, :display_label, entry.instance_id))
      |> Map.put(:department_label, Map.get(labels, :department_label, entry.department_id))
    end)
  end

  defp attach_tool_execution_labels(tool_executions, instance_labels) do
    Enum.map(tool_executions, fn tool_execution ->
      labels = Map.get(instance_labels, tool_execution.instance_id, %{})

      tool_execution
      |> Map.put(:display_label, Map.get(labels, :display_label, tool_execution.instance_id))
      |> Map.put(
        :department_label,
        Map.get(labels, :department_label, tool_execution.department_id)
      )
    end)
  end

  defp runtime_labels(executors, runtime_entries) do
    instance_ids =
      executors
      |> Enum.map(& &1.instance_id)
      |> Kernel.++(Enum.map(runtime_entries, & &1.instance_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    department_ids =
      executors
      |> Enum.map(& &1.department_id)
      |> Kernel.++(Enum.map(runtime_entries, & &1.department_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %{
      instance_labels: instance_labels(instance_ids),
      department_labels: department_labels(department_ids)
    }
  end

  defp instance_labels([]), do: %{}

  defp instance_labels(instance_ids) do
    LemmingInstance
    |> where([instance], instance.id in ^instance_ids)
    |> preload([:lemming, :department])
    |> Repo.all()
    |> Map.new(fn instance ->
      {instance.id,
       %{
         display_label: instance_display_label(instance),
         department_label: instance_department_label(instance)
       }}
    end)
  rescue
    _ -> %{}
  end

  defp department_labels([]), do: %{}

  defp department_labels(department_ids) do
    Department
    |> where([department], department.id in ^department_ids)
    |> Repo.all()
    |> Map.new(fn department ->
      label =
        cond do
          is_binary(department.slug) and department.slug != "" -> department.slug
          is_binary(department.name) and department.name != "" -> department.name
          true -> department.id
        end

      {department.id, label}
    end)
  rescue
    _ -> %{}
  end

  defp alive?(name) when is_atom(name), do: is_pid(Process.whereis(name))

  defp registry_alive?(registry), do: is_pid(Process.whereis(registry))

  defp registry_count(registry) do
    if Code.ensure_loaded?(Registry) and Process.whereis(registry) do
      registry |> Registry.count() |> Kernel.max(0)
    else
      0
    end
  rescue
    _ -> 0
  end

  defp registry_entries(registry) do
    if Code.ensure_loaded?(Registry) and Process.whereis(registry) do
      Registry.select(registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.map(fn {key, pid} -> {normalize_registry_key(key), pid} end)
    else
      []
    end
  rescue
    _ -> []
  end

  defp safe_runtime_call(pid, fun, fallback) when is_pid(pid) do
    fun.(pid)
  rescue
    _ -> fallback
  catch
    :exit, _reason -> fallback
  end

  defp service_name(:activity_log), do: LemmingsOs.Runtime.ActivityLog
  defp service_name(:runtime_table_owner), do: LemmingsOs.LemmingInstances.RuntimeTableOwner
  defp service_name(:executor_supervisor), do: LemmingsOs.LemmingInstances.ExecutorSupervisor
  defp service_name(:pool_supervisor), do: LemmingsOs.LemmingInstances.PoolSupervisor
  defp service_name(:scheduler_supervisor), do: LemmingsOs.LemmingInstances.SchedulerSupervisor
  defp service_name(:executor_registry), do: LemmingsOs.LemmingInstances.ExecutorRegistry
  defp service_name(:scheduler_registry), do: LemmingsOs.LemmingInstances.SchedulerRegistry
  defp service_name(:pool_registry), do: LemmingsOs.LemmingInstances.PoolRegistry

  defp named_pid_string(name) when is_atom(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) -> inspect(pid)
      _ -> "-"
    end
  end

  defp queue_depth(queue), do: queue |> :queue.len() |> Kernel.max(0)

  defp current_item_id(%{id: id}) when is_binary(id), do: id
  defp current_item_id(_item), do: nil

  defp normalize_registry_key({key}) when is_binary(key), do: key
  defp normalize_registry_key(key) when is_binary(key), do: key
  defp normalize_registry_key(other), do: other

  defp latest_first(entries) do
    Enum.sort_by(entries, &latest_sort_value/1, {:desc, DateTime})
  end

  defp latest_sort_value(%{last_activity_at: %DateTime{} = value}), do: value
  defp latest_sort_value(%{started_at: %DateTime{} = value}), do: value
  defp latest_sort_value(_entry), do: ~U[1970-01-01 00:00:00Z]

  defp recent_tool_executions(limit) do
    query =
      ToolExecution
      |> join(:inner, [tool_execution], instance in LemmingInstance,
        on: tool_execution.lemming_instance_id == instance.id
      )
      |> order_by([tool_execution, _instance], desc: tool_execution.inserted_at)
      |> order_by([tool_execution, _instance], desc: tool_execution.id)
      |> maybe_limit_tool_execution_query(limit)
      |> select([tool_execution, instance], %{
        id: tool_execution.id,
        instance_id: tool_execution.lemming_instance_id,
        department_id: instance.department_id,
        tool_name: tool_execution.tool_name,
        status: tool_execution.status,
        summary: tool_execution.summary,
        duration_ms: tool_execution.duration_ms,
        started_at: tool_execution.started_at,
        completed_at: tool_execution.completed_at,
        inserted_at: tool_execution.inserted_at
      })

    Repo.all(query)
  rescue
    _ -> []
  end

  defp maybe_limit_tool_execution_query(query, limit) when is_integer(limit) and limit >= 0 do
    limit(query, ^limit)
  end

  defp maybe_limit_tool_execution_query(query, _limit), do: query

  defp maybe_take(entries, limit) when is_integer(limit) and limit >= 0,
    do: Enum.take(entries, limit)

  defp maybe_take(entries, _limit), do: entries

  defp instance_display_label(%{lemming: %Lemming{} = lemming, id: instance_id}) do
    slug_or_name(lemming) || instance_id
  end

  defp instance_display_label(%{id: instance_id}), do: instance_id

  defp instance_department_label(%{
         department: %Department{} = department,
         department_id: department_id
       }) do
    slug_or_name(department) || department_id
  end

  defp instance_department_label(%{department_id: department_id}), do: department_id

  defp slug_or_name(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  defp slug_or_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp slug_or_name(_struct), do: nil
end
