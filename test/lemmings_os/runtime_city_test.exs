defmodule LemmingsOs.Cities.RuntimeTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Cities.Runtime
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  setup do
    previous_config = Application.get_env(:lemmings_os, :runtime_city)

    on_exit(fn ->
      Application.put_env(:lemmings_os, :runtime_city, previous_config)
    end)

    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "runtime_city_attrs/1" do
    test "derives slug, name, and host from node_name when not configured" do
      attrs = Runtime.runtime_city_attrs(config: %{node_name: "city-main@example.local"})

      assert attrs == %{
               slug: "city-main",
               name: "City Main",
               node_name: "city-main@example.local",
               host: "example.local",
               distribution_port: nil,
               epmd_port: nil,
               status: "active"
             }
    end

    test "honors explicit runtime city overrides" do
      attrs =
        Runtime.runtime_city_attrs(
          config: %{
            node_name: "beam@cluster.local",
            slug: "ops-west",
            name: "Ops West",
            host: "runtime.local",
            distribution_port: 9_100,
            epmd_port: 4_369
          }
        )

      assert attrs.slug == "ops-west"
      assert attrs.name == "Ops West"
      assert attrs.host == "runtime.local"
      assert attrs.distribution_port == 9_100
      assert attrs.epmd_port == 4_369
    end
  end

  describe "sync_runtime_city/1" do
    test "creates the first city for the resolved default world" do
      world = insert(:world)

      assert {:ok, city} =
               Runtime.sync_runtime_city(
                 config: %{
                   node_name: "primary@localhost",
                   slug: "primary",
                   name: "Primary"
                 }
               )

      assert city.world_id == world.id
      assert city.node_name == "primary@localhost"
      assert city.slug == "primary"
      assert city.name == "Primary"
      assert city.host == "localhost"
    end

    test "updates the matching runtime city when node_name already exists" do
      world = insert(:world)
      city = insert(:city, world: world, node_name: "primary@localhost", name: "Before")

      assert {:ok, updated_city} =
               Runtime.sync_runtime_city(
                 config: %{
                   node_name: "primary@localhost",
                   slug: city.slug,
                   name: "After"
                 }
               )

      assert updated_city.id == city.id
      assert updated_city.name == "After"
      assert Repo.aggregate(LemmingsOs.Cities.City, :count) == 1
    end

    test "returns an honest error when no default world can be resolved" do
      assert {:error, :default_world_not_found} = Runtime.sync_runtime_city()
    end
  end
end
