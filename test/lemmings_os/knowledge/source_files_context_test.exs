defmodule LemmingsOs.Knowledge.SourceFilesContextTest do
  use LemmingsOs.DataCase, async: false
  import Ecto.Query

  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileChunk
  alias LemmingsOs.Knowledge.SourceFileStorageService
  alias LemmingsOs.Repo

  defmodule StubExtractorExecutor do
    def run(_command, _args, _timeout_ms) do
      output =
        Application.get_env(:lemmings_os, :knowledge_chunking_test_output, "default output")

      {:ok, %{stdout: output, exit_status: 0}}
    end
  end

  defmodule WrongDimensionEmbedder do
    def embed_texts(texts, _opts) when is_list(texts) do
      {:ok, Enum.map(texts, fn _text -> [0.1, 0.2, 0.3] end)}
    end
  end

  describe "create_source_file/2" do
    test "creates source-file records and enqueues a knowledge indexing job" do
      world = insert(:world)

      assert {:ok, %{knowledge_item: knowledge_item, source_file: source_file}} =
               Knowledge.create_source_file(world, %{
                 source_file_type: "company_knowledge",
                 original_filename: "policy.pdf",
                 content_type: "application/pdf",
                 size_bytes: 2_048,
                 checksum: String.duplicate("a", 64),
                 storage_ref:
                   "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/policy.pdf",
                 metadata: %{"origin" => "upload"}
               })

      assert knowledge_item.kind == "source_file"
      assert knowledge_item.status == "pending_index"
      assert source_file.knowledge_item_id == knowledge_item.id
      assert source_file.indexing_status == "pending"
      assert source_file.extraction_status == "pending"

      assert Repo.exists?(
               from(job in Oban.Job,
                 where:
                   job.queue == "knowledge_indexing" and
                     fragment("?->>'source_file_id' = ?", job.args, ^source_file.id)
               )
             )
    end
  end

  describe "archive_source_file/2" do
    test "archives source-file and knowledge item statuses" do
      world = insert(:world)

      {:ok, %{knowledge_item: knowledge_item, source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "archive.pdf",
          content_type: "application/pdf",
          size_bytes: 2_048,
          storage_ref:
            "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/archive.pdf"
        })

      knowledge_item
      |> KnowledgeItem.changeset(%{status: "ready"})
      |> Repo.update!()

      source_file =
        source_file
        |> SourceFile.changeset(%{extraction_status: "ready", indexing_status: "ready"})
        |> Repo.update!()
        |> Repo.preload(:knowledge_item)

      assert {:ok, %{knowledge_item: knowledge_item, source_file: archived_source_file}} =
               Knowledge.archive_source_file(world, source_file)

      assert knowledge_item.status == "archived"
      assert archived_source_file.indexing_status == "archived"
    end
  end

  describe "retry_source_file_indexing/2" do
    test "clears stale chunks, resets status, and enqueues a new indexing job" do
      world = insert(:world)

      {:ok, %{knowledge_item: knowledge_item, source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "retry.pdf",
          content_type: "application/pdf",
          size_bytes: 2_048,
          storage_ref:
            "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/retry.pdf"
        })

      knowledge_item
      |> KnowledgeItem.changeset(%{status: "failed"})
      |> Repo.update!()

      source_file =
        source_file
        |> SourceFile.changeset(%{extraction_status: "failed", indexing_status: "failed"})
        |> Repo.update!()
        |> Repo.preload(:knowledge_item)

      _chunk =
        insert(:knowledge_source_file_chunk,
          knowledge_item: source_file.knowledge_item,
          knowledge_source_file: source_file
        )

      assert {:ok, %{knowledge_item: knowledge_item, source_file: retried_source_file}} =
               Knowledge.retry_source_file_indexing(world, source_file)

      assert knowledge_item.status == "pending_index"
      assert retried_source_file.indexing_status == "pending"
      assert retried_source_file.extraction_status == "pending"
      assert retried_source_file.failure_reason == nil

      refute Repo.exists?(
               from(chunk in SourceFileChunk,
                 where: chunk.knowledge_source_file_id == ^source_file.id
               )
             )

      assert Repo.exists?(
               from(job in Oban.Job,
                 where:
                   job.queue == "knowledge_indexing" and
                     fragment("?->>'source_file_id' = ?", job.args, ^source_file.id)
               )
             )
    end
  end

  describe "list_ready_source_files/1" do
    test "returns only ready source files for scope" do
      world = insert(:world)

      {:ok, %{source_file: ready_source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "ready.pdf",
          content_type: "application/pdf",
          size_bytes: 1_000,
          storage_ref:
            "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/ready.pdf"
        })

      {:ok, %{source_file: failed_source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "failed.pdf",
          content_type: "application/pdf",
          size_bytes: 1_000,
          storage_ref:
            "local://knowledge_source_files/#{world.id}/#{Ecto.UUID.generate()}/failed.pdf"
        })

      _ = Knowledge.run_source_file_indexing(failed_source_file.id)

      ready_knowledge_item = Repo.get!(KnowledgeItem, ready_source_file.knowledge_item_id)
      ready_source_file = Repo.get!(SourceFile, ready_source_file.id)

      # Directly transition one row to ready for retrieval-candidate filtering.
      ready_knowledge_item
      |> KnowledgeItem.changeset(%{status: "ready"})
      |> Repo.update!()

      ready_source_file
      |> SourceFile.changeset(%{extraction_status: "ready", indexing_status: "ready"})
      |> Repo.update!()

      [result] = Knowledge.list_ready_source_files(world)
      assert result.id == ready_source_file.id
    end
  end

  describe "chunk replacement during reindex" do
    test "replaces stale chunks with a deterministic new set" do
      world = insert(:world)
      old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)

      root_path =
        Path.join(
          System.tmp_dir!(),
          "lemmings_knowledge_chunking_reindex_#{System.unique_integer([:positive])}"
        )

      Application.put_env(:lemmings_os, :knowledge_source_file_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 10 * 1024 * 1024
      )

      Application.put_env(
        :lemmings_os,
        :knowledge_tools_runner,
        Keyword.merge(old_runner,
          executor_module: StubExtractorExecutor,
          capabilities: %{
            markitdown_extract_file: "markitdown",
            pdftotext_extract_file: "pdftotext",
            trafilatura_extract_url: "trafilatura"
          }
        )
      )

      on_exit(fn ->
        Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
        end

        Application.delete_env(:lemmings_os, :knowledge_chunking_test_output)
        File.rm_rf(root_path)
      end)

      source_path = Path.join(root_path, "source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "input")

      {:ok, stored} =
        SourceFileStorageService.put(world.id, Ecto.UUID.generate(), source_path, "source.md")

      {:ok, %{source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "source.md",
          content_type: "text/markdown",
          size_bytes: stored.size_bytes,
          checksum: stored.checksum,
          storage_ref: stored.storage_ref
        })

      Application.put_env(
        :lemmings_os,
        :knowledge_chunking_test_output,
        String.duplicate("alpha ", 400)
      )

      assert :ok = Knowledge.run_source_file_indexing(source_file.id)

      first_chunks =
        SourceFileChunk
        |> where([chunk], chunk.knowledge_source_file_id == ^source_file.id)
        |> order_by([chunk], asc: chunk.chunk_index)
        |> Repo.all()

      assert first_chunks != []

      assert {:ok, _retry_result} =
               Knowledge.retry_source_file_indexing(
                 world,
                 Repo.preload(source_file, :knowledge_item)
               )

      Application.put_env(
        :lemmings_os,
        :knowledge_chunking_test_output,
        String.duplicate("beta ", 180)
      )

      assert :ok = Knowledge.run_source_file_indexing(source_file.id)

      second_chunks =
        SourceFileChunk
        |> where([chunk], chunk.knowledge_source_file_id == ^source_file.id)
        |> order_by([chunk], asc: chunk.chunk_index)
        |> Repo.all()

      assert second_chunks != []

      assert length(second_chunks) != length(first_chunks) or
               Enum.map(second_chunks, & &1.chunk_ref) != Enum.map(first_chunks, & &1.chunk_ref)

      refute Enum.any?(second_chunks, fn chunk -> chunk.content =~ "alpha " end)
    end
  end

  describe "embedding pipeline" do
    test "marks source file as ready when fake embeddings are persisted" do
      world = insert(:world)
      old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)
      old_embeddings = Application.get_env(:lemmings_os, :knowledge_embeddings, [])

      root_path =
        Path.join(
          System.tmp_dir!(),
          "lemmings_knowledge_embedding_ready_#{System.unique_integer([:positive])}"
        )

      Application.put_env(:lemmings_os, :knowledge_source_file_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 10 * 1024 * 1024
      )

      Application.put_env(
        :lemmings_os,
        :knowledge_tools_runner,
        Keyword.merge(old_runner,
          executor_module: StubExtractorExecutor,
          capabilities: %{
            markitdown_extract_file: "markitdown",
            pdftotext_extract_file: "pdftotext",
            trafilatura_extract_url: "trafilatura"
          }
        )
      )

      Application.put_env(:lemmings_os, :knowledge_embeddings, provider: :fake, dimensions: 1536)

      on_exit(fn ->
        Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner)
        Application.put_env(:lemmings_os, :knowledge_embeddings, old_embeddings)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
        end

        Application.delete_env(:lemmings_os, :knowledge_chunking_test_output)
        File.rm_rf(root_path)
      end)

      source_path = Path.join(root_path, "source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "input")

      {:ok, stored} =
        SourceFileStorageService.put(world.id, Ecto.UUID.generate(), source_path, "source.md")

      {:ok, %{source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "source.md",
          content_type: "text/markdown",
          size_bytes: stored.size_bytes,
          checksum: stored.checksum,
          storage_ref: stored.storage_ref
        })

      Application.put_env(
        :lemmings_os,
        :knowledge_chunking_test_output,
        String.duplicate("ok ", 600)
      )

      assert :ok = Knowledge.run_source_file_indexing(source_file.id)

      updated_source_file = Repo.get!(SourceFile, source_file.id)
      updated_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)

      assert updated_source_file.indexing_status == "ready"
      assert updated_source_file.failure_reason == nil
      assert updated_item.status == "ready"
    end

    test "fails safely when provider returns wrong dimensions" do
      world = insert(:world)
      old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)
      old_embeddings = Application.get_env(:lemmings_os, :knowledge_embeddings, [])

      root_path =
        Path.join(
          System.tmp_dir!(),
          "lemmings_knowledge_embedding_bad_dims_#{System.unique_integer([:positive])}"
        )

      Application.put_env(:lemmings_os, :knowledge_source_file_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 10 * 1024 * 1024
      )

      Application.put_env(
        :lemmings_os,
        :knowledge_tools_runner,
        Keyword.merge(old_runner,
          executor_module: StubExtractorExecutor,
          capabilities: %{
            markitdown_extract_file: "markitdown",
            pdftotext_extract_file: "pdftotext",
            trafilatura_extract_url: "trafilatura"
          }
        )
      )

      Application.put_env(:lemmings_os, :knowledge_embeddings,
        provider: :fake,
        module: WrongDimensionEmbedder,
        dimensions: 1536
      )

      on_exit(fn ->
        Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner)
        Application.put_env(:lemmings_os, :knowledge_embeddings, old_embeddings)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
        end

        Application.delete_env(:lemmings_os, :knowledge_chunking_test_output)
        File.rm_rf(root_path)
      end)

      source_path = Path.join(root_path, "source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "input")

      {:ok, stored} =
        SourceFileStorageService.put(world.id, Ecto.UUID.generate(), source_path, "source.md")

      {:ok, %{source_file: source_file}} =
        Knowledge.create_source_file(world, %{
          source_file_type: "company_knowledge",
          original_filename: "source.md",
          content_type: "text/markdown",
          size_bytes: stored.size_bytes,
          checksum: stored.checksum,
          storage_ref: stored.storage_ref
        })

      Application.put_env(
        :lemmings_os,
        :knowledge_chunking_test_output,
        String.duplicate("ok ", 600)
      )

      assert :ok = Knowledge.run_source_file_indexing(source_file.id)

      updated_source_file = Repo.get!(SourceFile, source_file.id)
      updated_item = Repo.get!(KnowledgeItem, source_file.knowledge_item_id)

      assert updated_source_file.indexing_status == "failed"
      assert updated_source_file.failure_reason == "embedding_invalid_dimension"
      assert updated_item.status == "failed"
    end
  end
end
