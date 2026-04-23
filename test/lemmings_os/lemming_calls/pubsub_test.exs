defmodule LemmingsOs.LemmingCalls.PubSubTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingCalls.PubSub

  test "S01: topic helpers build lemming call topics" do
    assert PubSub.call_topic("call-1") == "lemming_call:call-1"
    assert PubSub.caller_instance_topic("instance-1") == "instance:instance-1:lemming_calls"
    assert PubSub.callee_instance_topic("instance-2") == "instance:instance-2:lemming_calls"
  end

  test "S02: broadcast_call_upserted/1 emits to call and instance topics" do
    call = %LemmingsOs.LemmingCalls.LemmingCall{
      id: "call-1",
      status: "running",
      world_id: "world-1",
      city_id: "city-1",
      caller_department_id: "dept-a",
      callee_department_id: "dept-b",
      caller_instance_id: "instance-a",
      callee_instance_id: "instance-b",
      recovery_status: nil
    }

    assert :ok = PubSub.subscribe_call(call.id)
    assert :ok = PubSub.subscribe_instance_calls(call.caller_instance_id)

    assert :ok = PubSub.broadcast_call_upserted(call)

    assert_receive {:lemming_call_upserted,
                    %{
                      lemming_call_id: "call-1",
                      status: "running",
                      caller_instance_id: "instance-a"
                    }}

    assert_receive {:lemming_call_upserted,
                    %{
                      lemming_call_id: "call-1",
                      status: "running",
                      caller_instance_id: "instance-a"
                    }}
  end

  test "S03: broadcast_status_changed/2 includes previous status" do
    call = %LemmingsOs.LemmingCalls.LemmingCall{
      id: "call-2",
      status: "completed",
      world_id: "world-1",
      city_id: "city-1",
      caller_department_id: "dept-a",
      callee_department_id: "dept-b",
      caller_instance_id: "instance-a",
      callee_instance_id: "instance-b",
      recovery_status: nil
    }

    assert :ok = PubSub.subscribe_call(call.id)
    assert :ok = PubSub.broadcast_status_changed(call, "running")

    assert_receive {:lemming_call_status_changed,
                    %{lemming_call_id: "call-2", previous_status: "running", status: "completed"}}
  end
end
