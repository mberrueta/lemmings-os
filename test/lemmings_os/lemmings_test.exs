defmodule LemmingsOs.LemmingsTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.DeleteDeniedError
  alias LemmingsOs.Lemmings.Lemming

  doctest LemmingsOs.Lemmings

  describe "list_lemmings/2" do
    test "returns lemmings for a world scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      other_world_department = insert(:department, world: other_world, city: other_city)

      lemming_a =
        insert(:lemming, world: world, city: city, department: department, status: "draft")

      lemming_b =
        insert(:lemming, world: world, city: city, department: department, status: "active")

      insert(:lemming, world: other_world, city: other_city, department: other_world_department)

      lemmings = Lemmings.list_lemmings(world)

      assert Enum.sort(Enum.map(lemmings, & &1.id)) == Enum.sort([lemming_a.id, lemming_b.id])
    end

    test "returns lemmings for a city scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      other_department = insert(:department, world: world, city: other_city)

      lemming = insert(:lemming, world: world, city: city, department: department)
      insert(:lemming, world: world, city: other_city, department: other_department)

      assert [fetched_lemming] = Lemmings.list_lemmings(city)
      assert fetched_lemming.id == lemming.id
    end

    test "returns lemmings for a department scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      other_department = insert(:department, world: world, city: city)

      lemming = insert(:lemming, world: world, city: city, department: department)
      insert(:lemming, world: world, city: city, department: other_department)

      assert [fetched_lemming] = Lemmings.list_lemmings(department)
      assert fetched_lemming.id == lemming.id
    end

    test "supports status, ids, slug, and preload filters" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      active_lemming =
        insert(:lemming, world: world, city: city, department: department, status: "active")

      draft_lemming =
        insert(:lemming, world: world, city: city, department: department, status: "draft")

      assert [filtered_lemming] =
               Lemmings.list_lemmings(department,
                 status: "draft",
                 ids: [draft_lemming.id],
                 slug: draft_lemming.slug,
                 preload: [:world, :city, :department]
               )

      assert filtered_lemming.id == draft_lemming.id
      assert Ecto.assoc_loaded?(filtered_lemming.world)
      assert Ecto.assoc_loaded?(filtered_lemming.city)
      assert Ecto.assoc_loaded?(filtered_lemming.department)
      refute filtered_lemming.id == active_lemming.id
    end

    test "orders lemmings by name and slug" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      gamma =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          name: "Gamma",
          slug: "gamma"
        )

      alpha_b =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          name: "Alpha",
          slug: "b"
        )

      alpha_a =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          name: "Alpha",
          slug: "a"
        )

      assert Enum.map(Lemmings.list_lemmings(department), & &1.id) == [
               alpha_a.id,
               alpha_b.id,
               gamma.id
             ]
    end
  end

  describe "get APIs" do
    test "get_lemming/2 returns the lemming by id" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      fetched_lemming = Lemmings.get_lemming(lemming.id)
      assert fetched_lemming.id == lemming.id
    end

    test "get_lemming/2 returns nil when the id is missing" do
      assert Lemmings.get_lemming(Ecto.UUID.generate()) == nil
    end

    test "get_lemming/2 supports explicit preloads" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      fetched_lemming =
        Lemmings.get_lemming(lemming.id, preload: [:world, :city, :department])

      assert Ecto.assoc_loaded?(fetched_lemming.world)
      assert Ecto.assoc_loaded?(fetched_lemming.city)
      assert Ecto.assoc_loaded?(fetched_lemming.department)
    end

    test "get by slug is department-scoped" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, slug: "ops")
      other_department = insert(:department, world: world, city: city, slug: "qa")

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          slug: "code-reviewer"
        )

      insert(:lemming,
        world: world,
        city: city,
        department: other_department,
        slug: "code-reviewer"
      )

      fetched_lemming = Lemmings.get_lemming_by_slug(department, lemming.slug)

      assert fetched_lemming.id == lemming.id
    end

    test "get_lemming_by_slug/2 returns nil when missing in department scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert Lemmings.get_lemming_by_slug(department, "missing") == nil
    end
  end

  describe "create_lemming/4" do
    test "creates a lemming scoped to the given world, city, and department" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, lemming} =
               Lemmings.create_lemming(world, city, department, %{
                 slug: "code-reviewer",
                 name: "Code Reviewer",
                 status: "draft",
                 tools_config: %{"allowed_tools" => ["github"]}
               })

      assert lemming.world_id == world.id
      assert lemming.city_id == city.id
      assert lemming.department_id == department.id
      assert lemming.tools_config.allowed_tools == ["github"]
    end

    test "rejects creating a lemming when the department does not belong to the city and world" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      department = insert(:department, world: other_world, city: other_city)

      assert {:error, :department_not_in_city_world} =
               Lemmings.create_lemming(world, city, department, %{
                 slug: "code-reviewer",
                 name: "Code Reviewer",
                 status: "draft"
               })
    end

    test "returns changeset error on duplicate slug within the same department" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      insert(:lemming, world: world, city: city, department: department, slug: "code-reviewer")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Lemmings.create_lemming(world, city, department, %{
                 slug: "code-reviewer",
                 name: "Another Reviewer",
                 status: "draft"
               })

      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "update_lemming/2 and lifecycle wrappers" do
    test "updates persisted lemming attributes" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming, world: world, city: city, department: department, status: "draft")

      assert {:ok, updated_lemming} =
               Lemmings.update_lemming(lemming, %{
                 name: "Renamed Lemming",
                 description: "Updated description"
               })

      assert updated_lemming.name == "Renamed Lemming"
      assert updated_lemming.description == "Updated description"
    end

    test "set_lemming_status/2 and archive wrapper delegate through the status path" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          status: "draft",
          instructions: "Review pull requests"
        )

      assert {:ok, active_lemming} = Lemmings.set_lemming_status(lemming, "active")
      assert active_lemming.status == "active"

      assert {:ok, archived_lemming} = Lemmings.set_lemming_status(active_lemming, "archived")
      assert archived_lemming.status == "archived"

      assert {:ok, active_again_lemming} =
               Lemmings.set_lemming_status(archived_lemming, "active")

      assert active_again_lemming.status == "active"
    end

    test "set_lemming_status/2 rejects nil instructions when activating" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          status: "draft",
          instructions: nil
        )

      assert {:error, :instructions_required} = Lemmings.set_lemming_status(lemming, "active")
    end

    test "set_lemming_status/2 rejects blank instructions when activating" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          status: "draft",
          instructions: "   "
        )

      assert {:error, :instructions_required} = Lemmings.set_lemming_status(lemming, "active")
    end
  end

  describe "delete_lemming/1" do
    test "rejects deleting lemmings in all statuses" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming, world: world, city: city, department: department, status: "active")

      assert {:error, %DeleteDeniedError{} = error} = Lemmings.delete_lemming(lemming)
      assert error.lemming_id == lemming.id
      assert error.reason == :safety_indeterminate
      assert Repo.get(Lemming, lemming.id)
    end
  end

  describe "topology_summary/1" do
    test "returns aggregate lemming counts for the world without department-by-department enumeration" do
      world = insert(:world)
      city = insert(:city, world: world)
      department_one = insert(:department, world: world, city: city)
      department_two = insert(:department, world: world, city: city)

      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      other_department = insert(:department, world: other_world, city: other_city)

      insert(:lemming, world: world, city: city, department: department_one, status: "active")
      insert(:lemming, world: world, city: city, department: department_one, status: "draft")
      insert(:lemming, world: world, city: city, department: department_two, status: "archived")

      insert(:lemming,
        world: other_world,
        city: other_city,
        department: other_department,
        status: "active"
      )

      assert Lemmings.topology_summary(world) == %{
               lemming_count: 3,
               active_lemming_count: 1
             }
    end

    test "returns zero counts for worlds without lemmings" do
      world = insert(:world)

      assert Lemmings.topology_summary(world) == %{
               lemming_count: 0,
               active_lemming_count: 0
             }
    end
  end
end
