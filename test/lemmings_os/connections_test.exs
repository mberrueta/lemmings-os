defmodule LemmingsOs.ConnectionsTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank

  doctest LemmingsOs.Connections

  describe "list/get local connections" do
    test "lists only local records for the exact scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      world_connection = insert(:world_connection, world: world, type: "mock")

      _city_connection =
        insert(:city_connection,
          world: world,
          city: city,
          type: "mock",
          config: %{
            "mode" => "echo",
            "base_url" => "https://city.example.test/mock",
            "api_key" => "$CITY_MOCK_API_KEY"
          }
        )

      _department_connection =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          type: "mock",
          config: %{
            "mode" => "echo",
            "base_url" => "https://department.example.test/mock",
            "api_key" => "$DEPARTMENT_MOCK_API_KEY"
          }
        )

      assert [result] = Connections.list_connections(world)
      assert result.id == world_connection.id

      assert nil == Connections.get_connection(city, world_connection.id)
      assert %{} = Connections.get_connection_by_type(world, "mock")
      assert nil == Connections.get_connection_by_type(city, "not-registered")
    end
  end

  describe "create_connection/2" do
    test "creates at exact world scope and records lifecycle event" do
      world = insert(:world)

      assert {:ok, connection} =
               Connections.create_connection(world, %{
                 type: "mock",
                 status: "enabled",
                 config: %{
                   "mode" => "echo",
                   "base_url" => "https://example.test/mock",
                   "api_key" => "$GITHUB_TOKEN"
                 }
               })

      assert connection.world_id == world.id
      assert is_nil(connection.city_id)
      assert is_nil(connection.department_id)

      [event] = Events.list_recent_events(world, event_types: ["connection.created"], limit: 1)
      assert event.payload["connection_id"] == connection.id
      assert event.payload["connection_type"] == "mock"
      refute String.contains?(inspect(event.payload), "$GITHUB_TOKEN")
    end

    test "returns invalid_scope for non-struct scope" do
      assert {:error, :invalid_scope} = Connections.create_connection(%{}, %{})
    end

    test "ignores caller-provided last_test when creating connection" do
      world = insert(:world)

      assert {:ok, connection} =
               Connections.create_connection(world, %{
                 type: "mock",
                 status: "enabled",
                 last_test: "leak_me_if_broken",
                 config: %{
                   "mode" => "echo",
                   "base_url" => "https://example.test/mock",
                   "api_key" => "$MOCK_API_KEY"
                 }
               })

      assert is_nil(connection.last_test)

      [event] = Events.list_recent_events(world, event_types: ["connection.created"], limit: 1)
      refute String.contains?(inspect(event.payload), "leak_me_if_broken")
    end
  end

  describe "update_connection/3" do
    test "updates local connection config and records lifecycle event" do
      world = insert(:world)
      connection = insert(:world_connection, world: world)

      assert {:ok, updated} =
               Connections.update_connection(world, connection, %{
                 config: %{
                   "mode" => "echo",
                   "base_url" => "https://updated.example.test/mock",
                   "api_key" => "$UPDATED_MOCK_API_KEY"
                 }
               })

      assert updated.config["base_url"] == "https://updated.example.test/mock"

      [event] = Events.list_recent_events(world, event_types: ["connection.updated"], limit: 1)
      assert event.payload["connection_id"] == connection.id
      assert event.payload["connection_type"] == "mock"
    end

    test "rejects updates outside exact scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      connection = insert(:world_connection, world: world)

      assert {:error, :scope_mismatch} =
               Connections.update_connection(city, connection, %{
                 config: %{
                   "mode" => "echo",
                   "base_url" => "https://nope.example.test/mock",
                   "api_key" => "$NOPE_MOCK_API_KEY"
                 }
               })
    end

    test "ignores caller-provided last_test when updating connection" do
      world = insert(:world)
      connection = insert(:world_connection, world: world, last_test: "succeeded: mock_echo_ok")

      assert {:ok, updated} =
               Connections.update_connection(world, connection, %{
                 last_test: "leak_me_if_broken",
                 config: %{
                   "mode" => "echo",
                   "base_url" => "https://updated.example.test/mock",
                   "api_key" => "$UPDATED_MOCK_API_KEY"
                 }
               })

      assert updated.last_test == "succeeded: mock_echo_ok"

      [event] = Events.list_recent_events(world, event_types: ["connection.updated"], limit: 1)
      refute String.contains?(inspect(event.payload), "leak_me_if_broken")
    end
  end

  describe "status transitions" do
    test "enable/disable/mark invalid update status and record events" do
      world = insert(:world)
      connection = insert(:world_connection, world: world, status: "enabled")

      assert {:ok, disabled} = Connections.disable_connection(world, connection)
      assert disabled.status == "disabled"

      assert {:ok, enabled} = Connections.enable_connection(world, disabled)
      assert enabled.status == "enabled"

      assert {:ok, invalid} = Connections.mark_connection_invalid(world, enabled)
      assert invalid.status == "invalid"

      event_types =
        Events.list_recent_events(world,
          event_types: [
            "connection.disabled",
            "connection.enabled",
            "connection.marked_invalid"
          ],
          limit: 10
        )
        |> Enum.map(& &1.event_type)

      assert "connection.disabled" in event_types
      assert "connection.enabled" in event_types
      assert "connection.marked_invalid" in event_types
    end
  end

  describe "delete_connection/2" do
    test "deletes only local connection and records lifecycle event" do
      world = insert(:world)
      connection = insert(:world_connection, world: world)

      assert {:ok, deleted} = Connections.delete_connection(world, connection)
      assert deleted.id == connection.id
      assert nil == Repo.get(LemmingsOs.Connections.Connection, connection.id)

      [event] = Events.list_recent_events(world, event_types: ["connection.deleted"], limit: 1)
      assert event.payload["connection_id"] == connection.id
    end

    test "rejects delete outside exact scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      connection = insert(:world_connection, world: world)

      assert {:error, :scope_mismatch} = Connections.delete_connection(city, connection)
      assert Repo.get(LemmingsOs.Connections.Connection, connection.id)
    end
  end

  describe "hierarchy lookup and read model" do
    test "nearest visible scope wins by type and shadowed parent is hidden in list" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      world_conn =
        insert(:world_connection,
          world: world,
          type: "mock",
          status: "disabled"
        )

      city_conn =
        insert(:city_connection,
          world: world,
          city: city,
          type: "mock",
          status: "enabled",
          config: %{
            "mode" => "echo",
            "base_url" => "https://city.example.test/mock",
            "api_key" => "$CITY_MOCK_API_KEY"
          }
        )

      department_conn =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          type: "mock",
          status: "invalid",
          config: %{
            "mode" => "echo",
            "base_url" => "https://department.example.test/mock",
            "api_key" => "$DEPARTMENT_MOCK_API_KEY"
          }
        )

      visible = Connections.list_visible_connections(department)
      types = Enum.map(visible, & &1.connection.type)

      assert types == ["mock"]

      shared = Enum.find(visible, fn row -> row.connection.type == "mock" end)
      assert shared.connection.id == department_conn.id
      assert shared.source_scope == "department"
      assert shared.local?
      refute shared.inherited?
      assert shared.scope_depth == 0

      resolved = Connections.resolve_visible_connection(department, "mock")
      assert resolved.connection.id == department_conn.id
      assert resolved.connection.status == "invalid"

      city_resolved = Connections.resolve_visible_connection(city, "mock")
      assert city_resolved.connection.id == city_conn.id
      assert city_resolved.source_scope == "city"
      assert city_resolved.local?

      world_resolved = Connections.resolve_visible_connection(world, "mock")
      assert world_resolved.connection.id == world_conn.id
      assert world_resolved.source_scope == "world"
      assert world_resolved.local?
    end

    test "department cannot see sibling department scoped connection" do
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

      assert nil == Connections.resolve_visible_connection(department_b, "mock")
      assert [] == Connections.list_visible_connections(department_b)
    end

    test "cross-world lookup fails safely" do
      world_a = insert(:world)
      world_b = insert(:world)
      city_b = insert(:city, world: world_b)

      insert(:world_connection, world: world_a, type: "mock")

      assert nil == Connections.resolve_visible_connection(world_b, "mock")
      assert nil == Connections.resolve_visible_connection(city_b, "mock")
    end

    test "non-struct scope inputs fail closed" do
      assert [] == Connections.list_visible_connections(%{})
      assert nil == Connections.resolve_visible_connection(%{}, "mock")
    end
  end

  describe "test_connection/2" do
    test "succeeds with valid mock config and resolvable secret refs in config" do
      world = insert(:world)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "MOCK_API_KEY", "dev_only_connection_secret_value")

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

      assert {:ok, %{connection: updated_connection, result: result}} =
               Connections.test_connection(world, "mock")

      assert updated_connection.last_test == "succeeded: mock_echo_ok"
      assert result.mode == "echo"
      assert result.outcome == "mock_echo_ok"
      assert result.resolved_secret_keys == ["api_key"]

      [event] =
        Events.list_recent_events(world,
          event_types: ["connection.test.succeeded"],
          limit: 1
        )

      assert event.payload["connection_id"] == updated_connection.id
      assert event.payload["connection_type"] == "mock"
      assert event.payload["last_test"] == "succeeded: mock_echo_ok"
      refute String.contains?(inspect(event.payload), "dev_only_connection_secret_value")
    end

    test "persists failed test state for invalid mock config" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        type: "mock",
        status: "enabled",
        config: %{"mode" => "echo"}
      )

      assert {:error, :invalid_config} = Connections.test_connection(world, "mock")

      updated = Connections.get_connection_by_type(world, "mock")

      assert updated.last_test == "failed: invalid_config"
    end

    test "fails safely when required secret ref cannot be resolved" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        type: "mock",
        status: "enabled",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "$NOT_CONFIGURED_ANYWHERE"
        }
      )

      assert {:error, :missing_secret} = Connections.test_connection(world, "mock")

      updated = Connections.get_connection_by_type(world, "mock")

      assert updated.last_test == "failed: missing_secret"
      refute updated.last_test == "dev_only_connection_secret_value"
    end

    test "disabled and invalid connections fail test execution and persist failure" do
      world = insert(:world)

      insert(:world_connection, world: world, type: "mock", status: "disabled")

      assert {:error, :disabled} = Connections.test_connection(world, "mock")
      assert "failed: disabled" == Connections.get_connection_by_type(world, "mock").last_test
    end

    test "testing inherited connection updates source row and does not create a child override" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "MOCK_API_KEY", "dev_only_world_mock_secret")

      world_connection =
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

      assert [] == Connections.list_connections(department)

      assert {:ok, %{connection: tested_connection}} =
               Connections.test_connection(department, "mock")

      assert tested_connection.id == world_connection.id

      updated_world_connection = Connections.get_connection(world, world_connection.id)
      assert updated_world_connection.last_test == "succeeded: mock_echo_ok"

      assert nil == Connections.get_connection(department, world_connection.id)
      assert [] == Connections.list_connections(department)
    end

    test "last_test never includes raw secret values" do
      world = insert(:world)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "MOCK_API_KEY", "leak_me_if_broken")

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

      assert {:ok, %{connection: connection}} = Connections.test_connection(world, "mock")

      refute String.contains?(connection.last_test || "", "leak_me_if_broken")

      [event] =
        Events.list_recent_events(world,
          event_types: ["connection.test.succeeded"],
          limit: 1
        )

      refute String.contains?(inspect(event.payload), "leak_me_if_broken")
    end
  end
end
