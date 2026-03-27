defmodule LemmingsOs.LemmingInstances.PubSubTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.PubSub

  test "S01: topic helpers build the expected runtime topics" do
    assert PubSub.scheduler_topic("dept-1") == "department:dept-1:scheduler"
    assert PubSub.instance_topic("instance-1") == "instance:instance-1:status"
  end

  test "S02: subscribe_scheduler/1 and broadcast_work_available/1 use the scheduler topic" do
    department_id = "dept-pubsub-work"

    assert :ok = PubSub.subscribe_scheduler(department_id)
    assert :ok = PubSub.broadcast_work_available(department_id)

    assert_receive {:work_available, %{department_id: ^department_id}}
  end

  test "S03: subscribe_instance/1 and broadcast_status_change/3 use the instance topic" do
    instance_id = "instance-pubsub-status"

    assert :ok = PubSub.subscribe_instance(instance_id)
    assert :ok = PubSub.broadcast_status_change(instance_id, "queued", %{retry_count: 1})

    assert_receive {:status_changed,
                    %{
                      instance_id: ^instance_id,
                      status: "queued",
                      metadata: %{retry_count: 1}
                    }}
  end

  test "S04: broadcast_capacity_released/2 emits the scheduler payload shape" do
    department_id = "dept-pubsub-capacity"
    resource_key = "ollama:llama3.2"

    assert :ok = PubSub.subscribe_scheduler(department_id)
    assert :ok = PubSub.broadcast_capacity_released(department_id, resource_key)

    assert_receive {:capacity_released,
                    %{department_id: ^department_id, resource_key: ^resource_key}}
  end

  test "S05: subscribe_capacity/0 and broadcast_capacity_released/1 use the global capacity topic" do
    resource_key = "ollama:llama3.2"

    assert :ok = PubSub.subscribe_capacity()
    assert :ok = PubSub.broadcast_capacity_released(resource_key)

    assert_receive {:capacity_released, %{resource_key: ^resource_key}}
  end

  test "S06: broadcast_scheduler_admit/3 emits the scheduler admission payload" do
    department_id = "dept-pubsub-admit"
    instance_id = "instance-pubsub-admit"
    resource_key = "ollama:llama3.2"

    assert :ok = PubSub.subscribe_scheduler(department_id)
    assert :ok = PubSub.broadcast_scheduler_admit(department_id, instance_id, resource_key)

    assert_receive {:scheduler_admit,
                    %{
                      department_id: ^department_id,
                      instance_id: ^instance_id,
                      resource_key: ^resource_key
                    }}
  end
end
