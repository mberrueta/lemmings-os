defmodule LemmingsOs.Runtime.ActivityLog do
  @moduledoc """
  In-memory ring buffer for recent runtime activity.

  This is an operator-facing feed used by the Logs page. It keeps the latest
  events emitted by the runtime engine so the UI can answer what is running,
  what is recovering, and what is failing right now.
  """

  use GenServer

  @default_limit 200

  @type entry :: %{
          id: binary(),
          type: atom(),
          agent: String.t(),
          action: String.t(),
          time: String.t(),
          inserted_at: DateTime.t(),
          metadata: map()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec record(atom(), String.t(), String.t(), map() | keyword()) :: :ok
  def record(type, agent, action, metadata \\ %{})
      when is_atom(type) and is_binary(agent) and is_binary(action) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:record, type, agent, action, Map.new(metadata)})
    end

    :ok
  end

  @spec recent_events(pos_integer()) :: [entry()]
  def recent_events(limit \\ 50) when is_integer(limit) and limit > 0 do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:recent_events, limit})
    else
      []
    end
  end

  @spec clear() :: :ok
  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{entries: [], limit: Keyword.get(opts, :limit, @default_limit)}}
  end

  @impl true
  def handle_cast({:record, type, agent, action, metadata}, state) do
    entry = build_entry(type, agent, action, metadata)
    entries = [entry | state.entries] |> Enum.take(state.limit)
    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_call({:recent_events, limit}, _from, state) do
    {:reply, Enum.take(state.entries, limit), state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | entries: []}}
  end

  defp build_entry(type, agent, action, metadata) do
    inserted_at = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      id: Ecto.UUID.generate(),
      type: type,
      agent: agent,
      action: action,
      time: Calendar.strftime(inserted_at, "%H:%M:%S"),
      inserted_at: inserted_at,
      metadata: metadata
    }
  end
end
