defmodule LemmingsOs.Knowledge.KnowledgeItemTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Knowledge.KnowledgeItem

  describe "changeset/2 kind and status rules" do
    test "accepts memory with active status" do
      world = insert(:world)

      changeset =
        KnowledgeItem.changeset(%KnowledgeItem{}, %{
          world_id: world.id,
          kind: "memory",
          title: "Memory title",
          content: "Memory content",
          source: "user",
          status: "active",
          tags: []
        })

      assert changeset.valid?
    end

    test "rejects memory with non-memory status" do
      world = insert(:world)

      changeset =
        KnowledgeItem.changeset(%KnowledgeItem{}, %{
          world_id: world.id,
          kind: "memory",
          title: "Memory title",
          content: "Memory content",
          source: "user",
          status: "ready",
          tags: []
        })

      refute changeset.valid?
      assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :status)
    end

    test "accepts source_file with ready status and optional artifact provenance" do
      world = insert(:world)

      changeset =
        KnowledgeItem.changeset(%KnowledgeItem{}, %{
          world_id: world.id,
          kind: "source_file",
          title: "Source file title",
          content: "Source file summary placeholder",
          source: "user",
          status: "ready",
          artifact_id: Ecto.UUID.generate(),
          tags: []
        })

      assert changeset.valid?
    end

    test "accepts source_file with needs_ocr status" do
      world = insert(:world)

      changeset =
        KnowledgeItem.changeset(%KnowledgeItem{}, %{
          world_id: world.id,
          kind: "source_file",
          title: "Scanned source file",
          content: "Source file summary placeholder",
          source: "user",
          status: "needs_ocr",
          tags: []
        })

      assert changeset.valid?
    end

    test "rejects memory rows with artifact provenance" do
      world = insert(:world)

      changeset =
        KnowledgeItem.changeset(%KnowledgeItem{}, %{
          world_id: world.id,
          kind: "memory",
          title: "Memory title",
          content: "Memory content",
          source: "user",
          status: "active",
          artifact_id: Ecto.UUID.generate(),
          tags: []
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).artifact_id
    end
  end
end
