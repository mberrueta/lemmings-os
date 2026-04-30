defmodule LemmingsOs.Connections.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections.Runtime
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank

  doctest LemmingsOs.Connections.Runtime

  describe "resolve_connection/3" do
    test "resolves nearest visible usable connection and returns safe descriptor" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      insert(:world_connection,
        world: world,
        type: "mock",
        config: %{
          "mode" => "echo",
          "base_url" => "https://world.example.test/mock",
          "api_key" => "$WORLD_TOKEN"
        }
      )

      department_connection =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://department.example.test/mock",
            "api_key" => "$DEPT_TOKEN"
          }
        )

      assert {:ok, descriptor} = Runtime.resolve_connection(department, "mock")
      assert descriptor.connection_id == department_connection.id
      assert descriptor.type == "mock"
      assert descriptor.source_scope == "department"
      assert descriptor.local?
      assert descriptor.inherited? == false
      assert descriptor.config["api_key"] == "$DEPT_TOKEN"

      inspected = inspect(descriptor)
      refute String.contains?(inspected, "$DEPT_TOKEN")
      refute String.contains?(inspected, "api_key")

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
        insert(:world_connection, world: world, type: "mock", status: "disabled")

      assert {:error, :disabled} = Runtime.resolve_connection(world, "mock")

      failure_reasons =
        Events.list_recent_events(world, event_types: ["connection.resolve.failed"], limit: 10)
        |> Enum.map(& &1.payload)

      assert Enum.any?(failure_reasons, fn payload ->
               payload["reason"] == "disabled" and
                 payload["connection_id"] == disabled_connection.id and
                 payload["connection_type"] == disabled_connection.type and
                 payload["status"] == "disabled"
             end)
    end

    test "returns missing for non-visible or absent type" do
      world = insert(:world)
      city = insert(:city, world: world)
      department_a = insert(:department, world: world, city: city)
      department_b = insert(:department, world: world, city: city)

      insert(:department_connection,
        world: world,
        city: city,
        department: department_a,
        type: "mock"
      )

      assert {:error, :missing} = Runtime.resolve_connection(department_b, "mock")
      assert {:error, :missing} = Runtime.resolve_connection(world, "unknown")

      [failure_event | _] =
        Events.list_recent_events(world, event_types: ["connection.resolve.failed"], limit: 10)

      assert failure_event.payload["reason"] == "missing"
      assert failure_event.payload["connection_id"] == nil
      assert failure_event.payload["connection_type"] in ["mock", "unknown"]
      assert failure_event.payload["status"] == nil
    end

    test "returns inaccessible for non-struct scope input" do
      assert {:error, :inaccessible} = Runtime.resolve_connection(%{}, "mock")
    end

    test "does not resolve secrets through runtime facade" do
      world = insert(:world)

      assert {:ok, _metadata} = SecretBank.upsert_secret(world, "MOCK_API_KEY", "runtime_secret")

      insert(:world_connection,
        world: world,
        type: "mock",
        status: "enabled",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "$MOCK_API_KEY"
        }
      )

      assert {:ok, _descriptor} = Runtime.resolve_connection(world, "mock")

      assert [] ==
               Events.list_recent_events(world,
                 event_types: ["secret.resolved"],
                 limit: 10
               )
    end
  end
end
