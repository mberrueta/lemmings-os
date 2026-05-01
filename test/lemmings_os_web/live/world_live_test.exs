defmodule LemmingsOsWeb.WorldLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Connections
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
    refute has_element?(view, "#world-cities-panel")
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
    refute has_element?(view, "#world-cities-panel")
    assert has_element?(view, "#world-overview-tab")
    assert has_element?(view, "#world-bootstrap-status[data-status='ok']")
    refute has_element?(view, "#world-page-empty-state")
  end

  test "renders read-only env fallback policy metadata in secrets tab", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    put_secret_bank_config(
      allowed_env_vars: ["$GITHUB_TOKEN"],
      env_fallbacks: ["$GITHUB_TOKEN", {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}]
    )

    insert(:world,
      slug: "local",
      name: "Local World",
      bootstrap_path: path,
      bootstrap_source: "direct",
      last_import_status: "ok"
    )

    {:ok, view, _html} = live(conn, ~p"/world")

    view |> element("#world-tab-secrets") |> render_click()

    assert has_element?(view, "#world-secrets-env-fallback-panel")
    assert has_element?(view, "#world-secrets-env-fallback-row-github-token")
    assert has_element?(view, "#world-secrets-env-fallback-type-github-token", "convention")
    assert has_element?(view, "#world-secrets-env-fallback-status-github-token", "allowlisted")
    assert has_element?(view, "#world-secrets-env-fallback-row-github-token", "$GITHUB_TOKEN")
    assert has_element?(view, "#world-secrets-env-fallback-row-openrouter-api-key")

    assert has_element?(
             view,
             "#world-secrets-env-fallback-row-openrouter-api-key",
             "$OPENROUTER_API_KEY"
           )

    assert has_element?(
             view,
             "#world-secrets-env-fallback-type-openrouter-api-key",
             "explicit override"
           )

    assert has_element?(
             view,
             "#world-secrets-env-fallback-status-openrouter-api-key",
             "blocked by allowlist"
           )
  end

  test "secret create and delete controls expose accessible names and safe state", %{conn: conn} do
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

    view |> element("#world-tab-secrets") |> render_click()

    assert has_element?(view, "#world-tab-secrets[aria-pressed='true']")
    assert has_element?(view, "#world-secret-form[aria-describedby='world-secret-form-help']")
    assert has_element?(view, "#world-secrets-activity-empty[role='status'][aria-live='polite']")

    assert has_element?(
             view,
             "#world-secret-bank-key[required][aria-describedby='world-secret-bank-key-help']"
           )

    assert has_element?(
             view,
             "#world-secret-value[type='password'][required][aria-describedby='world-secret-value-help']"
           )

    view
    |> element("#world-secret-form")
    |> render_submit(%{
      "secret" => %{
        "bank_key" => "GITHUB_TOKEN",
        "value" => "dev_only_accessibility_secret"
      }
    })

    assert has_element?(
             view,
             "#world-secret-action-state-github-token",
             "Local value can be replaced and deleted at this scope."
           )

    assert has_element?(
             view,
             "#world-secret-edit-github-token[aria-label='Edit local secret GITHUB_TOKEN']"
           )

    assert has_element?(
             view,
             "#world-secret-delete-github-token[aria-label='Delete local secret GITHUB_TOKEN'][data-confirm='Delete this local secret value?']"
           )

    assert has_element?(
             view,
             "#world-secrets-activity-scroll[role='region'][aria-labelledby='world-secrets-activity-heading'][aria-live='polite']"
           )

    assert has_element?(view, "ul#world-secrets-activity-list")
    assert has_element?(view, "#world-secrets-activity-list time[datetime]")

    refute render(view) =~ "dev_only_accessibility_secret"

    view |> element("#world-secret-delete-github-token") |> render_click()

    refute has_element?(view, "#world-secret-delete-github-token")
    assert has_element?(view, "#flash-info", "Local secret deleted")
  end

  test "connections tab creates, edits, tests, and deletes world connection", %{conn: conn} do
    path =
      WorldBootstrapTestHelpers.write_temp_file!(WorldBootstrapTestHelpers.valid_bootstrap_yaml())

    world =
      insert(:world,
        slug: "local",
        name: "Local World",
        bootstrap_path: path,
        bootstrap_source: "direct",
        last_import_status: "ok"
      )

    assert {:ok, _metadata} =
             LemmingsOs.SecretBank.upsert_secret(world, "MOCK_API_KEY", "world_tab_secret")

    {:ok, view, _html} = live(conn, ~p"/world")

    view |> element("#world-tab-connections") |> render_click()

    assert has_element?(view, "#world-connections-panel")
    assert has_element?(view, "#world-connections-open-create")

    view |> element("#world-connections-open-create") |> render_click()

    assert has_element?(view, "#world-connections-create-type")
    assert render(view) =~ "$MOCK_API_KEY"

    view
    |> element("#world-connections-create-form")
    |> render_submit(%{
      "connection_create" => %{
        "type" => "mock",
        "status" => "enabled",
        "config" =>
          ~s({"mode":"echo","base_url":"https://world.example.test/mock","api_key":"$MOCK_API_KEY"})
      }
    })

    created = Connections.get_connection_by_type(world, "mock")
    assert created
    assert has_element?(view, "#world-connections-row-#{created.id}")

    view
    |> element("#world-connections-edit-#{created.id}")
    |> render_click()

    view
    |> element("#world-connections-edit-form-#{created.id}")
    |> render_change(%{
      "connection_edit" => %{
        "connection_id" => created.id,
        "type" => "mock",
        "status" => "enabled"
      }
    })

    assert has_element?(view, "#world-connections-edit-form-#{created.id}")

    view
    |> element("#world-connections-edit-form-#{created.id}")
    |> render_submit(%{
      "connection_edit" => %{
        "connection_id" => created.id,
        "type" => "mock",
        "status" => "enabled",
        "config" =>
          ~s({"mode":"echo","base_url":"https://world-updated.example.test/mock","api_key":"$MOCK_API_KEY"})
      }
    })

    assert Connections.get_connection(world, created.id).config["base_url"] ==
             "https://world-updated.example.test/mock"

    view
    |> element("#world-connections-test-#{created.id}")
    |> render_click()

    assert Connections.get_connection(world, created.id).last_test in [
             "succeeded: mock_echo_ok",
             "failed: missing_secret",
             "failed: secret_resolution_failed",
             "failed: invalid_config"
           ]

    refute render(view) =~ "world_tab_secret"

    view
    |> element("#world-connections-delete-#{created.id}")
    |> render_click()

    refute Connections.get_connection(world, created.id)
  end

  defp put_secret_bank_config(config) do
    previous = Application.get_env(:lemmings_os, LemmingsOs.SecretBank, [])

    Application.put_env(:lemmings_os, LemmingsOs.SecretBank, config)

    on_exit(fn ->
      Application.put_env(:lemmings_os, LemmingsOs.SecretBank, previous)
    end)
  end
end
