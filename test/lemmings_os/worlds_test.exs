defmodule LemmingsOs.WorldsTest do
  use LemmingsOs.DataCase, async: false

  alias Ecto.NoResultsError
  alias LemmingsOs.World
  alias LemmingsOs.Worlds

  doctest LemmingsOs.Worlds

  describe "World.changeset/2" do
    test "requires slug and name" do
      changeset = World.changeset(%World{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.name
    end

    test "rejects statuses outside the frozen taxonomy" do
      changeset = World.changeset(%World{}, %{slug: "local", name: "Local", status: "broken"})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "is invalid" in errors.status
    end

    test "exposes translated status helpers for UI usage" do
      assert World.statuses() == ~w(ok degraded unavailable invalid unknown)
      assert World.translate_status("degraded") == "Degraded"
      assert World.translate_status(nil) == "Unknown"

      assert World.status_options() == [
               {"ok", "OK"},
               {"degraded", "Degraded"},
               {"unavailable", "Unavailable"},
               {"invalid", "Invalid"},
               {"unknown", "Unknown"}
             ]
    end
  end

  describe "fetch_world/1" do
    test "returns the persisted world" do
      world = insert(:world)

      assert {:ok, fetched_world} = Worlds.fetch_world(world.id)
      assert fetched_world.id == world.id
    end

    test "returns an error tuple when the world does not exist" do
      assert {:error, reason} = Worlds.fetch_world(Ecto.UUID.generate())
      assert reason in [:not_found, :world_not_found]
    end
  end

  describe "get_world!/1" do
    test "returns the persisted world" do
      world = insert(:world)

      fetched_world = Worlds.get_world!(world.id)

      assert fetched_world.id == world.id
    end

    test "raises when the world does not exist" do
      assert_raise NoResultsError, fn ->
        Worlds.get_world!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_default_world/0" do
    test "returns the default world when one exists" do
      Repo.delete_all(World)
      world = insert(:world)
      LemmingsOs.WorldCache.invalidate_all()

      assert {:ok, default_world} = Worlds.get_default_world()
      assert default_world.id == world.id
    end

    test "returns an error tuple when no world exists" do
      Repo.delete_all(World)
      LemmingsOs.WorldCache.invalidate_all()
      assert {:error, reason} = Worlds.get_default_world()
      assert reason in [:not_found, :world_not_found, :default_world_not_found]
    end
  end

  describe "upsert_world/1" do
    test "inserts a world with persisted defaults" do
      Repo.delete_all(World)
      unique_value = System.unique_integer([:positive])

      attrs =
        params_for(:world,
          slug: "local-#{unique_value}",
          name: "Local World #{unique_value}",
          bootstrap_path: "/tmp/worlds/local-#{unique_value}.default.world.yaml"
        )

      assert function_exported?(Worlds, :upsert_world, 1)
      assert {:ok, world} = Worlds.upsert_world(attrs)

      assert world.slug == "local-#{unique_value}"
      assert world.name == "Local World #{unique_value}"
      assert world.status == "unknown"
      assert world.last_import_status == "unknown"
      assert world.limits_config == %{}
      assert world.runtime_config == %{}
      assert world.costs_config == %{}
      assert world.models_config == %{}
    end

    test "updates the existing world instead of inserting a duplicate" do
      Repo.delete_all(World)
      unique_value = System.unique_integer([:positive])

      attrs =
        params_for(:world,
          slug: "local-#{unique_value}",
          name: "Local World #{unique_value}",
          bootstrap_path: "/tmp/worlds/local-#{unique_value}.default.world.yaml"
        )

      assert {:ok, world} = Worlds.upsert_world(attrs)

      assert {:ok, updated_world} =
               Worlds.upsert_world(%{
                 slug: "local-#{unique_value}",
                 name: "Renamed Local World",
                 status: "degraded",
                 bootstrap_path: "/tmp/worlds/local-#{unique_value}.default.world.yaml",
                 models_config: %{"providers" => %{"ollama" => %{"enabled" => true}}}
               })

      assert updated_world.id == world.id
      assert updated_world.name == "Renamed Local World"
      assert updated_world.status == "degraded"
      assert updated_world.models_config == %{"providers" => %{"ollama" => %{"enabled" => true}}}

      assert Repo.aggregate(World, :count) == 1
    end

    test "matches an existing world by bootstrap_path before slug" do
      Repo.delete_all(World)

      world =
        insert(:world, slug: "alpha", bootstrap_path: "/tmp/worlds/local.default.world.yaml")

      assert {:ok, updated_world} =
               Worlds.upsert_world(%{
                 slug: "different-slug",
                 name: "Renamed Local World",
                 bootstrap_path: "/tmp/worlds/local.default.world.yaml"
               })

      assert updated_world.id == world.id
      assert updated_world.slug == "different-slug"
      assert updated_world.name == "Renamed Local World"
      assert Repo.aggregate(World, :count) == 1
    end

    test "matches an existing world by id when slug and bootstrap_path change" do
      Repo.delete_all(World)

      world =
        insert(:world, slug: "alpha", bootstrap_path: "/tmp/worlds/alpha.default.world.yaml")

      assert {:ok, updated_world} =
               Worlds.upsert_world(%{
                 id: world.id,
                 slug: "alpha-renamed",
                 name: "Updated By Id",
                 bootstrap_path: "/tmp/worlds/alpha-renamed.default.world.yaml"
               })

      assert updated_world.id == world.id
      assert updated_world.slug == "alpha-renamed"
      assert updated_world.name == "Updated By Id"
      assert updated_world.bootstrap_path == "/tmp/worlds/alpha-renamed.default.world.yaml"
      assert Repo.aggregate(World, :count) == 1
    end
  end
end
