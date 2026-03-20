defmodule LemmingsOs.DepartmentsTest do
  use LemmingsOs.DataCase, async: false

  alias Ecto.NoResultsError
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.DeleteDeniedError
  alias LemmingsOs.Departments.Department

  doctest LemmingsOs.Departments

  describe "list_departments/3" do
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

      departments = Departments.list_departments(world, city)

      assert Enum.sort(Enum.map(departments, & &1.id)) ==
               Enum.sort([department_a.id, department_b.id])
    end

    test "supports status, ids, slug, and preload filters" do
      world = insert(:world)
      city = insert(:city, world: world)
      active_department = insert(:department, world: world, city: city, status: "active")
      disabled_department = insert(:department, world: world, city: city, status: "disabled")

      assert [filtered_department] =
               Departments.list_departments(world.id, city.id,
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

  describe "fetch/get APIs" do
    test "fetch_department/3 returns the scoped department" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, fetched_department} = Departments.fetch_department(world, city, department.id)
      assert fetched_department.id == department.id
    end

    test "fetch_department/3 returns not_found outside the scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      department = insert(:department, world: other_world, city: other_city)

      assert {:error, :not_found} = Departments.fetch_department(world, city, department.id)
    end

    test "get_department!/3 raises when missing" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert_raise NoResultsError, fn ->
        Departments.get_department!(world, city, Ecto.UUID.generate())
      end
    end

    test "fetch/get by slug are city-scoped" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, slug: "support")
      insert(:department, world: world, city: other_city, slug: "support")

      assert {:ok, fetched_department} =
               Departments.fetch_department_by_slug(city.id, department.slug)

      assert fetched_department.id == department.id
      assert Departments.get_department_by_slug!(city, department.slug).id == department.id
    end
  end

  describe "create_department/3" do
    test "creates a department scoped to the given world and city" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert {:ok, department} =
               Departments.create_department(world, city, %{
                 slug: "support",
                 name: "Support",
                 status: "active",
                 tags: ["Customer Support", "high_priority"]
               })

      assert department.world_id == world.id
      assert department.city_id == city.id
      assert department.tags == ["customer-support", "high-priority"]
    end

    test "rejects creating a department when the city does not belong to the world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: other_world)

      assert {:error, :city_not_in_world} =
               Departments.create_department(world.id, city.id, %{
                 slug: "support",
                 name: "Support",
                 status: "active"
               })
    end
  end

  describe "update_department/2 and lifecycle wrappers" do
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

    test "set_department_status/2 and wrappers delegate through the status path" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city, status: "disabled")

      assert {:ok, active_department} = Departments.activate_department(department)
      assert active_department.status == "active"

      assert {:ok, draining_department} = Departments.drain_department(active_department)
      assert draining_department.status == "draining"

      assert {:ok, disabled_department} = Departments.disable_department(draining_department)
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
end
