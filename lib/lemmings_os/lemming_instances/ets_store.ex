defmodule LemmingsOs.LemmingInstances.EtsStore do
  @moduledoc """
  ETS-backed runtime state store for active lemming instances.

  The store is intentionally small and thin: one named table, one row per
  instance, and a handful of wrappers around raw ETS reads and writes.
  """

  @table_name :lemming_instance_runtime
  @default_max_retries 3

  @type instance_id :: binary()
  @type work_item :: %{
          id: Ecto.UUID.t() | binary(),
          content: String.t(),
          origin: :user,
          inserted_at: DateTime.t()
        }

  @type state :: %{
          department_id: binary(),
          world_id: binary() | nil,
          queue: :queue.queue(),
          current_item: work_item() | nil,
          config_snapshot: map(),
          resource_key: binary() | nil,
          retry_count: non_neg_integer(),
          max_retries: pos_integer(),
          context_messages: [map()],
          last_error: String.t() | nil,
          status: atom(),
          started_at: DateTime.t() | nil,
          last_activity_at: DateTime.t() | nil
        }

  @doc """
  Creates the runtime ETS table if it does not already exist.

  ## Examples

      iex> LemmingsOs.LemmingInstances.EtsStore.init_table()
      :ok
  """
  @spec init_table() :: :ok
  def init_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        _ =
          :ets.new(@table_name, [
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

  @doc """
  Inserts or replaces an instance runtime entry.

  ## Examples

      iex> state = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> {:ok, stored} = LemmingsOs.LemmingInstances.EtsStore.put("instance-1", state)
      iex> stored.department_id
      "dept-1"
  """
  @spec put(instance_id(), map()) :: {:ok, state()} | {:error, atom()}
  def put(instance_id, state) when is_binary(instance_id) and is_map(state) do
    with :ok <- init_table(),
         {:ok, normalized_state} <- normalize_state(state) do
      true = :ets.insert(@table_name, {key(instance_id), normalized_state})
      {:ok, normalized_state}
    end
  end

  @doc """
  Returns the stored runtime entry for an instance.

  ## Examples

      iex> state = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-2", state)
      iex> {:ok, stored} = LemmingsOs.LemmingInstances.EtsStore.get("instance-2")
      iex> stored.department_id
      "dept-1"
  """
  @spec get(instance_id()) :: {:ok, state()} | {:error, :not_found}
  def get(instance_id) when is_binary(instance_id) do
    with :ok <- init_table(),
         [{_entry_key, state}] <- :ets.lookup(@table_name, key(instance_id)) do
      {:ok, state}
    else
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates a subset of fields in an existing runtime entry.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-3", base)
      iex> {:ok, updated} = LemmingsOs.LemmingInstances.EtsStore.update("instance-3", %{status: :queued})
      iex> updated.status
      :queued
  """
  @spec update(instance_id(), map()) :: {:ok, state()} | {:error, atom()}
  def update(instance_id, changes) when is_binary(instance_id) and is_map(changes) do
    with {:ok, state} <- get(instance_id),
         {:ok, normalized_changes} <- normalize_changes(changes),
         {:ok, normalized_state} <- normalize_state(Map.merge(state, normalized_changes)) do
      true = :ets.insert(@table_name, {key(instance_id), normalized_state})
      {:ok, normalized_state}
    end
  end

  @doc """
  Removes the runtime entry for an instance.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-4", base)
      iex> LemmingsOs.LemmingInstances.EtsStore.delete("instance-4")
      :ok
  """
  @spec delete(instance_id()) :: :ok
  def delete(instance_id) when is_binary(instance_id) do
    cleanup(instance_id)
  end

  @doc """
  Removes the runtime entry for an instance during expiry or failure cleanup.
  """
  @spec cleanup(instance_id()) :: :ok
  def cleanup(instance_id) when is_binary(instance_id) do
    with :ok <- init_table() do
      _ = :ets.delete(@table_name, key(instance_id))
      :ok
    end
  end

  @doc """
  Returns queued or active runtime entries for a department.

  The return value is a list of `{instance_id, state}` tuples.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-9",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :queued,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-9", base)
      iex> [{instance_id, _state}] = LemmingsOs.LemmingInstances.EtsStore.list_by_status(:queued, "dept-9")
      iex> instance_id
      "instance-9"
  """
  @spec list_by_status(atom() | String.t(), binary()) :: [{instance_id(), state()}]
  def list_by_status(status, department_id) when is_binary(department_id) do
    :ok = init_table()

    target_status = normalize_status(status)

    @table_name
    |> :ets.select(status_match_spec(department_id, target_status))
    |> Enum.map(fn {instance_id, state} -> {normalize_key(instance_id), state} end)
    |> Enum.sort_by(&status_sort_key/1)
  end

  @doc """
  Returns all active runtime entries currently stored in ETS.
  """
  @spec list_all() :: [{instance_id(), state()}]
  def list_all do
    :ok = init_table()

    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {instance_id, state} -> {normalize_key(instance_id), state} end)
    |> Enum.sort_by(&status_sort_key/1)
  end

  @doc """
  Appends a work item to an instance queue.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-5", base)
      iex> work_item = %{id: "msg-1", content: "hello", origin: :user, inserted_at: DateTime.utc_now()}
      iex> {:ok, updated} = LemmingsOs.LemmingInstances.EtsStore.enqueue_work_item("instance-5", work_item)
      iex> :queue.len(updated.queue)
      1
  """
  @spec enqueue_work_item(instance_id(), work_item()) :: {:ok, state()} | {:error, atom()}
  def enqueue_work_item(instance_id, work_item)
      when is_binary(instance_id) and is_map(work_item) do
    case get(instance_id) do
      {:ok, state} ->
        normalized_work_item = normalize_work_item(work_item)
        update(instance_id, %{queue: :queue.in(normalized_work_item, state.queue)})

      {:error, :not_found} = error ->
        error
    end
  end

  @doc """
  Removes and returns the next queued work item for an instance.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-6", base)
      iex> work_item = %{id: "msg-2", content: "hello", origin: :user, inserted_at: DateTime.utc_now()}
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.enqueue_work_item("instance-6", work_item)
      iex> {:ok, popped} = LemmingsOs.LemmingInstances.EtsStore.dequeue_work_item("instance-6")
      iex> popped.id
      "msg-2"
  """
  @spec dequeue_work_item(instance_id()) :: {:ok, work_item() | nil} | {:error, atom()}
  def dequeue_work_item(instance_id) when is_binary(instance_id) do
    with {:ok, state} <- get(instance_id) do
      case :queue.out(state.queue) do
        {:empty, _queue} ->
          {:ok, nil}

        {{:value, work_item}, queue} ->
          {:ok, _updated_state} = update(instance_id, %{queue: queue})
          {:ok, work_item}
      end
    end
  end

  @doc """
  Returns the queue depth for an instance.

  ## Examples

      iex> base = %{
      ...>   department_id: "dept-1",
      ...>   queue: :queue.new(),
      ...>   current_item: nil,
      ...>   retry_count: 0,
      ...>   max_retries: 3,
      ...>   context_messages: [],
      ...>   status: :created,
      ...>   started_at: nil,
      ...>   last_activity_at: nil
      ...> }
      iex> _ = LemmingsOs.LemmingInstances.EtsStore.put("instance-7", base)
      iex> LemmingsOs.LemmingInstances.EtsStore.get_queue_depth("instance-7")
      0
  """
  @spec get_queue_depth(instance_id()) :: non_neg_integer()
  def get_queue_depth(instance_id) when is_binary(instance_id) do
    case get(instance_id) do
      {:ok, state} -> :queue.len(state.queue)
      {:error, :not_found} -> 0
    end
  end

  defp key(instance_id), do: {instance_id}

  defp normalize_key({instance_id}) when is_binary(instance_id), do: instance_id
  defp normalize_key(instance_id) when is_binary(instance_id), do: instance_id
  defp normalize_key(other), do: other

  defp status_match_spec(department_id, target_status) do
    # Equivalent to:
    # fn {instance_id, state} ->
    #   state.department_id == department_id and state.status == target_status
    # end
    [
      {
        {:"$1", :"$2"},
        [
          {:==, {:map_get, :department_id, :"$2"}, department_id},
          {:==, {:map_get, :status, :"$2"}, target_status}
        ],
        [{{:"$1", :"$2"}}]
      }
    ]
  end

  defp status_sort_key({instance_id, state}) do
    {queue_rank(state.queue), queue_depth(state.queue), instance_id}
  end

  defp normalize_state(state) when is_map(state) do
    case Map.get(state, :department_id) || Map.get(state, "department_id") do
      department_id when is_binary(department_id) ->
        {:ok, apply_state_defaults(state, department_id)}

      _ ->
        {:error, :missing_department_id}
    end
  end

  defp apply_state_defaults(state, department_id) do
    state
    |> Map.put(:department_id, department_id)
    |> Map.put(:world_id, field_value(state, :world_id))
    |> Map.put(:queue, normalize_queue(Map.get(state, :queue) || Map.get(state, "queue")))
    |> Map.put(
      :current_item,
      normalize_current_item(Map.get(state, :current_item) || Map.get(state, "current_item"))
    )
    |> Map.put(:config_snapshot, normalize_config_snapshot(field_value(state, :config_snapshot)))
    |> Map.put(:resource_key, normalize_resource_key(field_value(state, :resource_key)))
    |> Map.put(:retry_count, normalize_retry_count(state))
    |> Map.put(:max_retries, normalize_max_retries(state))
    |> Map.put(
      :context_messages,
      normalize_context_messages(field_value(state, :context_messages))
    )
    |> Map.put(:last_error, normalize_last_error(field_value(state, :last_error)))
    |> Map.put(:status, normalize_status(field_value(state, :status)))
    |> Map.put(:started_at, field_value(state, :started_at))
    |> Map.put(:last_activity_at, field_value(state, :last_activity_at))
  end

  defp normalize_changes(changes) when is_map(changes) do
    {:ok,
     changes
     |> maybe_normalize_field(:queue, &normalize_queue/1)
     |> maybe_normalize_field(:current_item, &normalize_current_item/1)
     |> maybe_normalize_field(:config_snapshot, &normalize_config_snapshot/1)
     |> maybe_normalize_field(:resource_key, &normalize_resource_key/1)
     |> maybe_normalize_field(:retry_count, &normalize_non_neg_integer(&1, 0))
     |> maybe_normalize_field(:max_retries, &normalize_pos_integer(&1, @default_max_retries))
     |> maybe_normalize_field(:context_messages, &normalize_context_messages/1)
     |> maybe_normalize_field(:last_error, &normalize_last_error/1)
     |> maybe_normalize_field(:status, &normalize_status/1)}
  end

  defp maybe_normalize_field(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp normalize_queue(queue) when is_tuple(queue), do: queue
  defp normalize_queue(queue) when is_list(queue), do: :queue.from_list(queue)
  defp normalize_queue(_queue), do: :queue.new()

  defp normalize_context_messages(messages) when is_list(messages), do: messages
  defp normalize_context_messages(_messages), do: []

  defp normalize_last_error(error) when is_binary(error) and error != "", do: error
  defp normalize_last_error(_error), do: nil

  defp normalize_current_item(nil), do: nil

  defp normalize_current_item(%{} = work_item) do
    normalize_work_item(work_item)
  end

  defp normalize_current_item(_current_item), do: nil

  defp normalize_work_item(%{} = work_item) do
    %{}
    |> maybe_put_work_item_field(:id, field_value(work_item, :id))
    |> maybe_put_work_item_field(:content, field_value(work_item, :content))
    |> Map.put(:origin, :user)
    |> maybe_put_work_item_field(:inserted_at, field_value(work_item, :inserted_at))
  end

  defp maybe_put_work_item_field(map, key, value) when not is_nil(value),
    do: Map.put(map, key, value)

  defp maybe_put_work_item_field(map, _key, _value), do: map

  defp normalize_config_snapshot(snapshot) when is_map(snapshot), do: snapshot
  defp normalize_config_snapshot(_snapshot), do: %{}

  defp normalize_resource_key(resource_key) when is_binary(resource_key), do: resource_key
  defp normalize_resource_key(_resource_key), do: nil

  defp normalize_status(status) when is_atom(status), do: status

  defp normalize_status(status) when is_binary(status) do
    case status do
      "created" -> :created
      "queued" -> :queued
      "processing" -> :processing
      "retrying" -> :retrying
      "idle" -> :idle
      "failed" -> :failed
      "expired" -> :expired
      _ -> :created
    end
  end

  defp normalize_status(_status), do: :created

  defp normalize_non_neg_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_integer(_value, default), do: default

  defp normalize_pos_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_pos_integer(_value, default), do: default

  defp normalize_retry_count(state) do
    normalize_non_neg_integer(field_value(state, :retry_count), 0)
  end

  defp normalize_max_retries(state) do
    normalize_pos_integer(field_value(state, :max_retries), @default_max_retries)
  end

  defp field_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp queue_depth(queue) when is_tuple(queue) do
    if :queue.is_queue(queue), do: :queue.len(queue), else: 0
  end

  defp queue_depth(_queue), do: 0

  defp queue_rank(queue) when is_tuple(queue) do
    if :queue.is_queue(queue) do
      case :queue.out(queue) do
        {:empty, _} -> 1
        {{:value, _}, _} -> 0
      end
    else
      1
    end
  end

  defp queue_rank(_queue), do: 1
end
