defmodule LemmingsOs.LemmingInstances.ToolExecutionTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Repo

  test "create_changeset/2 accepts valid attrs with nullable result fields" do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")
    {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Initial request")

    changeset =
      ToolExecution.create_changeset(%ToolExecution{}, %{
        lemming_instance_id: instance.id,
        world_id: world.id,
        tool_name: "fs.read_text_file",
        status: "running",
        args: %{"path" => "notes.txt"},
        result: nil,
        error: nil,
        summary: nil,
        preview: nil,
        started_at: nil,
        completed_at: nil,
        duration_ms: nil
      })

    assert changeset.valid?
  end

  test "create_changeset/2 validates required fields, status inclusion, and map types" do
    changeset =
      ToolExecution.create_changeset(%ToolExecution{}, %{
        tool_name: "fs.read_text_file",
        status: "bogus",
        args: "nope",
        result: "invalid",
        error: "invalid",
        duration_ms: -1
      })

    refute changeset.valid?

    errors = errors_on(changeset)

    assert errors.lemming_instance_id == [".required"]
    assert errors.world_id == [".required"]
    assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :status)
    assert "is invalid" in errors.args
    assert "is invalid" in errors.result
    assert "is invalid" in errors.error
    assert ".invalid_value" in errors.duration_ms
  end

  test "create_changeset/2 enforces foreign-key constraints" do
    attrs = %{
      lemming_instance_id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      tool_name: "fs.read_text_file",
      status: "running",
      args: %{"path" => "notes.txt"}
    }

    assert {:error, changeset} =
             %ToolExecution{}
             |> ToolExecution.create_changeset(attrs)
             |> Repo.insert()

    refute changeset.valid?
    assert changeset.constraints != []
  end

  test "update_changeset/2 accepts valid persisted result updates" do
    changeset =
      ToolExecution.update_changeset(%ToolExecution{}, %{
        status: "ok",
        result: %{"content" => "done"},
        duration_ms: 12
      })

    assert changeset.valid?
  end

  test "update_changeset/2 validates status inclusion and map types" do
    changeset =
      ToolExecution.update_changeset(%ToolExecution{}, %{
        status: "bogus",
        result: "invalid",
        error: "invalid"
      })

    refute changeset.valid?
    assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :status)
    assert "is invalid" in errors_on(changeset).result
    assert "is invalid" in errors_on(changeset).error
  end
end
