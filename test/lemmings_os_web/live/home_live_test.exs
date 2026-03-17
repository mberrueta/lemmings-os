defmodule LemmingsOsWeb.HomeLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Repo
  alias LemmingsOs.World
  alias LemmingsOs.WorldCache
  alias LemmingsOs.WorldBootstrapTestHelpers

  setup do
    Repo.delete_all(World)
    WorldCache.invalidate_all()
    Application.delete_env(:lemmings_os, :tools_runtime_fetcher)
    Application.delete_env(:lemmings_os, :tools_policy_fetcher)

    on_exit(fn ->
      Application.delete_env(:lemmings_os, :tools_runtime_fetcher)
      Application.delete_env(:lemmings_os, :tools_policy_fetcher)
    end)

    :ok
  end

  test "renders an honest unavailable home overview when no world exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, "#home-world-status[data-status='unavailable']")
    assert has_element?(view, "#home-card-world_identity[data-status='unavailable']")
    assert has_element?(view, "#home-alert-home_world_unavailable")
    assert has_element?(view, "#home-omitted-panel")
    refute has_element?(view, "#home-card-bootstrap_health")
    refute has_element?(view, "#home-card-tools_health")
    refute has_element?(view, "#home-network-snapshot")
    refute has_element?(view, "#home-active-lemmings")
    refute has_element?(view, "#home-department-queues")
    refute has_element?(view, "#home-activity-feed")
  end

  test "renders snapshot-driven cards and removes the old mock dashboard", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "ok"
    )

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, "#home-card-world_identity")
    assert has_element?(view, "#home-card-bootstrap_health")
    assert has_element?(view, "#home-card-runtime_health")
    assert has_element?(view, "#home-card-tools_health")
    assert has_element?(view, "#home-quick-links-panel")
    assert has_element?(view, "#home-link-world")
    assert has_element?(view, "#home-link-tools")
    refute has_element?(view, "#home-network-snapshot")
    refute has_element?(view, "#home-active-lemmings")
    refute has_element?(view, "#home-department-queues")
    refute has_element?(view, "#home-activity-feed")
  end
end
