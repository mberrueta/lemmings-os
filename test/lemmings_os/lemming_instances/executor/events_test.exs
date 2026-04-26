defmodule LemmingsOs.LemmingInstances.Executor.EventsTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.Events
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.ModelRuntime.Response

  doctest LemmingsOs.LemmingInstances.Executor.Events

  test "emit_queue_enqueued/3 broadcasts queue metadata" do
    instance_id = "instance-events-queue-enqueued"
    state = %{instance_id: instance_id}
    item = %{id: "item-1"}

    assert :ok = PubSub.subscribe_instance_messages(instance_id)
    assert :ok = Events.emit_queue_enqueued(state, item, 2)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.queue.enqueued",
                      payload: %{
                        event: "runtime.queue.enqueued",
                        item_id: "item-1",
                        queue_depth: 2
                      }
                    }}
  end

  test "emit_model_finished/3 broadcasts completed payload for model response" do
    instance_id = "instance-events-model-completed"

    state = %{
      instance_id: instance_id,
      model_step_count: 2,
      phase: :action_selection,
      now_fun: &DateTime.utc_now/0
    }

    response =
      Response.new(
        action: :reply,
        reply: "Done",
        provider: "fake",
        model: "test-model",
        total_tokens: 123,
        raw: %{}
      )

    assert :ok = PubSub.subscribe_instance_messages(instance_id)
    assert :ok = Events.emit_model_finished(state, {:ok, response}, nil)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.model_step.completed",
                      current_item_id: nil,
                      phase: :action_selection,
                      step_index: 2,
                      payload: %{
                        event: "runtime.model_step.completed",
                        step_index: 2,
                        status: "ok",
                        action: :reply,
                        provider: "fake",
                        model: "test-model",
                        total_tokens: 123
                      }
                    }}
  end

  test "emit_model_finished/3 broadcasts failed payload with reason token" do
    instance_id = "instance-events-model-failed"

    state = %{
      instance_id: instance_id,
      model_step_count: 3,
      phase: :finalizing,
      now_fun: &DateTime.utc_now/0
    }

    assert :ok = PubSub.subscribe_instance_messages(instance_id)
    assert :ok = Events.emit_model_finished(state, {:error, :model_timeout}, nil)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.model_step.failed",
                      current_item_id: nil,
                      phase: :finalizing,
                      step_index: 3,
                      payload: %{
                        event: "runtime.model_step.failed",
                        step_index: 3,
                        status: "error",
                        reason: "model_timeout"
                      }
                    }}
  end

  test "tool events broadcast requested, started, failed, and rejected payloads" do
    instance_id = "instance-events-tool-failed"

    state = %{instance_id: instance_id}

    tool_execution = %{
      id: "tool-1",
      tool_name: "web.fetch",
      status: "error",
      duration_ms: 20,
      error: %{code: "tool.web.request_failed"}
    }

    assert :ok = PubSub.subscribe_instance_messages(instance_id)
    assert :ok = Events.emit_tool_requested(state, "web.fetch", %{"url" => "https://example.com"})
    assert :ok = Events.emit_tool_started(state, "web.fetch", %{"url" => "https://example.com"})
    assert :ok = Events.emit_tool_failed(state, tool_execution)
    assert :ok = Events.emit_tool_rejected(state, "web.fetch", :tool_execution_unavailable)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.tool_execution.requested",
                      payload: %{
                        event: "runtime.tool_execution.requested",
                        tool_name: "web.fetch",
                        args_keys: ["url"]
                      }
                    }}

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.tool_execution.started",
                      payload: %{
                        event: "runtime.tool_execution.started",
                        tool_name: "web.fetch",
                        args_keys: ["url"]
                      }
                    }}

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.tool_execution.failed",
                      payload: %{
                        event: "runtime.tool_execution.failed",
                        tool_execution_id: "tool-1",
                        tool_name: "web.fetch",
                        status: "error",
                        duration_ms: 20,
                        reason: "tool.web.request_failed"
                      }
                    }}

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.tool_execution.rejected",
                      payload: %{
                        event: "runtime.tool_execution.rejected",
                        tool_name: "web.fetch",
                        reason: "tool_execution_unavailable"
                      }
                    }}
  end

  test "resume events broadcast requested, started, rejected, and completed payloads" do
    instance_id = "instance-events-resume"
    assert :ok = PubSub.subscribe_instance_messages(instance_id)

    idle_state = %{instance_id: instance_id, status: "idle"}

    processing_state = %{
      instance_id: instance_id,
      status: "processing",
      current_item: %{id: "item-9"}
    }

    call = %{id: "call-1", status: "completed"}

    assert :ok = Events.emit_lemming_resume_requested(idle_state, call)
    assert :ok = Events.emit_lemming_resume_started(idle_state, call)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.lemming_call.resume.requested",
                      current_item_id: nil,
                      phase: nil,
                      payload: %{
                        event: "runtime.lemming_call.resume.requested",
                        call_id: "call-1",
                        call_status: "completed"
                      }
                    }}

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.lemming_call.resume.started",
                      current_item_id: nil,
                      phase: nil,
                      payload: %{
                        event: "runtime.lemming_call.resume.started",
                        call_id: "call-1",
                        call_status: "completed"
                      }
                    }}

    assert :ok =
             Events.emit_lemming_resume_rejected(
               %{instance_id: instance_id, status: "failed"},
               :terminal_instance
             )

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.lemming_call.resume.rejected",
                      current_item_id: nil,
                      payload: %{
                        event: "runtime.lemming_call.resume.rejected",
                        reason: "terminal_instance"
                      }
                    }}

    assert :ok = Events.emit_lemming_resume_completed(processing_state, call)

    assert_receive {:runtime_event,
                    %{
                      instance_id: ^instance_id,
                      event: "runtime.lemming_call.resume.completed",
                      current_item_id: "item-9",
                      phase: nil,
                      payload: %{
                        event: "runtime.lemming_call.resume.completed",
                        call_id: "call-1",
                        call_status: "completed"
                      }
                    }}
  end
end
