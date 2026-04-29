defmodule LemmingsOs.SecretBankTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Events.Event
  alias LemmingsOs.Repo
  alias LemmingsOs.SecretBank
  alias LemmingsOs.SecretBank.Secret

  doctest LemmingsOs.SecretBank

  describe "upsert_secret/3" do
    test "encrypts values at rest and returns only safe metadata" do
      world = insert(:world)

      assert {:ok, metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_mock_secret_value")

      assert metadata.bank_key == "GITHUB_TOKEN"
      assert metadata.scope == "world"
      assert metadata.source == "local"
      assert metadata.configured
      assert metadata.allowed_actions == ["upsert", "delete"]
      refute Map.has_key?(metadata, :value)

      %{rows: [[ciphertext]]} =
        Ecto.Adapters.SQL.query!(
          Repo,
          "select value_encrypted from secret_bank_secrets where bank_key = $1",
          ["GITHUB_TOKEN"]
        )

      assert is_binary(ciphertext)
      refute ciphertext == "dev_only_mock_secret_value"
      assert :nomatch = :binary.match(ciphertext, "dev_only_mock_secret_value")
    end

    test "redacts decrypted runtime values from inspect output" do
      secret = %Secret{bank_key: "GITHUB_TOKEN", value: "dev_only_mock_secret_value"}

      refute inspect(secret) =~ "dev_only_mock_secret_value"
    end
  end

  describe "effective metadata" do
    test "picks the most specific local secret without exposing values" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_world_token")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(department, "GITHUB_TOKEN", "dev_only_department_token")

      [metadata] = SecretBank.list_effective_metadata(lemming, bank_key: "$secrets.GITHUB_TOKEN")

      assert metadata.bank_key == "GITHUB_TOKEN"
      assert metadata.scope == "department"
      assert metadata.source == "local"
      assert metadata.configured
      assert metadata.allowed_actions == ["upsert"]
      refute Map.has_key?(metadata, :value)
    end

    test "reports configured env fallback state from a closed allowlist" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: [
          "GITHUB_TOKEN",
          "OPENROUTER_API_KEY"
        ],
        env_fallbacks: [
          "GITHUB_TOKEN",
          {"OPENROUTER_API_KEY", "OPENROUTER_API_KEY"}
        ]
      )

      System.put_env("GITHUB_TOKEN", "dev_only_mock_env_token")
      System.delete_env("OPENROUTER_API_KEY")

      on_exit(fn ->
        System.delete_env("GITHUB_TOKEN")
        System.delete_env("OPENROUTER_API_KEY")
      end)

      [github_metadata] =
        SecretBank.list_effective_metadata(world, bank_key: "$secrets.GITHUB_TOKEN")

      assert github_metadata.source == "env"
      assert github_metadata.scope == "env"
      assert github_metadata.configured
      assert github_metadata.allowed_actions == ["upsert"]
      refute Map.has_key?(github_metadata, :value)
      refute Map.has_key?(github_metadata, :env_var)

      [openrouter_metadata] =
        SecretBank.list_effective_metadata(world, bank_key: "OPENROUTER_API_KEY")

      refute openrouter_metadata.configured
      assert [] = SecretBank.list_effective_metadata(world, bank_key: "UNKNOWN_KEY")
    end

    test "does not read env vars outside the explicit env var allowlist" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["GITHUB_TOKEN"],
        env_fallbacks: [
          {"OPENROUTER_API_KEY", "OPENROUTER_API_KEY"}
        ]
      )

      System.put_env("OPENROUTER_API_KEY", "dev_only_mock_openrouter_token")

      on_exit(fn ->
        System.delete_env("OPENROUTER_API_KEY")
      end)

      assert [] =
               SecretBank.list_effective_metadata(world, bank_key: "$secrets.OPENROUTER_API_KEY")
    end
  end

  describe "upsert_secret/3 and delete_secret/2" do
    test "upserts exact local secrets and keeps inherited delete protections" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_world_token")

      assert {:error, :inherited_secret_not_deletable} =
               SecretBank.delete_secret(city, "GITHUB_TOKEN")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(city, "GITHUB_TOKEN", "dev_only_city_token")

      assert {:ok, metadata} =
               SecretBank.upsert_secret(city, "GITHUB_TOKEN", "dev_only_replaced_city_token")

      assert metadata.scope == "city"
      assert metadata.allowed_actions == ["upsert", "delete"]

      assert {:ok, deleted_metadata} = SecretBank.delete_secret(city, "GITHUB_TOKEN")
      assert deleted_metadata.scope == "city"

      [inherited_metadata] = SecretBank.list_effective_metadata(city, bank_key: "GITHUB_TOKEN")
      assert inherited_metadata.scope == "world"
      assert inherited_metadata.allowed_actions == ["upsert"]
    end

    test "returns safe error atoms for invalid scope and missing local secrets" do
      world = insert(:world)

      assert {:error, :invalid_scope} =
               SecretBank.upsert_secret(%{}, "$secrets.github", "dev_only_value")

      assert {:error, :not_found} = SecretBank.delete_secret(world, "MISSING_TOKEN")
    end
  end

  describe "resolve_runtime_secret/2" do
    test "resolves the most specific local secret across scope hierarchy" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_world_token")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(city, "GITHUB_TOKEN", "dev_only_city_token")

      assert {:ok, resolved} =
               SecretBank.resolve_runtime_secret(lemming, "$secrets.GITHUB_TOKEN")

      assert resolved.bank_key == "GITHUB_TOKEN"
      assert resolved.value == "dev_only_city_token"
      assert resolved.scope == "city"
      assert resolved.source == "local"

      assert {:ok, resolved_again} = SecretBank.resolve_runtime_secret(lemming, "GITHUB_TOKEN")
      assert resolved_again == resolved
    end

    test "falls back to allowlisted env var by convention when no local secret exists" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["GITHUB_TOKEN"],
        env_fallbacks: ["GITHUB_TOKEN"]
      )

      System.put_env("GITHUB_TOKEN", "dev_only_mock_env_token")

      on_exit(fn ->
        System.delete_env("GITHUB_TOKEN")
      end)

      assert {:ok, resolved} = SecretBank.resolve_runtime_secret(world, "$secrets.GITHUB_TOKEN")
      assert resolved.bank_key == "GITHUB_TOKEN"
      assert resolved.value == "dev_only_mock_env_token"
      assert resolved.scope == "env"
      assert resolved.source == "env"
    end

    test "falls back to explicit env var override when configured" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["OPENROUTER_API_KEY"],
        env_fallbacks: [{"OPENROUTER_API_KEY", "OPENROUTER_API_KEY"}]
      )

      System.put_env("OPENROUTER_API_KEY", "dev_only_mock_openrouter_token")

      on_exit(fn ->
        System.delete_env("OPENROUTER_API_KEY")
      end)

      assert {:ok, resolved} = SecretBank.resolve_runtime_secret(world, "OPENROUTER_API_KEY")
      assert resolved.value == "dev_only_mock_openrouter_token"
      assert resolved.scope == "env"
      assert resolved.source == "env"
    end

    test "returns missing_secret when no local or allowlisted env value exists" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["GITHUB_TOKEN"],
        env_fallbacks: ["GITHUB_TOKEN"]
      )

      System.delete_env("GITHUB_TOKEN")

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(world, "$secrets.GITHUB_TOKEN")
    end

    test "does not read env var outside the explicit allowlist" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["GITHUB_TOKEN"],
        env_fallbacks: [{"OPENROUTER_API_KEY", "OPENROUTER_API_KEY"}]
      )

      System.put_env("OPENROUTER_API_KEY", "dev_only_mock_openrouter_token")

      on_exit(fn ->
        System.delete_env("OPENROUTER_API_KEY")
      end)

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(world, "$secrets.OPENROUTER_API_KEY")
    end

    test "returns safe errors for invalid scope and invalid key" do
      world = insert(:world)

      assert {:error, :invalid_scope} = SecretBank.resolve_runtime_secret(%{}, "GITHUB_TOKEN")
      assert {:error, :invalid_key} = SecretBank.resolve_runtime_secret(world, "")
    end

    test "maps local decrypt failures to decrypt_failed" do
      world = insert(:world)

      assert {:ok, metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_world_token")

      %{num_rows: 1} =
        Ecto.Adapters.SQL.query!(
          Repo,
          "update secret_bank_secrets set value_encrypted = $1 where world_id = $2 and bank_key = $3",
          [<<1, 2, 3, 4>>, Ecto.UUID.dump!(world.id), metadata.bank_key]
        )

      assert {:error, :decrypt_failed} =
               SecretBank.resolve_runtime_secret(world, "$secrets.GITHUB_TOKEN")
    end
  end

  describe "durable audit events" do
    test "records created, replaced, and deleted events without value material" do
      world = insert(:world)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_created_value")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_replaced_value")

      assert {:ok, _metadata} = SecretBank.delete_secret(world, "GITHUB_TOKEN")

      events =
        Repo.all(
          from(event in Event,
            where:
              event.world_id == ^world.id and
                event.event_type in ^["secret.created", "secret.replaced", "secret.deleted"],
            order_by: [asc: event.inserted_at, asc: event.id]
          )
        )

      assert MapSet.new(Enum.map(events, & &1.event_type)) ==
               MapSet.new(["secret.created", "secret.replaced", "secret.deleted"])

      assert Enum.all?(events, fn event ->
               fetch_map(event.payload, :bank_key) == "GITHUB_TOKEN" and
                 fetch_map(event.payload, :secret_ref) == "$secrets.GITHUB_TOKEN"
             end)

      refute Enum.any?(events, fn event ->
               payload = inspect(event.payload || %{})
               payload =~ "dev_only_created_value" or payload =~ "dev_only_replaced_value"
             end)
    end

    test "records accessed and access_failed events with scope and reason" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(department, "GITHUB_TOKEN", "dev_only_department_value")

      assert {:ok, _resolved} =
               SecretBank.resolve_runtime_secret(
                 lemming,
                 "$secrets.GITHUB_TOKEN",
                 tool_name: "tools.gh"
               )

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(
                 lemming,
                 "$secrets.STRIPE_TOKEN",
                 tool_name: "tools.gh"
               )

      activities = SecretBank.list_recent_activity(lemming, limit: 10)
      activity_types = Enum.map(activities, & &1.event_type)

      assert "secret.accessed" in activity_types
      assert "secret.access_failed" in activity_types

      accessed = Enum.find(activities, &(&1.event_type == "secret.accessed"))
      failed = Enum.find(activities, &(&1.event_type == "secret.access_failed"))

      assert accessed.message == "GITHUB_TOKEN used in tools.gh"
      assert fetch_map(accessed.payload, :resolved_source) == "department"
      assert fetch_map(accessed.payload, :tool_name) == "tools.gh"

      assert failed.message == "STRIPE_TOKEN access failed"
      assert fetch_map(failed.payload, :reason) == "missing_secret"
      assert fetch_map(failed.payload, :tool_name) == "tools.gh"
    end

    test "lists recent activity filtered by scope relevance and event type" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_world_value")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(department, "GITHUB_TOKEN", "dev_only_department_value")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(other_city, "STRIPE_TOKEN", "dev_only_other_city_value")

      activities =
        SecretBank.list_recent_activity(department,
          event_types: ["secret.created"],
          limit: 20
        )

      scopes = MapSet.new(activities, & &1.scope)
      messages = Enum.map(activities, & &1.message)

      assert "world" in scopes
      assert "department" in scopes
      refute Enum.any?(messages, &String.contains?(&1, "STRIPE_TOKEN"))
      refute Enum.any?(activities, &(&1.event_type != "secret.created"))
    end
  end

  defp put_secret_bank_config(config) do
    previous = Application.get_env(:lemmings_os, SecretBank, [])

    Application.put_env(:lemmings_os, SecretBank, config)

    on_exit(fn ->
      Application.put_env(:lemmings_os, SecretBank, previous)
    end)
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
