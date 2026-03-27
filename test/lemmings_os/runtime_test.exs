defmodule LemmingsOs.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Runtime

  test "S01: spawn_session/3 persists an instance and its first user message" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)

    lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: department,
        status: "active"
      )

    assert {:ok, instance} = Runtime.spawn_session(lemming, "Summarize the roadmap")
    assert instance.status == "created"

    [message] = LemmingInstances.list_messages(instance)
    assert {message.role, message.content} == {"user", "Summarize the roadmap"}
  end
end
