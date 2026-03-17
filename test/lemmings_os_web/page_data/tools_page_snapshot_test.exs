defmodule LemmingsOsWeb.PageData.ToolsPageSnapshotTest do
  use ExUnit.Case, async: true

  alias LemmingsOsWeb.PageData.ToolsPageSnapshot

  describe "build/1" do
    test "returns an ok snapshot when runtime source is known but empty" do
      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: fn -> {:ok, []} end,
          policy_fetcher: fn -> :deferred end
        )

      assert snapshot.status == "ok"
      assert snapshot.runtime.status == "ok"
      assert snapshot.runtime.tool_count == 0
      assert snapshot.policy.status == "unknown"
      assert snapshot.policy.mode == "deferred"
      assert snapshot.tools == []
    end

    test "returns runtime-known tools with deferred policy state" do
      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: fn ->
            {:ok,
             [
               %{
                 id: "terminal",
                 name: "terminal",
                 description: "Execute shell commands",
                 icon: "hero-command-line",
                 usage_count: 3
               }
             ]}
          end,
          policy_fetcher: fn -> :deferred end
        )

      assert snapshot.status == "ok"
      assert snapshot.runtime.status == "ok"
      assert snapshot.policy.status == "unknown"
      assert snapshot.policy.mode == "deferred"
      assert [%{id: "terminal"} = tool] = snapshot.tools
      assert tool.runtime.status == "ok"
      assert tool.runtime.availability == "registered"
      assert tool.policy.status == "unknown"
    end

    test "returns an unavailable snapshot when the runtime source cannot be obtained" do
      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: fn -> {:error, :timeout} end,
          policy_fetcher: fn -> :deferred end
        )

      assert snapshot.status == "unavailable"
      assert snapshot.runtime.status == "unavailable"
      assert snapshot.tools == []
      assert Enum.any?(snapshot.issues, &(&1.code == "tools_runtime_source_unavailable"))
    end

    test "returns a degraded snapshot when policy reconciliation is partial" do
      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: fn ->
            {:ok,
             [
               %{id: "terminal", name: "terminal"},
               %{id: "git", name: "git"}
             ]}
          end,
          policy_fetcher: fn -> {:ok, %{"terminal" => "ok"}} end
        )

      assert snapshot.status == "degraded"
      assert snapshot.runtime.status == "ok"
      assert snapshot.policy.status == "degraded"
      assert snapshot.policy.mode == "partial"
      assert Enum.any?(snapshot.issues, &(&1.code == "tools_policy_partial"))

      [terminal, git] = snapshot.tools
      assert terminal.policy.status == "ok"
      assert git.policy.status == "unknown"
    end
  end
end
