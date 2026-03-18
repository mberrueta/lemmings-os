defmodule LemmingsOs.CitiesTest do
  use LemmingsOs.DataCase, async: false

  alias Ecto.NoResultsError
  alias LemmingsOs.Cities

  describe "list_cities/2" do
    test "returns only cities for the given world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: world)
      insert(:city, world: other_world)

      [fetched_city] = Cities.list_cities(world)

      assert fetched_city.id == city.id
      assert fetched_city.world_id == world.id
    end

    test "applies filters and explicit preloads" do
      world = insert(:world)
      active_city = insert(:city, world: world, status: "active")
      insert(:city, world: world, status: "disabled")

      [city] = Cities.list_cities(world, status: "active", preload: [:world])

      assert city.id == active_city.id
      assert city.world.id == world.id
    end
  end

  describe "fetch_city/2 and get_city!/2" do
    test "fetches a city only within the given world" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert {:ok, fetched_city} = Cities.fetch_city(world, city.id)
      assert fetched_city.id == city.id
    end

    test "returns not_found when the city is outside the given world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: other_world)

      assert {:error, :not_found} = Cities.fetch_city(world, city.id)

      assert_raise NoResultsError, fn ->
        Cities.get_city!(world, city.id)
      end
    end
  end

  describe "get_city_by_slug/2" do
    test "returns the city in the given world or nil" do
      world = insert(:world)
      city = insert(:city, world: world, slug: "ops")

      assert %_{id: fetched_id} = Cities.get_city_by_slug(world, "ops")
      assert fetched_id == city.id
      assert Cities.get_city_by_slug(world, "missing") == nil
    end
  end

  describe "create_city/2" do
    test "creates a world-scoped city" do
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
  end

  describe "update_city/2" do
    test "updates the persisted city" do
      city = insert(:city, status: "active")

      assert {:ok, updated_city} = Cities.update_city(city, %{status: "disabled"})
      assert updated_city.status == "disabled"
    end
  end

  describe "delete_city/1" do
    test "deletes the persisted city" do
      city = insert(:city)

      assert {:ok, deleted_city} = Cities.delete_city(city)
      assert deleted_city.id == city.id
      assert Repo.get(LemmingsOs.City, city.id) == nil
    end
  end

  describe "upsert_runtime_city/2" do
    test "creates a city when no runtime row exists" do
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

    test "updates an existing city matched by node_name" do
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
      assert Repo.aggregate(LemmingsOs.City, :count) == 1
    end
  end

  describe "heartbeat_city/2" do
    test "updates last_seen_at" do
      city = insert(:city, last_seen_at: nil)
      seen_at = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:ok, updated_city} = Cities.heartbeat_city(city, seen_at)
      assert updated_city.last_seen_at == seen_at
    end
  end

  describe "stale_cities/2" do
    test "returns only stale cities for the given world" do
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
  end
end
