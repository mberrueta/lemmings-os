defmodule LemmingsOs.Config.ToolsConfigTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Config.ToolsConfig

  describe "changeset/2" do
    test "casts both tool lists" do
      attrs = %{
        allowed_tools: ["github", "filesystem"],
        denied_tools: ["shell"]
      }

      changeset = ToolsConfig.changeset(%ToolsConfig{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :allowed_tools) == ["github", "filesystem"]
      assert Ecto.Changeset.get_field(changeset, :denied_tools) == ["shell"]
    end

    test "keeps empty-list defaults when attrs are empty" do
      changeset = ToolsConfig.changeset(%ToolsConfig{}, %{})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :allowed_tools) == []
      assert Ecto.Changeset.get_field(changeset, :denied_tools) == []
    end
  end
end
