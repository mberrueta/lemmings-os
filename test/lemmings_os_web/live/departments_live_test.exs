defmodule LemmingsOsWeb.DepartmentsLiveTest do
  use LemmingsOsWeb.ConnCase

  import Gettext
  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Connections
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(Department)
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "index flow" do
    test "S01: defaults to the first city when no city param is present", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      world = insert(:world, name: "Ops World", slug: "ops-world", status: "ok")

      first_city =
        insert(:city,
          world: world,
          name: "Alpha City",
          slug: "alpha-city",
          status: "active",
          inserted_at: DateTime.add(now, -60, :second),
          updated_at: DateTime.add(now, -60, :second)
        )

      _second_city =
        insert(:city,
          world: world,
          name: "Beta City",
          slug: "beta-city",
          status: "disabled",
          inserted_at: now,
          updated_at: now
        )

      department =
        insert(:department, world: world, city: first_city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments")

      assert has_element?(view, "#departments-layout")
      assert has_element?(view, "#departments-city-selector-panel")
      assert has_element?(view, "#departments-city-select-form")
      assert has_element?(view, "#departments-city-select")
      assert has_element?(view, "#department-link-#{department.id}")
      assert has_element?(view, "#departments-list-panel", "Alpha City")
      assert has_element?(view, "#departments-city-map")
      refute has_element?(view, "#departments-cities-panel")
    end

    test "S02: page scopes departments to the selected city only", %{conn: conn} do
      world = insert(:world)

      city_a =
        insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      city_b = insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")

      department_a =
        insert(:department,
          world: world,
          city: city_a,
          name: "Support",
          slug: "support",
          tags: ["customer-care"]
        )

      department_b =
        insert(:department,
          world: world,
          city: city_b,
          name: "Platform",
          slug: "platform",
          tags: ["platform"]
        )

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city_b.id}")

      assert has_element?(view, "#departments-city-selector-panel")
      assert has_element?(view, "#department-link-#{department_b.id}")
      assert has_element?(view, "#departments-list-panel", "Beta City")
      assert has_element?(view, "#departments-city-map")
      refute has_element?(view, "#department-link-#{department_a.id}")
    end

    test "S03: changing the city selector patches to the chosen city", %{conn: conn} do
      world = insert(:world)

      city_a =
        insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      city_b = insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")
      insert(:department, world: world, city: city_b, name: "Platform", slug: "platform")

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city_a.id}")

      view
      |> element("#departments-city-select-form")
      |> render_change(%{"city_selector" => %{"city_id" => city_b.id}})

      assert_patch(view, ~p"/departments?#{%{city: city_b.id}}")
      assert has_element?(view, "#departments-list-panel", "Beta City")
    end

    test "S04: clicking a department enters detail route state", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          notes: "Handles escalations"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?city=#{city.id}")

      view |> element("#department-link-#{department.id}") |> render_click()

      assert_patch(view, ~p"/departments?#{%{city: city.id, dept: department.id}}")
      assert has_element?(view, "#department-detail-panel")
      assert has_element?(view, "#department-overview-tab-panel")
      assert has_element?(view, "#department-detail-city", "Alpha City")
      assert has_element?(view, "#department-lifecycle-panel")
    end

    test "S05: renders an empty page state when there are no cities", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/departments")

      assert has_element?(view, "#departments-page-empty-state")
    end

    test "S06: department detail supports tab patching and settings form", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          notes: nil
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-settings") |> render_click()

      assert_patch(
        view,
        ~p"/departments?#{%{city: city.id, dept: department.id, tab: "settings"}}"
      )

      assert has_element?(view, "#department-settings-tab-panel")
      assert has_element?(view, "#department-settings-form")
      assert has_element?(view, "#department-settings-effective-panel")
      assert has_element?(view, "#department-settings-local-overrides-panel")
    end

    test "S07: overview renders the full department detail context", %{conn: conn} do
      world = insert(:world, name: "Ops World", slug: "ops-world")
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          status: "draining",
          tags: ["customer-care", "tier-2"],
          notes: "Handles escalations"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      assert has_element?(view, "#department-detail-panel")
      assert has_element?(view, "#department-detail-status", "Draining")
      assert has_element?(view, "#department-detail-city", "Alpha City")
      assert has_element?(view, "#department-detail-world", "Ops World")
      assert has_element?(view, "#department-detail-slug", "support")
      assert has_element?(view, "#department-detail-name", "Support")
      assert has_element?(view, "#department-detail-tags", "customer-care, tier-2")
      assert has_element?(view, "#department-detail-notes", "Handles escalations")
      assert has_element?(view, "#department-action-activate")
      assert has_element?(view, "#department-action-drain")
      assert has_element?(view, "#department-action-disable")
      assert has_element?(view, "#department-action-delete")
    end

    test "S08: index omits the notes preview when notes are absent", %{conn: conn} do
      world = insert(:world, name: "Ops World", slug: "ops-world")
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          notes: nil
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id}}")

      assert has_element?(view, "#department-link-#{department.id}")
      refute has_element?(view, "#department-notes-preview-#{department.id}")
    end

    test "S09: lemmings tab renders persisted lemming definitions", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          name: "Incident Triage",
          slug: "incident-triage",
          status: "active",
          description: "Classifies inbound incidents."
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-lemmings") |> render_click()

      assert_patch(
        view,
        ~p"/departments?#{%{city: city.id, dept: department.id, tab: "lemmings"}}"
      )

      assert has_element?(view, "#department-lemmings-tab-panel")
      assert has_element?(view, "#department-lemmings-list")
      assert has_element?(view, "#department-lemming-#{lemming.id}")
      assert has_element?(view, "#department-lemming-#{lemming.id}", "Incident Triage")
      assert has_element?(view, "#department-lemming-#{lemming.id}", "incident-triage")
    end

    test "S09b: detail surfaces the primary manager entry and lemming roles", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      manager =
        insert(:manager_lemming,
          world: world,
          city: city,
          department: department,
          status: "active",
          slug: "support-manager",
          name: "Support Manager"
        )

      worker =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          status: "active",
          collaboration_role: "worker",
          slug: "incident-triage",
          name: "Incident Triage"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      assert has_element?(view, "#department-primary-manager-panel")
      assert has_element?(view, "#department-primary-manager-name", "Support Manager")
      assert has_element?(view, "#department-primary-manager-role", "Manager")
      assert has_element?(view, "#department-primary-manager-open")

      view |> element("#department-tab-lemmings") |> render_click()

      assert has_element?(view, "#department-lemming-role-#{manager.id}", "Manager")
      assert has_element?(view, "#department-lemming-primary-manager-#{manager.id}")
      assert has_element?(view, "#department-lemming-role-#{worker.id}", "Worker")
    end

    test "S09c: city map payload includes persisted lemming counts", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      insert(:lemming,
        world: world,
        city: city,
        department: department,
        name: "Incident Triage",
        slug: "incident-triage",
        status: "active"
      )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id}}")

      assert has_element?(view, "#departments-city-map")
      assert render(view) =~ "lemming_count"
    end

    test "S09b: lemmings tab shows an honest empty state with create CTA", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-lemmings") |> render_click()

      assert has_element?(view, "#department-lemmings-empty-state")
      assert has_element?(view, "#department-lemmings-empty-cta")
    end

    test "S10: settings distinguish effective config from local overrides", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 90, cross_city_communication: true},
          costs_config: %CostsConfig{budgets: %Budgets{daily_tokens: 1_000}}
        )

      department = insert(:department, world: world, city: city, slug: "support", name: "Support")

      {:ok, view, _html} =
        live(conn, ~p"/departments?#{%{city: city.id, dept: department.id, tab: "settings"}}")

      assert has_element?(view, "#department-settings-effective-panel")
      assert has_element?(view, "#department-settings-local-overrides-panel")
      assert has_element?(view, "#department-effective-idle-ttl", "90")
      assert has_element?(view, "#department-effective-cross-city", "true")
      assert has_element?(view, "#department-effective-daily-tokens", "1000")

      assert has_element?(
               view,
               "#department-local-idle-ttl",
               dgettext(LemmingsOs.Gettext, "world", ".label_not_available")
             )

      assert has_element?(
               view,
               "#department-local-cross-city",
               dgettext(LemmingsOs.Gettext, "world", ".label_not_available")
             )

      assert has_element?(
               view,
               "#department-local-daily-tokens",
               dgettext(LemmingsOs.Gettext, "world", ".label_not_available")
             )
    end

    test "S11: lifecycle actions update status and keep the operator on detail", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-action-disable") |> render_click()

      updated = Repo.get!(Department, department.id)

      assert updated.status == "disabled"
      assert has_element?(view, "#department-detail-status", "Disabled")
      assert render(view) =~ dgettext(LemmingsOs.Gettext, "world", ".flash_department_disabled")
    end

    test "S12: delete from an active department shows the not-disabled guard", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-action-delete") |> render_click()

      assert Repo.get!(Department, department.id)
      assert has_element?(view, "#department-detail-panel")

      assert render(view) =~
               dgettext(LemmingsOs.Gettext, "errors", ".department_delete_denied_not_disabled")
    end

    test "S13: delete stays honest when hard delete safety cannot be proven", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          status: "disabled"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-action-delete") |> render_click()

      assert Repo.get!(Department, department.id)
      assert has_element?(view, "#department-detail-panel")

      assert render(view) =~
               dgettext(
                 LemmingsOs.Gettext,
                 "errors",
                 ".department_delete_denied_safety_indeterminate"
               )
    end

    test "S14: department settings save updates the persisted local overrides", %{conn: conn} do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 90},
          costs_config: %CostsConfig{budgets: %Budgets{daily_tokens: 1_000}}
        )

      department = insert(:department, world: world, city: city, slug: "support", name: "Support")

      {:ok, view, _html} =
        live(conn, ~p"/departments?#{%{city: city.id, dept: department.id, tab: "settings"}}")

      view
      |> element("#department-settings-form")
      |> render_submit(%{
        "department" => %{
          "limits_config" => %{"max_lemmings_per_department" => "12"},
          "runtime_config" => %{
            "idle_ttl_seconds" => "180",
            "cross_city_communication" => "true"
          },
          "costs_config" => %{"budgets" => %{"daily_tokens" => "2500"}}
        }
      })

      updated = Repo.get!(Department, department.id)

      assert updated.limits_config.max_lemmings_per_department == 12
      assert updated.runtime_config.idle_ttl_seconds == 180
      assert updated.runtime_config.cross_city_communication == true
      assert updated.costs_config.budgets.daily_tokens == 2500
      assert has_element?(view, "#department-settings-tab-panel")
    end

    test "S15: connections tab supports local overrides by type", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      insert(:city_connection,
        world: world,
        city: city,
        department: nil,
        type: "mock",
        config: %{
          "mode" => "echo",
          "base_url" => "https://city.example.test/mock",
          "api_key" => "$CITY_MOCK_API_KEY"
        }
      )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-connections") |> render_click()

      assert_patch(
        view,
        ~p"/departments?#{%{city: city.id, dept: department.id, tab: "connections"}}"
      )

      inherited = Connections.resolve_visible_connection(department, "mock")

      assert has_element?(
               view,
               "#department-connections-source-#{inherited.connection.id}",
               "City"
             )

      assert has_element?(view, "#department-connections-panel")
      assert has_element?(view, "#department-connections-open-create")
      view |> element("#department-connections-open-create") |> render_click()
      assert render(view) =~ "$MOCK_API_KEY"

      view
      |> element("#department-connections-create-form")
      |> render_submit(%{
        "connection_create" => %{
          "type" => "mock",
          "status" => "enabled",
          "config" =>
            ~s({"mode":"echo","base_url":"https://department.example.test/mock","api_key":"$DEPT_MOCK_API_KEY"})
        }
      })

      created = Connections.get_connection_by_type(department, "mock")
      assert created
      assert has_element?(view, "#department-connections-source-#{created.id}", "Local")

      view
      |> element("#department-connections-edit-#{created.id}")
      |> render_click()

      view
      |> element("#department-connections-edit-form-#{created.id}")
      |> render_change(%{
        "connection_edit" => %{
          "connection_id" => created.id,
          "type" => "mock",
          "status" => "enabled"
        }
      })

      assert has_element?(view, "#department-connections-edit-form-#{created.id}")

      view
      |> element("#department-connections-delete-#{created.id}")
      |> render_click()

      refute Connections.get_connection(department, created.id)
    end

    test "S16: artifacts tab lists artifacts filtered by department", %{conn: conn} do
      world = insert(:world)
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")
      department = insert(:department, world: world, city: city, name: "Support", slug: "support")

      lemming =
        insert(:lemming, world: world, city: city, department: department, status: "active")

      department_artifact =
        insert(:artifact,
          world: world,
          city: city,
          department: department,
          lemming: nil,
          lemming_instance: nil,
          filename: "department.md"
        )

      city_artifact =
        insert(:artifact,
          world: world,
          city: city,
          department: nil,
          lemming: nil,
          lemming_instance: nil,
          filename: "city.md"
        )

      lemming_artifact =
        insert(:artifact,
          world: world,
          city: city,
          department: department,
          lemming: lemming,
          lemming_instance: nil,
          filename: "lemming.md"
        )

      {:ok, view, _html} = live(conn, ~p"/departments?#{%{city: city.id, dept: department.id}}")

      view |> element("#department-tab-artifacts") |> render_click()

      assert_patch(
        view,
        ~p"/departments?#{%{city: city.id, dept: department.id, tab: "artifacts"}}"
      )

      assert has_element?(view, "#department-artifacts-panel")
      assert has_element?(view, "#department-artifacts-row-#{department_artifact.id}")
      refute has_element?(view, "#department-artifacts-row-#{city_artifact.id}")
      assert has_element?(view, "#department-artifacts-row-#{lemming_artifact.id}")

      assert has_element?(
               view,
               "#department-artifacts-context-city-#{department_artifact.id}",
               city.slug
             )

      assert has_element?(
               view,
               "#department-artifacts-context-department-#{department_artifact.id}",
               department.slug
             )

      assert has_element?(
               view,
               "#department-artifacts-context-lemming-#{lemming_artifact.id}",
               lemming.slug
             )
    end
  end

  describe "import lemmings" do
    setup do
      world = insert(:world)
      city = insert(:city, world: world, status: "active")

      department =
        insert(:department, world: world, city: city, slug: "research", name: "Research")

      %{world: world, city: city, department: department}
    end

    test "S15: import button navigates to the import page", %{
      conn: conn,
      city: city,
      department: department
    } do
      {:ok, view, _html} =
        live(conn, ~p"/departments?#{%{city: city.id, dept: department.id, tab: "lemmings"}}")

      assert has_element?(view, "#department-import-toggle-btn")

      assert view
             |> element("#department-import-toggle-btn")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.attribute("href")
             |> hd() =~ "/lemmings/import"
    end
  end
end
