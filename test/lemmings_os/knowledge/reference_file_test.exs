defmodule LemmingsOs.Knowledge.ReferenceFileTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Knowledge.ReferenceFile
  alias LemmingsOs.Repo

  doctest LemmingsOs.Knowledge.ReferenceFile

  describe "changeset/2" do
    test "persists reference file metadata with optional artifact provenance" do
      world = insert(:world)
      artifact = insert(:artifact, world: world, city: nil, department: nil, lemming: nil)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          artifact: artifact,
          kind: "reference_file",
          status: "active"
        )

      reference_file = insert(:knowledge_reference_file, knowledge_item: knowledge_item)

      assert reference_file.knowledge_item_id == knowledge_item.id
      assert reference_file.reference_file_type == "quote_template"

      reloaded =
        reference_file
        |> Repo.reload!()
        |> Repo.preload(knowledge_item: :artifact)

      assert reloaded.knowledge_item.artifact_id == artifact.id

      reloaded_item = Repo.preload(knowledge_item, :reference_file)
      assert reloaded_item.reference_file.id == reference_file.id
    end

    test "accepts valid reference file metadata with flexible type" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "reference_file",
          status: "active"
        )

      changeset =
        ReferenceFile.changeset(%ReferenceFile{}, %{
          knowledge_item_id: knowledge_item.id,
          reference_ref: "kref:default_quote_template",
          reference_file_type: "customer_specific_quote_template",
          original_filename: "quote-template.md",
          content_type: "text/markdown",
          size_bytes: 2048,
          checksum: String.duplicate("a", 64),
          storage_ref: "knowledge://local/reference_files/template.md"
        })

      assert changeset.valid?
    end

    test "rejects empty or oversized type and invalid descriptor refs" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "reference_file",
          status: "active"
        )

      changeset =
        ReferenceFile.changeset(%ReferenceFile{}, %{
          knowledge_item_id: knowledge_item.id,
          reference_ref: "../unsafe ref",
          reference_file_type: String.duplicate("a", 101),
          original_filename: "quote-template.md",
          content_type: "text/markdown",
          size_bytes: 2048,
          storage_ref: "knowledge://local/reference_files/template.md"
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).reference_ref
      assert ".invalid_value" in errors_on(changeset).reference_file_type
    end

    test "rejects invalid file metadata" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "reference_file",
          status: "active"
        )

      changeset =
        ReferenceFile.changeset(%ReferenceFile{}, %{
          knowledge_item_id: knowledge_item.id,
          reference_ref: "kref:invalid_metadata",
          reference_file_type: "style",
          original_filename: "",
          content_type: "",
          size_bytes: 0,
          storage_ref: ""
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).size_bytes
      assert "is required" in errors_on(changeset).original_filename
      assert "is required" in errors_on(changeset).content_type
      assert "is required" in errors_on(changeset).storage_ref
    end
  end
end
