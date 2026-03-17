defmodule LemmingsOs.WorldBootstrap.ShapeValidatorTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.WorldBootstrap.ShapeValidator
  alias LemmingsOs.WorldBootstrapTestHelpers

  describe "validate/1" do
    test "accepts the frozen valid bootstrap shape" do
      assert {:ok, %{config: config, issues: []}} =
               ShapeValidator.validate(WorldBootstrapTestHelpers.valid_bootstrap_config())

      assert config["world"]["slug"] == "local"
    end

    test "returns normalized errors for missing required sections" do
      config =
        WorldBootstrapTestHelpers.valid_bootstrap_config()
        |> Map.delete("runtime")

      assert {:error, %{issues: issues}} = ShapeValidator.validate(config)

      assert Enum.any?(issues, fn issue ->
               issue.code == "missing_required_section" and issue.path == "runtime"
             end)
    end

    test "returns normalized warnings for unknown keys" do
      config =
        put_in(
          WorldBootstrapTestHelpers.valid_bootstrap_config(),
          ["models", "providers", "ollama", "unexpected_flag"],
          true
        )

      assert {:ok, %{issues: issues}} = ShapeValidator.validate(config)

      assert Enum.any?(issues, fn issue ->
               issue.severity == "warning" and issue.code == "unknown_key" and
                 issue.path == "models.providers.ollama.unexpected_flag"
             end)
    end

    test "returns normalized errors for invalid nested types" do
      config =
        put_in(
          WorldBootstrapTestHelpers.valid_bootstrap_config(),
          ["models", "providers", "ollama", "allowed_models"],
          "llama3.2"
        )

      assert {:error, %{issues: issues}} = ShapeValidator.validate(config)

      assert Enum.any?(issues, fn issue ->
               issue.code == "invalid_value_type" and
                 issue.path == "models.providers.ollama.allowed_models"
             end)
    end
  end
end
