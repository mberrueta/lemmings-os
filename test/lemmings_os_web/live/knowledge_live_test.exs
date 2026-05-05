defmodule LemmingsOsWeb.KnowledgeLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Repo

  test "creates, edits, deletes memories and supports filtered empty states", %{conn: conn} do
    world = insert(:world, name: "Ops World", slug: "ops")

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
end
