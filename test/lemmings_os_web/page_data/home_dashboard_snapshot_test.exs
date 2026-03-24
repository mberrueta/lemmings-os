defmodule LemmingsOsWeb.PageData.HomeDashboardSnapshotTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOsWeb.PageData.HomeDashboardSnapshot
  alias LemmingsOsWeb.PageData.ToolsPageSnapshot

  doctest LemmingsOsWeb.PageData.HomeDashboardSnapshot

  describe "build/1" do
    test "returns a strict unavailable snapshot when no world can be resolved" do
      snapshot =
        HomeDashboardSnapshot.build(world_snapshot_builder: fn -> {:error, :not_found} end)

      assert snapshot.status == "unavailable"
      assert snapshot.world.available? == false
      assert Enum.map(snapshot.cards, & &1.id) == ["world_identity"]
      assert hd(snapshot.cards).status == "unavailable"
      assert Enum.any?(snapshot.alerts, &(&1.code == "home_world_unavailable"))
      assert [%{id: _, to: _} | _] = snapshot.actions
    end

    test "returns a degraded snapshot when bootstrap health is degraded" do
      snapshot =
        HomeDashboardSnapshot.build(
          world_snapshot: degraded_world_snapshot(),
          tools_snapshot: ok_tools_snapshot()
        )

      assert snapshot.status == "degraded"
      assert snapshot.world.available? == true
      assert card(snapshot, "world_identity").status == "ok"
      assert card(snapshot, "bootstrap_health").status == "degraded"
      assert card(snapshot, "runtime_health").status == "ok"
      assert card(snapshot, "tools_health").status == "ok"
      assert card(snapshot, "topology_summary").status == "unknown"
      assert Enum.any?(snapshot.alerts, &(&1.code == "bootstrap_warning"))
    end

    test "surfaces partial tools policy without inventing hierarchy cards" do
      snapshot =
        HomeDashboardSnapshot.build(
          world_snapshot: ok_world_snapshot(),
          tools_snapshot: partial_tools_snapshot()
        )

      assert snapshot.status == "degraded"
      assert card(snapshot, "tools_health").status == "degraded"
      assert card(snapshot, "tools_health").meta.tool_count == 2
      assert card(snapshot, "tools_health").meta.policy_mode == "partial"

      assert card(snapshot, "topology_summary").meta == %{
               city_count: 0,
               department_count: 0,
               active_department_count: 0,
               lemming_count: 0,
               active_lemming_count: 0
             }

      assert Enum.any?(snapshot.alerts, &(&1.code == "tools_policy_partial"))
    end

    test "includes truthful persisted topology counts for cities and departments" do
      world = insert(:world)
      city_one = insert(:city, world: world, status: "active")
      city_two = insert(:city, world: world, status: "active")
      department_one = insert(:department, world: world, city: city_one, status: "active")
      department_two = insert(:department, world: world, city: city_one, status: "draining")
      insert(:department, world: world, city: city_two, status: "disabled")
      insert(:lemming, world: world, city: city_one, department: department_one, status: "active")
      insert(:lemming, world: world, city: city_one, department: department_two, status: "draft")

      snapshot =
        HomeDashboardSnapshot.build(
          world_snapshot: ok_world_snapshot(world.id),
          tools_snapshot: ok_tools_snapshot()
        )

      assert card(snapshot, "topology_summary").status == "ok"

      assert card(snapshot, "topology_summary").meta == %{
               city_count: 2,
               department_count: 3,
               active_department_count: 1,
               lemming_count: 2,
               active_lemming_count: 1
             }
    end
  end

  defp card(snapshot, id), do: Enum.find(snapshot.cards, &(&1.id == id))

  defp ok_world_snapshot(world_id \\ "world-1") do
    %{
      world: %{
        id: world_id,
        slug: "local",
        name: "Local World",
        status: "ok",
        status_label: "OK"
      },
      bootstrap: %{
        status: "ok",
        status_label: "OK",
        path: "/tmp/default.world.yaml",
        issues: []
      },
      runtime: %{
        status: "ok",
        status_label: "OK",
        checks: [
          %{code: "bootstrap_file", status: "ok"},
          %{code: "postgres_connection", status: "ok"},
          %{code: "provider_credentials", status: "ok"},
          %{code: "provider_reachability", status: "unknown"}
        ],
        deferred_sources: ["provider_reachability"]
      }
    }
  end

  defp degraded_world_snapshot do
    snapshot = ok_world_snapshot()

    put_in(snapshot, [:bootstrap], %{
      status: "degraded",
      status_label: "Degraded",
      path: "/tmp/default.world.yaml",
      issues: [
        %{
          severity: "warning",
          code: "bootstrap_warning",
          summary: "Bootstrap warning",
          detail: "Unknown key detected.",
          source: "shape_validation",
          path: "unexpected_root",
          action_hint: "Review the declared bootstrap shape."
        }
      ]
    })
  end

  defp ok_tools_snapshot do
    %ToolsPageSnapshot{
      status: "ok",
      status_label: "OK",
      runtime: %{
        status: "ok",
        status_label: "OK",
        tool_count: 2,
        issues: [],
        source: "runtime"
      },
      policy: %{
        status: "unknown",
        status_label: "Unknown",
        mode: "deferred",
        issues: []
      },
      tools: [
        %{id: "terminal"},
        %{id: "git"}
      ],
      issues: []
    }
  end

  defp partial_tools_snapshot do
    %ToolsPageSnapshot{
      status: "degraded",
      status_label: "Degraded",
      runtime: %{
        status: "ok",
        status_label: "OK",
        tool_count: 2,
        issues: [],
        source: "runtime"
      },
      policy: %{
        status: "degraded",
        status_label: "Degraded",
        mode: "partial",
        issues: []
      },
      tools: [
        %{id: "terminal"},
        %{id: "git"}
      ],
      issues: [
        %{
          severity: "info",
          code: "tools_policy_partial",
          summary: "Tools policy reconciliation is partial",
          detail: "1 runtime tool entry has no policy reconciliation yet.",
          source: "tool_policy",
          path: nil,
          action_hint: "Treat policy state as partial until the hierarchy policy engine exists."
        }
      ]
    }
  end
end
