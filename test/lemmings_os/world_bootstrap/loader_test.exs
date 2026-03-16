defmodule LemmingsOs.WorldBootstrap.LoaderTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.WorldBootstrap.Loader
  alias LemmingsOs.WorldBootstrapTestHelpers

  describe "load/1" do
    test "loads and parses valid yaml" do
      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:ok, result} = Loader.load(path: path, source: "direct")
      assert result.path == path
      assert result.source == "direct"
      assert result.config["world"]["slug"] == "local"
    end

    test "returns a normalized missing-file error" do
      path = Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}.yaml")

      assert {:error, %{issues: [issue]}} = Loader.load(path: path, source: "direct")
      assert issue.severity == "error"
      assert issue.code == "bootstrap_file_not_found"
      assert issue.summary == "Bootstrap file not found"
      assert issue.action_hint == "Create the file or update LEMMINGS_WORLD_BOOTSTRAP_PATH."
      assert issue.source == "bootstrap_file"
      assert issue.path == path
    end

    test "returns a normalized parse error" do
      path = WorldBootstrapTestHelpers.write_temp_file!("world:\n  id: [unterminated\n")

      assert {:error, %{issues: [issue]}} = Loader.load(path: path, source: "direct")
      assert issue.severity == "error"
      assert issue.code == "bootstrap_yaml_parse_error"
      assert issue.summary == "Bootstrap YAML could not be parsed"
      assert issue.action_hint == "Fix the YAML syntax and try the bootstrap load again."
      assert issue.source == "bootstrap_file"
      assert issue.path == path
    end
  end
end
