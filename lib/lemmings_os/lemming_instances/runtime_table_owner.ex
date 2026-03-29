defmodule LemmingsOs.LemmingInstances.RuntimeTableOwner do
  @moduledoc """
  Long-lived ETS owner for active runtime instance state.

  The owner process creates the runtime ETS table once and keeps ownership
  alive for the lifetime of the application supervisor. Individual executors
  read and write through `LemmingsOs.LemmingInstances.EtsStore`.
  """

  use GenServer

  alias LemmingsOs.LemmingInstances.EtsStore

  @doc """
  Starts the ETS owner process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
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
    :ok = EtsStore.init_table()
    {:ok, %{}}
  end
end
