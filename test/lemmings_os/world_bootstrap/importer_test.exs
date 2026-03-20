defmodule LemmingsOs.WorldBootstrap.ImporterTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Worlds.World
  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOs.WorldBootstrapTestHelpers

  doctest LemmingsOs.WorldBootstrap.Importer

  describe "sync_default_world/1" do
    test "creates a persisted world from valid bootstrap yaml" do
      Repo.delete_all(World)

      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:ok, result} = Importer.sync_default_world(path: path, source: "direct")
      assert result.operation_status == "ok"
      assert result.issues == []
      assert %World{} = result.world
      assert result.persisted_last_import_status == "ok"

      assert result.world.slug == "local"
      assert result.world.name == "Local World"
      assert result.world.bootstrap_path == path
      assert result.world.bootstrap_source == "direct"
      assert result.world.last_import_status == "ok"
      assert result.world.status == "ok"
      assert result.world.last_bootstrap_hash

      assert result.world.models_config.providers["ollama"]["allowed_models"] == [
               "llama3.2",
               "qwen2.5:7b"
             ]

      assert Repo.aggregate(World, :count) == 1
    end

    test "updates the existing world when the bootstrap file changes at the same path" do
      Repo.delete_all(World)

      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:ok, first_result} = Importer.sync_default_world(path: path, source: "direct")

      updated_yaml =
        WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        |> String.replace("name: \"Local World\"", "name: \"Renamed Local World\"")
        |> String.replace("- \"llama3.2\"\n", "- \"phi4-mini\"\n")

      File.write!(path, updated_yaml)

      assert {:ok, second_result} = Importer.sync_default_world(path: path, source: "direct")
      assert second_result.world.id == first_result.world.id
      assert second_result.world.name == "Renamed Local World"

      assert second_result.world.models_config.providers["ollama"]["allowed_models"] == [
               "phi4-mini",
               "qwen2.5:7b"
             ]

      assert Repo.aggregate(World, :count) == 1
    end

    test "returns an invalid result and updates persisted import metadata for invalid bootstrap input" do
      Repo.delete_all(World)

      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:ok, first_result} = Importer.sync_default_world(path: path, source: "direct")

      invalid_yaml =
        WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        |> String.replace(
          "runtime:\n  idle_ttl_seconds: 3600\n  cross_city_communication: false\n",
          ""
        )

      File.write!(path, invalid_yaml)

      assert {:error, second_result} = Importer.sync_default_world(path: path, source: "direct")
      assert second_result.operation_status == "invalid"
      assert second_result.world.id == first_result.world.id
      assert second_result.persisted_last_import_status == "invalid"

      assert Enum.any?(second_result.issues, fn issue ->
               issue.code == "missing_required_section" and issue.path == "runtime"
             end)

      persisted_world = Repo.get!(World, first_result.world.id)
      assert persisted_world.last_import_status == "invalid"
      assert persisted_world.status == "invalid"
    end

    test "returns an unavailable result for missing bootstrap files" do
      Repo.delete_all(World)

      path =
        Path.join(
          System.tmp_dir!(),
          "missing-bootstrap-#{System.unique_integer([:positive])}.yaml"
        )

      assert {:error, result} = Importer.sync_default_world(path: path, source: "direct")
      assert result.operation_status == "unavailable"
      assert result.world == nil
      assert result.persisted_last_import_status == nil

      assert Enum.any?(result.issues, fn issue ->
               issue.code == "bootstrap_file_not_found" and issue.path == path
             end)
    end

    test "returns a translated persistence issue when the world cannot be synced" do
      Repo.delete_all(World)

      insert(:world,
        slug: "local",
        name: "Existing Local World",
        bootstrap_path: "/tmp/worlds/existing-local.default.world.yaml"
      )

      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:error, result} = Importer.sync_default_world(path: path, source: "direct")

      assert Enum.any?(result.issues, fn issue ->
               issue.code == "bootstrap_persistence_failed" and
                 issue.summary == "Bootstrap world sync failed" and
                 issue.action_hint ==
                   "Fix the persisted World data contract and retry the bootstrap sync."
             end)
    end
  end
end
