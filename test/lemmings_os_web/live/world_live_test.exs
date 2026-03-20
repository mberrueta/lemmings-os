defmodule LemmingsOsWeb.WorldLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.WorldBootstrapTestHelpers

  setup do
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  test "renders the persisted world snapshot", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "ok"
    )

    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-status-panel")
    assert has_element?(view, "#world-tab-overview")
    assert has_element?(view, "#world-tab-import")
    assert has_element?(view, "#world-tab-bootstrap")
    assert has_element?(view, "#world-tab-runtime")
    assert has_element?(view, "#world-cities-panel")
    assert has_element?(view, "#world-overview-tab")
    refute has_element?(view, "#world-import-panel")
    refute has_element?(view, "#world-bootstrap-panel")
    refute has_element?(view, "#world-runtime-panel")
    refute has_element?(view, "#world-issues-panel")
    refute has_element?(view, "#world-cities-placeholder-panel")
    refute has_element?(view, "#world-tools-placeholder-panel")
    assert has_element?(view, "#world-bootstrap-status[data-status='ok']")
    assert has_element?(view, "#world-status-panel")
  end

  test "switches world tabs without losing the status strip", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "ok"
    )

    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-status-panel")

    view |> element("#world-tab-import") |> render_click()

    assert has_element?(view, "#world-import-panel")
    assert has_element?(view, "#world-issues-panel")
    refute has_element?(view, "#world-map-panel")

    view |> element("#world-tab-bootstrap") |> render_click()

    assert has_element?(view, "#world-bootstrap-panel")
    assert has_element?(view, "#world-bootstrap-source-field")
    assert has_element?(view, "#world-bootstrap-path-field")
    assert has_element?(view, "#world-bootstrap-postgres-env-field")
    assert has_element?(view, "#world-bootstrap-world-field")
    assert has_element?(view, "#world-provider-ollama")
    assert has_element?(view, "#world-profile-default")
    assert has_element?(view, "#world-cities-placeholder-panel")
    assert has_element?(view, "#world-tools-placeholder-panel")
    refute has_element?(view, "#world-import-panel")

    view |> element("#world-tab-runtime") |> render_click()

    assert has_element?(view, "#world-runtime-panel")
    assert has_element?(view, "#world-runtime-check-bootstrap_file[data-status='ok']")
    refute has_element?(view, "#world-bootstrap-panel")
  end

  test "renders invalid bootstrap issues in the import tab", %{conn: conn} do
    invalid_yaml =
      WorldBootstrapTestHelpers.valid_bootstrap_yaml()
      |> String.replace(
        "runtime:\n  idle_ttl_seconds: 3600\n  cross_city_communication: false\n",
        ""
      )

    path = WorldBootstrapTestHelpers.write_temp_file!(invalid_yaml)

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "invalid"
    )

    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-bootstrap-status[data-status='invalid']")

    view |> element("#world-tab-import") |> render_click()

    assert has_element?(view, "#world-issues-panel")
    assert has_element?(view, "[id^='world-issue-missing_required_section-']")
  end

  test "renders unavailable bootstrap state when the configured file is missing", %{conn: conn} do
    missing_path =
      Path.join(
        System.tmp_dir!(),
        "missing-world-live-bootstrap-#{System.unique_integer([:positive])}.yaml"
      )

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: missing_path,
      bootstrap_source: "direct",
      last_import_status: "unavailable"
    )

    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-bootstrap-status[data-status='unavailable']")
    assert has_element?(view, "#world-runtime-status[data-status='unavailable']")

    view |> element("#world-tab-runtime") |> render_click()

    assert has_element?(view, "#world-runtime-check-bootstrap_file[data-status='unavailable']")
  end

  test "imports the default bootstrap world from the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/world")

    assert has_element?(view, "#world-page-empty-state")

    view
    |> element("#world-import-button")
    |> render_click()

    assert has_element?(view, "#world-status-panel")
    assert has_element?(view, "#world-cities-panel")
    assert has_element?(view, "#world-overview-tab")
    assert has_element?(view, "#world-bootstrap-status[data-status='ok']")
    refute has_element?(view, "#world-page-empty-state")
  end
end
