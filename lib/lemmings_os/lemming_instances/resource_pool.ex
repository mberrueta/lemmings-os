defmodule LemmingsOs.LemmingInstances.ResourcePool do
  @moduledoc """
  Counter-based semaphore for scarce model resources.

  The pool is keyed by resource key, not by Department or City. It keeps only
  the current token count, the configured maximum, a simple gate for tests,
  and monitors for active holders so crashed callers release capacity.

  The notification seam is intentionally small: on release, the pool can emit a
  capacity-released PubSub message on a resource-scoped topic. The scheduler
  can use that seam later without changing the checkout/checkin API.
  """

  use GenServer

  require Logger

  alias LemmingsOs.LemmingInstances.Telemetry

  @default_capacity 1
  @default_pubsub_mod Phoenix.PubSub
  @default_pubsub_name LemmingsOs.PubSub
  @default_pool_supervisor LemmingsOs.LemmingInstances.PoolSupervisor

  @type gate :: :open | :closed
  @type holder :: pid() | nil
  @type state :: %{
          resource_key: binary(),
          current: non_neg_integer(),
          max: pos_integer(),
          gate: gate(),
          holders: %{reference() => %{pid: pid(), department_id: binary() | nil}},
          pubsub_mod: module() | nil,
          pubsub_name: atom() | nil
        }

  @doc """
  Returns the Registry name tuple for a resource pool process.

  ## Examples

      iex> LemmingsOs.LemmingInstances.ResourcePool.via_name("ollama:llama3.2")
      {:via, Registry, {LemmingsOs.LemmingInstances.PoolRegistry, "ollama:llama3.2"}}
  """
  @spec via_name(binary()) :: {:via, Registry, {module(), binary()}}
  def via_name(resource_key) when is_binary(resource_key) do
    {:via, Registry, {LemmingsOs.LemmingInstances.PoolRegistry, resource_key}}
  end

  @doc """
  Starts a resource pool for the given resource key.

  The pool can be started with a Registry name or with `name: nil` for an
  isolated supervised test instance.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> is_pid(pid)
      true
      iex> GenServer.stop(pid)
      :ok
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    resource_key = Keyword.get(opts, :resource_key)

    genserver_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, nil} ->
          []

        {:ok, name} ->
          [name: name]

        :error ->
          case resource_key do
            resource_key when is_binary(resource_key) -> [name: via_name(resource_key)]
            _ -> []
          end
      end

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @doc """
  Builds a DynamicSupervisor-compatible child spec.

  ## Examples

      iex> spec = LemmingsOs.LemmingInstances.ResourcePool.child_spec(resource_key: "ollama:llama3.2")
      iex> {mod, _fun, _args} = spec.start
      iex> mod == LemmingsOs.LemmingInstances.ResourcePool
      true
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    resource_key = Keyword.get(opts, :resource_key)

    %{
      id: if(is_binary(resource_key), do: {__MODULE__, resource_key}, else: __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Requests a pool token for the given resource key or server.

  Returns `:ok` when capacity is available, otherwise `{:error, :at_capacity}`.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.ResourcePool.checkout(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec checkout(GenServer.server() | binary(), keyword()) ::
          :ok | {:error, :at_capacity | term()}
  def checkout(server_or_resource_key, opts \\ []) when is_list(opts) do
    server_or_resource_key
    |> ensure_started()
    |> case do
      {:ok, server} ->
        GenServer.call(
          server,
          {:checkout, checkout_holder(opts), Keyword.get(opts, :department_id)}
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Releases one pool token for the given resource key or server.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> :ok = LemmingsOs.LemmingInstances.ResourcePool.checkout(pid)
      iex> LemmingsOs.LemmingInstances.ResourcePool.checkin(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec checkin(GenServer.server() | binary(), holder()) :: :ok
  def checkin(server_or_resource_key, holder \\ self()) do
    case lookup_server(server_or_resource_key) do
      {:ok, server} ->
        _ = GenServer.call(server, {:checkin, holder_pid(holder)})
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @doc """
  Returns the current and maximum token counts.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.ResourcePool.status(pid)
      {0, 1}
      iex> GenServer.stop(pid)
      :ok
  """
  @spec status(GenServer.server() | binary()) :: {non_neg_integer(), pos_integer()}
  def status(server_or_resource_key) do
    case lookup_server(server_or_resource_key) do
      {:ok, server} -> GenServer.call(server, :status)
      {:error, _reason} -> {0, default_capacity()}
    end
  end

  @doc """
  Returns an operator-facing snapshot for pool inspection.
  """
  @spec snapshot(GenServer.server() | binary()) :: map()
  def snapshot(server_or_resource_key) do
    case lookup_server(server_or_resource_key) do
      {:ok, server} ->
        GenServer.call(server, :snapshot)

      {:error, _reason} ->
        %{
          resource_key: extract_resource_key(server_or_resource_key),
          current: 0,
          max: default_capacity(),
          gate: :open,
          available?: true,
          holders_count: 0,
          holder_department_ids: []
        }
    end
  end

  @doc """
  Returns whether a token is currently available.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.ResourcePool.available?(pid)
      true
      iex> GenServer.stop(pid)
      :ok
  """
  @spec available?(GenServer.server() | binary()) :: boolean()
  def available?(server_or_resource_key) do
    case lookup_server(server_or_resource_key) do
      {:ok, server} -> GenServer.call(server, :available?)
      {:error, _reason} -> default_capacity() > 0
    end
  end

  @doc """
  Opens the test gate and allows checkouts.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     gate: :closed,
      ...>     pubsub_mod: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.ResourcePool.open_gate(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec open_gate(GenServer.server() | binary()) :: :ok
  def open_gate(server_or_resource_key) do
    case ensure_started(server_or_resource_key) do
      {:ok, server} ->
        _ = GenServer.call(server, :open_gate)
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @doc """
  Closes the test gate and blocks new checkouts.

  ## Examples

      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.ResourcePool.start_link(
      ...>     resource_key: "ollama:llama3.2",
      ...>     name: nil,
      ...>     pubsub_mod: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.ResourcePool.close_gate(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec close_gate(GenServer.server() | binary()) :: :ok
  def close_gate(server_or_resource_key) do
    case ensure_started(server_or_resource_key) do
      {:ok, server} ->
        _ = GenServer.call(server, :close_gate)
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  @impl true
  def init(opts) do
    resource_key = Keyword.get(opts, :resource_key)

    if is_binary(resource_key) do
      state = %{
        resource_key: resource_key,
        current: 0,
        max: max_capacity(opts),
        gate: gate_mode(opts),
        holders: %{},
        pubsub_mod: Keyword.get(opts, :pubsub_mod, @default_pubsub_mod),
        pubsub_name: Keyword.get(opts, :pubsub_name, @default_pubsub_name)
      }

      Logger.info("resource pool started",
        event: "instance.pool.started",
        world_id: nil,
        city_id: nil,
        department_id: nil,
        lemming_id: nil,
        instance_id: nil,
        resource_key: resource_key,
        pool_current: 0,
        pool_max: state.max
      )

      {:ok, state}
    else
      {:stop, :missing_resource_key}
    end
  end

  @impl true
  def handle_call({:checkout, holder_pid, department_id}, _from, state)
      when is_pid(holder_pid) do
    if state.gate == :closed or state.current >= state.max do
      reason = Telemetry.reason_token(:at_capacity)

      Logger.warning("resource pool checkout denied",
        event: "instance.pool.exhausted",
        world_id: nil,
        city_id: nil,
        department_id: department_id,
        lemming_id: nil,
        instance_id: nil,
        resource_key: state.resource_key,
        reason: reason,
        pool_current: state.current,
        pool_max: state.max
      )

      _ =
        Telemetry.execute(
          [:lemmings_os, :pool, :exhausted],
          %{count: 1},
          Telemetry.pool_metadata(%{
            department_id: department_id,
            resource_key: state.resource_key,
            pool_current: state.current,
            pool_max: state.max,
            reason: reason
          })
        )

      {:reply, {:error, :at_capacity}, state}
    else
      monitor_ref = Process.monitor(holder_pid)

      state = %{
        state
        | current: state.current + 1,
          holders:
            Map.put(state.holders, monitor_ref, %{pid: holder_pid, department_id: department_id})
      }

      Logger.info("resource pool checkout granted",
        event: "instance.pool.checkout",
        world_id: nil,
        city_id: nil,
        resource_key: state.resource_key,
        holder_pid: inspect(holder_pid),
        department_id: department_id,
        pool_current: state.current,
        pool_max: state.max
      )

      _ =
        Telemetry.execute(
          [:lemmings_os, :pool, :acquired],
          %{count: 1},
          Telemetry.pool_metadata(%{
            department_id: department_id,
            resource_key: state.resource_key,
            pool_current: state.current,
            pool_max: state.max
          })
        )

      {:reply, :ok, state}
    end
  end

  def handle_call({:checkout, _holder_pid, _department_id}, _from, state) do
    {:reply, {:error, :invalid_holder}, state}
  end

  @impl true
  def handle_call({:checkin, pid}, _from, state) when is_pid(pid) do
    case pop_holder_for_pid(state.holders, pid) do
      {nil, holders} ->
        {:reply, :ok, %{state | holders: holders}}

      {monitor_ref, holder, holders} ->
        Process.demonitor(monitor_ref, [:flush])

        state = %{
          state
          | current: max(state.current - 1, 0),
            holders: holders
        }

        Logger.info("resource pool checkout released",
          event: "instance.pool.checkin",
          world_id: nil,
          city_id: nil,
          resource_key: state.resource_key,
          holder_pid: inspect(pid),
          department_id: holder.department_id,
          pool_current: state.current,
          pool_max: state.max
        )

        _ =
          Telemetry.execute(
            [:lemmings_os, :pool, :released],
            %{count: 1},
            Telemetry.pool_metadata(%{
              department_id: holder.department_id,
              resource_key: state.resource_key,
              pool_current: state.current,
              pool_max: state.max
            })
          )

        {:reply, :ok, broadcast_capacity_released(state, holder.department_id)}
    end
  end

  def handle_call({:checkin, _pid}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, {state.current, state.max}, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      resource_key: state.resource_key,
      current: state.current,
      max: state.max,
      gate: state.gate,
      available?: state.gate == :open and state.current < state.max,
      holders_count: map_size(state.holders),
      holder_department_ids:
        state.holders
        |> Map.values()
        |> Enum.map(& &1.department_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort()
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.gate == :open and state.current < state.max, state}
  end

  @impl true
  def handle_call(:open_gate, _from, state) do
    {:reply, :ok, %{state | gate: :open}}
  end

  @impl true
  def handle_call(:close_gate, _from, state) do
    {:reply, :ok, %{state | gate: :closed}}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.pop(state.holders, monitor_ref) do
      {nil, _holders} ->
        {:noreply, state}

      {holder, holders} ->
        state = %{
          state
          | current: max(state.current - 1, 0),
            holders: holders
        }

        log_holder_down(state, holder, reason)

        {:noreply, broadcast_capacity_released(state, holder.department_id)}
    end
  end

  defp ensure_started(server) when is_pid(server) or is_atom(server) or is_tuple(server),
    do: {:ok, server}

  defp ensure_started(resource_key) when is_binary(resource_key) do
    case resolve_running_server(resource_key) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        start_pool(resource_key)
    end
  end

  defp lookup_server(server) when is_pid(server) or is_atom(server) or is_tuple(server),
    do: {:ok, server}

  defp lookup_server(resource_key) when is_binary(resource_key) do
    case registry_pid(resource_key) do
      {:ok, pid} -> {:ok, pid}
      :error -> {:error, :not_found}
    end
  end

  defp resolve_running_server(resource_key) do
    registry_pid(resource_key)
  end

  defp registry_pid(resource_key) do
    if registry_running?() do
      case Registry.lookup(LemmingsOs.LemmingInstances.PoolRegistry, resource_key) do
        [{pid, _value}] when is_pid(pid) ->
          alive_pid(pid)

        _ ->
          :error
      end
    else
      :error
    end
  end

  defp alive_pid(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: :error
  end

  defp registry_running? do
    not is_nil(Process.whereis(LemmingsOs.LemmingInstances.PoolRegistry))
  end

  defp start_pool(resource_key) do
    opts = [resource_key: resource_key]

    if registry_running?() and pool_supervisor_running?() do
      case DynamicSupervisor.start_child(@default_pool_supervisor, child_spec(opts)) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :pool_supervisor_not_running}
    end
  end

  defp extract_resource_key(resource_key) when is_binary(resource_key), do: resource_key
  defp extract_resource_key(_server), do: nil

  defp log_holder_down(state, holder, reason) when reason in [:normal, :shutdown] do
    Logger.info("resource pool holder exited and capacity was reclaimed",
      event: "instance.pool.holder_down",
      world_id: nil,
      city_id: nil,
      resource_key: state.resource_key,
      holder_pid: inspect(holder.pid),
      department_id: holder.department_id,
      pool_current: state.current,
      pool_max: state.max,
      reason: inspect(reason)
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :pool, :released],
        %{count: 1},
        Telemetry.pool_metadata(%{
          department_id: holder.department_id,
          resource_key: state.resource_key,
          pool_current: state.current,
          pool_max: state.max
        })
      )
  end

  defp log_holder_down(state, holder, {:shutdown, _detail} = reason) do
    Logger.info("resource pool holder exited and capacity was reclaimed",
      event: "instance.pool.holder_down",
      world_id: nil,
      city_id: nil,
      resource_key: state.resource_key,
      holder_pid: inspect(holder.pid),
      department_id: holder.department_id,
      pool_current: state.current,
      pool_max: state.max,
      reason: inspect(reason)
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :pool, :released],
        %{count: 1},
        Telemetry.pool_metadata(%{
          department_id: holder.department_id,
          resource_key: state.resource_key,
          pool_current: state.current,
          pool_max: state.max
        })
      )
  end

  defp log_holder_down(state, holder, reason) do
    Logger.warning("resource pool holder crashed and capacity was reclaimed",
      event: "instance.pool.holder_down",
      world_id: nil,
      city_id: nil,
      resource_key: state.resource_key,
      holder_pid: inspect(holder.pid),
      department_id: holder.department_id,
      pool_current: state.current,
      pool_max: state.max,
      reason: inspect(reason)
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :pool, :released],
        %{count: 1},
        Telemetry.pool_metadata(%{
          department_id: holder.department_id,
          resource_key: state.resource_key,
          pool_current: state.current,
          pool_max: state.max
        })
      )
  end

  defp pool_supervisor_running? do
    not is_nil(Process.whereis(@default_pool_supervisor))
  end

  defp max_capacity(opts) do
    config_capacity(Keyword.get(opts, :max_capacity, Keyword.get(opts, :capacity)))
  end

  defp default_capacity do
    config_capacity(Application.get_env(:lemmings_os, :resource_pool, []), @default_capacity)
  end

  defp config_capacity(config, default \\ @default_capacity)

  defp config_capacity(nil, default), do: default

  defp config_capacity(config, default) when is_list(config) do
    config
    |> Keyword.get(:max_capacity, Keyword.get(config, :capacity, default))
    |> normalize_positive_integer(default)
  end

  defp config_capacity(value, default), do: normalize_positive_integer(value, default)

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp gate_mode(opts) do
    case Keyword.get(opts, :gate, :open) do
      :closed -> :closed
      _ -> :open
    end
  end

  defp pop_holder_for_pid(holders, pid) do
    case Enum.find(holders, fn {_ref, holder} -> holder.pid == pid end) do
      {monitor_ref, holder} -> {monitor_ref, holder, Map.delete(holders, monitor_ref)}
      nil -> {nil, holders}
    end
  end

  defp broadcast_capacity_released(%{pubsub_mod: nil} = state, _department_id), do: state
  defp broadcast_capacity_released(%{pubsub_name: nil} = state, _department_id), do: state

  defp broadcast_capacity_released(state, department_id) do
    _ = LemmingsOs.LemmingInstances.PubSub.broadcast_capacity_released(state.resource_key)

    if is_binary(department_id) do
      _ =
        LemmingsOs.LemmingInstances.PubSub.broadcast_capacity_released(
          department_id,
          state.resource_key
        )
    end

    state
  end

  defp checkout_holder(opts) do
    opts
    |> Keyword.get(:holder, self())
    |> holder_pid()
  end

  defp holder_pid(pid) when is_pid(pid), do: pid
  defp holder_pid(_holder), do: nil
end
