defmodule LemmingsOs.LemmingInstances.Executor.QueueDataTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.QueueData
  doctest QueueData

  test "enqueue_data/3 returns blank for blank content" do
    state = %{
      status: "idle",
      queue: :queue.new(),
      context_messages: [],
      now_fun: &DateTime.utc_now/0
    }

    assert QueueData.enqueue_data(state, "   ", append_to_context?: true) == :blank
  end

  test "enqueue_data/3 builds queue/context and queued transition for idle status" do
    now = ~U[2026-04-25 12:00:00Z]

    state = %{
      status: "idle",
      queue: :queue.new(),
      context_messages: [],
      now_fun: fn -> now end
    }

    data = QueueData.enqueue_data(state, "Investigate outage", append_to_context?: true)

    assert data.next_status == "queued"
    assert data.should_notify? == true
    assert :queue.len(data.queue) == 1
    assert [%{role: "user", content: "Investigate outage"}] = data.context_messages
    assert %{id: id, content: "Investigate outage", origin: :user, inserted_at: ^now} = data.item
    assert is_binary(id)
  end

  test "dequeue_for_processing/1 returns noop when current item exists or queue is empty" do
    assert QueueData.dequeue_for_processing(%{current_item: %{id: "item-1"}, queue: :queue.new()}) ==
             :noop

    assert QueueData.dequeue_for_processing(%{current_item: nil, queue: :queue.new()}) == :noop
  end

  test "dequeue_for_processing/1 pops the next queued item" do
    queue =
      :queue.from_list([
        %{id: "first", content: "First"},
        %{id: "second", content: "Second"}
      ])

    assert {:ok, %{id: "first"}, next_queue} =
             QueueData.dequeue_for_processing(%{current_item: nil, queue: queue})

    assert :queue.to_list(next_queue) == [%{id: "second", content: "Second"}]
  end

  test "prepare_state_for_processing/3 resets phase/finalization/retry and sets current item" do
    state = %{
      queue: :queue.new(),
      current_item: nil,
      phase: :finalizing,
      finalization_context: %{foo: :bar},
      finalization_repair_attempted?: true,
      retry_count: 2
    }

    item = %{id: "item-1"}
    queue = :queue.from_list([%{id: "remaining"}])
    updated = QueueData.prepare_state_for_processing(state, item, queue)

    assert updated.current_item == item
    assert updated.queue == queue
    assert updated.phase == :action_selection
    assert updated.finalization_context == nil
    assert updated.finalization_repair_attempted? == false
    assert updated.retry_count == 0
  end

  test "retry_queue/1 appends current item to the tail when present" do
    queue = :queue.from_list([%{id: "queued-1"}])
    state = %{queue: queue, current_item: %{id: "current"}}

    assert :queue.to_list(QueueData.retry_queue(state)) == [%{id: "current"}, %{id: "queued-1"}]
  end

  test "prepare_state_for_retry/2 clears transient runtime fields" do
    queue = :queue.from_list([%{id: "retry"}])

    state = %{
      queue: :queue.new(),
      current_item: %{id: "current"},
      current_resource_key: "ollama:test",
      phase: :finalizing,
      finalization_context: %{foo: :bar},
      finalization_repair_attempted?: true,
      retry_count: 2,
      last_error: "boom",
      internal_error_details: %{kind: :model_timeout}
    }

    updated = QueueData.prepare_state_for_retry(state, queue)

    assert updated.queue == queue
    assert updated.current_item == nil
    assert updated.current_resource_key == nil
    assert updated.phase == :action_selection
    assert updated.finalization_context == nil
    assert updated.finalization_repair_attempted? == false
    assert updated.retry_count == 0
    assert updated.last_error == nil
    assert updated.internal_error_details == nil
  end
end
