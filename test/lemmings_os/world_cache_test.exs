defmodule LemmingsOs.WorldCacheTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.World
  alias LemmingsOs.WorldCache
  alias LemmingsOs.Worlds

  doctest LemmingsOs.WorldCache

  setup do
    Repo.delete_all(World)
    WorldCache.invalidate_all()
    :ok
  end

  describe "fetch_world/1" do
    test "returns the cached world after the first lookup" do
      world = insert(:world)

      assert {:ok, fetched_world} = Worlds.fetch_world(world.id)
      assert fetched_world.id == world.id

      Repo.delete!(world)

      assert {:ok, cached_world} = Worlds.fetch_world(world.id)
      assert cached_world.id == world.id
    end
  end

  describe "get_default_world/0" do
    test "returns the cached default world after the first lookup" do
      world = insert(:world)

      assert {:ok, default_world} = Worlds.get_default_world()
      assert default_world.id == world.id

      Repo.delete!(world)

      assert {:ok, cached_default_world} = Worlds.get_default_world()
      assert cached_default_world.id == world.id
    end
  end

  describe "world mutations" do
    test "refreshes cached world and default-world reads after upsert_world/1" do
      world = insert(:world, name: "Before")

      assert {:ok, fetched_world} = Worlds.fetch_world(world.id)
      assert fetched_world.name == "Before"

      assert {:ok, default_world} = Worlds.get_default_world()
      assert default_world.id == world.id
      assert default_world.name == "Before"

      assert {:ok, updated_world} =
               Worlds.upsert_world(%{
                 id: world.id,
                 slug: world.slug,
                 name: "After",
                 bootstrap_path: world.bootstrap_path
               })

      assert updated_world.name == "After"

      assert {:ok, refreshed_world} = Worlds.fetch_world(world.id)
      assert refreshed_world.id == world.id
      assert refreshed_world.name == "After"

      assert {:ok, refreshed_default_world} = Worlds.get_default_world()
      assert refreshed_default_world.id == world.id
      assert refreshed_default_world.name == "After"
    end
  end
end
