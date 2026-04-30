defmodule LemmingsOs.Connections.Providers.MockCallerTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Connections.Providers.MockCaller
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank

  doctest LemmingsOs.Connections.Providers.MockCaller

  test "resolves config secret refs through Secret Bank and returns sanitized result" do
    world = insert(:world)

    assert {:ok, _metadata} = SecretBank.upsert_secret(world, "MOCK_API_KEY", "very_secret_value")

    connection =
      insert(:world_connection,
        world: world,
        type: "mock",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "$MOCK_API_KEY"
        }
      )

    assert {:ok, result} = MockCaller.call(world, connection)
    assert result.outcome == "mock_echo_ok"
    assert result.resolved_secret_keys == ["api_key"]
    refute String.contains?(inspect(result), "very_secret_value")

    [event] =
      Events.list_recent_events(world,
        event_types: ["secret.resolved"],
        limit: 1
      )

    assert event.event_type == "secret.resolved"
    refute String.contains?(inspect(event.payload), "very_secret_value")
  end

  test "returns missing_secret when referenced key is not configured" do
    world = insert(:world)

    connection =
      insert(:world_connection,
        world: world,
        type: "mock",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "$MISSING_MOCK_API_KEY"
        }
      )

    assert {:error, :missing_secret} = MockCaller.call(world, connection)
  end

  test "rejects invalid config and never resolves secrets" do
    world = insert(:world)

    connection =
      insert(:world_connection,
        world: world,
        type: "mock",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "raw-secret"
        }
      )

    assert {:error, :invalid_config} = MockCaller.call(world, connection)

    assert [] ==
             Events.list_recent_events(world,
               event_types: ["secret.resolved"],
               limit: 5
             )
  end

  test "rejects disabled and invalid connections before any secret resolution" do
    world = insert(:world)

    assert {:ok, _metadata} = SecretBank.upsert_secret(world, "MOCK_API_KEY", "very_secret_value")

    disabled_connection =
      insert(:world_connection,
        world: world,
        type: "mock",
        status: "disabled",
        config: %{
          "mode" => "echo",
          "base_url" => "https://example.test/mock",
          "api_key" => "$MOCK_API_KEY"
        }
      )

    invalid_connection = %{disabled_connection | status: "invalid"}

    assert {:error, :disabled} = MockCaller.call(world, disabled_connection)
    assert {:error, :invalid} = MockCaller.call(world, invalid_connection)

    assert [] ==
             Events.list_recent_events(world,
               event_types: ["secret.resolved"],
               limit: 10
             )
  end
end
