defmodule LemmingsOs.Connections.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections.Runtime
  alias LemmingsOs.Events

  doctest LemmingsOs.Connections.Runtime

  describe "resolve_connection/3" do
    test "resolves nearest visible usable connection and returns safe descriptor" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      insert(:world_connection,
        world: world,
        slug: "shared",
        name: "World Shared",
        secret_refs: %{"api_key" => "$WORLD_TOKEN"}
      )

      department_connection =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          slug: "shared",
          name: "Department Shared",
          status: "enabled",
          secret_refs: %{"api_key" => "$DEPT_TOKEN"}
        )

      assert {:ok, descriptor} = Runtime.resolve_connection(department, "shared")
      assert descriptor.connection_id == department_connection.id
      assert descriptor.slug == "shared"
      assert descriptor.source_scope == "department"
      assert descriptor.local?
      assert descriptor.inherited? == false
      assert descriptor.secret_ref_keys == ["api_key"]

      refute Map.has_key?(Map.from_struct(descriptor), :secret_refs)
      inspected = inspect(descriptor)
      refute String.contains?(inspected, "$DEPT_TOKEN")

      event_types =
        Events.list_recent_events(department,
          event_types: ["connection.resolve.started", "connection.resolve.succeeded"],
          limit: 10
        )
        |> Enum.map(& &1.event_type)

      assert "connection.resolve.started" in event_types
      assert "connection.resolve.succeeded" in event_types
    end

    test "returns disabled and invalid errors for unusable statuses" do
      world = insert(:world)

      disabled_connection =
        insert(:world_connection, world: world, slug: "disabled-conn", status: "disabled")

      invalid_connection =
        insert(:world_connection, world: world, slug: "invalid-conn", status: "invalid")

      assert {:error, :disabled} = Runtime.resolve_connection(world, "disabled-conn")
      assert {:error, :invalid} = Runtime.resolve_connection(world, "invalid-conn")

      failure_reasons =
        Events.list_recent_events(world, event_types: ["connection.resolve.failed"], limit: 10)
        |> Enum.map(& &1.payload)

      assert Enum.any?(failure_reasons, fn payload ->
               payload["reason"] == "disabled" and
                 payload["connection_id"] == disabled_connection.id and
                 payload["connection_slug"] == "disabled-conn" and
                 payload["connection_type"] == disabled_connection.type and
                 payload["provider"] == disabled_connection.provider and
                 payload["status"] == "disabled"
             end)

      assert Enum.any?(failure_reasons, fn payload ->
               payload["reason"] == "invalid" and
                 payload["connection_id"] == invalid_connection.id and
                 payload["connection_slug"] == "invalid-conn" and
                 payload["connection_type"] == invalid_connection.type and
                 payload["provider"] == invalid_connection.provider and
                 payload["status"] == "invalid"
             end)
    end

    test "returns missing for non-visible or absent slug" do
      world = insert(:world)
      city = insert(:city, world: world)
      department_a = insert(:department, world: world, city: city)
      department_b = insert(:department, world: world, city: city)

      insert(:department_connection,
        world: world,
        city: city,
        department: department_a,
        slug: "dept-a-only"
      )

      assert {:error, :missing} = Runtime.resolve_connection(department_b, "dept-a-only")
      assert {:error, :missing} = Runtime.resolve_connection(world, "unknown")

      [failure_event | _] =
        Events.list_recent_events(world, event_types: ["connection.resolve.failed"], limit: 10)

      assert failure_event.payload["reason"] == "missing"
      assert failure_event.payload["connection_id"] == nil
      assert failure_event.payload["connection_type"] == nil
      assert failure_event.payload["provider"] == nil
      assert failure_event.payload["status"] == nil
      assert failure_event.payload["connection_slug"] in ["dept-a-only", "unknown"]
      refute String.contains?(inspect(failure_event.payload), "$")
    end

    test "returns inaccessible for invalid scope shape" do
      assert {:error, :inaccessible} =
               Runtime.resolve_connection(%{city_id: Ecto.UUID.generate()}, "anything")
    end

    test "does not record started event when scope is invalid" do
      assert {:error, :inaccessible} = Runtime.resolve_connection(%{}, "whatever")

      assert [] ==
               Events.list_recent_events(%{world_id: Ecto.UUID.generate()},
                 event_types: ["connection.resolve.started"],
                 limit: 5
               )
    end
  end
end
