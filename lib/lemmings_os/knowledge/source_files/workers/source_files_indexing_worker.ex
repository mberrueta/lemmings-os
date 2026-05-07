defmodule LemmingsOs.Knowledge.SourceFiles.Workers.SourceFilesIndexingWorker do
  @moduledoc """
  Oban worker placeholder for the source-file indexing lifecycle.

  This worker is intentionally narrow. It owns only source-file indexing work and
  uses the dedicated `knowledge_indexing` queue. Extraction, chunking, embedding,
  and lifecycle transitions will be implemented in the source-file task sequence.
  """

  use Oban.Worker, queue: :knowledge_indexing, max_attempts: 3
  alias LemmingsOs.Knowledge

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"source_file_id" => source_file_id}})
      when is_binary(source_file_id) do
    case Knowledge.run_source_file_indexing(source_file_id) do
      :ok -> :ok
      {:error, :not_found} -> :discard
    end
  end
end
