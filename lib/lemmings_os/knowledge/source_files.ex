defmodule LemmingsOs.Knowledge.SourceFiles do
  @moduledoc false

  import Ecto.Query, warn: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.Shared
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileChunk
  alias LemmingsOs.Knowledge.SourceFileStorageService
  alias LemmingsOs.Lemmings.Lemming
  alias Pgvector.Ecto.Vector
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  alias __MODULE__.ChunkingService
  alias __MODULE__.EmbeddingService
  alias __MODULE__.ExtractionService
  alias __MODULE__.Workers.SourceFilesIndexingWorker

  @default_top_k 5
  @max_top_k 20
  @default_read_max_chars 4_000
  @max_read_max_chars 8_000

  @spec create_source_file(World.t() | City.t() | Department.t() | Lemming.t(), map()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), source_file: SourceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_source_file(scope, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         {:ok, knowledge_item_attrs, source_file_attrs} <-
           source_file_create_attrs(attrs, scope_data) do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :knowledge_item,
          KnowledgeItem.changeset(%KnowledgeItem{}, knowledge_item_attrs)
        )
        |> Ecto.Multi.insert(:source_file, fn %{knowledge_item: knowledge_item} ->
          SourceFile.changeset(
            %SourceFile{},
            Map.put(source_file_attrs, :knowledge_item_id, knowledge_item.id)
          )
        end)
        |> Oban.insert(:index_job, fn %{source_file: source_file} ->
          SourceFilesIndexingWorker.new(%{"source_file_id" => source_file.id})
        end)

      case Repo.transaction(multi) do
        {:ok, %{knowledge_item: knowledge_item, source_file: source_file}} ->
          {:ok, %{knowledge_item: knowledge_item, source_file: source_file}}

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  def create_source_file(_scope, _attrs), do: {:error, :invalid_attrs}

  @spec create_source_file_upload(
          World.t() | City.t() | Department.t() | Lemming.t(),
          map(),
          String.t()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), source_file: SourceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_source_file_upload(scope, attrs, source_path)
      when is_map(attrs) and is_binary(source_path) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         filename when is_binary(filename) <- fetch(attrs, :original_filename),
         {:ok, storage_id} <- Ecto.UUID.cast(Ecto.UUID.generate()),
         {:ok, stored} <-
           SourceFileStorageService.put(scope_data.world_id, storage_id, source_path, filename) do
      attrs =
        attrs
        |> Map.put(:storage_ref, stored.storage_ref)
        |> Map.put(:size_bytes, stored.size_bytes)
        |> Map.put(:checksum, stored.checksum)

      create_source_file(scope, attrs)
    else
      {:error, reason}
      when reason in [:invalid_source_path, :source_not_found, :file_too_large] ->
        {:error, :invalid_attrs}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :invalid_attrs}
    end
  end

  def create_source_file_upload(_scope, _attrs, _source_path), do: {:error, :invalid_attrs}

  @spec list_source_files(World.t() | City.t() | Department.t() | Lemming.t(), keyword()) ::
          [SourceFile.t()]
  def list_source_files(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        status = Keyword.get(opts, :status)

        SourceFile
        |> join(:inner, [source_file], knowledge_item in KnowledgeItem,
          on: knowledge_item.id == source_file.knowledge_item_id
        )
        |> where(
          [_source_file, knowledge_item],
          knowledge_item.world_id == ^scope_data.world_id
        )
        |> maybe_scope_eq(:city_id, scope_data.city_id)
        |> maybe_scope_eq(:department_id, scope_data.department_id)
        |> maybe_scope_eq(:lemming_id, scope_data.lemming_id)
        |> maybe_filter_source_file_status(status)
        |> order_by([source_file, _knowledge_item],
          desc: source_file.inserted_at,
          desc: source_file.id
        )
        |> Repo.all()
        |> Repo.preload(:knowledge_item)

      {:error, _reason} ->
        []
    end
  end

  @spec archive_source_file(World.t() | City.t() | Department.t() | Lemming.t(), SourceFile.t()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), source_file: SourceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def archive_source_file(scope, %SourceFile{} = source_file) do
    with {:ok, scope_data} <- scope_data(scope),
         %SourceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} <-
           Repo.preload(source_file, :knowledge_item),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      set_source_file_status(source_file, :archived)
    else
      {:error, _reason} = error -> error
      _other -> {:error, :scope_mismatch}
    end
  end

  @spec retry_source_file_indexing(
          World.t() | City.t() | Department.t() | Lemming.t(),
          SourceFile.t()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), source_file: SourceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def retry_source_file_indexing(scope, %SourceFile{} = source_file) do
    with {:ok, scope_data} <- scope_data(scope),
         %SourceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} = source_file <-
           Repo.preload(source_file, :knowledge_item),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.delete_all(
          :delete_chunks,
          from(chunk in SourceFileChunk, where: chunk.knowledge_source_file_id == ^source_file.id)
        )
        |> Ecto.Multi.update(
          :knowledge_item,
          KnowledgeItem.changeset(knowledge_item, %{status: "pending_index"})
        )
        |> Ecto.Multi.update(
          :source_file,
          SourceFile.changeset(source_file, %{
            extraction_status: "pending",
            indexing_status: "pending",
            failure_reason: nil,
            extracted_at: nil,
            indexed_at: nil
          })
        )
        |> Oban.insert(:index_job, fn %{source_file: refreshed_source_file} ->
          SourceFilesIndexingWorker.new(%{"source_file_id" => refreshed_source_file.id})
        end)

      case Repo.transaction(multi) do
        {:ok, %{knowledge_item: updated_knowledge_item, source_file: updated_source_file}} ->
          {:ok, %{knowledge_item: updated_knowledge_item, source_file: updated_source_file}}

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :scope_mismatch}
    end
  end

  @spec run_source_file_indexing(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def run_source_file_indexing(source_file_id) when is_binary(source_file_id) do
    case Repo.get(SourceFile, source_file_id) do
      nil ->
        {:error, :not_found}

      %SourceFile{indexing_status: "archived"} ->
        :ok

      %SourceFile{} = source_file ->
        _ = set_source_file_status(source_file, :extracting)
        continue_indexing_after_extraction(source_file)
    end
  end

  def run_source_file_indexing(_source_file_id), do: {:error, :not_found}

  @spec list_ready_source_files(World.t() | City.t() | Department.t() | Lemming.t()) ::
          [SourceFile.t()]
  def list_ready_source_files(scope) do
    list_source_files(scope, status: "ready")
  end

  @spec update_source_file_metadata(
          World.t() | City.t() | Department.t() | Lemming.t(),
          SourceFile.t(),
          map()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), source_file: SourceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def update_source_file_metadata(scope, %SourceFile{} = source_file, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         %SourceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} = source_file <-
           Repo.preload(source_file, :knowledge_item),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      knowledge_attrs =
        attrs
        |> Map.take([:title, :tags])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      source_file_attrs =
        attrs
        |> Map.take([:source_file_type, :metadata])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      multi =
        Ecto.Multi.new()
        |> maybe_update_knowledge_item(knowledge_item, knowledge_attrs)
        |> maybe_update_source_file(source_file, source_file_attrs)

      case Repo.transaction(multi) do
        {:ok, %{source_file: updated_source_file, knowledge_item: updated_knowledge_item}} ->
          {:ok, %{knowledge_item: updated_knowledge_item, source_file: updated_source_file}}

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :scope_mismatch}
    end
  end

  def update_source_file_metadata(_scope, _source_file, _attrs), do: {:error, :invalid_attrs}

  @spec search_source_file_chunks(
          World.t() | City.t() | Department.t() | Lemming.t(),
          [number()],
          keyword()
        ) ::
          [map()]
  def search_source_file_chunks(scope, query_embedding, opts \\ [])

  def search_source_file_chunks(scope, query_embedding, opts)
      when is_list(query_embedding) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_query_embedding(query_embedding) do
      top_k = top_k_value(opts)
      snippet_length = snippet_length_value(opts)
      query_text = normalize_query_text(Keyword.get(opts, :query_text))

      source_file_chunk_search_query(scope_data, query_embedding, opts, top_k)
      |> Repo.all()
      |> map_source_file_chunk_search_results(query_text, snippet_length)
    else
      _error -> []
    end
  end

  def search_source_file_chunks(_scope, _query_embedding, _opts), do: []

  @spec read_source_file_chunk(
          World.t() | City.t() | Department.t() | Lemming.t(),
          String.t(),
          keyword()
        ) ::
          {:ok, map()} | {:error, :invalid_scope | :scope_mismatch | :not_found}
  def read_source_file_chunk(scope, chunk_ref, opts \\ [])

  def read_source_file_chunk(scope, chunk_ref, opts)
      when is_binary(chunk_ref) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      max_chars = read_max_chars_value(opts)

      SourceFileChunk
      |> join(:inner, [chunk], source_file in SourceFile,
        on: source_file.id == chunk.knowledge_source_file_id
      )
      |> join(:inner, [_chunk, _source_file], knowledge_item in KnowledgeItem,
        on: knowledge_item.id == _chunk.knowledge_item_id
      )
      |> filter_ready_source_file_chunks()
      |> filter_scope_relevance_joined(scope_data)
      |> where([chunk, _source_file, _knowledge_item], chunk.chunk_ref == ^chunk_ref)
      |> select([chunk, source_file, knowledge_item], %{
        chunk_ref: chunk.chunk_ref,
        chunk_index: chunk.chunk_index,
        knowledge_item_id: knowledge_item.id,
        title: knowledge_item.title,
        source_file_type: source_file.source_file_type,
        content:
          fragment(
            "left(?, ?)",
            chunk.content,
            ^max_chars
          ),
        content_length: fragment("char_length(?)", chunk.content),
        metadata: chunk.metadata
      })
      |> Repo.one()
      |> read_source_file_chunk_result(max_chars)
    end
  end

  def read_source_file_chunk(_scope, _chunk_ref, _opts), do: {:error, :not_found}

  defp source_file_chunk_search_query(scope_data, query_embedding, opts, top_k) do
    SourceFileChunk
    |> join(:inner, [chunk], source_file in SourceFile,
      on: source_file.id == chunk.knowledge_source_file_id
    )
    |> join(:inner, [_chunk, _source_file], knowledge_item in KnowledgeItem,
      on: knowledge_item.id == _chunk.knowledge_item_id
    )
    |> filter_ready_source_file_chunks()
    |> filter_scope_relevance_joined(scope_data)
    |> maybe_filter_source_file_type(Keyword.get(opts, :source_file_type))
    |> maybe_filter_source_file_tags(Keyword.get(opts, :tags))
    |> select_source_file_chunk_search_fields(query_embedding)
    |> order_by([chunk, _source_file, _knowledge_item],
      desc: fragment("? <=> ?", chunk.embedding, type(^query_embedding, Vector))
    )
    |> limit(^top_k)
  end

  defp filter_ready_source_file_chunks(query) do
    from([_chunk, source_file, knowledge_item] in query,
      where:
        source_file.indexing_status == "ready" and
          source_file.extraction_status == "ready" and
          knowledge_item.status == "ready"
    )
  end

  defp select_source_file_chunk_search_fields(query, query_embedding) do
    from([chunk, source_file, knowledge_item] in query,
      select: %{
        knowledge_item_id: knowledge_item.id,
        knowledge_source_file_id: source_file.id,
        chunk_id: chunk.id,
        chunk_ref: chunk.chunk_ref,
        chunk_index: chunk.chunk_index,
        title: knowledge_item.title,
        source_file_type: source_file.source_file_type,
        tags: knowledge_item.tags,
        score: fragment("1 - (? <=> ?)", chunk.embedding, type(^query_embedding, Vector)),
        content: chunk.content,
        scope: %{
          type:
            fragment(
              "case when ? is not null then 'lemming' when ? is not null then 'department' when ? is not null then 'city' else 'world' end",
              knowledge_item.lemming_id,
              knowledge_item.department_id,
              knowledge_item.city_id
            )
        }
      }
    )
  end

  defp map_source_file_chunk_search_results(rows, query_text, snippet_length) do
    Enum.map(rows, fn row ->
      content = fetch(row, :content) || ""

      row
      |> Map.put(:snippet, snippet_from_content(content, query_text, snippet_length))
      |> Map.delete(:content)
    end)
  end

  defp read_max_chars_value(opts) do
    case Keyword.get(opts, :max_chars, @default_read_max_chars) do
      value when is_integer(value) and value > 0 -> min(value, @max_read_max_chars)
      _value -> @default_read_max_chars
    end
  end

  defp read_source_file_chunk_result(nil, _max_chars), do: {:error, :not_found}

  defp read_source_file_chunk_result(row, max_chars) when is_map(row) do
    content_length = fetch(row, :content_length) || 0

    {:ok,
     %{
       chunk_ref: fetch(row, :chunk_ref),
       chunk_index: fetch(row, :chunk_index),
       knowledge_item_id: fetch(row, :knowledge_item_id),
       title: fetch(row, :title),
       source_file_type: fetch(row, :source_file_type),
       content: fetch(row, :content) || "",
       metadata: fetch(row, :metadata) || %{},
       truncated: is_integer(content_length) and content_length > max_chars
     }}
  end

  defp maybe_filter_source_file_status(query, status) when is_binary(status) do
    if status in KnowledgeItem.statuses() or status == "pending" do
      {knowledge_status, source_file_status} = source_file_status_filter_pair(status)

      from([source_file, knowledge_item] in query,
        where:
          knowledge_item.status == ^knowledge_status and
            source_file.indexing_status == ^source_file_status
      )
    else
      query
    end
  end

  defp maybe_filter_source_file_status(query, _status), do: query

  defp source_file_status_filter_pair("pending"), do: {"pending_index", "pending"}
  defp source_file_status_filter_pair("pending_index"), do: {"pending_index", "pending"}
  defp source_file_status_filter_pair(status), do: {status, status}

  defp maybe_scope_eq(query, field, nil) when field in [:city_id, :department_id, :lemming_id] do
    from([_source_file, knowledge_item] in query, where: is_nil(field(knowledge_item, ^field)))
  end

  defp maybe_scope_eq(query, field, value)
       when field in [:city_id, :department_id, :lemming_id] and is_binary(value) do
    from([_source_file, knowledge_item] in query, where: field(knowledge_item, ^field) == ^value)
  end

  defp maybe_update_knowledge_item(multi, knowledge_item, attrs) when map_size(attrs) == 0 do
    Ecto.Multi.put(multi, :knowledge_item, knowledge_item)
  end

  defp maybe_update_knowledge_item(multi, knowledge_item, attrs) do
    Ecto.Multi.update(
      multi,
      :knowledge_item,
      KnowledgeItem.user_update_changeset(knowledge_item, attrs)
    )
  end

  defp maybe_update_source_file(multi, source_file, attrs) when map_size(attrs) == 0 do
    Ecto.Multi.put(multi, :source_file, source_file)
  end

  defp maybe_update_source_file(multi, source_file, attrs) do
    Ecto.Multi.update(multi, :source_file, SourceFile.changeset(source_file, attrs))
  end

  defp set_source_file_status(%SourceFile{} = source_file, :extracting) do
    set_source_file_status(source_file, "extracting", "extracting")
  end

  defp set_source_file_status(%SourceFile{} = source_file, :chunking) do
    set_source_file_status(source_file, "chunking", "chunking")
  end

  defp set_source_file_status(%SourceFile{} = source_file, :embedding) do
    set_source_file_status(source_file, "embedding", "embedding")
  end

  defp set_source_file_status(%SourceFile{} = source_file, :ready) do
    set_source_file_status(source_file, "ready", "ready")
  end

  defp set_source_file_status(%SourceFile{} = source_file, :archived) do
    set_source_file_status(source_file, "archived", "archived")
  end

  defp set_source_file_status(%SourceFile{} = source_file, :needs_ocr, failure_reason) do
    set_source_file_status(source_file, "needs_ocr", "needs_ocr", failure_reason)
  end

  defp set_source_file_status(%SourceFile{} = source_file, :failed, failure_reason) do
    set_source_file_status(source_file, "failed", "failed", failure_reason)
  end

  defp continue_indexing_after_extraction(%SourceFile{} = source_file) do
    case ExtractionService.extract(source_file) do
      {:ok, result} ->
        _ = set_source_file_status(source_file, :chunking)

        replace_source_file_chunks(source_file, result.text, result.method)
        |> handle_chunking_result(source_file)

      {:error, reason} ->
        handle_extraction_error(source_file, reason)
    end
  end

  defp handle_chunking_result({:ok, rows}, %SourceFile{} = source_file) do
    _ = set_source_file_status(source_file, :embedding)

    rows
    |> embed_chunk_vectors()
    |> handle_embedding_result(source_file)
  end

  defp handle_chunking_result({:error, :empty_chunks}, %SourceFile{} = source_file) do
    _ = set_source_file_status(source_file, :failed, "extraction_empty")
    :ok
  end

  defp handle_chunking_result({:error, _reason}, %SourceFile{} = source_file) do
    _ = set_source_file_status(source_file, :failed, "chunking_failed")
    :ok
  end

  defp handle_embedding_result(:ok, %SourceFile{} = source_file) do
    _ = set_source_file_status(source_file, :ready)
    :ok
  end

  defp handle_embedding_result({:error, failure_reason}, %SourceFile{} = source_file)
       when is_binary(failure_reason) do
    _ = set_source_file_status(source_file, :failed, failure_reason)
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, :needs_ocr) do
    _ = set_source_file_status(source_file, :needs_ocr, "needs_ocr")
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, :source_not_found) do
    _ = set_source_file_status(source_file, :failed, "source_not_found")
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, :timeout) do
    _ = set_source_file_status(source_file, :failed, "extraction_timeout")
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, :unsupported) do
    _ = set_source_file_status(source_file, :failed, "extraction_unsupported")
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, :empty) do
    _ = set_source_file_status(source_file, :failed, "extraction_empty")
    :ok
  end

  defp handle_extraction_error(%SourceFile{} = source_file, _reason) do
    _ = set_source_file_status(source_file, :failed, "extraction_failed")
    :ok
  end

  defp replace_source_file_chunks(%SourceFile{} = source_file, text, extraction_method)
       when is_binary(text) and is_binary(extraction_method) do
    chunks =
      ChunkingService.chunk_text(source_file.id, text, %{
        extraction_method: extraction_method
      })

    if chunks == [] do
      {:error, :empty_chunks}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(chunks, fn chunk ->
          %{
            id: Ecto.UUID.generate(),
            knowledge_item_id: source_file.knowledge_item_id,
            knowledge_source_file_id: source_file.id,
            chunk_index: chunk.chunk_index,
            chunk_ref: chunk.chunk_ref,
            content: chunk.content,
            content_hash: chunk.content_hash,
            token_count: chunk.token_count,
            char_count: chunk.char_count,
            metadata: chunk.metadata,
            inserted_at: now,
            updated_at: now
          }
        end)

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.delete_all(
          :delete_chunks,
          from(chunk in SourceFileChunk, where: chunk.knowledge_source_file_id == ^source_file.id)
        )
        |> Ecto.Multi.insert_all(:insert_chunks, SourceFileChunk, rows)

      case Repo.transaction(multi) do
        {:ok, %{insert_chunks: {count, _inserted_rows}}} when count > 0 -> {:ok, rows}
        {:ok, %{insert_chunks: {0, _inserted_rows}}} -> {:error, :empty_chunks}
        {:error, _step, _reason, _changes_so_far} -> {:error, :chunking_failed}
      end
    end
  end

  defp embed_chunk_vectors([]), do: {:error, "embedding_invalid_response"}

  defp embed_chunk_vectors(rows) when is_list(rows) do
    texts = Enum.map(rows, &Map.get(&1, :content, ""))

    case EmbeddingService.embed_texts(texts) do
      {:ok, vectors} when length(vectors) == length(rows) ->
        persist_chunk_embeddings(rows, vectors)

      {:ok, _vectors} ->
        {:error, "embedding_invalid_response"}

      {:error, reason} ->
        {:error, embedding_failure_reason(reason)}
    end
  end

  defp embedding_failure_reason(:provider_not_configured), do: "embedding_provider_not_configured"
  defp embedding_failure_reason(:provider_timeout), do: "embedding_timeout"
  defp embedding_failure_reason(:provider_network_error), do: "embedding_network_error"
  defp embedding_failure_reason(:provider_http_error), do: "embedding_provider_error"
  defp embedding_failure_reason(:provider_invalid_dimension), do: "embedding_invalid_dimension"
  defp embedding_failure_reason(:provider_invalid_input), do: "embedding_invalid_input"
  defp embedding_failure_reason(:provider_invalid_response), do: "embedding_invalid_response"

  defp persist_chunk_embeddings(rows, vectors) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows
    |> Enum.zip(vectors)
    |> Enum.reduce_while(:ok, fn {row, vector}, :ok ->
      id = Map.fetch!(row, :id)

      case Repo.query(
             "update knowledge_source_file_chunks set embedding = $1, updated_at = $2 where id = $3::uuid",
             [vector, now, Ecto.UUID.dump!(id)]
           ) do
        {:ok, _result} -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, "embedding_invalid_response"}}
      end
    end)
  end

  defp set_source_file_status(
         %SourceFile{} = source_file,
         knowledge_status,
         source_file_status,
         failure_reason \\ nil
       ) do
    source_file = Repo.preload(source_file, :knowledge_item)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    source_file_attrs =
      %{
        extraction_status: extraction_status_for(source_file_status),
        indexing_status: source_file_status,
        failure_reason: failure_reason
      }
      |> maybe_put(:extracted_at, extracted_at_for(source_file_status, now))
      |> maybe_put(:indexed_at, indexed_at_for(source_file_status, now))

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :knowledge_item,
        KnowledgeItem.changeset(source_file.knowledge_item, %{status: knowledge_status})
      )
      |> Ecto.Multi.update(:source_file, SourceFile.changeset(source_file, source_file_attrs))

    case Repo.transaction(multi) do
      {:ok, %{knowledge_item: updated_knowledge_item, source_file: updated_source_file}} ->
        {:ok, %{knowledge_item: updated_knowledge_item, source_file: updated_source_file}}

      {:error, _step, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp extraction_status_for(status) when status in ["ready", "chunking", "embedding"],
    do: "ready"

  defp extraction_status_for("extracting"), do: "extracting"
  defp extraction_status_for("needs_ocr"), do: "needs_ocr"
  defp extraction_status_for("failed"), do: "failed"
  defp extraction_status_for("archived"), do: "ready"

  defp extracted_at_for(status, now)
       when status in ["chunking", "embedding", "ready", "archived"],
       do: now

  defp extracted_at_for(_status, _now), do: nil

  defp indexed_at_for(status, now) when status in ["ready", "archived"], do: now
  defp indexed_at_for(_status, _now), do: nil

  defp source_file_create_attrs(attrs, scope_data) do
    filename = fetch(attrs, :original_filename)
    content_type = fetch(attrs, :content_type)
    storage_ref = fetch(attrs, :storage_ref)
    source_file_type = fetch(attrs, :source_file_type)
    size_bytes = fetch(attrs, :size_bytes)
    checksum = fetch(attrs, :checksum)
    metadata = fetch(attrs, :metadata) || %{}
    title = fetch(attrs, :title) || filename || "Source file"
    content = fetch(attrs, :content) || "Source file registered for indexing."
    tags = fetch(attrs, :tags) || []

    with :ok <-
           validate_source_file_create_inputs(
             filename,
             content_type,
             storage_ref,
             source_file_type,
             size_bytes
           ),
         :ok <- validate_source_file_storage_ref(storage_ref, scope_data.world_id),
         {:ok, artifact_id} <- normalize_optional_artifact_id(fetch(attrs, :artifact_id)) do
      knowledge_item_attrs =
        %{
          world_id: scope_data.world_id,
          city_id: scope_data.city_id,
          department_id: scope_data.department_id,
          lemming_id: scope_data.lemming_id,
          kind: "source_file",
          source: "user",
          status: "pending_index",
          title: title,
          content: content,
          tags: tags
        }
        |> maybe_put(:artifact_id, artifact_id)

      source_file_attrs = %{
        source_file_type: source_file_type,
        original_filename: filename,
        content_type: content_type,
        size_bytes: size_bytes,
        checksum: checksum,
        storage_ref: storage_ref,
        extraction_status: "pending",
        indexing_status: "pending",
        metadata: metadata
      }

      {:ok, knowledge_item_attrs, source_file_attrs}
    end
  end

  defp validate_source_file_create_inputs(
         filename,
         content_type,
         storage_ref,
         source_file_type,
         size_bytes
       )
       when is_binary(filename) and is_binary(content_type) and is_binary(storage_ref) and
              is_binary(source_file_type) and is_integer(size_bytes) and size_bytes > 0,
       do: :ok

  defp validate_source_file_create_inputs(
         _filename,
         _content_type,
         _storage_ref,
         _source_file_type,
         _size_bytes
       ),
       do: {:error, :invalid_attrs}

  defp validate_source_file_storage_ref(storage_ref, world_id) do
    case SourceFileStorageService.storage_ref_world_id(storage_ref) do
      {:ok, ^world_id} -> :ok
      {:ok, _other_world_id} -> {:error, :scope_mismatch}
      {:error, _reason} -> {:error, :invalid_attrs}
    end
  end

  defp normalize_optional_artifact_id(nil), do: {:ok, nil}

  defp normalize_optional_artifact_id(artifact_id) when is_binary(artifact_id) do
    case Ecto.UUID.cast(artifact_id) do
      {:ok, _uuid} -> {:ok, artifact_id}
      :error -> {:error, :invalid_attrs}
    end
  end

  defp normalize_optional_artifact_id(_artifact_id), do: {:error, :invalid_attrs}

  defp validate_exact_scope(%KnowledgeItem{} = knowledge_item, scope_data),
    do: Shared.validate_exact_scope(knowledge_item, scope_data)

  defp validate_requested_scope(attrs, scope_data),
    do: Shared.validate_requested_scope(attrs, scope_data)

  defp maybe_put(map, key, value), do: Shared.maybe_put(map, key, value)

  defp scope_data(scope), do: Shared.scope_data(scope)

  defp filter_scope_relevance_joined(
         query,
         %{
           world_id: world_id,
           city_id: nil,
           department_id: nil,
           lemming_id: nil
         }
       ) do
    from([_chunk, _source_file, knowledge_item] in query,
      where:
        knowledge_item.world_id == ^world_id and is_nil(knowledge_item.city_id) and
          is_nil(knowledge_item.department_id) and is_nil(knowledge_item.lemming_id)
    )
  end

  defp filter_scope_relevance_joined(
         query,
         %{world_id: world_id, city_id: city_id, department_id: nil, lemming_id: nil}
       )
       when is_binary(city_id) do
    from([_chunk, _source_file, knowledge_item] in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          is_nil(knowledge_item.department_id) and is_nil(knowledge_item.lemming_id)
    )
  end

  defp filter_scope_relevance_joined(
         query,
         %{world_id: world_id, city_id: city_id, department_id: department_id, lemming_id: nil}
       )
       when is_binary(city_id) and is_binary(department_id) do
    from([_chunk, _source_file, knowledge_item] in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id)
    )
  end

  defp filter_scope_relevance_joined(
         query,
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         }
       )
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) do
    from([_chunk, _source_file, knowledge_item] in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id) and
          (is_nil(knowledge_item.lemming_id) or knowledge_item.lemming_id == ^lemming_id)
    )
  end

  defp maybe_filter_source_file_type(query, type) when is_binary(type) do
    if type in SourceFile.types() do
      from([_chunk, source_file, _knowledge_item] in query,
        where: source_file.source_file_type == ^type
      )
    else
      query
    end
  end

  defp maybe_filter_source_file_type(query, _type), do: query

  defp maybe_filter_source_file_tags(query, tags) when is_list(tags) do
    normalized =
      tags
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if normalized == [] do
      query
    else
      from([_chunk, _source_file, knowledge_item] in query,
        where: fragment("? @> ?", knowledge_item.tags, type(^normalized, {:array, :string}))
      )
    end
  end

  defp maybe_filter_source_file_tags(query, _tags), do: query

  defp validate_query_embedding(values) when is_list(values) and values != [] do
    if Enum.all?(values, &(is_float(&1) or is_integer(&1))) do
      :ok
    else
      {:error, :invalid_embedding}
    end
  end

  defp validate_query_embedding(_values), do: {:error, :invalid_embedding}

  defp top_k_value(opts) do
    case Keyword.get(opts, :top_k, @default_top_k) do
      value when is_integer(value) and value > 0 -> min(value, @max_top_k)
      _value -> @default_top_k
    end
  end

  defp snippet_length_value(opts) do
    case Keyword.get(opts, :snippet_length, 240) do
      value when is_integer(value) and value > 0 -> min(value, 1_000)
      _value -> 240
    end
  end

  defp normalize_query_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_query_text(_value), do: nil

  defp snippet_from_content(content, query_text, snippet_length) when is_binary(content) do
    normalized = String.replace(content, ~r/[\n\r\t]+/u, " ")
    default_snippet = String.slice(normalized, 0, snippet_length)

    case query_text do
      nil ->
        default_snippet

      query ->
        query
        |> query_candidates()
        |> Enum.find_value(&excerpt_around_query(normalized, &1, snippet_length))
        |> case do
          nil -> default_snippet
          excerpt -> excerpt
        end
    end
  end

  defp snippet_from_content(_content, _query_text, _snippet_length), do: ""

  defp query_candidates(query) when is_binary(query) do
    trimmed = String.trim(query)
    tokens = query_tokens(trimmed)
    token_count = length(tokens)
    max_phrase_size = min(token_count, 4)

    phrase_candidates =
      if max_phrase_size > 0 do
        Enum.reduce(max_phrase_size..1//-1, [], fn phrase_size, acc ->
          acc ++ phrase_candidates_for_size(tokens, token_count, phrase_size)
        end)
      else
        []
      end

    [trimmed | phrase_candidates]
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> Enum.uniq()
  end

  defp query_tokens(value) when is_binary(value) do
    String.split(value, ~r/[^\p{L}\p{N}\-]+/u, trim: true)
  end

  defp phrase_candidates_for_size(_tokens, token_count, phrase_size)
       when token_count <= 0 or phrase_size <= 0 or token_count < phrase_size,
       do: []

  defp phrase_candidates_for_size(tokens, token_count, phrase_size) do
    0..(token_count - phrase_size)
    |> Enum.map(fn start ->
      tokens
      |> Enum.slice(start, phrase_size)
      |> Enum.join(" ")
    end)
  end

  defp excerpt_around_query(content, query, snippet_length) do
    trailing = max(snippet_length - String.length(query) - 80, 0)

    regex =
      Regex.compile!(
        "(.{0,80}#{Regex.escape(query)}.{0,#{trailing}})",
        "iu"
      )

    case Regex.run(regex, content, capture: :all_but_first) do
      [excerpt | _rest] -> String.slice(excerpt, 0, snippet_length)
      _other -> nil
    end
  end

  defp fetch(map, key), do: Shared.fetch(map, key)
end
