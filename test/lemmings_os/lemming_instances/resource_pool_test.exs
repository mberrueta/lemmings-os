defmodule LemmingsOs.LemmingInstances.ResourcePoolTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool

  setup do
    ensure_registry!(LemmingsOs.LemmingInstances.PoolRegistry)
    ensure_dynamic_supervisor!(LemmingsOs.LemmingInstances.PoolSupervisor)
    :ok
  end

  test "S01: via_name and child_spec build the expected registry wiring" do
    assert ResourcePool.via_name("ollama:llama3.2") ==
             {:via, Registry, {LemmingsOs.LemmingInstances.PoolRegistry, "ollama:llama3.2"}}

    spec = ResourcePool.child_spec(resource_key: "ollama:llama3.2")
    assert spec.id == {ResourcePool, "ollama:llama3.2"}
    assert spec.start == {ResourcePool, :start_link, [[resource_key: "ollama:llama3.2"]]}
  end

  test "S02: checkout, status, available?, and checkin track capacity" do
    {:ok, pid} =
      ResourcePool.start_link(
        resource_key: "ollama:test-capacity",
        name: nil,
        gate: :open,
        pubsub_mod: nil
      )

    assert ResourcePool.status(pid) == {0, 1}
    assert ResourcePool.available?(pid)
    assert :ok = ResourcePool.checkout(pid)
    assert ResourcePool.status(pid) == {1, 1}
    refute ResourcePool.available?(pid)
    assert :ok = ResourcePool.checkin(pid)
    assert ResourcePool.status(pid) == {0, 1}
    assert ResourcePool.available?(pid)

    GenServer.stop(pid)
  end

  test "S03: open_gate and close_gate toggle checkout availability" do
    {:ok, pid} =
      ResourcePool.start_link(
        resource_key: "ollama:test-gate",
        name: nil,
        gate: :closed,
        pubsub_mod: nil
      )

    refute ResourcePool.available?(pid)
    assert :ok = ResourcePool.open_gate(pid)
    assert ResourcePool.available?(pid)
    assert :ok = ResourcePool.close_gate(pid)
    refute ResourcePool.available?(pid)

    GenServer.stop(pid)
  end

  test "S04: checkout can reserve capacity for another holder and release on holder crash" do
    resource_key = "ollama:test-crash"

    {:ok, pid} =
      ResourcePool.start_link(
        resource_key: resource_key,
        name: nil,
        gate: :open,
        pubsub_mod: Phoenix.PubSub
      )

    holder =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert :ok = PubSub.subscribe_capacity()
    assert :ok = ResourcePool.checkout(pid, holder: holder, department_id: "dept-1")
    assert ResourcePool.status(pid) == {1, 1}

    send(holder, :stop)

    assert_receive {:capacity_released, %{resource_key: ^resource_key}}
    assert ResourcePool.status(pid) == {0, 1}

    GenServer.stop(pid)
  end

  test "S05: checkout by resource key starts the pool under the pool supervisor" do
    resource_key = "ollama:autostart"

    assert :ok = ResourcePool.checkout(resource_key)

    assert [{pool_pid, _value}] =
             Registry.lookup(LemmingsOs.LemmingInstances.PoolRegistry, resource_key)

    assert DynamicSupervisor.which_children(LemmingsOs.LemmingInstances.PoolSupervisor) != []
    assert ResourcePool.status(resource_key) == {1, 1}

    assert :ok = ResourcePool.checkin(resource_key)
    GenServer.stop(pool_pid)
  end

  defp ensure_registry!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({Registry, keys: :unique, name: name})
        :ok
    end
  end

  defp ensure_dynamic_supervisor!(name) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        start_supervised!({DynamicSupervisor, name: name, strategy: :one_for_one})
        :ok
    end
  end
end
