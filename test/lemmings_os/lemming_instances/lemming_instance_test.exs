defmodule LemmingsOs.LemmingInstances.LemmingInstanceTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Repo

  test "create_changeset/2 accepts valid attrs with nullable temporal markers" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department)

    attrs = %{
      lemming_id: lemming.id,
      world_id: world.id,
      city_id: city.id,
      department_id: department.id,
      status: "created",
      config_snapshot: %{"instructions" => "Be concise."},
      started_at: nil,
      stopped_at: nil,
      last_activity_at: nil
    }

    changeset = LemmingInstance.create_changeset(%LemmingInstance{}, attrs)

    assert changeset.valid?
  end

  test "create_changeset/2 validates required fields and status inclusion" do
    changeset =
      LemmingInstance.create_changeset(%LemmingInstance{}, %{
        status: "bogus",
        config_snapshot: nil
      })

    refute changeset.valid?

    errors = errors_on(changeset)

    assert errors.lemming_id == [".required"]
    assert errors.world_id == [".required"]
    assert errors.city_id == [".required"]
    assert errors.department_id == [".required"]
    assert ".required" in errors.config_snapshot
    assert errors.config_snapshot == [".required"]

    assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :status)
  end

  test "create_changeset/2 enforces foreign-key constraints" do
    attrs = %{
      lemming_id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      city_id: Ecto.UUID.generate(),
      department_id: Ecto.UUID.generate(),
      config_snapshot: %{}
    }

    assert {:error, changeset} =
             %LemmingInstance{}
             |> LemmingInstance.create_changeset(attrs)
             |> Repo.insert()

    refute changeset.valid?
    assert changeset.constraints != []
  end

  test "status_changeset/2 validates status inclusion" do
    changeset = LemmingInstance.status_changeset(%LemmingInstance{}, %{status: "bogus"})

    refute changeset.valid?
    assert ".invalid_choice" in errors_on(changeset).status
  end
end
