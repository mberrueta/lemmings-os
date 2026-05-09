defmodule LemmingsOs.Knowledge do
  @moduledoc """
  Knowledge domain boundary for memory, source-file, and reference-file APIs.
  """

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.Memories
  alias LemmingsOs.Knowledge.ReferenceFile
  alias LemmingsOs.Knowledge.ReferenceFiles
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFiles
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @type scope :: World.t() | City.t() | Department.t() | Lemming.t()

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

  @type reference_file_descriptor :: %{
          required(:reference_ref) => String.t(),
          required(:knowledge_item_id) => Ecto.UUID.t(),
          required(:kind) => String.t(),
          required(:reference_file_type) => String.t(),
          required(:title) => String.t(),
          required(:tags) => [String.t()],
          required(:status) => String.t(),
          required(:content_type) => String.t()
        }

  @type reference_file_row :: %{
          required(:reference_file) => ReferenceFile.t(),
          required(:descriptor) => reference_file_descriptor(),
          required(:owner_scope) => String.t(),
          required(:owner_scope_label) => String.t(),
          required(:local?) => boolean(),
          required(:inherited?) => boolean(),
          required(:descendant?) => boolean()
        }

  @type paginated_reference_files :: %{
          required(:entries) => [reference_file_row()],
          required(:total_count) => non_neg_integer(),
          required(:limit) => pos_integer(),
          required(:offset) => non_neg_integer()
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
  def list_memories(scope, opts \\ []),
    do: Memories.list_memories(scope, opts)

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
  def list_effective_memories(scope, opts \\ []),
    do: Memories.list_effective_memories(scope, opts)

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
  def list_all_memories(opts \\ []),
    do: Memories.list_all_memories(opts)

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
  def list_scope_memories(scope, opts \\ []),
    do: Memories.list_scope_memories(scope, opts)

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
  def get_memory(scope, id, opts \\ []),
    do: Memories.get_memory(scope, id, opts)

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
  def get_memory_by_id(id),
    do: Memories.get_memory_by_id(id)

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
  def create_memory(scope, attrs, opts \\ []),
    do: Memories.create_memory(scope, attrs, opts)

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
  def update_memory(scope, knowledge_item, attrs),
    do: Memories.update_memory(scope, knowledge_item, attrs)

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
  def delete_memory(scope, knowledge_item),
    do: Memories.delete_memory(scope, knowledge_item)

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
  def change_memory(knowledge_item, attrs \\ %{}),
    do: Memories.change_memory(knowledge_item, attrs)

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
  def create_source_file(scope, attrs),
    do: SourceFiles.create_source_file(scope, attrs)

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
  def create_source_file_upload(scope, attrs, source_path),
    do: SourceFiles.create_source_file_upload(scope, attrs, source_path)

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
  def list_source_files(scope, opts \\ []),
    do: SourceFiles.list_source_files(scope, opts)

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
  def archive_source_file(scope, source_file),
    do: SourceFiles.archive_source_file(scope, source_file)

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
  def retry_source_file_indexing(scope, source_file),
    do: SourceFiles.retry_source_file_indexing(scope, source_file)

  @doc """
  Executes source-file lifecycle transitions for one indexing run.

  ## Parameters

  - `source_file_id` - source-file UUID to process.

  ## Examples

      iex> LemmingsOs.Knowledge.run_source_file_indexing(Ecto.UUID.generate())
      {:error, :not_found}
  """
  @spec run_source_file_indexing(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def run_source_file_indexing(source_file_id),
    do: SourceFiles.run_source_file_indexing(source_file_id)

  @doc """
  Returns source files that are retrieval candidates (ready-only, non-failed).

  ## Parameters

  - `scope` - exact ownership scope used to select ready rows.

  ## Examples

      iex> LemmingsOs.Knowledge.list_ready_source_files(%{})
      []
  """
  @spec list_ready_source_files(scope()) :: [SourceFile.t()]
  def list_ready_source_files(scope),
    do: SourceFiles.list_ready_source_files(scope)

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
  def update_source_file_metadata(scope, source_file, attrs),
    do: SourceFiles.update_source_file_metadata(scope, source_file, attrs)

  @doc """
  Creates a reference-file knowledge item using an existing managed `storage_ref`.

  ## Parameters

  - `scope` - exact ownership scope (`%World{}`, `%City{}`, `%Department{}`, `%Lemming{}`).
  - `attrs` - reference-file attributes.

  `attrs` supports:
  - required: `:reference_file_type`, `:original_filename`, `:content_type`, `:size_bytes`, `:storage_ref`
  - optional: `:title`, `:content` (short summary), `:tags`, `:checksum`,
    `:artifact_id`, `:reference_ref` (auto-generated when omitted)
  - optional explicit scope IDs are allowed only when they match `scope`

  Runtime-owned defaults:
  - `kind = "reference_file"`
  - `source = "user"`
  - `status = "active"`

  ## Examples

      iex> LemmingsOs.Knowledge.create_reference_file(%{}, %{})
      {:error, :invalid_scope}

  Happy-path (integration-style):

      world = insert(:world)

      {:ok, %{knowledge_item: item, reference_file: file}} =
        LemmingsOs.Knowledge.create_reference_file(world, %{
          title: "Quote template",
          content: "Reusable quote summary.",
          tags: ["quote", "template"],
          reference_file_type: "quote_template",
          original_filename: "quote.md",
          content_type: "text/markdown",
          size_bytes: 128,
          storage_ref:
            "local://knowledge_reference_files/\#{world.id}/\#{Ecto.UUID.generate()}/quote.md"
        })

      item.kind == "reference_file"
      file.knowledge_item_id == item.id
  """
  @spec create_reference_file(scope(), map()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_reference_file(scope, attrs),
    do: ReferenceFiles.create_reference_file(scope, attrs)

  @doc """
  Copies an uploaded file into managed reference-file storage and creates rows.

  ## Parameters

  - `scope` - exact ownership scope.
  - `attrs` - metadata/create attributes.
  - `source_path` - trusted absolute upload temp path.

  `attrs` supports:
  - required for upload path: `:original_filename`, `:reference_file_type`, `:content_type`
  - optional: `:title`, `:content` (short summary), `:tags`,
    `:artifact_id`, `:reference_ref`
  - `:reference_ref` is generated when omitted

  ## Examples

      iex> LemmingsOs.Knowledge.create_reference_file_upload(%{}, %{}, "/tmp/missing")
      {:error, :invalid_scope}

  Happy-path (integration-style):

      world = insert(:world)
      source_path = "/tmp/uploaded-template.md"

      {:ok, %{knowledge_item: item, reference_file: file}} =
        LemmingsOs.Knowledge.create_reference_file_upload(
          world,
          %{
            title: "Uploaded template",
            content: "Short summary.",
            reference_file_type: "quote_template",
            original_filename: "template.md",
            content_type: "text/markdown"
          },
          source_path
        )

      item.kind == "reference_file"
      file.size_bytes > 0
  """
  @spec create_reference_file_upload(scope(), map(), String.t()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_reference_file_upload(scope, attrs, source_path),
    do: ReferenceFiles.create_reference_file_upload(scope, attrs, source_path)

  @doc """
  Promotes an existing Artifact into Knowledge-managed reference-file storage.

  Promotion is explicit operator action and requires `:operator_approved` to be
  true. Artifact provenance (`artifact_id`) is recorded when promotion succeeds,
  but reference-file storage and reads remain Knowledge-managed.

  Safe failures:
  - inaccessible, missing, archived, deleted, or unreadable Artifacts return
    `{:error, :artifact_unavailable}`.
  - scope mismatch between the requested target scope and selected Artifact
    returns `{:error, :artifact_unavailable}`.
  """
  @spec promote_artifact_to_reference_file(scope(), Ecto.UUID.t(), map()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error,
             Ecto.Changeset.t()
             | :invalid_scope
             | :scope_mismatch
             | :invalid_attrs
             | :operator_approval_required
             | :artifact_unavailable}
  def promote_artifact_to_reference_file(scope, artifact_id, attrs),
    do: ReferenceFiles.promote_artifact_to_reference_file(scope, artifact_id, attrs)

  @doc """
  Lists reference files local to the exact scope.

  ## Parameters

  - `scope` - exact ownership scope.
  - `opts` - optional filters.

  `opts` supports:
  - `:status` - `"active"` or `"archived"`; when omitted, returns both

  ## Examples

      iex> LemmingsOs.Knowledge.list_reference_files(%{})
      []

  Happy-path (integration-style):

      world = insert(:world)
      files = LemmingsOs.Knowledge.list_reference_files(world, status: "active")
      is_list(files)
  """
  @spec list_reference_files(scope(), keyword()) :: [ReferenceFile.t()]
  def list_reference_files(scope, opts \\ []),
    do: ReferenceFiles.list_reference_files(scope, opts)

  @doc """
  Lists reference files visible from scope (local + inherited + descendants).

  Returns read-model rows with:
  - `:reference_file`
  - `:descriptor` (safe descriptor)
  - `:owner_scope`, `:owner_scope_label`
  - `:local?`, `:inherited?`, `:descendant?`

  ## Parameters

  - `scope` - visibility anchor scope.
  - `opts` - optional filters.

  `opts` supports:
  - `:status` - `"active"` or `"archived"` (default `"active"`)

  ## Examples

      iex> LemmingsOs.Knowledge.list_effective_reference_files(%{})
      {:error, :invalid_scope}

  Happy-path (integration-style):

      city = insert(:city, world: insert(:world))
      {:ok, rows} = LemmingsOs.Knowledge.list_effective_reference_files(city)
      Enum.all?(rows, &Map.has_key?(&1, :descriptor))
  """
  @spec list_effective_reference_files(scope(), keyword()) ::
          {:ok, [map()]} | {:error, :invalid_scope | :scope_mismatch}
  def list_effective_reference_files(scope, opts \\ []),
    do: ReferenceFiles.list_effective_reference_files(scope, opts)

  @doc """
  Updates editable metadata for a reference file at exact scope.

  ## Parameters

  - `scope` - exact ownership scope expected for the target row.
  - `reference_file` - persisted `%ReferenceFile{}` to update.
  - `attrs` - editable fields.

  `attrs` supports:
  - knowledge fields: `:title`, `:content` (short summary), `:tags`
  - reference fields: `:reference_file_type`

  Unknown or nil fields are ignored. Scope mismatch is rejected.

  ## Examples

      iex> LemmingsOs.Knowledge.update_reference_file_metadata(%{}, %LemmingsOs.Knowledge.ReferenceFile{}, %{})
      {:error, :invalid_scope}

  Happy-path (integration-style):

      world = insert(:world)
      reference_file = insert(:knowledge_reference_file, knowledge_item: build(:knowledge_item, world: world))

      {:ok, %{knowledge_item: item, reference_file: file}} =
        LemmingsOs.Knowledge.update_reference_file_metadata(world, reference_file, %{
          title: "Updated title",
          content: "Updated summary",
          tags: ["updated"],
          reference_file_type: "style_guide",
          metadata: %{"origin" => "operator_edit"}
        })

      item.title == "Updated title"
      file.reference_file_type == "style_guide"
  """
  @spec update_reference_file_metadata(scope(), ReferenceFile.t(), map()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def update_reference_file_metadata(scope, reference_file, attrs),
    do: ReferenceFiles.update_reference_file_metadata(scope, reference_file, attrs)

  @doc """
  Archives a reference file at exact scope.

  This performs a soft lifecycle transition only:
  - `knowledge_items.status` is set to `"archived"`
  - no restore/recover or hard delete is performed here

  ## Parameters

  - `scope` - exact ownership scope expected for the target row.
  - `reference_file` - persisted `%ReferenceFile{}` to archive.

  ## Examples

      iex> LemmingsOs.Knowledge.archive_reference_file(%{}, %LemmingsOs.Knowledge.ReferenceFile{})
      {:error, :invalid_scope}

  Happy-path (integration-style):

      world = insert(:world)
      reference_file = insert(:knowledge_reference_file, knowledge_item: build(:knowledge_item, world: world, kind: "reference_file", status: "active"))

      {:ok, %{knowledge_item: item}} =
        LemmingsOs.Knowledge.archive_reference_file(world, reference_file)

      item.status == "archived"
  """
  @spec archive_reference_file(scope(), ReferenceFile.t()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def archive_reference_file(scope, reference_file),
    do: ReferenceFiles.archive_reference_file(scope, reference_file)

  @doc """
  Builds a safe public descriptor for a reference file.

  The descriptor intentionally excludes internal storage details like
  `storage_ref`, filesystem paths, checksum, and byte size.

  ## Parameters

  - `reference_file` - persisted `%ReferenceFile{}`; `knowledge_item` is preloaded as needed.

  ## Examples

      iex> descriptor = LemmingsOs.Knowledge.build_reference_file_descriptor(%LemmingsOs.Knowledge.ReferenceFile{
      ...>   knowledge_item_id: Ecto.UUID.generate(),
      ...>   reference_ref: "kref:test",
      ...>   reference_file_type: "template",
      ...>   original_filename: "template.md",
      ...>   content_type: "text/markdown",
      ...>   knowledge_item: %LemmingsOs.Knowledge.KnowledgeItem{
      ...>     kind: "reference_file",
      ...>     title: "Template",
      ...>     tags: [],
      ...>     status: "active"
      ...>   }
      ...> })
      iex> Map.has_key?(descriptor, :storage_ref)
      false

  Happy-path (integration-style):

      reference_file = insert(:knowledge_reference_file)
      descriptor = LemmingsOs.Knowledge.build_reference_file_descriptor(reference_file)
      descriptor.kind == "reference_file"
  """
  @spec build_reference_file_descriptor(ReferenceFile.t()) :: reference_file_descriptor()
  def build_reference_file_descriptor(reference_file),
    do: ReferenceFiles.build_reference_file_descriptor(reference_file)

  @doc """
  Lists active reference files available to a caller's effective scope.

  This is a metadata-only availability read. It never reads file bytes and never
  consults source-file chunks, embeddings, vector indexes, or RAG records.

  `opts` accepts the same metadata filters as `search_reference_files/2`, except
  `:status` is forced to `"active"`.

  ## Examples

      iex> LemmingsOs.Knowledge.list_available_reference_files(%{})
      {:error, :invalid_scope}
  """
  @spec list_available_reference_files(scope(), keyword()) ::
          {:ok, [reference_file_row()]} | {:error, :invalid_scope | :scope_mismatch}
  def list_available_reference_files(scope, opts \\ []),
    do: ReferenceFiles.list_available_reference_files(scope, opts)

  @doc """
  Searches authorized reference files by metadata only.

  `opts` supports:
  - `:kind` - only `"reference_file"` matches.
  - `:reference_file_type` or `:type` - exact reference-file type.
  - `:category` - exact match against safe metadata category.
  - `:tags` - required tags; all requested tags must be present.
  - `:status` - `"active"` (default), `"archived"`, or `"all"`.
  - `:q` or `:query` - text match over title, summary, tags, type, ref, content type, and safe metadata values.
  - `:owner_scope` or `:scope` - `"world"`, `"city"`, `"department"`, or `"lemming"`.
  - `:limit` and `:offset` - bounded pagination.

  Sorting is deterministic: nearer owner scopes are preferred first, then
  stronger metadata matches, then newest rows.

  ## Examples

      iex> LemmingsOs.Knowledge.search_reference_files(%{})
      {:error, :invalid_scope}
  """
  @spec search_reference_files(scope(), keyword()) ::
          {:ok, paginated_reference_files()} | {:error, :invalid_scope | :scope_mismatch}
  def search_reference_files(scope, opts \\ []),
    do: ReferenceFiles.search_reference_files(scope, opts)

  @doc """
  Reads an authorized reference file by `knowledge_item_id` or `reference_ref`.

  The read result always includes a safe descriptor. Text content is bounded by
  `:max_chars` (default `4000`, max `8000`). Directly readable text files return
  bounded direct text. Supported document-like files are converted through the
  existing safe source-file conversion boundary at read time only; no chunks,
  embeddings, vector indexes, or RAG records are created.

  Unsupported, unsafe, missing, or conversion-failed content returns a descriptor
  with a non-leaking `content_status` and no raw file bytes.

  ## Examples

      iex> LemmingsOs.Knowledge.read_reference_file(%{}, "kref:missing")
      {:error, :invalid_scope}
  """
  @spec read_reference_file(scope(), String.t() | map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, :invalid_scope | :scope_mismatch | :not_found}
  def read_reference_file(scope, identifier, opts \\ []),
    do: ReferenceFiles.read_reference_file(scope, identifier, opts)

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
  def search_source_file_chunks(scope, query_embedding, opts \\ []),
    do: SourceFiles.search_source_file_chunks(scope, query_embedding, opts)

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
  def read_source_file_chunk(scope, chunk_ref, opts \\ []),
    do: SourceFiles.read_source_file_chunk(scope, chunk_ref, opts)
end
