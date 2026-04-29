defmodule LemmingsOs.EventsTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.Events

  doctest LemmingsOs.Events

  describe "record_event/4" do
    test "records generic non-secret event types without schema changes" do
      world = insert(:world)

      assert {:ok, event} =
               Events.record_event(
                 "api.requested",
                 world,
                 "POST /v1/issues requested",
                 payload: %{method: "POST", endpoint: "/v1/issues"}
               )

      assert event.event_family == "audit"
      assert event.event_type == "api.requested"
      assert event.world_id == world.id
      assert event.message == "POST /v1/issues requested"
      assert fetch_map(event.payload, :method) == "POST"
      assert is_binary(event.correlation_id)
    end
  end

  describe "list_recent_events/2" do
    test "filters by hierarchy relevance and event type" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, _event} =
               Events.record_event("api.requested", world, "world event",
                 payload: %{scope: "world"}
               )

      assert {:ok, _event} =
               Events.record_event("api.requested", city, "city event", payload: %{scope: "city"})

      assert {:ok, _event} =
               Events.record_event("api.requested", department, "department event",
                 payload: %{scope: "department"}
               )

      assert {:ok, _event} =
               Events.record_event("api.requested", lemming, "lemming event",
                 payload: %{scope: "lemming"}
               )

      assert {:ok, _event} =
               Events.record_event("api.requested", other_city, "other city event",
                 payload: %{scope: "other_city"}
               )

      events = Events.list_recent_events(department, event_types: ["api.requested"], limit: 10)
      messages = MapSet.new(events, & &1.message)

      assert "world event" in messages
      assert "city event" in messages
      assert "department event" in messages
      assert "lemming event" in messages
      refute "other city event" in messages
    end
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
