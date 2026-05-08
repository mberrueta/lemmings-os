defmodule LemmingsOs.Knowledge do
  @moduledoc """
  Knowledge domain boundary for memory CRUD and scope-safe retrieval.

  This phase is memory-only and keeps product-state rules (`kind`, `source`,
  `status`) in context/schema validations.
  """

  import Ecto.Query, warn: false

  require Logger

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Events
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileChunk
  alias LemmingsOs.Knowledge.SourceFileStorageService
  alias LemmingsOs.Knowledge.SourceFiles.ChunkingService
  alias LemmingsOs.Knowledge.SourceFiles.EmbeddingService
  alias LemmingsOs.Knowledge.SourceFiles.ExtractionService
  alias LemmingsOs.Knowledge.SourceFiles.Workers.SourceFilesIndexingWorker
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @default_limit 25
  @max_limit 100
  @default_top_k 5
  @max_top_k 20
  @default_read_max_chars 4_000
  @max_read_max_chars 8_000

  @type scope :: World.t() | City.t() | Department.t() | Lemming.t()

  @type scope_data :: %{
          required(:world_id) => Ecto.UUID.t(),
          required(:city_id) => Ecto.UUID.t() | nil,
          required(:department_id) => Ecto.UUID.t() | nil,
          required(:lemming_id) => Ecto.UUID.t() | nil
        }

  @type creator_metadata :: %{
          optional(:creator_type) => String.t(),
          optional(:creator_id) => String.t(),
          optional(:creator_lemming_id) => Ecto.UUID.t(),
          optional(:creator_lemming_instance_id) => Ecto.UUID.t(),
          optional(:creator_tool_execution_id) => Ecto.UUID.t()
        }

  @type effective_memory_row :: %{
          required(:memory) => KnowledgeItem.t(),
          required(:owner_scope) => String.t(),
          required(:owner_scope_label) => String.t(),
          required(:local?) => boolean(),
          required(:inherited?) => boolean(),
          required(:descendant?) => boolean()
        }

  @type paginated_memories :: %{
          required(:entries) => [effective_memory_row()],
          required(:total_count) => non_neg_integer(),
          required(:limit) => pos_integer(),
          required(:offset) => non_neg_integer()
        }

  @type source_file_chunk_search_result :: %{
          required(:knowledge_item_id) => Ecto.UUID.t(),
          required(:knowledge_source_file_id) => Ecto.UUID.t(),
          required(:chunk_id) => Ecto.UUID.t(),
          required(:chunk_ref) => String.t(),
          required(:chunk_index) => non_neg_integer(),
          required(:title) => String.t(),
          required(:source_file_type) => String.t(),
          required(:tags) => [String.t()],
          required(:score) => float(),
          required(:snippet) => String.t(),
          required(:scope) => %{required(:type) => String.t()}
        }

  @doc """
  Lists memories at the exact requested scope (local-only).

  ## Parameters

  - `scope` - one hierarchy scope struct (`%World{}`, `%City{}`, `%Department{}`, `%Lemming{}`).
  - `opts` - optional filters and pagination controls.

  `opts` supports:
  - `:source` (`"user"` or `"llm"`)
  - `:status` (`"active"`)
  - `:q` or `:query` (text match over title and tags)

  ## Examples

      iex> LemmingsOs.Knowledge.list_memories(%{})
      []
  """
  @spec list_memories(scope(), keyword()) :: [KnowledgeItem.t()]
  def list_memories(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        KnowledgeItem
        |> filter_query(scope_filters(scope_data) ++ [{:kind, "memory"}])
        |> apply_memory_filters(opts)
        |> order_by([knowledge_item], asc: knowledge_item.inserted_at, asc: knowledge_item.id)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Lists effective visible memories with filters and local Ecto pagination.

  ## Parameters

  - `scope` - visibility anchor scope (`%World{}`, `%City{}`, `%Department{}`, `%Lemming{}`).
  - `opts` - optional filters and pagination controls.

  `opts` supports:
  - `:q` (single text query over title and tags)
  - `:source` (`"user"` or `"llm"`)
  - `:status` (`"active"` for current MVP)
  - `:limit` (default `25`, max `100`)
  - `:offset` (default `0`)

  Returns read-model rows with ownership metadata:
  - `:owner_scope` (`"world" | "city" | "department" | "lemming"`)
  - `:local?`, `:inherited?`, `:descendant?`

  ## Examples

      iex> LemmingsOs.Knowledge.list_effective_memories(%{})
      {:error, :invalid_scope}
  """
  @spec list_effective_memories(scope(), keyword()) ::
          {:ok, paginated_memories()} | {:error, :invalid_scope | :scope_mismatch}
  def list_effective_memories(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      limit = limit_value(opts)
      offset = offset_value(opts)

      query =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.kind == "memory")
        |> filter_scope_relevance(scope_data)
        |> apply_memory_filters(opts)

      result =
        query
        |> paginate_query(offset, limit, &to_effective_row(&1, scope_data))

      {:ok,
       %{
         entries: result.entries,
         total_count: result.total_count,
         limit: result.limit,
         offset: result.offset
       }}
    end
  end

  @doc """
  Lists all memories across scopes with filters and local Ecto pagination.

  ## Parameters

  - `opts` - optional filters and pagination controls.

  This read is intentionally unscoped and intended for operator-facing global
  memory inventory surfaces.

  `opts` supports:
  - `:source` (`"user"` or `"llm"`)
  - `:status` (`"active"`)
  - `:q` or `:query` (text match over title and tags)
  - `:limit` (default `25`, max `100`)
  - `:offset` (default `0`)

  ## Examples

      iex> {:ok, page} = LemmingsOs.Knowledge.list_all_memories(limit: 5, offset: 0)
      iex> is_list(page.entries) and is_integer(page.total_count)
      true
  """
  @spec list_all_memories(keyword()) :: {:ok, paginated_memories()}
  def list_all_memories(opts \\ []) when is_list(opts) do
    limit = limit_value(opts)
    offset = offset_value(opts)

    result =
      KnowledgeItem
      |> where([knowledge_item], knowledge_item.kind == "memory")
      |> apply_memory_filters(opts)
      |> paginate_query(offset, limit, &to_unscoped_row/1)

    {:ok,
     %{
       entries: result.entries,
       total_count: result.total_count,
       limit: result.limit,
       offset: result.offset
     }}
  end

  @doc """
  Lists memories filtered by concrete scope identifiers (including descendants
  for broader scopes).

  ## Parameters

  - `scope` - hierarchy scope that determines local and descendant rows.
  - `opts` - optional filters and pagination controls.

  Scope semantics:
  - world: all memories in world
  - city: all memories in city (city + department + lemming owned)
  - department: all memories in department (department + lemming owned)
  - lemming: only lemming-owned memories

  `opts` supports:
  - `:source` (`"user"` or `"llm"`)
  - `:status` (`"active"`)
  - `:q` or `:query` (text match over title and tags)
  - `:limit` (default `25`, max `100`)
  - `:offset` (default `0`)

  ## Examples

      iex> LemmingsOs.Knowledge.list_scope_memories(%{})
      {:error, :invalid_scope}
  """
  @spec list_scope_memories(scope(), keyword()) ::
          {:ok, paginated_memories()} | {:error, :invalid_scope | :scope_mismatch}
  def list_scope_memories(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      limit = limit_value(opts)
      offset = offset_value(opts)

      result =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.kind == "memory")
        |> filter_scope_descendants(scope_data)
        |> apply_memory_filters(opts)
        |> paginate_query(offset, limit, &to_effective_row(&1, scope_data))

      {:ok,
       %{
         entries: result.entries,
         total_count: result.total_count,
         limit: result.limit,
         offset: result.offset
       }}
    end
  end

  @doc """
  Returns one memory visible from the requested scope.

  ## Parameters

  - `scope` - caller scope used for visibility checks.
  - `id` - memory `knowledge_items.id`.
  - `opts` - optional read settings (`:mode`).

  Visibility follows hierarchy inheritance:
  - city sees world + city memories
  - department sees world + city + department + department lemming memories
  - lemming sees world + city + department + own lemming memories

  `opts` supports:
  - `:mode` (`:visible` default, or `:local`)

  ## Examples

      iex> LemmingsOs.Knowledge.get_memory(%{}, Ecto.UUID.generate())
      nil
  """
  @spec get_memory(scope(), Ecto.UUID.t(), keyword()) :: KnowledgeItem.t() | nil
  def get_memory(scope, id, opts \\ [])

  def get_memory(scope, id, opts) when is_binary(id) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :visible)

    with {:ok, scope_data} <- scope_data(scope),
         {:ok, mode} <- normalize_read_mode(mode) do
      base_query =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.id == ^id)
        |> where([knowledge_item], knowledge_item.kind == "memory")

      query =
        case mode do
          :local -> filter_query(base_query, scope_filters(scope_data))
          :visible -> filter_scope_relevance(base_query, scope_data)
        end

      Repo.one(query)
    else
      {:error, _reason} -> nil
    end
  end

  def get_memory(_scope, _id, _opts), do: nil

  @doc """
  Returns one memory by ID without scope visibility filtering.

  ## Parameters

  - `id` - memory `knowledge_items.id`.

  This helper is intended for internal wiring flows that need to infer the
  owning scope before applying visibility checks.

  ## Examples

      iex> LemmingsOs.Knowledge.get_memory_by_id(Ecto.UUID.generate())
      nil
  """
  @spec get_memory_by_id(Ecto.UUID.t()) :: KnowledgeItem.t() | nil
  def get_memory_by_id(id) when is_binary(id) do
    KnowledgeItem
    |> where([knowledge_item], knowledge_item.id == ^id)
    |> where([knowledge_item], knowledge_item.kind == "memory")
    |> Repo.one()
  end

  def get_memory_by_id(_id), do: nil

  @doc """
  Creates one user memory at the exact requested scope.

  ## Parameters

  - `scope` - exact ownership scope for the new memory.
  - `attrs` - user-writable fields (`:title`, `:content`, `:tags`).
  - `opts` - optional creator/runtime metadata.

  Runtime-owned fields are assigned by this context:
  - `kind = "memory"`
  - `source = "user"`
  - `status = "active"`

  Optional creator metadata can be passed via `opts[:creator]`.

  `opts` supports:
  - `:creator` map:
    - `:creator_type`
    - `:creator_id`
    - `:creator_lemming_id`
    - `:creator_lemming_instance_id`
    - `:creator_tool_execution_id`
  - `:source` (validated but currently forced by runtime defaults)
  - `:status` (validated but currently forced by runtime defaults)
  - `:kind` (validated but currently forced by runtime defaults)

  ## Examples

      iex> LemmingsOs.Knowledge.create_memory(%{}, %{})
      {:error, :invalid_scope}
  """
  @spec create_memory(scope(), map(), keyword()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_memory(scope, attrs, opts \\ [])

  def create_memory(scope, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         {:ok, creator_metadata} <- creator_metadata(opts),
         {:ok, source} <- normalize_source(Keyword.get(opts, :source, "user")),
         {:ok, status} <- normalize_status(Keyword.get(opts, :status, "active")),
         {:ok, kind} <- normalize_kind(Keyword.get(opts, :kind, "memory")) do
      attrs =
        attrs
        |> Map.take([:title, :content, :tags])
        |> Map.merge(scope_data)
        |> Map.merge(%{kind: kind, source: source, status: status})
        |> Map.merge(creator_metadata)

      %KnowledgeItem{}
      |> KnowledgeItem.changeset(attrs)
      |> Repo.insert()
      |> maybe_record_memory_event("knowledge.memory.created", scope_data, "Memory created")
    end
  end

  def create_memory(_scope, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc """
  Updates mutable user fields on a memory at exact scope.

  ## Parameters

  - `scope` - exact ownership scope expected for the target memory.
  - `knowledge_item` - memory row (`kind = "memory"`).
  - `attrs` - user-writable updates (`:title`, `:content`, `:tags`).

  Only `title`, `content`, and `tags` are mutable through this API.

  ## Examples

      iex> LemmingsOs.Knowledge.update_memory(%{}, %LemmingsOs.Knowledge.KnowledgeItem{}, %{})
      {:error, :invalid_scope}
  """
  @spec update_memory(scope(), KnowledgeItem.t(), map()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def update_memory(scope, %KnowledgeItem{} = knowledge_item, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      knowledge_item
      |> KnowledgeItem.user_update_changeset(Map.take(attrs, [:title, :content, :tags]))
      |> Repo.update()
      |> maybe_record_memory_event("knowledge.memory.updated", scope_data, "Memory updated")
    end
  end

  def update_memory(_scope, _knowledge_item, _attrs), do: {:error, :invalid_attrs}

  @doc """
  Hard deletes a memory at exact scope.

  ## Parameters

  - `scope` - exact ownership scope expected for the target memory.
  - `knowledge_item` - memory row (`kind = "memory"`).

  ## Examples

      iex> LemmingsOs.Knowledge.delete_memory(%{}, %LemmingsOs.Knowledge.KnowledgeItem{})
      {:error, :invalid_scope}
  """
  @spec delete_memory(scope(), KnowledgeItem.t()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def delete_memory(scope, %KnowledgeItem{} = knowledge_item) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      Repo.delete(knowledge_item)
      |> maybe_record_memory_event("knowledge.memory.deleted", scope_data, "Memory deleted")
    end
  end

  @doc """
  Returns a changeset for memory form handling.

  ## Parameters

  - `knowledge_item` - memory struct to validate.
  - `attrs` - optional pending form values.

  ## Examples

      iex> changeset = LemmingsOs.Knowledge.change_memory(%LemmingsOs.Knowledge.KnowledgeItem{})
      iex> changeset.valid?
      false
  """
  @spec change_memory(KnowledgeItem.t(), map()) :: Ecto.Changeset.t()
  def change_memory(%KnowledgeItem{} = knowledge_item, attrs \\ %{}) when is_map(attrs) do
    KnowledgeItem.user_update_changeset(knowledge_item, attrs)
  end

  @doc """
  Creates a source-file knowledge item and enqueues non-blocking indexing.

  ## Parameters

  - `scope` - exact ownership scope for the source file.
  - `attrs` - source-file creation attributes (including storage info).

  ## Examples

      iex> LemmingsOs.Knowledge.create_source_file(%{}, %{})
      {:error, :invalid_scope}
  """
  @spec create_source_file(scope(), map()) ::
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

  @doc """
  Creates a source file from an uploaded local temp path.

  The file is first copied into Knowledge-managed storage and then persisted as
  a source-file knowledge item using the generated storage reference.

  ## Parameters

  - `scope` - exact ownership scope for the source file.
  - `attrs` - source-file creation fields (`:title`, `:source_file_type`, tags, etc.).
  - `source_path` - trusted absolute temp path from upload consumption.

  ## Examples

      iex> LemmingsOs.Knowledge.create_source_file_upload(%{}, %{}, "/tmp/missing")
      {:error, :invalid_scope}
  """
  @spec create_source_file_upload(scope(), map(), String.t()) ::
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

  @doc """
  Lists source-file rows local to the provided scope.

  ## Parameters

  - `scope` - exact ownership scope for source-file rows.
  - `opts` - optional lifecycle filters.

  `opts` supports:
  - `:status` (source-file lifecycle status; matches both knowledge and source-file status fields)

  ## Examples

      iex> LemmingsOs.Knowledge.list_source_files(%{})
      []
  """
  @spec list_source_files(scope(), keyword()) :: [SourceFile.t()]
  def list_source_files(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        status = Keyword.get(opts, :status)

        SourceFile
        |> join(:inner, [source_file], knowledge_item in KnowledgeItem,
          on: knowledge_item.id == source_file.knowledge_item_id
        )
        |> where([_source_file, knowledge_item], knowledge_item.world_id == ^scope_data.world_id)
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

  @doc """
  Archives a source file and excludes it from indexing/retrieval candidates.

  ## Parameters

  - `scope` - exact ownership scope expected for the target row.
  - `source_file` - source-file row to archive.

  ## Examples

      iex> LemmingsOs.Knowledge.archive_source_file(%{}, %LemmingsOs.Knowledge.SourceFile{})
      {:error, :invalid_scope}
  """
  @spec archive_source_file(scope(), SourceFile.t()) ::
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

  @doc """
  Retries a source-file indexing run by resetting lifecycle and re-enqueueing work.

  ## Parameters

  - `scope` - exact ownership scope expected for the target row.
  - `source_file` - source-file row to reset and re-enqueue.

  ## Examples

      iex> LemmingsOs.Knowledge.retry_source_file_indexing(%{}, %LemmingsOs.Knowledge.SourceFile{})
      {:error, :invalid_scope}
  """
  @spec retry_source_file_indexing(scope(), SourceFile.t()) ::
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

  @doc """
  Executes source-file lifecycle transitions for one indexing run.

  ## Parameters

  - `source_file_id` - source-file UUID to process.

  ## Examples

      iex> LemmingsOs.Knowledge.run_source_file_indexing(Ecto.UUID.generate())
      {:error, :not_found}
  """
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

  @doc """
  Returns source files that are retrieval candidates (ready-only, non-failed).

  ## Parameters

  - `scope` - exact ownership scope used to select ready rows.

  ## Examples

      iex> LemmingsOs.Knowledge.list_ready_source_files(%{})
      []
  """
  @spec list_ready_source_files(scope()) :: [SourceFile.t()]
  def list_ready_source_files(scope) do
    list_source_files(scope, status: "ready")
  end

  @doc """
  Updates editable source-file metadata in both knowledge item and source-file rows.

  ## Parameters

  - `scope` - exact ownership scope expected for the target row.
  - `source_file` - source-file row to update.
  - `attrs` - editable fields (`:title`, `:tags`, `:source_file_type`, optional `:metadata`).

  ## Examples

      iex> LemmingsOs.Knowledge.update_source_file_metadata(%{}, %LemmingsOs.Knowledge.SourceFile{}, %{})
      {:error, :invalid_scope}
  """
  @spec update_source_file_metadata(scope(), SourceFile.t(), map()) ::
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

  @doc """
  Performs scope-safe vector retrieval over ready source-file chunks.

  ## Parameters

  - `scope` - caller scope used for visibility filtering.
  - `query_embedding` - numeric embedding vector for nearest-neighbor search.
  - `opts` - optional retrieval filters and caps.

  `opts` supports:
  - `:source_file_type` (must be one of `LemmingsOs.Knowledge.SourceFile.types/0`)
  - `:tags` (list of required tags; containment match)
  - `:query_text` (optional raw query for query-centered snippet extraction)
  - `:top_k` (result cap, default `5`, max `20`)
  - `:snippet_length` (snippet char cap, default `240`, max `1000`)

  Returns ranked chunk rows with safe metadata for retrieval surfaces:
  - `knowledge_item_id`, `knowledge_source_file_id`, `chunk_id`, `chunk_ref`, `chunk_index`
  - `title`, `source_file_type`, `tags`, `score`, `snippet`
  - `scope` (`%{type: "world" | "city" | "department" | "lemming"}`)

  ## Examples

      iex> LemmingsOs.Knowledge.search_source_file_chunks(%{}, [0.1, 0.2], top_k: 5)
      []
  """
  @spec search_source_file_chunks(scope(), [number()], keyword()) ::
          [source_file_chunk_search_result()]
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

  @doc """
  Reads one ready source-file chunk by `chunk_ref` with scope enforcement.

  ## Parameters

  - `scope` - caller scope used for visibility filtering.
  - `chunk_ref` - stable chunk reference (`ksf:...`).
  - `opts` - optional read caps.

  `opts` supports:
  - `:max_chars` (content cap, default `4000`, max `8000`)

  Returns safe chunk/read metadata and bounded content.

  ## Examples

      iex> LemmingsOs.Knowledge.read_source_file_chunk(%{}, "missing")
      {:error, :invalid_scope}
  """
  @spec read_source_file_chunk(scope(), String.t(), keyword()) ::
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
    |> order_by(
      [chunk, _source_file, _knowledge_item],
      asc: fragment("? <=> ?", chunk.embedding, ^query_embedding)
    )
    |> limit(^top_k)
    |> select_source_file_chunk_search_fields(query_embedding)
  end

  defp filter_ready_source_file_chunks(query) do
    from([chunk, source_file, knowledge_item] in query,
      where:
        knowledge_item.kind == "source_file" and
          knowledge_item.status == "ready" and
          source_file.indexing_status == "ready" and
          source_file.extraction_status == "ready" and
          not is_nil(chunk.embedding)
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
        score: fragment("(1 - (? <=> ?))::float", chunk.embedding, ^query_embedding),
        content: chunk.content,
        scope_type:
          fragment(
            "case when ? is not null then 'lemming' when ? is not null then 'department' when ? is not null then 'city' else 'world' end",
            knowledge_item.lemming_id,
            knowledge_item.department_id,
            knowledge_item.city_id
          )
      }
    )
  end

  defp map_source_file_chunk_search_results(rows, query_text, snippet_length) do
    Enum.map(rows, fn %{scope_type: scope_type} = row ->
      snippet =
        row
        |> fetch(:content)
        |> snippet_from_content(query_text, snippet_length)

      row
      |> Map.delete(:scope_type)
      |> Map.delete(:content)
      |> Map.put(:snippet, snippet)
      |> Map.put(:scope, %{type: scope_type})
    end)
  end

  defp apply_memory_filters(query, opts) do
    query
    |> maybe_filter_source(Keyword.get(opts, :source))
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_query(Keyword.get(opts, :q) || Keyword.get(opts, :query))
  end

  defp maybe_filter_source(query, source) when source in ["user", "llm"] do
    from(knowledge_item in query, where: knowledge_item.source == ^source)
  end

  defp maybe_filter_source(query, _source), do: query

  defp maybe_filter_status(query, status) when status in ["active"] do
    from(knowledge_item in query, where: knowledge_item.status == ^status)
  end

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      query
    else
      pattern = "%" <> trimmed <> "%"

      from(knowledge_item in query,
        where:
          ilike(knowledge_item.title, ^pattern) or
            ilike(fragment("array_to_string(?, ' ')", knowledge_item.tags), ^pattern)
      )
    end
  end

  defp maybe_filter_query(query, _value), do: query

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

  defp to_effective_row(%KnowledgeItem{} = knowledge_item, scope_data) do
    owner_scope = owner_scope(knowledge_item)
    local? = knowledge_item_in_scope?(knowledge_item, scope_data)
    inherited? = inherited_owner?(knowledge_item, scope_data, local?)

    %{
      memory: knowledge_item,
      owner_scope: owner_scope,
      owner_scope_label: String.capitalize(owner_scope),
      local?: local?,
      inherited?: inherited?,
      descendant?: not local? and not inherited?
    }
  end

  defp inherited_owner?(_knowledge_item, _scope_data, true), do: false

  defp inherited_owner?(
         %KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil},
         _scope_data,
         false
       ),
       do: true

  defp inherited_owner?(
         %KnowledgeItem{department_id: nil, lemming_id: nil} = knowledge_item,
         scope_data,
         false
       ) do
    is_binary(scope_data.city_id) and knowledge_item.city_id == scope_data.city_id
  end

  defp inherited_owner?(%KnowledgeItem{lemming_id: nil} = knowledge_item, scope_data, false) do
    is_binary(scope_data.department_id) and
      knowledge_item.department_id == scope_data.department_id
  end

  defp inherited_owner?(_knowledge_item, _scope_data, false), do: false

  defp owner_scope(%KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil}), do: "world"
  defp owner_scope(%KnowledgeItem{department_id: nil, lemming_id: nil}), do: "city"
  defp owner_scope(%KnowledgeItem{lemming_id: nil}), do: "department"
  defp owner_scope(%KnowledgeItem{}), do: "lemming"

  defp to_unscoped_row(%KnowledgeItem{} = knowledge_item) do
    owner_scope = owner_scope(knowledge_item)

    %{
      memory: knowledge_item,
      owner_scope: owner_scope,
      owner_scope_label: String.capitalize(owner_scope),
      local?: true,
      inherited?: false,
      descendant?: false
    }
  end

  defp limit_value(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @max_limit)
      _limit -> @default_limit
    end
  end

  defp offset_value(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) and offset >= 0 -> offset
      _offset -> 0
    end
  end

  defp paginate_query(query, offset, limit, map_entry_fun) when is_function(map_entry_fun, 1) do
    total_count = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_by([knowledge_item], desc: knowledge_item.inserted_at, desc: knowledge_item.id)
      |> offset(^offset)
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(map_entry_fun)

    %{
      entries: entries,
      total_count: total_count,
      limit: limit,
      offset: offset
    }
  end

  defp validate_exact_scope(%KnowledgeItem{} = knowledge_item, scope_data) do
    if knowledge_item_in_scope?(knowledge_item, scope_data) do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp knowledge_item_in_scope?(%KnowledgeItem{} = knowledge_item, scope_data) do
    knowledge_item.world_id == scope_data.world_id and
      knowledge_item.city_id == scope_data.city_id and
      knowledge_item.department_id == scope_data.department_id and
      knowledge_item.lemming_id == scope_data.lemming_id
  end

  defp validate_requested_scope(attrs, scope_data) do
    attrs_scope_data =
      attrs
      |> Map.take([
        :world_id,
        :city_id,
        :department_id,
        :lemming_id,
        "world_id",
        "city_id",
        "department_id",
        "lemming_id"
      ])
      |> scope_data_from_attrs()

    case attrs_scope_data do
      :none -> :ok
      %{} = attrs_scope when attrs_scope == scope_data -> :ok
      %{} -> {:error, :scope_mismatch}
    end
  end

  defp scope_data_from_attrs(attrs) do
    world_id = fetch(attrs, :world_id)
    city_id = fetch(attrs, :city_id)
    department_id = fetch(attrs, :department_id)
    lemming_id = fetch(attrs, :lemming_id)

    if is_nil(world_id) and is_nil(city_id) and is_nil(department_id) and is_nil(lemming_id) do
      :none
    else
      %{
        world_id: world_id,
        city_id: city_id,
        department_id: department_id,
        lemming_id: lemming_id
      }
    end
  end

  defp creator_metadata(opts) do
    opts
    |> Keyword.get(:creator, %{})
    |> normalize_creator_metadata()
  end

  defp normalize_creator_metadata(%{} = creator) do
    creator_type = fetch(creator, :creator_type)
    creator_id = fetch(creator, :creator_id)
    creator_lemming_id = fetch(creator, :creator_lemming_id)
    creator_lemming_instance_id = fetch(creator, :creator_lemming_instance_id)
    creator_tool_execution_id = fetch(creator, :creator_tool_execution_id)

    with :ok <- maybe_validate_uuid(creator_lemming_id),
         :ok <- maybe_validate_uuid(creator_lemming_instance_id),
         :ok <- maybe_validate_uuid(creator_tool_execution_id),
         :ok <- validate_creator_refs(creator_lemming_instance_id, creator_tool_execution_id) do
      {:ok,
       %{}
       |> maybe_put(:creator_type, creator_type)
       |> maybe_put(:creator_id, creator_id)
       |> maybe_put(:creator_lemming_id, creator_lemming_id)
       |> maybe_put(:creator_lemming_instance_id, creator_lemming_instance_id)
       |> maybe_put(:creator_tool_execution_id, creator_tool_execution_id)}
    end
  end

  defp normalize_creator_metadata(_creator), do: {:error, :invalid_attrs}

  defp validate_creator_refs(nil, nil), do: :ok
  defp validate_creator_refs(instance_id, nil) when is_binary(instance_id), do: :ok

  defp validate_creator_refs(instance_id, tool_execution_id)
       when is_binary(instance_id) and is_binary(tool_execution_id) do
    exists? =
      ToolExecution
      |> where(
        [tool_execution],
        tool_execution.id == ^tool_execution_id and
          tool_execution.lemming_instance_id == ^instance_id
      )
      |> Repo.exists?()

    if exists?, do: :ok, else: {:error, :scope_mismatch}
  end

  defp validate_creator_refs(_instance_id, _tool_execution_id), do: {:error, :invalid_attrs}

  defp maybe_validate_uuid(nil), do: :ok

  defp maybe_validate_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_attrs}
    end
  end

  defp maybe_validate_uuid(_value), do: {:error, :invalid_attrs}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_record_memory_event(
         {:ok, %KnowledgeItem{} = memory} = result,
         event_type,
         scope_data,
         message
       )
       when is_binary(event_type) and is_map(scope_data) and is_binary(message) do
    payload = memory_event_payload(memory)

    case Events.record_event(
           event_type,
           scope_data,
           message,
           payload: payload,
           event_family: "audit",
           action: memory_event_action(event_type),
           status: "succeeded",
           resource_type: "knowledge_item",
           resource_id: memory.id
         ) do
      {:ok, _event} ->
        result

      {:error, reason} ->
        Logger.warning("failed to record memory lifecycle event",
          event: "knowledge.memory.event_failed",
          world_id: memory.world_id,
          department_id: memory.department_id,
          lemming_id: memory.lemming_id,
          reason: safe_reason(reason)
        )

        result
    end
  end

  defp maybe_record_memory_event(result, _event_type, _scope_data, _message), do: result

  defp memory_event_action("knowledge.memory.created"), do: "create"
  defp memory_event_action("knowledge.memory.updated"), do: "update"
  defp memory_event_action("knowledge.memory.deleted"), do: "delete"
  defp memory_event_action(_event_type), do: "update"

  defp memory_event_payload(%KnowledgeItem{} = memory) do
    %{
      knowledge_item_id: memory.id,
      kind: memory.kind,
      source: memory.source,
      status: memory.status,
      world_id: memory.world_id,
      city_id: memory.city_id,
      department_id: memory.department_id,
      lemming_id: memory.lemming_id,
      creator_type: memory.creator_type,
      creator_id: memory.creator_id,
      creator_lemming_id: memory.creator_lemming_id,
      creator_lemming_instance_id: memory.creator_lemming_instance_id,
      creator_tool_execution_id: memory.creator_tool_execution_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_read_mode(:local), do: {:ok, :local}
  defp normalize_read_mode(:visible), do: {:ok, :visible}
  defp normalize_read_mode(_mode), do: {:error, :invalid_attrs}

  defp normalize_source(source) when is_binary(source) do
    if source in KnowledgeItem.sources(), do: {:ok, source}, else: {:error, :invalid_attrs}
  end

  defp normalize_source(_source), do: {:error, :invalid_attrs}

  defp normalize_status(status) when is_binary(status) do
    if status in KnowledgeItem.statuses(), do: {:ok, status}, else: {:error, :invalid_attrs}
  end

  defp normalize_status(_status), do: {:error, :invalid_attrs}

  defp normalize_kind(kind) when is_binary(kind) do
    if kind in KnowledgeItem.kinds(), do: {:ok, kind}, else: {:error, :invalid_attrs}
  end

  defp normalize_kind(_kind), do: {:error, :invalid_attrs}

  defp scope_data(%World{id: world_id}) when is_binary(world_id),
    do:
      validate_scope_consistency(%{
        world_id: world_id,
        city_id: nil,
        department_id: nil,
        lemming_id: nil
      })

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id),
       do:
         validate_scope_consistency(%{
           world_id: world_id,
           city_id: city_id,
           department_id: nil,
           lemming_id: nil
         })

  defp scope_data(%Department{id: department_id, world_id: world_id, city_id: city_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    validate_scope_consistency(%{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: nil
    })
  end

  defp scope_data(%Lemming{
         id: lemming_id,
         world_id: world_id,
         city_id: city_id,
         department_id: department_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    validate_scope_consistency(%{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: lemming_id
    })
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: nil,
           department_id: nil,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) do
    exists? = world_scope_exists?(world_id)
    scope_consistency_result(exists?, scope_data)
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: nil,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) do
    scope_consistency_result(city_scope_exists?(world_id, city_id), scope_data)
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    scope_consistency_result(
      department_scope_exists?(world_id, city_id, department_id),
      scope_data
    )
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    scope_consistency_result(
      lemming_scope_exists?(world_id, city_id, department_id, lemming_id),
      scope_data
    )
  end

  defp validate_scope_consistency(_scope_data), do: {:error, :invalid_scope}

  defp scope_consistency_result(true, scope_data), do: {:ok, scope_data}
  defp scope_consistency_result(false, _scope_data), do: {:error, :scope_mismatch}

  defp scope_filters(scope_data) do
    [
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id,
      lemming_id: scope_data.lemming_id
    ]
  end

  defp filter_scope_relevance(query, %{world_id: world_id, city_id: nil}) do
    from(knowledge_item in query,
      where: knowledge_item.world_id == ^world_id
    )
    |> world_only_filter()
  end

  defp filter_scope_relevance(query, %{world_id: world_id, city_id: city_id, department_id: nil})
       when is_binary(city_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id)
    )
    |> city_only_filter()
  end

  defp filter_scope_relevance(
         query,
         %{world_id: world_id, city_id: city_id, department_id: department_id, lemming_id: nil}
       )
       when is_binary(city_id) and is_binary(department_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id)
    )
  end

  defp filter_scope_relevance(
         query,
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         }
       )
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id) and
          (is_nil(knowledge_item.lemming_id) or knowledge_item.lemming_id == ^lemming_id)
    )
  end

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

  defp world_scope_exists?(world_id) do
    World
    |> where([world], world.id == ^world_id)
    |> Repo.exists?()
  end

  defp city_scope_exists?(world_id, city_id) do
    City
    |> where([city], city.id == ^city_id and city.world_id == ^world_id)
    |> Repo.exists?()
  end

  defp department_scope_exists?(world_id, city_id, department_id) do
    Department
    |> join(:inner, [department], city in City, on: city.id == department.city_id)
    |> where(
      [department, city],
      department.id == ^department_id and department.world_id == ^world_id and
        department.city_id == ^city_id and city.world_id == ^world_id
    )
    |> Repo.exists?()
  end

  defp lemming_scope_exists?(world_id, city_id, department_id, lemming_id) do
    Lemming
    |> join(:inner, [lemming], department in Department,
      on: department.id == lemming.department_id
    )
    |> join(:inner, [lemming, department], city in City, on: city.id == lemming.city_id)
    |> where(
      [lemming, department, city],
      lemming.id == ^lemming_id and lemming.world_id == ^world_id and
        lemming.city_id == ^city_id and lemming.department_id == ^department_id and
        department.world_id == ^world_id and department.city_id == ^city_id and
        city.world_id == ^world_id
    )
    |> Repo.exists?()
  end

  defp world_only_filter(query) do
    from(knowledge_item in query,
      where:
        is_nil(knowledge_item.city_id) and is_nil(knowledge_item.department_id) and
          is_nil(knowledge_item.lemming_id)
    )
  end

  defp city_only_filter(query) do
    from(knowledge_item in query,
      where: is_nil(knowledge_item.department_id) and is_nil(knowledge_item.lemming_id)
    )
  end

  defp filter_scope_descendants(query, %{world_id: world_id, city_id: nil}) do
    from(knowledge_item in query, where: knowledge_item.world_id == ^world_id)
  end

  defp filter_scope_descendants(
         query,
         %{world_id: world_id, city_id: city_id, department_id: nil}
       )
       when is_binary(city_id) do
    from(knowledge_item in query,
      where: knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id
    )
  end

  defp filter_scope_descendants(
         query,
         %{world_id: world_id, city_id: city_id, department_id: department_id, lemming_id: nil}
       )
       when is_binary(city_id) and is_binary(department_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id and
          knowledge_item.department_id == ^department_id
    )
  end

  defp filter_scope_descendants(
         query,
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         }
       )
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id and
          knowledge_item.department_id == ^department_id and
          knowledge_item.lemming_id == ^lemming_id
    )
  end

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do:
      filter_query(
        from(knowledge_item in query, where: knowledge_item.world_id == ^world_id),
        rest
      )

  defp filter_query(query, [{:city_id, city_id} | rest]) when is_binary(city_id),
    do:
      filter_query(from(knowledge_item in query, where: knowledge_item.city_id == ^city_id), rest)

  defp filter_query(query, [{:city_id, nil} | rest]),
    do: filter_query(from(knowledge_item in query, where: is_nil(knowledge_item.city_id)), rest)

  defp filter_query(query, [{:department_id, department_id} | rest])
       when is_binary(department_id),
       do:
         filter_query(
           from(knowledge_item in query, where: knowledge_item.department_id == ^department_id),
           rest
         )

  defp filter_query(query, [{:department_id, nil} | rest]),
    do:
      filter_query(
        from(knowledge_item in query, where: is_nil(knowledge_item.department_id)),
        rest
      )

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]) when is_binary(lemming_id),
    do:
      filter_query(
        from(knowledge_item in query, where: knowledge_item.lemming_id == ^lemming_id),
        rest
      )

  defp filter_query(query, [{:lemming_id, nil} | rest]),
    do:
      filter_query(from(knowledge_item in query, where: is_nil(knowledge_item.lemming_id)), rest)

  defp filter_query(query, [{:kind, kind} | rest]),
    do: filter_query(from(knowledge_item in query, where: knowledge_item.kind == ^kind), rest)

  defp filter_query(query, [_unknown | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

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

  defp safe_reason(%Ecto.Changeset{}), do: "changeset_error"
  defp safe_reason(:invalid_scope), do: "invalid_scope"
  defp safe_reason(:invalid_event), do: "invalid_event"

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
