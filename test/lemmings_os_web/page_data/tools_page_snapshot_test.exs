defmodule LemmingsOsWeb.PageData.ToolsPageSnapshotTest do
  use ExUnit.Case, async: true

  import Mox

  alias LemmingsOs.Tools.MockPolicyFetcher
  alias LemmingsOs.Tools.MockRuntimeFetcher
  alias LemmingsOsWeb.PageData.ToolsPageSnapshot

  setup :verify_on_exit!

  setup do
    stub(MockRuntimeFetcher, :fetch, fn -> {:error, :not_implemented} end)
    stub(MockPolicyFetcher, :fetch, fn -> :deferred end)
    :ok
  end

  describe "build/1" do
    test "returns an ok snapshot when runtime source is known but empty" do
      stub(MockRuntimeFetcher, :fetch, fn -> {:ok, []} end)

      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: MockRuntimeFetcher,
          policy_fetcher: MockPolicyFetcher
        )

      assert snapshot.status == "ok"
      assert snapshot.runtime.status == "ok"
      assert snapshot.runtime.tool_count == 0
      assert snapshot.policy.status == "unknown"
      assert snapshot.policy.mode == "deferred"
      assert snapshot.tools == []
    end

    test "returns runtime-known tools with deferred policy state" do
      stub(MockRuntimeFetcher, :fetch, fn ->
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
      end)

      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: MockRuntimeFetcher,
          policy_fetcher: MockPolicyFetcher
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
      stub(MockRuntimeFetcher, :fetch, fn -> {:error, :timeout} end)

      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: MockRuntimeFetcher,
          policy_fetcher: MockPolicyFetcher
        )

      assert snapshot.status == "unavailable"
      assert snapshot.runtime.status == "unavailable"
      assert snapshot.tools == []
      assert Enum.any?(snapshot.issues, &(&1.code == "tools_runtime_source_unavailable"))
    end

    test "returns a degraded snapshot when policy reconciliation is partial" do
      stub(MockRuntimeFetcher, :fetch, fn ->
        {:ok, [%{id: "terminal", name: "terminal"}, %{id: "git", name: "git"}]}
      end)

      stub(MockPolicyFetcher, :fetch, fn -> {:ok, %{"terminal" => "ok"}} end)

      snapshot =
        ToolsPageSnapshot.build(
          runtime_fetcher: MockRuntimeFetcher,
          policy_fetcher: MockPolicyFetcher
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
