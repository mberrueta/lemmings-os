defmodule LemmingsOs.Knowledge.SourceFiles.IndexingWorker do
  @moduledoc """
  Oban worker placeholder for the source-file indexing lifecycle.

  This worker is intentionally narrow. It owns only source-file indexing work and
  uses the dedicated `knowledge_indexing` queue. Extraction, chunking, embedding,
  and lifecycle transitions will be implemented in the source-file task sequence.
  """

  use Oban.Worker, queue: :knowledge_indexing, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_file_id" => source_file_id}})
      when is_binary(source_file_id) do
    # TODO: Implement source-file indexing lifecycle: extract, chunk, embed, mark ready,
    # mark failed, or mark needs_ocr. This intentionally raises until Task 04/05 wiring lands.
    raise "source-file indexing worker is not implemented yet"
  end
end
