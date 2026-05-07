defmodule LemmingsOs.Knowledge.SourceFiles.Workers.SourceFilesIndexingWorkerTest do
  use LemmingsOs.DataCase, async: true

  alias Ecto.Changeset
  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFiles.Workers.SourceFilesIndexingWorker, as: IndexingWorker
  alias LemmingsOs.Repo

  defmodule StubExecutor do
    def run(_command, _args, _timeout_ms), do: {:ok, %{stdout: "Extracted text", exit_status: 0}}
  end

  setup do
    old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])

    Application.put_env(
      :lemmings_os,
      :knowledge_tools_runner,
      Keyword.merge(old_runner,
        executor_module: StubExecutor,
        capabilities: %{
          markitdown_extract_file: "markitdown",
          pdftotext_extract_file: "pdftotext",
          trafilatura_extract_url: "trafilatura"
        }
      )
    )

    on_exit(fn -> Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner) end)
    :ok
  end

  describe "new/2" do
    test "builds jobs for the dedicated knowledge indexing queue" do
      changeset = IndexingWorker.new(%{"source_file_id" => Ecto.UUID.generate()})

      assert Changeset.get_field(changeset, :queue) == "knowledge_indexing"
      assert Changeset.get_field(changeset, :max_attempts) == 3
    end
  end

  describe "perform/1" do
    test "returns :discard when source file is not found" do
      job = %Oban.Job{args: %{"source_file_id" => Ecto.UUID.generate()}}

      assert :discard = IndexingWorker.perform(job)
    end

    test "runs lifecycle transition flow and returns :ok" do
      world = insert(:world)

      {:ok, %{source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "policy.pdf",
          content_type: "application/pdf",
          size_bytes: 2_048,
          storage_ref:
            "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/policy.pdf"
        })

      job = %Oban.Job{args: %{"source_file_id" => source_file.id}}

      assert :ok = IndexingWorker.perform(job)

      updated_source_file = Repo.get!(SourceFile, source_file.id)
      assert updated_source_file.indexing_status == "failed"
      assert updated_source_file.extraction_status == "failed"
      assert updated_source_file.failure_reason in ["source_not_found", "extraction_failed"]
    end
  end
end
