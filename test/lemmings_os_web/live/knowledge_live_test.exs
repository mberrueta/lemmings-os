defmodule LemmingsOsWeb.KnowledgeLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds

  test "knowledge tabs support deep links and source-file form is hidden by default", %{
    conn: conn
  } do
    _world = insert(:world)

    {:ok, memories_view, _html} = live(conn, ~p"/knowledge")

    assert has_element?(memories_view, "#knowledge-tab-memories[aria-selected]")
    assert has_element?(memories_view, "#knowledge-tab-panel-memories")
    refute has_element?(memories_view, "#knowledge-tab-panel-source-files")

    {:ok, source_files_view, _html} = live(conn, ~p"/knowledge?#{%{k_tab: "source_files"}}")

    assert has_element?(source_files_view, "#knowledge-tab-source-files[aria-selected]")
    assert has_element?(source_files_view, "#knowledge-tab-panel-source-files")
    assert has_element?(source_files_view, "#knowledge-source-file-open")
    assert has_element?(source_files_view, "#knowledge-source-file-empty-state")
    refute has_element?(source_files_view, "#knowledge-source-file-scope-empty-state")
    refute has_element?(source_files_view, "#knowledge-source-file-create-panel")
  end

  test "source-file tab defaults to world scope in global mode", %{conn: conn} do
    world =
      Worlds.list_worlds()
      |> Enum.sort_by(&{&1.inserted_at, &1.id})
      |> List.first()
      |> case do
        nil -> insert(:world, name: "Ops World", slug: "ops")
        existing -> existing
      end

    source_file =
      insert(:knowledge_source_file,
        knowledge_item:
          build(:knowledge_item,
            world: world,
            city: nil,
            department: nil,
            lemming: nil,
            kind: "source_file",
            status: "ready",
            title: "Default World Price List"
          ),
        source_file_type: "price_list",
        extraction_status: "ready",
        indexing_status: "ready",
        original_filename: "default-world-pricing.md"
      )

    {:ok, view, _html} = live(conn, ~p"/knowledge?#{%{k_tab: "source_files"}}")

    refute has_element?(view, "#knowledge-source-file-scope-empty-state")
    assert has_element?(view, "#knowledge-source-file-row-#{source_file.id}")
  end

  test "source-file scope selection persists through URL params in global mode", %{conn: conn} do
    world = insert(:world)

    {:ok, view, _html} = live(conn, ~p"/knowledge?#{%{k_tab: "source_files"}}")

    view
    |> element("#knowledge-source-file-open")
    |> render_click()

    view
    |> element("#knowledge-scope-form")
    |> render_change(%{"scope" => %{"scope_type" => "world", "scope_id" => world.id}})

    {redirected_path, _redirected_params} = assert_redirect(view)
    assert redirected_path =~ "k_tab=source_files"
    assert redirected_path =~ "status=active"
    assert redirected_path =~ "create_scope_type=world"
    assert redirected_path =~ "create_scope_id=#{world.id}"

    {:ok, view, _html} = live(conn, redirected_path)

    refute has_element?(view, "#knowledge-source-file-scope-empty-state")
    assert has_element?(view, "#knowledge-source-file-empty-state")
  end

  test "creates, edits, deletes memories and supports filtered empty states", %{conn: conn} do
    world = insert(:world)

    {:ok, view, _html} = live(conn, ~p"/knowledge")

    assert has_element?(view, "#knowledge-page")
    assert has_element?(view, "#knowledge-memory-open")
    refute has_element?(view, "#knowledge-memory-form")

    view
    |> element("#knowledge-memory-open")
    |> render_click()

    assert has_element?(view, "#knowledge-memory-form")
    assert has_element?(view, "#knowledge-scope-type")

    view
    |> element("#knowledge-scope-form")
    |> render_change(%{"scope" => %{"scope_type" => "world", "scope_id" => world.id}})

    view
    |> element("#knowledge-memory-form")
    |> render_submit(%{
      "memory" => %{
        "title" => "ACME language",
        "content" => "Use Portuguese summaries.",
        "tags" => "customer:acme, language:pt-BR"
      }
    })

    memory = Repo.one!(KnowledgeItem)

    assert has_element?(view, "#knowledge-memory-row-#{memory.id}")
    assert has_element?(view, "#knowledge-memory-source-#{memory.id}", "USER")
    assert has_element?(view, "#knowledge-memory-tag-#{memory.id}-0", "customer:acme")
    assert has_element?(view, "#knowledge-memory-tag-#{memory.id}-1", "language:pt-BR")

    view
    |> element("#knowledge-memory-edit-#{memory.id}")
    |> render_click()

    view
    |> element("#knowledge-memory-form")
    |> render_submit(%{
      "memory" => %{
        "title" => "ACME language updated",
        "content" => "Still Portuguese.",
        "tags" => "customer:acme"
      }
    })

    assert has_element?(view, "#knowledge-memory-title-#{memory.id}", "ACME language updated")

    view
    |> element("#knowledge-filters-form")
    |> render_change(%{
      "filter" => %{"query" => "missing-fragment", "source" => "", "status" => "active"}
    })

    assert has_element?(view, "#knowledge-filter-empty-state")

    view
    |> element("#knowledge-filters-form")
    |> render_change(%{"filter" => %{"query" => "", "source" => "", "status" => "active"}})

    view
    |> element("#knowledge-memory-delete-#{memory.id}")
    |> render_click()

    assert has_element?(view, "#knowledge-list-empty-state")
  end

  test "changing memory scope does not show required errors before memory form interaction", %{
    conn: conn
  } do
    world = insert(:world)

    {:ok, view, _html} = live(conn, ~p"/knowledge")

    view
    |> element("#knowledge-memory-open")
    |> render_click()

    view
    |> element("#knowledge-scope-form")
    |> render_change(%{"scope" => %{"scope_type" => "world", "scope_id" => world.id}})

    refute has_element?(view, "#knowledge-memory-content-error")
    refute render(view) =~ ".required"
  end

  test "changing memory scope clears stale blank validation feedback", %{conn: conn} do
    world = insert(:world)

    {:ok, view, _html} = live(conn, ~p"/knowledge")

    view
    |> element("#knowledge-memory-open")
    |> render_click()

    view
    |> element("#knowledge-memory-form")
    |> render_change(%{"memory" => %{"title" => "", "content" => "", "tags" => ""}})

    assert has_element?(view, "#knowledge-memory-content-error")

    view
    |> element("#knowledge-scope-form")
    |> render_change(%{"scope" => %{"scope_type" => "world", "scope_id" => world.id}})

    refute has_element?(view, "#knowledge-memory-content-error")
  end

  test "memory deep link selects scope and opens edit mode", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")
    city = insert(:city, world: world, name: "Ops City", slug: "ops-city")
    department = insert(:department, world: world, city: city, name: "Ops Dept", slug: "ops-dept")
    lemming = insert(:lemming, world: world, city: city, department: department, name: "Ops Bot")

    memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: department,
        lemming: lemming,
        title: "Deep link memory",
        content: "Memory opened by direct link."
      )

    {:ok, view, _html} = live(conn, ~p"/knowledge?#{%{memory_id: memory.id}}")

    assert has_element?(view, "#knowledge-memory-row-#{memory.id}")
    assert has_element?(view, "#knowledge-memory-form")
    assert has_element?(view, "#knowledge-memory-title[value='Deep link memory']")
    assert has_element?(view, "#knowledge-memory-edit-#{memory.id}")
    assert has_element?(view, "#knowledge-memory-delete-#{memory.id}")
  end

  test "default knowledge page lists memories without scope filters", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")
    city = insert(:city, world: world, name: "Ops City", slug: "ops-city")
    department = insert(:department, world: world, city: city, name: "Ops Dept", slug: "ops-dept")
    lemming = insert(:lemming, world: world, city: city, department: department, name: "Ops Bot")

    memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: department,
        lemming: lemming,
        title: "Visible on default knowledge",
        content: "This should appear without explicit scope params."
      )

    {:ok, view, _html} = live(conn, ~p"/knowledge")

    assert has_element?(view, "#knowledge-memory-row-#{memory.id}")

    assert has_element?(
             view,
             "#knowledge-memory-title-#{memory.id}",
             "Visible on default knowledge"
           )

    assert has_element?(view, "#knowledge-memory-city-link-#{memory.id}")
    assert has_element?(view, "#knowledge-memory-department-link-#{memory.id}")
    assert has_element?(view, "#knowledge-memory-lemming-link-#{memory.id}")
  end

  test "department scoped view shows local and descendant ownership labels", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")
    city = insert(:city, world: world, name: "Ops City", slug: "ops-city")
    department = insert(:department, world: world, city: city, name: "Ops Dept", slug: "ops-dept")
    lemming = insert(:lemming, world: world, city: city, department: department, name: "Ops Bot")

    department_memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: department,
        lemming: nil,
        title: "Department local memory"
      )

    lemming_memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: department,
        lemming: lemming,
        title: "Department descendant memory"
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/knowledge?#{%{scope_type: "department", scope_id: department.id, status: "active"}}"
      )

    assert has_element?(view, "#knowledge-memory-row-#{department_memory.id}")
    assert has_element?(view, "#knowledge-memory-row-#{lemming_memory.id}")
    assert has_element?(view, "#knowledge-memory-local-#{department_memory.id}", "Local")
    assert has_element?(view, "#knowledge-memory-local-#{lemming_memory.id}", "Descendant")
  end

  test "scoped lemming query params do not expose sibling memories", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")
    city = insert(:city, world: world, name: "Ops City", slug: "ops-city")
    department = insert(:department, world: world, city: city, name: "Ops Dept", slug: "ops-dept")

    sibling_department =
      insert(:department, world: world, city: city, name: "Ops Other", slug: "ops-other")

    lemming = insert(:lemming, world: world, city: city, department: department, name: "Ops Bot")

    sibling_lemming =
      insert(:lemming,
        world: world,
        city: city,
        department: sibling_department,
        name: "Other Bot"
      )

    local_memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: department,
        lemming: lemming,
        title: "Visible lemming memory"
      )

    sibling_memory =
      insert(:knowledge_item,
        world: world,
        city: city,
        department: sibling_department,
        lemming: sibling_lemming,
        title: "Hidden sibling memory"
      )

    {:ok, view, _html} =
      live(conn, ~p"/knowledge?#{%{scope_type: "lemming", scope_id: lemming.id}}")

    assert has_element?(view, "#knowledge-memory-row-#{local_memory.id}")
    refute has_element?(view, "#knowledge-memory-row-#{sibling_memory.id}")
  end

  test "pagination controls move between pages with stable selectors", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")

    Enum.each(1..26, fn index ->
      insert(:knowledge_item,
        world: world,
        city: nil,
        department: nil,
        lemming: nil,
        title: "Paged Memory #{index}",
        inserted_at: DateTime.add(~U[2026-01-01 00:00:00Z], index, :second)
      )
    end)

    {:ok, view, _html} = live(conn, ~p"/knowledge")

    assert has_element?(view, "#knowledge-page-range", "Showing 1 to 25")
    assert has_element?(view, "#knowledge-page-next")
    assert has_element?(view, "#knowledge-page-prev[disabled]")

    view
    |> element("#knowledge-page-next")
    |> render_click()

    assert has_element?(view, "#knowledge-page-range", "Showing 26 to 26")
    assert has_element?(view, "#knowledge-page-prev")

    view
    |> element("#knowledge-page-prev")
    |> render_click()

    assert has_element?(view, "#knowledge-page-range", "Showing 1 to 25")
  end

  test "source-file list supports metadata edit, retry and archive actions", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")

    source_file =
      insert(:knowledge_source_file,
        knowledge_item:
          build(:knowledge_item,
            world: world,
            city: nil,
            department: nil,
            lemming: nil,
            kind: "source_file",
            status: "ready",
            title: "Pricing Handbook",
            tags: ["pricing", "customer:acme"]
          ),
        source_file_type: "company_knowledge",
        extraction_status: "ready",
        indexing_status: "ready",
        original_filename: "pricing.md"
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/knowledge?#{%{scope_type: "world", scope_id: world.id, status: "active", k_tab: "source_files"}}"
      )

    assert has_element?(view, "#knowledge-source-file-row-#{source_file.id}")

    assert has_element?(
             view,
             "#knowledge-source-file-title-text-#{source_file.id}",
             "Pricing Handbook"
           )

    assert has_element?(
             view,
             "#knowledge-source-file-edit-#{source_file.id}[aria-label='Edit source file metadata']"
           )

    assert has_element?(
             view,
             "#knowledge-source-file-retry-#{source_file.id}[aria-label='Retry source file indexing']"
           )

    assert has_element?(
             view,
             "#knowledge-source-file-archive-#{source_file.id}[aria-label='Archive source file']"
           )

    view
    |> element("#knowledge-source-file-edit-#{source_file.id}")
    |> render_click()

    assert has_element?(view, "#knowledge-source-file-edit-form-#{source_file.id}")

    view
    |> element("#knowledge-source-file-edit-form-#{source_file.id}")
    |> render_submit(%{
      "source_file_id" => source_file.id,
      "source_file_edit" => %{
        "title" => "Pricing Handbook Updated",
        "tags" => "pricing, customer:globex",
        "source_file_type" => "policy"
      }
    })

    assert has_element?(
             view,
             "#knowledge-source-file-title-text-#{source_file.id}",
             "Pricing Handbook Updated"
           )

    updated_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)
    updated_source_file = Repo.get!(SourceFile, source_file.id)

    assert updated_item.tags == ["pricing", "customer:globex"]
    assert updated_source_file.source_file_type == "policy"

    view
    |> element("#knowledge-source-file-retry-#{source_file.id}")
    |> render_click()

    retried_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)
    retried_source_file = Repo.get!(SourceFile, source_file.id)

    assert retried_item.status == "pending_index"
    assert retried_source_file.indexing_status == "pending"

    view
    |> element("#knowledge-source-file-archive-#{source_file.id}")
    |> render_click()

    archived_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)
    archived_source_file = Repo.get!(SourceFile, source_file.id)

    assert archived_item.status == "archived"
    assert archived_source_file.indexing_status == "archived"
  end

  test "source-file filters narrow by query, status, and type with stable selectors", %{
    conn: conn
  } do
    world = insert(:world)

    policy_file =
      insert(:knowledge_source_file,
        knowledge_item:
          build(:knowledge_item,
            world: world,
            city: nil,
            department: nil,
            lemming: nil,
            kind: "source_file",
            status: "ready",
            title: "Policy Guide",
            tags: ["policy", "customer:acme"]
          ),
        source_file_type: "policy",
        extraction_status: "ready",
        indexing_status: "ready",
        original_filename: "policy.md"
      )

    failed_file =
      insert(:knowledge_source_file,
        knowledge_item:
          build(:knowledge_item,
            world: world,
            city: nil,
            department: nil,
            lemming: nil,
            kind: "source_file",
            status: "failed",
            title: "Pricing Catalog",
            tags: ["pricing"]
          ),
        source_file_type: "company_knowledge",
        extraction_status: "failed",
        indexing_status: "failed",
        failure_reason: "extraction_failed",
        original_filename: "pricing.md"
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/knowledge?#{%{scope_type: "world", scope_id: world.id, status: "active", k_tab: "source_files"}}"
      )

    assert has_element?(view, "#knowledge-source-file-row-#{policy_file.id}")
    assert has_element?(view, "#knowledge-source-file-row-#{failed_file.id}")

    assert has_element?(
             view,
             "#knowledge-source-file-failure-#{failed_file.id}",
             "extraction_failed"
           )

    view
    |> element("#knowledge-source-file-filter-form")
    |> render_change(%{
      "source_file_filter" => %{"query" => "pricing", "status" => "", "source_file_type" => ""}
    })

    assert has_element?(view, "#knowledge-source-file-row-#{failed_file.id}")
    refute has_element?(view, "#knowledge-source-file-row-#{policy_file.id}")

    view
    |> element("#knowledge-source-file-filter-form")
    |> render_change(%{
      "source_file_filter" => %{
        "query" => "",
        "status" => "ready",
        "source_file_type" => "policy"
      }
    })

    assert has_element?(view, "#knowledge-source-file-row-#{policy_file.id}")
    refute has_element?(view, "#knowledge-source-file-row-#{failed_file.id}")
  end

  test "source-file upload create flow handles consumed upload metadata without crashing", %{
    conn: conn
  } do
    world = insert(:world)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/knowledge?#{%{scope_type: "world", scope_id: world.id, status: "active", k_tab: "source_files"}}"
      )

    view
    |> element("#knowledge-source-file-open")
    |> render_click()

    upload =
      file_input(view, "#knowledge-source-file-form", :source_file, [
        %{name: "pricing.txt", content: "line one\nline two\n", type: "text/plain"}
      ])

    assert render_upload(upload, "pricing.txt") =~ "pricing.txt"

    view
    |> element("#knowledge-source-file-form")
    |> render_submit(%{
      "source_file" => %{
        "title" => "Pricing Source",
        "source_file_type" => "price_list",
        "tags" => "",
        "content" => "Source file registered for indexing."
      }
    })

    source_file = Repo.one!(SourceFile)
    source_file_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)

    assert source_file.original_filename == "pricing.txt"
    assert source_file_item.title == "Pricing Source"
    assert has_element?(view, "#knowledge-source-file-row-#{source_file.id}")
  end
end
