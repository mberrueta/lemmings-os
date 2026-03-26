defmodule LemmingsOs.DepartmentsTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.DeleteDeniedError
  alias LemmingsOs.Departments.Department

  doctest LemmingsOs.Departments

  describe "list_departments/2" do
    test "returns departments for the explicit world/city scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      other_world = insert(:world)
      other_world_city = insert(:city, world: other_world)

      department_a = insert(:department, world: world, city: city, status: "active")
      department_b = insert(:department, world: world, city: city, status: "disabled")
      insert(:department, world: world, city: other_city)
      insert(:department, world: other_world, city: other_world_city)

      departments = Departments.list_departments(city)

      assert Enum.sort(Enum.map(departments, & &1.id)) ==
               Enum.sort([department_a.id, department_b.id])
    end

    test "supports status, ids, slug, and preload filters" do
      world = insert(:world)
      city = insert(:city, world: world)
      active_department = insert(:department, world: world, city: city, status: "active")
      disabled_department = insert(:department, world: world, city: city, status: "disabled")

      assert [filtered_department] =
               Departments.list_departments(city,
                 status: "disabled",
                 ids: [disabled_department.id],
                 slug: disabled_department.slug,
                 preload: [:city, :world]
               )

      assert filtered_department.id == disabled_department.id
      assert Ecto.assoc_loaded?(filtered_department.city)
      assert Ecto.assoc_loaded?(filtered_department.world)
      refute filtered_department.id == active_department.id
    end
  end

  describe "get APIs" do
    test "get_department/2 returns the department by id" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert %Department{} = fetched_department = Departments.get_department(department.id)
      assert fetched_department.id == department.id
    end

    test "get_department/2 returns nil when the id is missing" do
      _world = insert(:world)
      _city = insert(:city)

      assert Departments.get_department(Ecto.UUID.generate()) == nil
    end

    test "get_department/2 supports explicit preloads" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      fetched_department =
        Departments.get_department(department.id, preload: [:world, :city])

      assert %Department{} = fetched_department

      assert Ecto.assoc_loaded?(fetched_department.world)
      assert Ecto.assoc_loaded?(fetched_department.city)
      refute Ecto.assoc_loaded?(fetched_department.city.world)
      assert fetched_department.city.world_id == world.id
    end

    test "fetch/get by slug are city-scoped" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, slug: "support")
      insert(:department, world: world, city: other_city, slug: "support")

      fetched_department =
        Departments.get_department_by_slug(city, department.slug)

      assert %Department{} = fetched_department

      assert fetched_department.id == department.id
    end
  end

  describe "create_department/2" do
    test "creates a department scoped to the given world and city" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert {:ok, department} =
               Departments.create_department(city, %{
                 slug: "support",
                 name: "Support",
                 status: "active",
                 tags: ["Customer Support", "high_priority"]
               })

      assert department.world_id == world.id
      assert department.city_id == city.id
      assert department.tags == ["customer-support", "high-priority"]
    end
  end

  describe "update_department/2 and status transitions" do
    test "updates persisted department attributes" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, status: "active")

      assert {:ok, updated_department} =
               Departments.update_department(department, %{
                 name: "Renamed Department",
                 notes: "Updated notes"
               })

      assert updated_department.name == "Renamed Department"
      assert updated_department.notes == "Updated notes"
    end

    test "set_department_status/2 drives lifecycle transitions" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, status: "disabled")

      assert {:ok, draining_department} =
               Departments.set_department_status(department, "draining")

      assert draining_department.status == "draining"

      assert {:ok, disabled_department} =
               Departments.set_department_status(draining_department, "disabled")

      assert disabled_department.status == "disabled"

      assert {:ok, active_again_department} =
               Departments.set_department_status(disabled_department, "active")

      assert active_again_department.status == "active"
    end
  end

  describe "delete_department/1" do
    test "rejects deleting departments that are not disabled" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, status: "active")

      assert {:error, %DeleteDeniedError{} = error} = Departments.delete_department(department)
      assert error.department_id == department.id
      assert error.reason == :not_disabled
    end

    test "rejects deleting disabled departments when safe removal cannot be proven" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, status: "disabled")

      assert {:error, %DeleteDeniedError{} = error} = Departments.delete_department(department)
      assert error.department_id == department.id
      assert error.reason == :safety_indeterminate
      assert Repo.get(Department, department.id)
    end
  end

  describe "topology_summary/1" do
    test "returns aggregate department counts for the world without city-by-city enumeration" do
      world = insert(:world)
      other_world = insert(:world)
      city_one = insert(:city, world: world)
      city_two = insert(:city, world: world)
      other_city = insert(:city, world: other_world)

      insert(:department, world: world, city: city_one, status: "active")
      insert(:department, world: world, city: city_one, status: "draining")
      insert(:department, world: world, city: city_two, status: "disabled")
      insert(:department, world: other_world, city: other_city, status: "active")

      assert Departments.topology_summary(world) == %{
               department_count: 3,
               active_department_count: 1
             }
    end

    test "returns zero counts for worlds without departments" do
      world = insert(:world)

      assert Departments.topology_summary(world) == %{
               department_count: 0,
               active_department_count: 0
             }
    end
  end
end
