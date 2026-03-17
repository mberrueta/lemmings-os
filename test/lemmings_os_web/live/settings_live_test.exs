defmodule LemmingsOsWeb.SettingsLiveTest do
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
    :ok
  end

  test "renders read-only runtime and world settings", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "ok"
    )

    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#settings-page")
    assert has_element?(view, "#settings-instance-card")
    assert has_element?(view, "#settings-world-card")
    assert has_element?(view, "#settings-bootstrap-panel")
    assert has_element?(view, "#settings-help-panel")
    refute has_element?(view, "#settings-form")
  end

  test "renders unavailable values honestly when no world exists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#settings-page")
    assert has_element?(view, "#settings-world-card [data-status='unknown']")
    assert has_element?(view, "#settings-bootstrap-panel [data-status='unknown']")
    refute has_element?(view, "#settings-form")
  end
end
