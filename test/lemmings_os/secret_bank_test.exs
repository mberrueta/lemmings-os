defmodule LemmingsOs.SecretBankTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Events.Event
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.SecretBank
  alias LemmingsOs.SecretBank.Secret
  alias LemmingsOs.Worlds.World

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

      [metadata] = SecretBank.list_effective_metadata(lemming, bank_key: "$GITHUB_TOKEN")

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
          "$GITHUB_TOKEN",
          "$OPENROUTER_API_KEY"
        ],
        env_fallbacks: ["$GITHUB_TOKEN", {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}]
      )

      System.put_env("GITHUB_TOKEN", "dev_only_mock_env_token")
      System.delete_env("OPENROUTER_API_KEY")

      on_exit(fn ->
        System.delete_env("GITHUB_TOKEN")
        System.delete_env("OPENROUTER_API_KEY")
      end)

      [github_metadata] =
        SecretBank.list_effective_metadata(world, bank_key: "$GITHUB_TOKEN")

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
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: [
          {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}
        ]
      )

      System.put_env("OPENROUTER_API_KEY", "dev_only_mock_openrouter_token")

      on_exit(fn ->
        System.delete_env("OPENROUTER_API_KEY")
      end)

      assert [] =
               SecretBank.list_effective_metadata(world, bank_key: "$OPENROUTER_API_KEY")
    end
  end

  describe "list_env_fallback_policy/0" do
    test "distinguishes convention mappings from explicit overrides and allowlist status" do
      put_secret_bank_config(
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: ["$GITHUB_TOKEN", {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}]
      )

      policy = SecretBank.list_env_fallback_policy()

      convention_entry =
        Enum.find(policy, fn entry ->
          entry.bank_key == "GITHUB_TOKEN"
        end)

      explicit_entry =
        Enum.find(policy, fn entry ->
          entry.bank_key == "OPENROUTER_API_KEY"
        end)

      assert convention_entry.mapping_kind == "convention"
      assert convention_entry.env_var == "GITHUB_TOKEN"
      assert convention_entry.allowlisted
      refute Map.has_key?(convention_entry, :value)

      assert explicit_entry.mapping_kind == "explicit_override"
      assert explicit_entry.env_var == "OPENROUTER_API_KEY"
      refute explicit_entry.allowlisted
      refute Map.has_key?(explicit_entry, :value)
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

      assert {:error, :invalid_scope} = SecretBank.list_effective_metadata(%{})
      assert {:error, :not_found} = SecretBank.delete_secret(world, "MISSING_TOKEN")
    end
  end

  describe "scope hierarchy consistency" do
    test "rejects non-persisted world scopes before env fallback resolution" do
      put_secret_bank_config(
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: ["$GITHUB_TOKEN"]
      )

      System.put_env("GITHUB_TOKEN", "dev_only_unscoped_env_token")

      on_exit(fn ->
        System.delete_env("GITHUB_TOKEN")
      end)

      world = %World{id: Ecto.UUID.generate()}

      assert {:error, :scope_mismatch} =
               SecretBank.upsert_secret(world, "GITHUB_TOKEN", "dev_only_unscoped_local_token")

      assert {:error, :scope_mismatch} =
               SecretBank.list_effective_metadata(world, bank_key: "GITHUB_TOKEN")

      assert {:error, :scope_mismatch} =
               SecretBank.list_recent_activity(world, limit: 5)

      assert {:error, :scope_mismatch} =
               SecretBank.resolve_runtime_secret(world, "GITHUB_TOKEN")

      refute secret_events_contain?([
               "dev_only_unscoped_env_token",
               "dev_only_unscoped_local_token"
             ])
    end

    test "rejects city-scoped create and replace calls with a mismatched world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: world)
      mismatched_city = %{city | world_id: other_world.id}

      assert {:error, :scope_mismatch} =
               SecretBank.upsert_secret(mismatched_city, "GITHUB_TOKEN", "dev_only_city_value")

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(city, "GITHUB_TOKEN", "dev_only_original_city_value")

      assert {:error, :scope_mismatch} =
               SecretBank.upsert_secret(mismatched_city, "GITHUB_TOKEN", "dev_only_replace_value")

      assert {:ok, resolved} = SecretBank.resolve_runtime_secret(city, "GITHUB_TOKEN")
      assert resolved.value == "dev_only_original_city_value"

      refute secret_events_contain?([
               "dev_only_city_value",
               "dev_only_replace_value",
               "dev_only_original_city_value"
             ])
    end

    test "rejects manually constructed spoofed structs with valid IDs and forged parent fields" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      other_department = insert(:department, world: other_world, city: other_city)

      spoofed_city = %City{id: city.id, world_id: other_world.id}

      spoofed_department = %Department{
        id: department.id,
        world_id: other_world.id,
        city_id: other_city.id
      }

      spoofed_lemming = %Lemming{
        id: lemming.id,
        world_id: other_world.id,
        city_id: other_city.id,
        department_id: other_department.id
      }

      assert {:error, :scope_mismatch} =
               SecretBank.upsert_secret(spoofed_city, "GITHUB_TOKEN", "dev_only_spoofed_city")

      assert {:error, :scope_mismatch} =
               SecretBank.upsert_secret(
                 spoofed_department,
                 "GITHUB_TOKEN",
                 "dev_only_spoofed_department"
               )

      assert {:error, :scope_mismatch} =
               SecretBank.resolve_runtime_secret(spoofed_lemming, "GITHUB_TOKEN")

      refute secret_events_contain?([
               "dev_only_spoofed_city",
               "dev_only_spoofed_department"
             ])
    end

    test "rejects department-scoped creates with a mismatched city or world" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      department = insert(:department, world: world, city: city)

      assert {:error, :scope_mismatch} =
               department
               |> Map.put(:city_id, other_city.id)
               |> SecretBank.upsert_secret("GITHUB_TOKEN", "dev_only_wrong_city_value")

      assert {:error, :scope_mismatch} =
               department
               |> Map.put(:world_id, other_world.id)
               |> SecretBank.upsert_secret("GITHUB_TOKEN", "dev_only_wrong_world_value")

      refute secret_events_contain?([
               "dev_only_wrong_city_value",
               "dev_only_wrong_world_value"
             ])
    end

    test "rejects lemming-scoped creates with a mismatched department, city, or world" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      other_department = insert(:department, world: other_world, city: other_city)

      assert {:error, :scope_mismatch} =
               lemming
               |> Map.put(:department_id, other_department.id)
               |> SecretBank.upsert_secret("GITHUB_TOKEN", "dev_only_wrong_department_value")

      assert {:error, :scope_mismatch} =
               lemming
               |> Map.put(:city_id, other_city.id)
               |> SecretBank.upsert_secret("GITHUB_TOKEN", "dev_only_wrong_city_value")

      assert {:error, :scope_mismatch} =
               lemming
               |> Map.put(:world_id, other_world.id)
               |> SecretBank.upsert_secret("GITHUB_TOKEN", "dev_only_wrong_world_value")

      refute secret_events_contain?([
               "dev_only_wrong_department_value",
               "dev_only_wrong_city_value",
               "dev_only_wrong_world_value"
             ])
    end

    test "rejects delete and effective metadata list calls with an inconsistent scope" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: world)
      mismatched_city = %{city | world_id: other_world.id}

      assert {:error, :scope_mismatch} =
               SecretBank.delete_secret(mismatched_city, "GITHUB_TOKEN")

      assert {:error, :scope_mismatch} =
               SecretBank.list_effective_metadata(mismatched_city, bank_key: "GITHUB_TOKEN")

      assert {:error, :scope_mismatch} =
               SecretBank.list_recent_activity(mismatched_city, limit: 5)
    end

    test "does not resolve cross-world inherited secrets through mismatched child scopes" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      other_department = insert(:department, world: other_world, city: other_city)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(other_world, "GITHUB_TOKEN", "dev_only_other_world_value")

      assert {:error, :scope_mismatch} =
               city
               |> Map.put(:world_id, other_world.id)
               |> SecretBank.resolve_runtime_secret("GITHUB_TOKEN")

      assert {:error, :scope_mismatch} =
               department
               |> Map.merge(%{world_id: other_world.id, city_id: other_city.id})
               |> SecretBank.resolve_runtime_secret("GITHUB_TOKEN")

      assert {:error, :scope_mismatch} =
               lemming
               |> Map.merge(%{
                 world_id: other_world.id,
                 city_id: other_city.id,
                 department_id: other_department.id
               })
               |> SecretBank.resolve_runtime_secret("GITHUB_TOKEN")

      refute secret_events_contain?(["dev_only_other_world_value"])
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
               SecretBank.resolve_runtime_secret(lemming, "$GITHUB_TOKEN")

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
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: ["$GITHUB_TOKEN"]
      )

      System.put_env("GITHUB_TOKEN", "dev_only_mock_env_token")

      on_exit(fn ->
        System.delete_env("GITHUB_TOKEN")
      end)

      assert {:ok, resolved} = SecretBank.resolve_runtime_secret(world, "$GITHUB_TOKEN")
      assert resolved.bank_key == "GITHUB_TOKEN"
      assert resolved.value == "dev_only_mock_env_token"
      assert resolved.scope == "env"
      assert resolved.source == "env"
    end

    test "falls back to explicit env var override when configured" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["$OPENROUTER_API_KEY"],
        env_fallbacks: [{"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}]
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
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: ["$GITHUB_TOKEN"]
      )

      System.delete_env("GITHUB_TOKEN")

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(world, "$GITHUB_TOKEN")
    end

    test "does not read env var outside the explicit allowlist" do
      world = insert(:world)

      put_secret_bank_config(
        allowed_env_vars: ["$GITHUB_TOKEN"],
        env_fallbacks: [{"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}]
      )

      System.put_env("OPENROUTER_API_KEY", "dev_only_mock_openrouter_token")

      on_exit(fn ->
        System.delete_env("OPENROUTER_API_KEY")
      end)

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(world, "$OPENROUTER_API_KEY")
    end

    test "returns safe errors for invalid scope and invalid key" do
      world = insert(:world)

      assert {:error, :invalid_scope} = SecretBank.resolve_runtime_secret(%{}, "GITHUB_TOKEN")
      assert {:error, :invalid_key} = SecretBank.resolve_runtime_secret(world, "")

      assert {:error, :invalid_key} =
               SecretBank.resolve_runtime_secret(world, "$secrets.GITHUB_TOKEN")
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
               SecretBank.resolve_runtime_secret(world, "$GITHUB_TOKEN")
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
                 fetch_map(event.payload, :secret_ref) == "$GITHUB_TOKEN"
             end)

      refute Enum.any?(events, fn event ->
               payload = inspect(event.payload || %{})
               payload =~ "dev_only_created_value" or payload =~ "dev_only_replaced_value"
             end)
    end

    test "records resolved and resolve_failed events with safe metadata" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, _metadata} =
               SecretBank.upsert_secret(department, "GITHUB_TOKEN", "dev_only_department_value")

      assert {:ok, _resolved} =
               SecretBank.resolve_runtime_secret(
                 lemming,
                 "$GITHUB_TOKEN",
                 tool_name: "tools.gh"
               )

      assert {:error, :missing_secret} =
               SecretBank.resolve_runtime_secret(
                 lemming,
                 "$STRIPE_TOKEN",
                 tool_name: "tools.gh"
               )

      activities = SecretBank.list_recent_activity(lemming, limit: 10)
      activity_types = Enum.map(activities, & &1.event_type)

      assert "secret.resolved" in activity_types
      assert "secret.resolve_failed" in activity_types
      refute "secret.accessed" in activity_types
      refute "secret.access_failed" in activity_types

      resolved = Enum.find(activities, &(&1.event_type == "secret.resolved"))
      failed = Enum.find(activities, &(&1.event_type == "secret.resolve_failed"))

      assert resolved.message == "GITHUB_TOKEN resolved"
      assert fetch_map(resolved.payload, :key) == "GITHUB_TOKEN"
      assert fetch_map(resolved.payload, :resolved_source) == "department"

      requested_scope = fetch_map(resolved.payload, :requested_scope)
      assert fetch_map(requested_scope, :world_id) == world.id
      assert fetch_map(requested_scope, :city_id) == city.id
      assert fetch_map(requested_scope, :department_id) == department.id
      assert fetch_map(requested_scope, :lemming_id) == lemming.id

      assert failed.message == "STRIPE_TOKEN resolve failed"
      assert fetch_map(failed.payload, :key) == "STRIPE_TOKEN"
      assert fetch_map(failed.payload, :reason) == "missing_secret"

      refute inspect(resolved.payload) =~ "dev_only_department_value"
      refute inspect(failed.payload) =~ "dev_only_department_value"
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

  describe "schema safety constraints" do
    test "does not define a secret_bank_tool_bindings table in the database schema" do
      %{rows: [[table_name]]} =
        Ecto.Adapters.SQL.query!(
          Repo,
          "select to_regclass('public.secret_bank_tool_bindings')"
        )

      assert is_nil(table_name)
    end
  end

  defp put_secret_bank_config(config) do
    previous = Application.get_env(:lemmings_os, SecretBank, [])

    Application.put_env(:lemmings_os, SecretBank, config)

    on_exit(fn ->
      Application.put_env(:lemmings_os, SecretBank, previous)
    end)
  end

  defp secret_events_contain?(values) when is_list(values) do
    event_text =
      Event
      |> Repo.all()
      |> Enum.filter(&String.starts_with?(&1.event_type, "secret."))
      |> inspect()

    Enum.any?(values, &String.contains?(event_text, &1))
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
