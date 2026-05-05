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
end
