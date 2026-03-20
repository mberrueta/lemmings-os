defmodule LemmingsOs.Cities.Heartbeat do
  @moduledoc """
  Local-city heartbeat worker.

  This worker updates only `last_seen_at` for the local runtime City on a fixed
  interval. Derived liveness uses the same issue-local freshness assumption:

  - heartbeat interval: 30 seconds by default
  - stale threshold: 90 seconds by default

  The worker never reinterprets admin status as presence and never rewrites
  `status` during normal heartbeats.
  """

  use GenServer

  require Logger

  alias Ecto.Changeset
  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Cities.Runtime

  @type state :: %{
          interval_ms: pos_integer() | :manual,
          runtime_city: module(),
          cities: module(),
          now_fun: (-> DateTime.t()),
          current_city: City.t() | nil
        }

  @doc """
  Starts the runtime-city heartbeat worker.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    genserver_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, name} -> [name: name]
        :error -> []
      end

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [Keyword.put_new(opts, :name, __MODULE__)]}
    }
  end

  @doc """
  Triggers a synchronous heartbeat cycle.
  """
  @spec heartbeat(GenServer.server()) ::
          :ok | {:error, :default_world_not_found | :runtime_city_not_found | Changeset.t()}
  def heartbeat(server \\ __MODULE__) do
    GenServer.call(server, :heartbeat)
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, heartbeat_config(:interval_ms)),
      runtime_city: Keyword.get(opts, :runtime_city, Runtime),
      cities: Keyword.get(opts, :cities, Cities),
      now_fun: Keyword.get(opts, :now_fun, &DateTime.utc_now/0),
      current_city: Keyword.get(opts, :current_city)
    }

    {:ok, schedule_next(state)}
  end

  @impl true
  def handle_call(:heartbeat, _from, state) do
    {result, next_state} = run_heartbeat(state)
    {:reply, result, schedule_next(next_state)}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    {_result, next_state} = run_heartbeat(state)
    {:noreply, schedule_next(next_state)}
  end

  defp run_heartbeat(state) do
    with {:ok, city, next_state} <- runtime_city(state),
         {:ok, updated_city} <- heartbeat_city(next_state, city) do
      log_heartbeat(:debug, "runtime city heartbeat persisted", updated_city)
      {:ok, %{next_state | current_city: updated_city}}
    else
      {:error, :default_world_not_found} = error ->
        Logger.error("runtime city heartbeat failed",
          event: "runtime_city.heartbeat",
          reason: "default_world_not_found"
        )

        {error, %{state | current_city: nil}}

      {:error, :runtime_city_not_found} = error ->
        Logger.error("runtime city heartbeat failed",
          event: "runtime_city.heartbeat",
          reason: "runtime_city_not_found"
        )

        {error, %{state | current_city: nil}}

      {:error, %Changeset{} = changeset} = error ->
        Logger.error("runtime city heartbeat failed",
          event: "runtime_city.heartbeat",
          reason: inspect(changeset.errors),
          city_id: city_id(state.current_city),
          world_id: world_id(state.current_city),
          node_name: node_name(state.current_city)
        )

        {error, state}
    end
  end

  defp runtime_city(%{current_city: %City{} = city} = state), do: {:ok, city, state}

  defp runtime_city(state) do
    case state.runtime_city.fetch_runtime_city() do
      {:ok, %City{} = city} ->
        {:ok, city, %{state | current_city: city}}

      {:error, :runtime_city_not_found} ->
        case state.runtime_city.sync_runtime_city() do
          {:ok, %City{} = city} -> {:ok, city, %{state | current_city: city}}
          {:error, _reason} = error -> error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp heartbeat_city(state, %City{} = city) do
    state.cities.heartbeat_city(city, state.now_fun.())
  end

  defp schedule_next(%{interval_ms: :manual} = state), do: state

  defp schedule_next(%{interval_ms: interval_ms} = state)
       when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :heartbeat, interval_ms)
    state
  end

  defp log_heartbeat(level, message, %City{} = city) do
    Logger.log(level, message,
      event: "runtime_city.heartbeat",
      world_id: city.world_id,
      city_id: city.id,
      node_name: city.node_name
    )
  end

  defp city_id(%City{id: id}), do: id
  defp city_id(_city), do: nil

  defp world_id(%City{world_id: world_id}), do: world_id
  defp world_id(_city), do: nil

  defp node_name(%City{node_name: node_name}), do: node_name
  defp node_name(_city), do: nil

  defp heartbeat_config(key) do
    :lemmings_os
    |> Application.get_env(:runtime_city_heartbeat, [])
    |> Keyword.fetch!(key)
  end
end
