defmodule LemmingsOs.Artifacts.ArtifactTest do
  use LemmingsOs.DataCase, async: true

  import LemmingsOs.Factory

  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Repo

  doctest Artifact

  describe "changeset/2" do
    test "validates required fields" do
      changeset = Artifact.changeset(%Artifact{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert ".required" in errors.world_id
      assert ".required" in errors.filename
      assert ".required" in errors.type
      assert ".required" in errors.content_type
      assert ".required" in errors.storage_ref
      assert ".required" in errors.size_bytes
      assert ".required" in errors.checksum
      assert ".required" in errors.status
      refute Map.has_key?(errors, :metadata)
    end

    test "accepts allowed type and status values" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          city_id: Ecto.UUID.generate(),
          department_id: Ecto.UUID.generate(),
          lemming_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/city/department/lemming/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{"source" => "manual_promotion"}
        })

      assert changeset.valid?
    end

    test "rejects unknown type values" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "docx",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).type
    end

    test "rejects unknown status values" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "pending",
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).status
    end

    test "defaults metadata to empty map when omitted" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :metadata) == %{}
    end

    test "rejects metadata that is not a map" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: "bad"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).metadata
    end

    test "rejects metadata keys outside source contract" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{"prompt" => "leak"}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).metadata
    end

    test "rejects unsupported metadata source value" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{"source" => "tool_output"}
        })

      refute changeset.valid?
      assert ".invalid_choice" in errors_on(changeset).metadata
    end

    test "rejects invalid scope shape when lemming_id is set without department_id" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          city_id: Ecto.UUID.generate(),
          lemming_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/city/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{}
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).city_id
    end

    test "accepts world, city, department, and lemming scope shape" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          city_id: Ecto.UUID.generate(),
          department_id: Ecto.UUID.generate(),
          lemming_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/city/department/lemming/artifact.md",
          size_bytes: 128,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{"source" => "manual_promotion"}
        })

      assert changeset.valid?
    end
  end

  describe "database constraints" do
    test "enforces associated world existence" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          world_id: Ecto.UUID.generate(),
          filename: "artifact.md",
          type: "markdown",
          content_type: "text/markdown",
          storage_ref: "local://artifacts/world/artifact.md",
          size_bytes: 10,
          checksum: String.duplicate("a", 64),
          status: "ready",
          metadata: %{}
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).world
    end

    test "SCH-05: nilifies provenance references when instance is deleted" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      instance =
        insert(:lemming_instance,
          world: world,
          city: city,
          department: department,
          lemming: lemming
        )

      tool_execution =
        insert(:tool_execution,
          world: world,
          lemming_instance: instance
        )

      artifact =
        insert(:artifact,
          world: world,
          city: city,
          department: department,
          lemming: lemming,
          lemming_instance: instance,
          created_by_tool_execution: tool_execution
        )

      Repo.delete!(instance)

      persisted = Repo.get!(Artifact, artifact.id)
      assert persisted.id == artifact.id
      assert persisted.lemming_instance_id == nil
      assert persisted.created_by_tool_execution_id == nil
    end
  end
end
