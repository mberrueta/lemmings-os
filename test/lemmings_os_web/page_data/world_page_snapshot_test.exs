defmodule LemmingsOsWeb.PageData.WorldPageSnapshotTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.WorldBootstrapTestHelpers
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  doctest LemmingsOsWeb.PageData.WorldPageSnapshot

  setup do
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "build/1" do
    test "builds a snapshot with separated bootstrap, last sync, immediate import, and runtime sections" do
      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      world =
        insert(:world,
          bootstrap_path: path,
          bootstrap_source: "direct",
          last_import_status: "ok",
          last_imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 env_getter: &env_value/1,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.world.id == world.id
      assert snapshot.world.status == world.status
      assert snapshot.bootstrap.status == "ok"
      assert snapshot.bootstrap.declared_config.world.slug == "local"

      assert Enum.map(snapshot.bootstrap.declared_config.models.providers, & &1.name) == [
               "ollama"
             ]

      assert snapshot.immediate_import.status == "unknown"
      refute snapshot.immediate_import.available?
      assert snapshot.last_sync.status == "ok"
      assert snapshot.last_sync.bootstrap_path == path
      assert snapshot.runtime.status == "ok"
      assert runtime_check(snapshot, "bootstrap_file").status == "ok"
      assert runtime_check(snapshot, "postgres_connection").status == "ok"
      assert runtime_check(snapshot, "provider_credentials").status == "unknown"
      assert runtime_check(snapshot, "provider_reachability").status == "unknown"
      assert snapshot.runtime.deferred_sources == ["provider_reachability"]
    end

    test "returns a degraded bootstrap status when validation emits warnings" do
      warned_yaml =
        WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        |> String.replace("runtime:\n", "unexpected_root: true\nruntime:\n")

      path = WorldBootstrapTestHelpers.write_temp_file!(warned_yaml)

      world =
        insert(:world, bootstrap_path: path, bootstrap_source: "direct", last_import_status: "ok")

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 env_getter: &env_value/1,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.bootstrap.status == "degraded"

      assert Enum.any?(
               snapshot.bootstrap.issues,
               &(&1.code == "unknown_key" and &1.path == "unexpected_root")
             )
    end

    test "returns an unavailable bootstrap status when the bootstrap file is missing" do
      path =
        Path.join(
          System.tmp_dir!(),
          "missing-world-bootstrap-#{System.unique_integer([:positive])}.yaml"
        )

      world =
        insert(:world, bootstrap_path: path, bootstrap_source: "direct", last_import_status: "ok")

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.bootstrap.status == "unavailable"
      assert snapshot.bootstrap.declared_config == nil
      assert runtime_check(snapshot, "bootstrap_file").status == "unavailable"
    end

    test "returns an invalid bootstrap status when the shape is invalid" do
      invalid_yaml =
        WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        |> String.replace(
          "runtime:\n  idle_ttl_seconds: 3600\n  cross_city_communication: false\n",
          ""
        )

      path = WorldBootstrapTestHelpers.write_temp_file!(invalid_yaml)

      world =
        insert(:world, bootstrap_path: path, bootstrap_source: "direct", last_import_status: "ok")

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 env_getter: &env_value/1,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.bootstrap.status == "invalid"

      assert Enum.any?(
               snapshot.bootstrap.issues,
               &(&1.code == "missing_required_section" and &1.path == "runtime")
             )
    end

    test "keeps immediate import result separate from the persisted last sync status" do
      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      world =
        insert(:world, bootstrap_path: path, bootstrap_source: "direct", last_import_status: "ok")

      immediate_import_result = %{
        operation_status: "invalid",
        source: "manual_refresh",
        path: path,
        issues: [%{code: "bootstrap_yaml_parse_error"}],
        persisted_last_import_status: "ok"
      }

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 immediate_import_result: {:error, immediate_import_result},
                 env_getter: &env_value/1,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.immediate_import.status == "invalid"
      assert snapshot.immediate_import.available?
      assert snapshot.immediate_import.persisted_last_import_status == "ok"
      assert snapshot.last_sync.status == "ok"
    end

    test "returns a degraded runtime status when provider credentials are missing" do
      yaml = """
      world:
        id: "world_local"
        slug: "local"
        name: "Local World"

      infrastructure:
        postgres:
          url_env: "DATABASE_URL"

      cities: {}

      tools: {}

      models:
        providers:
          ollama:
            enabled: true
            base_url: "http://127.0.0.1:11434"
            default_billing_mode: "zero_cost"
            allowed_models:
              - "llama3.2"
              - "qwen2.5:7b"
          openai:
            enabled: true
            api_key_env: "OPENAI_API_KEY"
            base_url: "https://api.openai.com/v1"
            default_billing_mode: "metered"
            allowed_models:
              - "gpt-4o-mini"
        profiles:
          default:
            provider: "ollama"
            model: "qwen2.5:7b"
            fallbacks:
              - provider: "ollama"
                model: "gemma2"

      limits:
        max_cities: 1
        max_departments_per_city: 20
        max_lemmings_per_department: 50

      costs:
        budgets:
          monthly_usd: 0
          daily_tokens: 1000000

      runtime:
        idle_ttl_seconds: 3600
        cross_city_communication: false
      """

      path = WorldBootstrapTestHelpers.write_temp_file!(yaml)

      world =
        insert(:world, bootstrap_path: path, bootstrap_source: "direct", last_import_status: "ok")

      assert {:ok, snapshot} =
               WorldPageSnapshot.build(
                 world: world,
                 env_getter: &env_value/1,
                 postgres_check: fn -> {:ok, %{rows: [[1]]}} end
               )

      assert snapshot.runtime.status == "degraded"

      assert runtime_check(snapshot, "provider_credentials").detail.missing_envs == [
               "OPENAI_API_KEY"
             ]
    end

    test "returns an unknown bootstrap status when the persisted world has no bootstrap path" do
      world = insert(:world, bootstrap_path: nil, bootstrap_source: nil, last_import_status: "ok")

      assert {:ok, snapshot} = WorldPageSnapshot.build(world: world)
      assert snapshot.bootstrap.status == "unknown"

      assert Enum.any?(
               snapshot.bootstrap.issues,
               &(&1.code == "bootstrap_input_not_configured")
             )
    end

    test "returns an error when no persisted world can be resolved" do
      assert {:error, :not_found} = WorldPageSnapshot.build()
    end
  end

  defp runtime_check(snapshot, code), do: Enum.find(snapshot.runtime.checks, &(&1.code == code))
  defp env_value("DATABASE_URL"), do: "ecto://localhost/lemmings_os"
  defp env_value(_env_var), do: nil
end
