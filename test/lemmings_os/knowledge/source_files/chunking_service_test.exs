defmodule LemmingsOs.Knowledge.SourceFiles.ChunkingServiceTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Knowledge.SourceFiles.ChunkingService

  test "applies ordering, overlap, and stable refs" do
    source_file_id = Ecto.UUID.generate()
    text = String.duplicate("a", 1_500)

    chunks = ChunkingService.chunk_text(source_file_id, text, %{kind: "test"})

    assert length(chunks) == 2
    assert Enum.map(chunks, & &1.chunk_index) == [0, 1]
    assert Enum.at(chunks, 0).char_count == 1_200
    assert Enum.at(chunks, 1).char_count == 500
    assert String.ends_with?(Enum.at(chunks, 0).content, String.duplicate("a", 200))
    assert String.starts_with?(Enum.at(chunks, 1).content, String.duplicate("a", 200))

    chunks_again = ChunkingService.chunk_text(source_file_id, text, %{kind: "test"})
    assert Enum.map(chunks, & &1.chunk_ref) == Enum.map(chunks_again, & &1.chunk_ref)
  end

  test "skips empty chunks and enforces max chunk cap" do
    source_file_id = Ecto.UUID.generate()
    text = String.duplicate("x", 700_000)

    chunks = ChunkingService.chunk_text(source_file_id, text)
    assert length(chunks) == 500
    assert Enum.all?(chunks, &(String.trim(&1.content) != ""))
  end
end
