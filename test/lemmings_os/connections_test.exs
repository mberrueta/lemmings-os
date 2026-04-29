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

      world_connection = insert(:world_connection, world: world, slug: "world-main")
      _city_connection = insert(:city_connection, world: world, city: city, slug: "city-main")

      _department_connection =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          slug: "department-main"
        )

      assert [result] = Connections.list_connections(world)
      assert result.id == world_connection.id

      assert nil == Connections.get_connection(city, world_connection.id)
      assert %{} = Connections.get_connection_by_slug(world, "world-main")
      assert nil == Connections.get_connection_by_slug(city, "world-main")
    end
  end

  describe "create_connection/2" do
    test "creates at exact world scope and records lifecycle event" do
      world = insert(:world)

      assert {:ok, connection} =
               Connections.create_connection(world, %{
                 slug: "github-main",
                 name: "GitHub Main",
                 type: "mock",
                 provider: "mock",
                 status: "enabled",
                 config: %{"base_url" => "https://example.test"},
                 secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
                 metadata: %{"env" => "dev"}
               })

      assert connection.world_id == world.id
      assert is_nil(connection.city_id)
      assert is_nil(connection.department_id)

      [event] = Events.list_recent_events(world, event_types: ["connection.created"], limit: 1)
      assert event.payload["connection_id"] == connection.id
      assert event.payload["secret_ref_keys"] == ["api_key"]
      refute Map.has_key?(event.payload, "secret_refs")
    end

    test "returns invalid_scope for malformed map scope" do
      assert {:error, :invalid_scope} =
               Connections.create_connection(%{city_id: Ecto.UUID.generate()}, %{})
    end
  end

  describe "update_connection/3" do
    test "updates local connection and records lifecycle event" do
      world = insert(:world)
      connection = insert(:world_connection, world: world, name: "Before")

      assert {:ok, updated} = Connections.update_connection(world, connection, %{name: "After"})
      assert updated.name == "After"

      [event] = Events.list_recent_events(world, event_types: ["connection.updated"], limit: 1)
      assert event.payload["connection_id"] == connection.id
      assert event.payload["connection_name"] == "After"
    end

    test "rejects updates outside exact scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      connection = insert(:world_connection, world: world)

      assert {:error, :scope_mismatch} =
               Connections.update_connection(city, connection, %{name: "Nope"})
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
    test "nearest visible scope wins and shadowed parent slug is hidden in list" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      world_conn =
        insert(:world_connection,
          world: world,
          slug: "shared",
          name: "World Shared",
          status: "disabled"
        )

      city_conn =
        insert(:city_connection,
          world: world,
          city: city,
          slug: "shared",
          name: "City Shared",
          status: "enabled"
        )

      department_conn =
        insert(:department_connection,
          world: world,
          city: city,
          department: department,
          slug: "shared",
          name: "Department Shared",
          status: "invalid"
        )

      insert(:world_connection, world: world, slug: "world-only", name: "World Only")

      visible = Connections.list_visible_connections(department)
      slugs = Enum.map(visible, & &1.connection.slug)

      assert slugs == ["shared", "world-only"]

      shared = Enum.find(visible, fn row -> row.connection.slug == "shared" end)
      assert shared.connection.id == department_conn.id
      assert shared.source_scope == "department"
      assert shared.local?
      refute shared.inherited?
      assert shared.scope_depth == 0

      resolved = Connections.resolve_visible_connection(department, "shared")
      assert resolved.connection.id == department_conn.id
      assert resolved.connection.status == "invalid"

      city_resolved = Connections.resolve_visible_connection(city, "shared")
      assert city_resolved.connection.id == city_conn.id
      assert city_resolved.source_scope == "city"
      assert city_resolved.local?

      world_resolved = Connections.resolve_visible_connection(world, "shared")
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
        slug: "dept-a-only"
      )

      assert nil == Connections.resolve_visible_connection(department_b, "dept-a-only")

      refute Enum.any?(
               Connections.list_visible_connections(department_b),
               &(&1.connection.slug == "dept-a-only")
             )
    end

    test "cross-world lookup fails safely" do
      world_a = insert(:world)
      world_b = insert(:world)
      city_b = insert(:city, world: world_b)

      insert(:world_connection, world: world_a, slug: "world-a-secret")

      assert nil == Connections.resolve_visible_connection(world_b, "world-a-secret")
      assert nil == Connections.resolve_visible_connection(city_b, "world-a-secret")
    end
  end

  describe "test_connection/2" do
    test "succeeds with valid mock config and resolvable secret refs" do
      world = insert(:world)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "MOCK_API_KEY", "dev_only_connection_secret_value")

      insert(:world_connection,
        world: world,
        slug: "mock-success",
        type: "mock",
        provider: "mock",
        status: "enabled",
        config: %{"mode" => "echo", "base_url" => "https://example.test"},
        secret_refs: %{"api_key" => "$MOCK_API_KEY"}
      )

      assert {:ok, %{connection: updated_connection, result: result}} =
               Connections.test_connection(world, "mock-success")

      assert updated_connection.last_test_status == "succeeded"
      assert is_nil(updated_connection.last_test_error)
      assert %DateTime{} = updated_connection.last_tested_at
      assert result.mode == "echo"
      assert result.outcome == "mock_echo_ok"
      assert result.resolved_secret_count == 1
      assert result.secret_ref_keys == ["api_key"]

      event_types =
        Events.list_recent_events(world,
          event_types: [
            "connection.test.started",
            "connection.test.succeeded",
            "connection.test.failed"
          ],
          limit: 10
        )
        |> Enum.map(& &1.event_type)

      assert "connection.test.started" in event_types
      assert "connection.test.succeeded" in event_types
      refute "connection.test.failed" in event_types

      [event] =
        Events.list_recent_events(world,
          event_types: ["connection.test.succeeded"],
          limit: 1
        )

      assert event.payload["connection_id"] == updated_connection.id
      assert event.payload["connection_slug"] == "mock-success"
      assert event.payload["connection_type"] == "mock"
      assert event.payload["provider"] == "mock"
      assert event.payload["status"] == "enabled"
      assert event.payload["last_test_status"] == "succeeded"
      assert event.payload["last_test_error"] == nil

      refute String.contains?(inspect(event.payload), "dev_only_connection_secret_value")
    end

    test "persists failed test state for invalid mock config" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        slug: "mock-invalid-config",
        type: "mock",
        provider: "mock",
        status: "enabled",
        config: %{"mode" => "echo"},
        secret_refs: %{"api_key" => "$MISSING_TOKEN"}
      )

      assert {:error, :invalid_config} = Connections.test_connection(world, "mock-invalid-config")

      updated = Connections.get_connection_by_slug(world, "mock-invalid-config")

      assert updated.last_test_status == "failed"
      assert updated.last_test_error == "invalid_config"
      assert %DateTime{} = updated.last_tested_at

      [failed_event] =
        Events.list_recent_events(world,
          event_types: ["connection.test.failed"],
          limit: 1
        )

      assert failed_event.payload["connection_slug"] == "mock-invalid-config"
      assert failed_event.payload["connection_type"] == "mock"
      assert failed_event.payload["provider"] == "mock"
      assert failed_event.payload["status"] == "enabled"
      assert failed_event.payload["last_test_status"] == "failed"
      assert failed_event.payload["last_test_error"] == "invalid_config"
      assert failed_event.payload["reason"] == "invalid_config"
      refute String.contains?(inspect(failed_event.payload), "$MISSING_TOKEN")
    end

    test "fails safely when required secret ref cannot be resolved" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        slug: "mock-missing-secret",
        type: "mock",
        provider: "mock",
        status: "enabled",
        config: %{"mode" => "echo", "base_url" => "https://example.test"},
        secret_refs: %{"api_key" => "$NOT_CONFIGURED_ANYWHERE"}
      )

      assert {:error, :missing_secret} = Connections.test_connection(world, "mock-missing-secret")

      updated = Connections.get_connection_by_slug(world, "mock-missing-secret")

      assert updated.last_test_status == "failed"
      assert updated.last_test_error == "missing_secret"
      assert %DateTime{} = updated.last_tested_at
      refute updated.last_test_error == "dev_only_connection_secret_value"
    end

    test "disabled and invalid connections fail test execution and persist failure" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        slug: "disabled-conn",
        status: "disabled",
        config: %{"mode" => "echo", "base_url" => "https://example.test"},
        secret_refs: %{"api_key" => "$NOT_USED"}
      )

      insert(:world_connection,
        world: world,
        slug: "invalid-conn",
        status: "invalid",
        config: %{"mode" => "echo", "base_url" => "https://example.test"},
        secret_refs: %{"api_key" => "$NOT_USED"}
      )

      assert {:error, :disabled} = Connections.test_connection(world, "disabled-conn")
      assert {:error, :invalid} = Connections.test_connection(world, "invalid-conn")

      assert "disabled" ==
               Connections.get_connection_by_slug(world, "disabled-conn").last_test_error

      assert "invalid" ==
               Connections.get_connection_by_slug(world, "invalid-conn").last_test_error
    end

    test "unsupported provider combinations fail without provider-specific execution" do
      world = insert(:world)

      insert(:world_connection,
        world: world,
        slug: "non-mock-provider",
        type: "generic",
        provider: "generic",
        status: "enabled",
        config: %{},
        secret_refs: %{}
      )

      assert {:error, :unsupported_provider} =
               Connections.test_connection(world, "non-mock-provider")

      updated = Connections.get_connection_by_slug(world, "non-mock-provider")
      assert updated.last_test_status == "failed"
      assert updated.last_test_error == "unsupported_provider"
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
          slug: "shared-inherited",
          status: "enabled",
          config: %{"mode" => "echo", "base_url" => "https://example.test"},
          secret_refs: %{"api_key" => "$MOCK_API_KEY"}
        )

      assert [] == Connections.list_connections(department)

      assert {:ok, %{connection: tested_connection}} =
               Connections.test_connection(department, "shared-inherited")

      assert tested_connection.id == world_connection.id

      updated_world_connection = Connections.get_connection(world, world_connection.id)
      assert updated_world_connection.last_test_status == "succeeded"
      assert is_nil(updated_world_connection.last_test_error)
      assert %DateTime{} = updated_world_connection.last_tested_at

      assert nil == Connections.get_connection(department, world_connection.id)
      assert [] == Connections.list_connections(department)
    end
  end
end
