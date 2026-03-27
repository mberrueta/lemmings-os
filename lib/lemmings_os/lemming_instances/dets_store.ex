defmodule LemmingsOs.LemmingInstances.DetsStore do
  @moduledoc """
  Supervised DETS snapshot store for idle runtime state.

  The DETS table is opened once by this GenServer and callers use a small API
  for snapshot persistence, lookup, and cleanup.
  """

  use GenServer

  require Logger

  @table_name :lemming_instance_snapshots
  @file_name "lemming_instance_snapshots.dets"

  @type instance_id :: binary()
  @type snapshot :: LemmingsOs.LemmingInstances.EtsStore.state()
  @type state :: %{}

  @doc """
  Starts the DETS owner process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Returns `:ok` when the store process is ready.

  This is retained for compatibility with the task contract. Use `ready?/0`
  for the clearer intent.

  ## Examples

      iex> LemmingsOs.LemmingInstances.DetsStore.init_store()
      :ok
  """
  @spec init_store() :: :ok | {:error, term()}
  def init_store, do: ready?()

  @doc """
  Checks whether the DETS owner process is available.

  ## Examples

      iex> LemmingsOs.LemmingInstances.DetsStore.ready?()
      :ok
  """
  @spec ready?() :: :ok | {:error, term()}
  def ready? do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(__MODULE__, :ready)
    end
  end

  @doc """
  Writes a best-effort DETS snapshot for an instance.

  Snapshot failures are logged and reported, but never raised.

  ## Examples

      iex> state = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :idle,
      ...>   started_at: DateTime.utc_now(),
      ...>   last_activity_at: DateTime.utc_now()
      ...> }
      iex> LemmingsOs.LemmingInstances.DetsStore.snapshot("instance-1", state)
      :ok
  """
  @spec snapshot(instance_id(), snapshot()) :: :ok | {:error, term()}
  def snapshot(instance_id, state_map) when is_binary(instance_id) and is_map(state_map) do
    GenServer.call(__MODULE__, {:snapshot, instance_id, state_map})
  end

  def snapshot(instance_id, _state_map) when is_binary(instance_id) do
    {:error, :invalid_state}
  end

  @doc """
  Deletes a snapshot for an instance.

  ## Examples

      iex> state = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :idle,
      ...>   started_at: DateTime.utc_now(),
      ...>   last_activity_at: DateTime.utc_now()
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.DetsStore.snapshot("instance-2", state)
      iex> LemmingsOs.LemmingInstances.DetsStore.delete("instance-2")
      :ok
  """
  @spec delete(instance_id()) :: :ok | {:error, term()}
  def delete(instance_id) when is_binary(instance_id) do
    GenServer.call(__MODULE__, {:delete, instance_id})
  end

  @doc """
  Reads a snapshot for future rehydration.

  ## Examples

      iex> state = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :idle,
      ...>   started_at: DateTime.utc_now(),
      ...>   last_activity_at: DateTime.utc_now()
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.DetsStore.snapshot("instance-3", state)
      iex> {:ok, snapshot} = LemmingsOs.LemmingInstances.DetsStore.read("instance-3")
      iex> snapshot.department_id
      "dept-1"
  """
  @spec read(instance_id()) :: {:ok, snapshot()} | {:error, :not_found | term()}
  def read(instance_id) when is_binary(instance_id) do
    GenServer.call(__MODULE__, {:read, instance_id})
  end

  @impl true
  def init(_opts) do
    case open_store() do
      :ok -> {:ok, %{}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:ready, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:snapshot, instance_id, state_map}, _from, state) do
    reply =
      case safe_dets_call(fn -> :dets.insert(@table_name, {instance_id, state_map}) end) do
        :ok -> :ok
        {:error, reason} -> fail(:snapshot, instance_id, reason)
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, instance_id}, _from, state) do
    reply =
      case safe_dets_call(fn -> :dets.delete(@table_name, instance_id) end) do
        :ok -> :ok
        {:error, reason} -> fail(:delete, instance_id, reason)
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:read, instance_id}, _from, state) do
    {:reply, read_snapshot(instance_id), state}
  end

  @impl true
  def terminate(_reason, _state) do
    case :dets.close(@table_name) do
      :ok -> :ok
      _ -> :ok
    end
  end

  defp safe_dets_call(fun) do
    try do
      fun.()
    rescue
      exception ->
        {:error, exception}
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp read_snapshot(instance_id) do
    case safe_dets_call(fn -> lookup_snapshot(instance_id) end) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> fail(:read, instance_id, reason)
    end
  end

  defp lookup_snapshot(instance_id) do
    case :dets.lookup(@table_name, instance_id) do
      [{^instance_id, snapshot}] ->
        {:ok, snapshot}

      [] ->
        {:error, :not_found}

      other ->
        {:error, {:unexpected_lookup_result, other}}
    end
  end

  defp open_store do
    case File.mkdir_p(directory()) do
      :ok ->
        case :dets.open_file(@table_name, type: :set, file: String.to_charlist(file_path())) do
          {:ok, _table} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fail(operation, instance_id, reason) do
    log_failure(operation, instance_id, reason)
    emit_failure_telemetry(operation, instance_id, reason)
    {:error, reason}
  end

  defp log_failure(operation, instance_id, reason) do
    Logger.error("lemming instance dets operation failed",
      event: "lemming_instances.dets.#{operation}.failure",
      operation: operation,
      instance_id: instance_id,
      table: @table_name,
      path: file_path(),
      reason: inspect(reason)
    )
  end

  defp emit_failure_telemetry(operation, instance_id, reason) do
    :telemetry.execute(
      [:lemmings_os, :lemming_instances, :dets_store, operation, :failure],
      %{count: 1},
      %{
        instance_id: instance_id,
        table: @table_name,
        path: file_path(),
        reason: reason
      }
    )
  end

  defp directory do
    config = Application.get_env(:lemmings_os, :runtime_dets, [])

    Keyword.get(config, :directory, default_directory())
  end

  defp default_directory do
    Application.app_dir(:lemmings_os, "priv/runtime/dets")
  end

  defp file_path do
    Path.join(directory(), @file_name)
  end
end
