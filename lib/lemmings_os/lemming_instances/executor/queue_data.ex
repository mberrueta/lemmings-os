defmodule LemmingsOs.LemmingInstances.Executor.QueueData do
  @moduledoc """
  Pure queue/work-item helpers for executor state transitions.
  """

  alias LemmingsOs.Helpers

  @type dequeue_result :: :noop | {:ok, map(), :queue.queue()}

  @doc """
  Computes enqueue data without side effects.

  ## Examples

      iex> now = ~U[2026-04-26 10:00:00Z]
      iex> state = %{status: "idle", queue: :queue.new(), context_messages: [], now_fun: fn -> now end}
      iex> data = LemmingsOs.LemmingInstances.Executor.QueueData.enqueue_data(state, "Hello", append_to_context?: true)
      iex> data.next_status
      "queued"
      iex> data.should_notify?
      true
      iex> :queue.len(data.queue)
      1
      iex> is_binary(data.item.id)
      true
      iex> data.item.inserted_at
      ~U[2026-04-26 10:00:00Z]

      iex> state = %{status: "idle", queue: :queue.new(), context_messages: [], now_fun: &DateTime.utc_now/0}
      iex> LemmingsOs.LemmingInstances.Executor.QueueData.enqueue_data(state, "   ", append_to_context?: true)
      :blank
  """
  @spec enqueue_data(map(), binary(), keyword()) ::
          :blank
          | %{
              item: map(),
              queue: :queue.queue(),
              context_messages: list(),
              next_status: binary(),
              should_notify?: boolean()
            }
  def enqueue_data(state, content, opts)
      when is_binary(content) and is_map(state) and is_list(opts) do
    case Helpers.blank?(content) do
      true ->
        :blank

      false ->
        now = state.now_fun.()
        item = %{id: Ecto.UUID.generate(), content: content, origin: :user, inserted_at: now}
        queue = :queue.in(item, state.queue)

        context_messages =
          maybe_append_context_message(state.context_messages, item, content, opts)

        next_status = next_status_for_enqueue(state.status)

        %{
          item: item,
          queue: queue,
          context_messages: context_messages,
          next_status: next_status,
          should_notify?: next_status == "queued"
        }
    end
  end

  @doc """
  Dequeues the next queue item only when processing can start.

  ## Examples

      iex> queue = :queue.from_list([%{id: "first"}, %{id: "second"}])
      iex> {:ok, item, next_queue} =
      ...>   LemmingsOs.LemmingInstances.Executor.QueueData.dequeue_for_processing(%{current_item: nil, queue: queue})
      iex> item.id
      "first"
      iex> :queue.to_list(next_queue)
      [%{id: "second"}]

      iex> LemmingsOs.LemmingInstances.Executor.QueueData.dequeue_for_processing(%{current_item: %{id: "busy"}, queue: :queue.new()})
      :noop
  """
  @spec dequeue_for_processing(map()) :: dequeue_result()
  def dequeue_for_processing(%{current_item: current_item}) when not is_nil(current_item) do
    :noop
  end

  def dequeue_for_processing(%{queue: queue}) do
    case :queue.out(queue) do
      {{:value, item}, next_queue} -> {:ok, item, next_queue}
      {:empty, _queue} -> :noop
    end
  end

  @doc """
  Returns the state map reset for a new processing turn.

  ## Examples

      iex> state = %{phase: :finalizing, finalization_context: %{x: 1}, finalization_repair_attempted?: true, retry_count: 2}
      iex> queue = :queue.from_list([%{id: "remaining"}])
      iex> item = %{id: "current"}
      iex> updated = LemmingsOs.LemmingInstances.Executor.QueueData.prepare_state_for_processing(state, item, queue)
      iex> {updated.current_item, updated.phase, updated.finalization_context, updated.retry_count}
      {%{id: "current"}, :action_selection, nil, 0}
  """
  @spec prepare_state_for_processing(map(), map(), :queue.queue()) :: map()
  def prepare_state_for_processing(state, item, queue) do
    state
    |> Map.put(:queue, queue)
    |> Map.put(:current_item, item)
    |> Map.put(:phase, :action_selection)
    |> Map.put(:finalization_context, nil)
    |> Map.put(:finalization_repair_attempted?, false)
    |> Map.put(:retry_count, 0)
  end

  @doc """
  Computes the retry queue including the failed current item when present.

  ## Examples

      iex> queue = :queue.from_list([%{id: "queued"}])
      iex> state = %{queue: queue, current_item: %{id: "current"}}
      iex> LemmingsOs.LemmingInstances.Executor.QueueData.retry_queue(state) |> :queue.to_list()
      [%{id: "current"}, %{id: "queued"}]
  """
  @spec retry_queue(map()) :: :queue.queue()
  def retry_queue(%{queue: queue, current_item: nil}), do: queue

  def retry_queue(%{queue: queue, current_item: current_item}),
    do: :queue.in_r(current_item, queue)

  @doc """
  Returns the state map reset for retrying a failed item.

  ## Examples

      iex> state = %{current_item: %{id: "x"}, current_resource_key: "ollama:test", phase: :finalizing, finalization_context: %{x: 1}, finalization_repair_attempted?: true, retry_count: 2, last_error: "boom", internal_error_details: %{kind: :model_timeout}}
      iex> queue = :queue.from_list([%{id: "retry"}])
      iex> updated = LemmingsOs.LemmingInstances.Executor.QueueData.prepare_state_for_retry(state, queue)
      iex> {updated.current_item, updated.current_resource_key, updated.phase, updated.last_error, updated.internal_error_details}
      {nil, nil, :action_selection, nil, nil}
  """
  @spec prepare_state_for_retry(map(), :queue.queue()) :: map()
  def prepare_state_for_retry(state, queue) do
    state
    |> Map.put(:queue, queue)
    |> Map.put(:current_item, nil)
    |> Map.put(:current_resource_key, nil)
    |> Map.put(:phase, :action_selection)
    |> Map.put(:finalization_context, nil)
    |> Map.put(:finalization_repair_attempted?, false)
    |> Map.put(:retry_count, 0)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
  end

  defp next_status_for_enqueue(status) when status in ["created", "idle"], do: "queued"
  defp next_status_for_enqueue(status), do: status

  defp maybe_append_context_message(context_messages, item, content, opts)
       when is_list(context_messages) and is_map(item) and is_binary(content) and is_list(opts) do
    case Keyword.get(opts, :append_to_context?, true) do
      true -> context_messages ++ [%{role: "user", content: content, request_id: item.id}]
      false -> context_messages
    end
  end
end
