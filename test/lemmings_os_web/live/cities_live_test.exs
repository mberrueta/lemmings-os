defmodule LemmingsOsWeb.CitiesLiveTest do
  use LemmingsOsWeb.ConnCase

  import LemmingsOs.Factory
  import Phoenix.LiveViewTest

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  test "renders real persisted cities and the selected city detail", %{conn: conn} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    world = insert(:world, name: "City World", slug: "city-world", status: "ok")

    city_a =
      insert(:city,
        world: world,
        name: "Alpha City",
        slug: "alpha-city",
        status: "active",
        last_seen_at: now
      )

    city_b =
      insert(:city,
        world: world,
        name: "Beta City",
        slug: "beta-city",
        status: "draining",
        last_seen_at: DateTime.add(now, -300, :second)
      )

    {:ok, view, _html} = live(conn, ~p"/cities?city=#{city_b.id}")

    assert has_element?(view, "#cities-page")
    assert has_element?(view, "#cities-list-panel")
    assert has_element?(view, "#city-card-link-#{city_a.id}")
    assert has_element?(view, "#city-card-link-#{city_b.id}")
    assert has_element?(view, "#city-detail-panel")
    assert has_element?(view, "#city-admin-status[data-status='draining']")
    assert has_element?(view, "#city-liveness-status[data-status='stale']")
    assert has_element?(view, "#city-effective-config-panel")
    assert has_element?(view, "#city-departments-panel")
    assert has_element?(view, "#city-active-lemmings-panel")
  end

  test "renders the empty state when there is no persisted world", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cities")

    assert has_element?(view, "#cities-page-empty-state")
  end
end
