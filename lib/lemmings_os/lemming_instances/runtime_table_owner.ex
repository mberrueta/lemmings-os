defmodule LemmingsOs.LemmingInstances.RuntimeTableOwner do
  @moduledoc """
  Long-lived ETS owner for active runtime instance state.

  The owner process creates the runtime ETS table once and keeps ownership
  alive for the lifetime of the application supervisor. Individual executors
  read and write through `LemmingsOs.LemmingInstances.EtsStore`.
  """

  use GenServer

  @doc """
  Starts the ETS owner process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Ensures the runtime ETS table exists under the long-lived owner.
  """
  @spec ensure_table() :: :ok | {:error, :not_started}
  def ensure_table do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(__MODULE__, :ensure_table)
    end
  end

  @doc """
  Returns a child spec for the runtime table owner.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(_opts) do
    :ok = create_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    {:reply, create_table(), state}
  end

  defp create_table do
    case :ets.whereis(:lemming_instance_runtime) do
      :undefined ->
        _ =
          :ets.new(:lemming_instance_runtime, [
            :set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: true
          ])

        :ok

      _tid ->
        :ok
    end
  end
end
