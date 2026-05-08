defmodule LemmingsOs.Knowledge.SourceFileChunkTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Knowledge.SourceFileChunk

  describe "changeset/2" do
    test "accepts valid chunk attributes" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "source_file",
          status: "ready"
        )

      source_file =
        insert(:knowledge_source_file, knowledge_item: knowledge_item, indexing_status: "ready")

      changeset =
        SourceFileChunk.changeset(%SourceFileChunk{}, %{
          knowledge_item_id: knowledge_item.id,
          knowledge_source_file_id: source_file.id,
          chunk_index: 0,
          chunk_ref: "chunk-ref-1",
          content: "Chunk content",
          content_hash: String.duplicate("b", 64),
          token_count: 3,
          char_count: 13,
          metadata: %{"section" => "intro"}
        })

      assert changeset.valid?
    end

    test "rejects negative counters and empty content" do
      world = insert(:world)

      knowledge_item =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          kind: "source_file",
          status: "ready"
        )

      source_file =
        insert(:knowledge_source_file, knowledge_item: knowledge_item, indexing_status: "ready")

      changeset =
        SourceFileChunk.changeset(%SourceFileChunk{}, %{
          knowledge_item_id: knowledge_item.id,
          knowledge_source_file_id: source_file.id,
          chunk_index: -1,
          chunk_ref: "chunk-ref-1",
          content: "",
          content_hash: String.duplicate("b", 64),
          token_count: -1,
          char_count: 0
        })

      refute changeset.valid?
      assert ".invalid_value" in errors_on(changeset).chunk_index
      assert ".invalid_value" in errors_on(changeset).token_count
      assert ".invalid_value" in errors_on(changeset).char_count
      assert "is required" in errors_on(changeset).content
    end
  end
end
