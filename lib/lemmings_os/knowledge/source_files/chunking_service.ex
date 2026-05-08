defmodule LemmingsOs.Knowledge.SourceFiles.ChunkingService do
  @moduledoc """
  Deterministic chunking service for extracted source-file text.

  This service is the boundary that converts one extracted document body into
  ordered retrieval chunks for `knowledge_source_file_chunks`.

  Responsibilities:
  - apply the MVP chunking defaults/config (`chunk_size`, `overlap`, `max_chunks`)
  - preserve source order through `chunk_index`
  - generate stable deterministic `chunk_ref` values
  - skip empty/whitespace-only chunks
  - provide metadata needed by downstream indexing stages
  """

  alias LemmingsOs.Helpers

  @default_chunk_size 1_200
  @default_overlap 200
  @default_max_chunks 500

  @type chunk :: %{
          required(:chunk_index) => non_neg_integer(),
          required(:chunk_ref) => String.t(),
          required(:content) => String.t(),
          required(:content_hash) => String.t(),
          required(:char_count) => pos_integer(),
          required(:token_count) => non_neg_integer(),
          required(:metadata) => map()
        }

  @doc """
  Splits extracted text into ordered retrieval chunks.

  Chunks are deterministic for the same `source_file_id`, `text`, and config.

  ## Examples

      iex> source_file_id = "11111111-1111-4111-8111-111111111111"
      iex> text = String.duplicate("a", 1500)
      iex> chunks = LemmingsOs.Knowledge.SourceFiles.ChunkingService.chunk_text(source_file_id, text)
      iex> Enum.map(chunks, & &1.chunk_index)
      [0, 1]
      iex> Enum.at(chunks, 0).char_count
      1200
      iex> Enum.at(chunks, 1).char_count
      500
      iex> Enum.all?(chunks, &String.starts_with?(&1.chunk_ref, "ksf:\#{source_file_id}:"))
      true

      iex> LemmingsOs.Knowledge.SourceFiles.ChunkingService.chunk_text(source_file_id, "   \\n\\n  ")
      []
  """
  @spec chunk_text(Ecto.UUID.t(), String.t(), map()) :: [chunk()]
  def chunk_text(source_file_id, text, metadata \\ %{})

  def chunk_text(source_file_id, text, metadata)
      when is_binary(source_file_id) and is_binary(text) and is_map(metadata) do
    chunk_size = config(:chunk_size, @default_chunk_size)
    overlap = config(:overlap, @default_overlap)
    max_chunks = config(:max_chunks, @default_max_chunks)

    text
    |> do_chunk(chunk_size, overlap, max_chunks, 0, [])
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {content, index} ->
      trimmed = String.trim(content)
      hash = sha256(trimmed)

      %{
        chunk_index: index,
        chunk_ref: "ksf:#{source_file_id}:#{index}:#{String.slice(hash, 0, 16)}",
        content: trimmed,
        content_hash: hash,
        char_count: String.length(trimmed),
        token_count: token_count(trimmed),
        metadata: metadata
      }
    end)
  end

  def chunk_text(_source_file_id, _text, _metadata), do: []

  defp do_chunk(_text, _chunk_size, _overlap, max_chunks, count, acc) when count >= max_chunks,
    do: acc

  defp do_chunk(text, chunk_size, overlap, max_chunks, count, acc) do
    text_length = String.length(text)

    if text_length <= 0 do
      acc
    else
      segment = String.slice(text, 0, chunk_size) |> String.trim()

      acc =
        if segment == "" do
          acc
        else
          [segment | acc]
        end

      if text_length <= chunk_size do
        acc
      else
        next_offset = max(chunk_size - overlap, 1)
        remainder = String.slice(text, next_offset, text_length - next_offset)
        do_chunk(remainder, chunk_size, overlap, max_chunks, count + 1, acc)
      end
    end
  end

  defp config(key, default) do
    Application.get_env(:lemmings_os, :knowledge_chunking, [])
    |> Keyword.get(key, default)
    |> parse_config!(key)
  end

  defp parse_config!(value, :overlap) do
    case Helpers.parse_non_negative_integer(value) do
      {:ok, parsed} -> parsed
      :error -> raise ArgumentError, "invalid knowledge_chunking overlap: #{inspect(value)}"
    end
  end

  defp parse_config!(value, key) when key in [:chunk_size, :max_chunks] do
    case Helpers.parse_positive_integer(value) do
      {:ok, parsed} -> parsed
      :error -> raise ArgumentError, "invalid knowledge_chunking #{key}: #{inspect(value)}"
    end
  end

  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp token_count(content) do
    content
    |> String.split(~r/\s+/u, trim: true)
    |> length()
  end
end
