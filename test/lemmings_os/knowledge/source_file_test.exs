defmodule LemmingsOs.Knowledge.SourceFileTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Knowledge.SourceFile

  describe "changeset/2" do
    test "accepts valid source file metadata" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "source_file",
          status: "pending_index"
        )

      changeset =
        SourceFile.changeset(%SourceFile{}, %{
          knowledge_item_id: knowledge_item.id,
          source_file_type: "company_knowledge",
          original_filename: "policy.pdf",
          content_type: "application/pdf",
          size_bytes: 2048,
          checksum: String.duplicate("a", 64),
          storage_ref: "knowledge://local/source_files/file.pdf",
          extraction_status: "pending",
          indexing_status: "pending",
          metadata: %{"origin" => "upload"}
        })

      assert changeset.valid?
    end

    test "rejects unsupported type and invalid size" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "source_file",
          status: "pending_index"
        )

      changeset =
        SourceFile.changeset(%SourceFile{}, %{
          knowledge_item_id: knowledge_item.id,
          source_file_type: "unsupported_type",
          original_filename: "policy.pdf",
          content_type: "application/pdf",
          size_bytes: 0,
          storage_ref: "knowledge://local/source_files/file.pdf",
          extraction_status: "pending",
          indexing_status: "pending"
        })

      refute changeset.valid?
      assert {".invalid_choice", _details} = Keyword.fetch!(changeset.errors, :source_file_type)
      assert ".invalid_value" in errors_on(changeset).size_bytes
    end
  end
end
