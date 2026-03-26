defmodule LemmingsOs.CitiesTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City

  describe "list_cities/2" do
    test "S01: returns only cities for the given world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: world)
      insert(:city, world: other_world)

      [fetched_city] = Cities.list_cities(world)

      assert fetched_city.id == city.id
      assert fetched_city.world_id == world.id
    end

    test "S02: applies filters and explicit preloads" do
      world = insert(:world)
      active_city = insert(:city, world: world, status: "active")
      insert(:city, world: world, status: "disabled")

      [city] = Cities.list_cities(world, status: "active", preload: [:world])

      assert city.id == active_city.id
      assert city.world.id == world.id
    end

    test "S03: returns cities sorted by inserted_at then id" do
      world = insert(:world)
      insert(:city, world: world)
      insert(:city, world: world)

      cities = Cities.list_cities(world)

      assert length(cities) == 2

      # Verify stable ordering: sorted by inserted_at ASC, then id ASC
      [first, second] = cities
      assert {first.inserted_at, first.id} <= {second.inserted_at, second.id}
    end

    test "S05: returns empty list for a world with no cities" do
      world = insert(:world)

      assert Cities.list_cities(world) == []
    end

    test "S06: filters by node_name" do
      world = insert(:world)
      insert(:city, world: world, node_name: "alpha@localhost")
      beta = insert(:city, world: world, node_name: "beta@localhost")

      [city] = Cities.list_cities(world, node_name: "beta@localhost")

      assert city.id == beta.id
    end

    test "S07: filters by ids list" do
      world = insert(:world)
      city_a = insert(:city, world: world)
      insert(:city, world: world)

      [city] = Cities.list_cities(world, ids: [city_a.id])

      assert city.id == city_a.id
    end

    test "S08: filters by stale_before cutoff" do
      world = insert(:world)
      # City seen recently (after cutoff) should NOT be returned
      insert(:city, world: world, last_seen_at: ~U[2026-03-18 18:01:00Z])
      # City seen before cutoff should be returned
      stale = insert(:city, world: world, last_seen_at: ~U[2026-03-18 17:50:00Z])

      cutoff = ~U[2026-03-18 18:00:00Z]
      cities = Cities.list_cities(world, stale_before: cutoff)

      assert length(cities) == 1
      assert hd(cities).id == stale.id
    end
  end

  describe "get_city/3" do
    test "S09: fetches a city only within the given world" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert %City{} = fetched_city = Cities.get_city(world, city.id)
      assert fetched_city.id == city.id
    end

    test "S10: returns not_found when the city does not exist" do
      world = insert(:world)

      assert Cities.get_city(world, Ecto.UUID.generate()) == nil
    end

    test "S11: returns not_found when the city is outside the given world (cross-world isolation)" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: other_world)

      assert Cities.get_city(world, city.id) == nil
    end
  end

  describe "get_city_by_slug/2" do
    test "S12: returns the city in the given world or nil" do
      world = insert(:world)
      city = insert(:city, world: world, slug: "ops")

      assert %_{id: fetched_id} = Cities.get_city_by_slug(world, "ops")
      assert fetched_id == city.id
      assert Cities.get_city_by_slug(world, "missing") == nil
    end
  end

  describe "create_city/2" do
    test "S13: creates a world-scoped city with config embeds" do
      world = insert(:world)

      assert {:ok, city} =
               Cities.create_city(world, %{
                 slug: "ops",
                 name: "Ops",
                 node_name: "ops@localhost",
                 status: "active",
                 runtime_config: %{"cross_city_communication" => false}
               })

      assert city.world_id == world.id
      assert city.runtime_config.cross_city_communication == false
    end

    test "S14: returns changeset error when required fields are missing" do
      world = insert(:world)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Cities.create_city(world, %{name: "Incomplete"})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.node_name
      assert "can't be blank" in errors.status
    end

    test "S15: returns changeset error on duplicate slug within the same world" do
      world = insert(:world)
      insert(:city, world: world, slug: "ops", node_name: "ops-a@localhost")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Cities.create_city(world, %{
                 slug: "ops",
                 name: "Another Ops",
                 node_name: "ops-b@localhost",
                 status: "active"
               })

      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "update_city/2" do
    test "S16: updates the persisted city" do
      city = insert(:city, status: "active")

      assert {:ok, updated_city} = Cities.update_city(city, %{status: "disabled"})
      assert updated_city.status == "disabled"
    end

    test "S17: returns changeset error on invalid update" do
      city = insert(:city, status: "active")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Cities.update_city(city, %{status: "bogus"})

      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "delete_city/1" do
    test "S18: deletes the persisted city and confirms it is gone" do
      city = insert(:city)

      assert {:ok, deleted_city} = Cities.delete_city(city)
      assert deleted_city.id == city.id
      assert Repo.get(City, city.id) == nil
    end
  end

  describe "upsert_runtime_city/2" do
    test "S19: creates a city when no runtime row exists" do
      world = insert(:world)

      assert {:ok, city} =
               Cities.upsert_runtime_city(world, %{
                 slug: "primary",
                 name: "Primary",
                 node_name: "primary@localhost",
                 status: "active"
               })

      assert city.world_id == world.id
    end

    test "S20: updates an existing city matched by node_name" do
      world = insert(:world)
      city = insert(:city, world: world, node_name: "primary@localhost", name: "Before")

      assert {:ok, updated_city} =
               Cities.upsert_runtime_city(world, %{
                 node_name: "primary@localhost",
                 slug: city.slug,
                 name: "After",
                 status: "active"
               })

      assert updated_city.id == city.id
      assert updated_city.name == "After"
      assert Repo.aggregate(City, :count) == 1
    end
  end

  describe "heartbeat_city/2" do
    test "S21: updates last_seen_at" do
      city = insert(:city, last_seen_at: nil)
      seen_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, updated_city} = Cities.heartbeat_city(city, seen_at)
      assert updated_city.last_seen_at == seen_at
    end

    test "S22: truncates last_seen_at to seconds" do
      city = insert(:city, last_seen_at: nil)
      seen_at = ~U[2026-03-18 18:00:00.123456Z]

      assert {:ok, updated_city} = Cities.heartbeat_city(city, seen_at)
      assert updated_city.last_seen_at == ~U[2026-03-18 18:00:00Z]
    end
  end

  describe "stale_cities/2" do
    test "S23: returns only stale cities for the given world" do
      world = insert(:world)
      cutoff = DateTime.utc_now() |> DateTime.truncate(:second)
      stale_time = DateTime.add(cutoff, -60, :second)
      fresh_time = DateTime.add(cutoff, 60, :second)

      stale_city = insert(:city, world: world, last_seen_at: stale_time)
      insert(:city, world: world, last_seen_at: fresh_time)
      insert(:city, world: insert(:world), last_seen_at: stale_time)

      [fetched_city] = Cities.stale_cities(world, cutoff)

      assert fetched_city.id == stale_city.id
      assert fetched_city.world_id == world.id
    end

    test "S24: excludes cities with nil last_seen_at" do
      world = insert(:world)
      cutoff = DateTime.utc_now() |> DateTime.truncate(:second)
      insert(:city, world: world, last_seen_at: nil)

      assert Cities.stale_cities(world, cutoff) == []
    end
  end
end
