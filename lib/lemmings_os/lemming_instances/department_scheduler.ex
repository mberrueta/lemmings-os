defmodule LemmingsOs.LemmingInstances.DepartmentScheduler do
  @moduledoc """
  Per-department runtime scheduler for spawned lemming instances.

  The scheduler is intentionally small: it watches the department PubSub topic,
  asks the ETS runtime store for queued instances, requests pool capacity by
  resource key, and then grants admission to executors. It does not execute
  work itself and it does not own queue state.

  The v1 selection policy is oldest eligible first. The selection policy is
  kept as an explicit seam so later dependency-aware scheduling can plug in
  without changing the scheduler entrypoints.
  """

  use GenServer

  require Logger

  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.LemmingInstances.Executor
  @default_pubsub_mod Phoenix.PubSub
  @default_pubsub_name LemmingsOs.PubSub
  @default_context_mod LemmingsOs.LemmingInstances
  @default_pool_mod LemmingsOs.LemmingInstances.ResourcePool
  @default_ets_mod LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.Telemetry

  @type admission_mode :: :auto | :manual
  @type selection_policy :: ([map()] -> [map()])

  @type state :: %{
          department_id: binary(),
          admission_mode: admission_mode(),
          selection_policy: selection_policy(),
          context_mod: module(),
          pool_mod: module(),
          ets_mod: module(),
          pubsub_mod: module() | nil,
          pubsub_name: atom() | nil
        }

  @doc """
  Returns the Registry name tuple for a department scheduler process.

  ## Examples

      iex> LemmingsOs.LemmingInstances.DepartmentScheduler.via_name("dept-1")
      {:via, Registry, {LemmingsOs.LemmingInstances.SchedulerRegistry, "dept-1"}}
  """
  @spec via_name(binary()) :: {:via, Registry, {module(), binary()}}
  def via_name(department_id) when is_binary(department_id) do
    {:via, Registry, {LemmingsOs.LemmingInstances.SchedulerRegistry, department_id}}
  end

  @doc """
  Starts a scheduler process for the given department.

  Pass `name: nil` to skip Registry naming in tests.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.DepartmentScheduler.start_link(
      ...>     department_id: "dept-1",
      ...>     pubsub_mod: nil,
      ...>     pool_mod: nil,
      ...>     ets_mod: nil,
      ...>     context_mod: nil,
      ...>     name: nil
      ...>   )
      iex> is_pid(pid)
      true
      iex> GenServer.stop(pid)
      :ok
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    department_id = Keyword.get(opts, :department_id)

    genserver_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, nil} ->
          []

        {:ok, name} ->
          [name: name]

        :error ->
          case department_id do
            department_id when is_binary(department_id) -> [name: via_name(department_id)]
            _ -> []
          end
      end

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @doc """
  Builds a DynamicSupervisor-compatible child spec.

  ## Examples

      iex> spec = LemmingsOs.LemmingInstances.DepartmentScheduler.child_spec(department_id: "dept-2")
      iex> {mod, _fun, _args} = spec.start
      iex> mod == LemmingsOs.LemmingInstances.DepartmentScheduler
      true
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    department_id = Keyword.get(opts, :department_id)

    id =
      case department_id do
        department_id when is_binary(department_id) -> {__MODULE__, department_id}
        _ -> __MODULE__
      end

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Manually admits the next eligible instance.

  This is the testability gate. In `:manual` mode, PubSub signals are ignored
  and tests drive admission explicitly with this call.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.DepartmentScheduler.start_link(
      ...>     department_id: "dept-3",
      ...>     admission_mode: :manual,
      ...>     pubsub_mod: nil,
      ...>     pool_mod: nil,
      ...>     ets_mod: nil,
      ...>     context_mod: nil,
      ...>     name: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.DepartmentScheduler.admit_next(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec admit_next(GenServer.server() | binary()) :: :ok
  def admit_next(server) do
    GenServer.call(normalize_server(server), :admit_next)
  end

  @doc """
  Returns an operator-facing snapshot for scheduler inspection.
  """
  @spec snapshot(GenServer.server() | binary()) :: map()
  def snapshot(server) do
    GenServer.call(normalize_server(server), :snapshot)
  end

  @doc false
  @spec oldest_eligible_first([map()]) :: [map()]
  def oldest_eligible_first(candidates) when is_list(candidates) do
    Enum.sort_by(candidates, fn candidate ->
      {queued_item_rank(candidate), queued_item_unix(candidate), candidate_sort_key(candidate)}
    end)
  end

  @impl true
  def init(opts) do
    department_id = Keyword.get(opts, :department_id)

    if is_binary(department_id) do
      state = %{
        department_id: department_id,
        admission_mode: admission_mode(Keyword.get(opts, :admission_mode, :auto)),
        selection_policy:
          Keyword.get(opts, :selection_policy, &__MODULE__.oldest_eligible_first/1),
        context_mod: Keyword.get(opts, :context_mod, @default_context_mod),
        pool_mod: Keyword.get(opts, :pool_mod, @default_pool_mod),
        ets_mod: Keyword.get(opts, :ets_mod, @default_ets_mod),
        pubsub_mod: Keyword.get(opts, :pubsub_mod, @default_pubsub_mod),
        pubsub_name: Keyword.get(opts, :pubsub_name, @default_pubsub_name)
      }

      state = subscribe_scheduler_topic(state)

      Logger.info("scheduler started",
        event: "instance.scheduler.started",
        world_id: nil,
        city_id: nil,
        lemming_id: nil,
        instance_id: nil,
        resource_key: nil,
        department_id: department_id,
        admission_mode: state.admission_mode
      )

      {:ok, state}
    else
      {:stop, :missing_department_id}
    end
  end

  @impl true
  def handle_call(:admit_next, _from, state) do
    _ = admit_candidates(state, 1)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    queued_instances = fetch_candidates(state)

    snapshot = %{
      department_id: state.department_id,
      admission_mode: state.admission_mode,
      queued_count: length(queued_instances),
      queued_instance_ids: Enum.map(queued_instances, & &1.instance_id)
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_info({:scheduler_admit, _payload}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:work_available, _payload}, %{admission_mode: :auto} = state) do
    _ = admit_candidates(state, :unbounded)
    {:noreply, state}
  end

  @impl true
  def handle_info({:capacity_released, _payload}, %{admission_mode: :auto} = state) do
    _ = admit_candidates(state, :unbounded)
    {:noreply, state}
  end

  @impl true
  def handle_info(%{instance_id: _} = _payload, %{admission_mode: :auto} = state) do
    _ = admit_candidates(state, :unbounded)
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp admit_candidates(%{admission_mode: :manual} = state, _limit) do
    admit_candidates_for_state(state, 1)
  end

  defp admit_candidates(state, limit) do
    admit_candidates_for_state(state, limit)
  end

  defp admit_candidates_for_state(state, limit) do
    state
    |> fetch_candidates()
    |> apply_selection_policy(state.selection_policy)
    |> Enum.reduce_while(0, fn candidate, admitted_count ->
      admit_candidate_step(candidate, state, limit, admitted_count)
    end)
  end

  defp admit_candidate_step(candidate, state, limit, admitted_count) do
    if limit_reached?(limit, admitted_count) do
      {:halt, admitted_count}
    else
      case admit_candidate(candidate, state) do
        :admitted -> {:cont, admitted_count + 1}
        :at_capacity -> {:halt, admitted_count}
        :skip -> {:cont, admitted_count}
      end
    end
  end

  defp fetch_candidates(%{ets_mod: ets_mod, department_id: department_id} = state)
       when is_atom(ets_mod) and is_binary(department_id) do
    ets_candidates =
      if function_exported?(ets_mod, :list_by_status, 2) do
        case ets_mod.list_by_status(:queued, department_id) do
          {:ok, entries} when is_list(entries) -> normalize_candidates(entries)
          entries when is_list(entries) -> normalize_candidates(entries)
          _ -> []
        end
      else
        []
      end

    fallback_candidates = executor_fallback_candidates(state, ets_candidates)

    ets_candidates ++ fallback_candidates
  end

  defp fetch_candidates(_state), do: []

  defp executor_fallback_candidates(state, ets_candidates) do
    queued_instance_ids = MapSet.new(Enum.map(ets_candidates, & &1.instance_id))

    Registry.select(LemmingsOs.LemmingInstances.ExecutorRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.reject(fn {instance_id, _pid} -> MapSet.member?(queued_instance_ids, instance_id) end)
    |> Enum.map(fn {instance_id, pid} -> fallback_executor_candidate(instance_id, pid, state) end)
    |> Enum.reject(fn
      nil -> true
      _candidate -> false
    end)
  rescue
    _ -> []
  end

  defp fallback_executor_candidate(instance_id, pid, state)
       when is_binary(instance_id) and is_pid(pid) do
    case safe_executor_snapshot(pid) do
      %{
        instance_id: ^instance_id,
        department_id: department_id,
        status: "queued",
        queue_depth: queue_depth,
        current_item_id: nil
      } = snapshot
      when department_id == state.department_id and queue_depth > 0 ->
        %{
          instance_id: instance_id,
          department_id: department_id,
          world_id: Map.get(snapshot, :world_id),
          city_id: Map.get(snapshot, :city_id),
          lemming_id: Map.get(snapshot, :lemming_id),
          queue: :queue.new(),
          work_item: fallback_work_item(snapshot),
          current_item: nil,
          config_snapshot: nil,
          resource_key: Map.get(snapshot, :resource_key)
        }

      _other ->
        nil
    end
  end

  defp fallback_executor_candidate(_instance_id, _pid, _state), do: nil

  defp fallback_work_item(snapshot) do
    %{
      id: Map.get(snapshot, :current_item_id) || "queued-work",
      inserted_at: Map.get(snapshot, :last_activity_at) || Map.get(snapshot, :started_at)
    }
  end

  defp safe_executor_snapshot(pid) when is_pid(pid) do
    Executor.snapshot(pid)
  rescue
    _ -> %{}
  catch
    :exit, _reason -> %{}
  end

  defp normalize_candidates(entries) do
    entries
    |> Enum.map(&normalize_candidate/1)
    |> Enum.reject(&is_nil(candidate_work_item(&1)))
  end

  defp normalize_candidate({instance_id, state}) when is_binary(instance_id) and is_map(state) do
    normalize_candidate(Map.put_new(state, :instance_id, instance_id))
  end

  defp normalize_candidate(%{instance_id: instance_id} = state) when is_binary(instance_id) do
    %{
      instance_id: instance_id,
      department_id: fetch_map_value(state, :department_id),
      world_id: fetch_map_value(state, :world_id),
      city_id: fetch_map_value(state, :city_id),
      lemming_id: fetch_map_value(state, :lemming_id),
      queue: fetch_map_value(state, :queue),
      work_item: queued_item(state),
      current_item: fetch_map_value(state, :current_item),
      config_snapshot: fetch_map_value(state, :config_snapshot),
      resource_key: fetch_map_value(state, :resource_key)
    }
  end

  defp normalize_candidate(%{id: instance_id} = state) when is_binary(instance_id) do
    normalize_candidate(Map.put_new(state, :instance_id, instance_id))
  end

  defp normalize_candidate(_candidate), do: nil

  defp apply_selection_policy(candidates, selection_policy)
       when is_function(selection_policy, 1) do
    selection_policy.(candidates)
  end

  defp apply_selection_policy(candidates, _selection_policy),
    do: oldest_eligible_first(candidates)

  defp admit_candidate(candidate, state) do
    with {:ok, resource_key} <- resolve_resource_key(candidate, state),
         {:ok, executor_pid} <- resolve_executor_pid(candidate.instance_id),
         :ok <- checkout_pool(state, resource_key, executor_pid) do
      Logger.info("scheduler admitted instance",
        event: "instance.scheduler.admit",
        world_id: Map.get(candidate, :world_id),
        city_id: Map.get(candidate, :city_id),
        lemming_id: Map.get(candidate, :lemming_id),
        department_id: state.department_id,
        instance_id: candidate.instance_id,
        resource_key: resource_key,
        executor_pid: inspect(executor_pid)
      )

      _ =
        Telemetry.execute(
          [:lemmings_os, :scheduler, :admission_granted],
          %{count: 1},
          Telemetry.candidate_metadata(candidate, %{
            department_id: state.department_id,
            instance_id: candidate.instance_id,
            resource_key: resource_key
          })
        )

      broadcast_admission(state, candidate, resource_key)
      :admitted
    else
      {:error, :at_capacity} ->
        log_admission_denied(candidate, state, :at_capacity)
        :at_capacity

      {:error, :missing_resource_key} ->
        :skip

      {:error, :executor_unavailable} ->
        :skip

      {:error, _reason} ->
        :skip
    end
  end

  defp resolve_resource_key(%{resource_key: resource_key}, _state) when is_binary(resource_key),
    do: {:ok, resource_key}

  defp resolve_resource_key(candidate, state) do
    case candidate_config_snapshot(candidate, state) do
      {:ok, config_snapshot} ->
        case ConfigSnapshot.resource_key(config_snapshot) do
          nil -> {:error, :missing_resource_key}
          resource_key -> {:ok, resource_key}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp candidate_config_snapshot(%{config_snapshot: config_snapshot}, _state)
       when is_map(config_snapshot),
       do: {:ok, config_snapshot}

  defp candidate_config_snapshot(%{world_id: world_id, instance_id: instance_id}, state)
       when is_binary(world_id) and is_binary(instance_id) do
    fetch_instance_config_snapshot(state.context_mod, instance_id, world_id)
  end

  defp candidate_config_snapshot(%{instance_id: instance_id}, state)
       when is_binary(instance_id) do
    fetch_instance_config_snapshot(state.context_mod, instance_id, nil)
  end

  defp candidate_config_snapshot(_candidate, _state), do: {:error, :missing_config_snapshot}

  defp fetch_instance_config_snapshot(context_mod, instance_id, world_id)
       when is_binary(instance_id) do
    case context_mod do
      nil ->
        {:error, :context_lookup_unavailable}

      mod ->
        opts = world_scope_opts(world_id)

        case apply(mod, :get_instance, [instance_id, opts]) do
          {:ok, instance} -> instance_config_snapshot(instance)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp instance_config_snapshot(instance) do
    case fetch_map_value(instance, :config_snapshot) do
      config_snapshot when is_map(config_snapshot) -> {:ok, config_snapshot}
      _ -> {:error, :missing_config_snapshot}
    end
  end

  defp world_scope_opts(world_id) when is_binary(world_id), do: [world_id: world_id]
  defp world_scope_opts(_world_id), do: []

  defp checkout_pool(
         %{pool_mod: pool_mod, department_id: department_id},
         resource_key,
         executor_pid
       )
       when is_binary(resource_key) and is_pid(executor_pid) do
    case pool_mod do
      nil ->
        :ok

      mod ->
        case apply(mod, :checkout, [
               resource_key,
               [holder: executor_pid, department_id: department_id]
             ]) do
          :ok -> :ok
          {:error, :at_capacity} -> {:error, :at_capacity}
          {:error, reason} -> {:error, reason}
          other -> {:error, other}
        end
    end
  end

  defp broadcast_admission(state, candidate, resource_key) do
    PubSub.broadcast_scheduler_admit(state.department_id, candidate.instance_id, resource_key)
  end

  defp log_admission_denied(candidate, state, reason) do
    reason_token = Telemetry.reason_token(reason)

    Logger.warning("scheduler admission denied",
      event: "instance.scheduler.admission_denied",
      world_id: Map.get(candidate, :world_id),
      city_id: Map.get(candidate, :city_id),
      lemming_id: Map.get(candidate, :lemming_id),
      department_id: state.department_id,
      instance_id: Map.get(candidate, :instance_id),
      resource_key: Map.get(candidate, :resource_key),
      reason: reason_token
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :scheduler, :admission_denied],
        %{count: 1},
        Telemetry.candidate_metadata(candidate, %{
          department_id: state.department_id,
          instance_id: Map.get(candidate, :instance_id),
          resource_key: Map.get(candidate, :resource_key),
          reason: reason_token
        })
      )
  end

  defp subscribe_scheduler_topic(state) do
    _ = PubSub.subscribe_scheduler(state.department_id)
    _ = PubSub.subscribe_capacity()

    state
  end

  defp resolve_executor_pid(instance_id) when is_binary(instance_id) do
    case Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance_id) do
      [{pid, _value}] when is_pid(pid) -> {:ok, pid}
      _ -> {:error, :executor_unavailable}
    end
  end

  defp limit_reached?(:unbounded, _count), do: false
  defp limit_reached?(limit, count) when is_integer(limit), do: count >= limit

  defp queued_item(%{work_item: %{} = work_item}), do: work_item

  defp queued_item(%{queue: queue}) when is_nil(queue), do: nil

  defp queued_item(%{queue: queue}) when is_list(queue) do
    List.first(queue)
  end

  defp queued_item(%{queue: queue}) do
    queue
    |> queue_to_list()
    |> List.first()
  end

  defp queued_item(_state), do: nil

  defp candidate_work_item(%{work_item: work_item}), do: work_item
  defp candidate_work_item(_candidate), do: nil

  defp queue_to_list(queue) do
    :queue.to_list(queue)
  end

  defp queued_item_rank(%{work_item: %{inserted_at: %DateTime{}}}), do: 0

  defp queued_item_rank(%{queue: queue}) do
    case queued_item(%{queue: queue}) do
      %{inserted_at: %DateTime{}} -> 0
      _ -> 1
    end
  end

  defp queued_item_rank(_candidate), do: 1

  defp queued_item_unix(%{work_item: %{inserted_at: %DateTime{} = inserted_at}}),
    do: DateTime.to_unix(inserted_at, :microsecond)

  defp queued_item_unix(%{queue: queue}) do
    case queued_item(%{queue: queue}) do
      %{inserted_at: %DateTime{} = inserted_at} -> DateTime.to_unix(inserted_at, :microsecond)
      _ -> max_unix_value()
    end
  end

  defp queued_item_unix(_candidate), do: max_unix_value()

  defp candidate_sort_key(%{instance_id: instance_id}) when is_binary(instance_id),
    do: instance_id

  defp candidate_sort_key(_candidate), do: ""

  defp max_unix_value, do: 253_402_300_799_000_000

  defp fetch_map_value(%{} = map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      true -> nil
    end
  end

  defp normalize_server(server) when is_binary(server), do: via_name(server)
  defp normalize_server(server), do: server

  defp admission_mode(:auto), do: :auto
  defp admission_mode(:manual), do: :manual
  defp admission_mode(_other), do: :auto
end
