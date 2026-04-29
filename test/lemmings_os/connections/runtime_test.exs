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

      insert(:world_connection, world: world, slug: "disabled-conn", status: "disabled")
      insert(:world_connection, world: world, slug: "invalid-conn", status: "invalid")

      assert {:error, :disabled} = Runtime.resolve_connection(world, "disabled-conn")
      assert {:error, :invalid} = Runtime.resolve_connection(world, "invalid-conn")

      failure_reasons =
        Events.list_recent_events(world, event_types: ["connection.resolve.failed"], limit: 10)
        |> Enum.map(& &1.payload["reason"])

      assert "disabled" in failure_reasons
      assert "invalid" in failure_reasons
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
