defmodule LemmingsOs.Knowledge.SourceFile do
  @moduledoc """
  Source-file metadata for Knowledge-managed retrieval documents.

  `LemmingsOs.Knowledge.SourceFile` represents durable documents that operators
  add so Lemmings can search and read chunked content later (for example:
  policies, contracts, catalogs, and client material).

  This schema is intentionally different from Artifacts:
  - Source files are Knowledge assets for retrieval (`knowledge.search` /
    `knowledge.read`).
  - Artifacts are runtime outputs/files produced during Lemming executions.
  - Source files do not require an `artifact_id`; Artifact linkage is optional
    provenance when a user explicitly ingests an existing Artifact.

  Storage and indexing lifecycle data live here (storage reference, extraction
  status, indexing status, timestamps, and safe metadata) while chunk rows are
  stored in `LemmingsOs.Knowledge.SourceFileChunk`.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Knowledge.KnowledgeItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(
    price_list
    contract
    policy
    branding
    product_catalog
    company_knowledge
    client_material
    example_email
    book
    other
  )

  @statuses ~w(pending extracting ready needs_ocr failed no_content)
  @indexing_statuses ~w(pending chunking embedding ready needs_ocr failed archived deleted)

  @required ~w(
    knowledge_item_id
    source_file_type
    original_filename
    content_type
    size_bytes
    storage_ref
    extraction_status
    indexing_status
  )a

  @optional ~w(
    checksum
    failure_reason
    extracted_at
    indexed_at
    metadata
  )a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          knowledge_item_id: Ecto.UUID.t() | nil,
          knowledge_item: KnowledgeItem.t() | Ecto.Association.NotLoaded.t() | nil,
          source_file_type: String.t() | nil,
          original_filename: String.t() | nil,
          content_type: String.t() | nil,
          size_bytes: integer() | nil,
          checksum: String.t() | nil,
          storage_ref: String.t() | nil,
          extraction_status: String.t() | nil,
          indexing_status: String.t() | nil,
          failure_reason: String.t() | nil,
          extracted_at: DateTime.t() | nil,
          indexed_at: DateTime.t() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "knowledge_source_files" do
    field :source_file_type, :string
    field :original_filename, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :checksum, :string
    field :storage_ref, :string
    field :extraction_status, :string
    field :indexing_status, :string
    field :failure_reason, :string
    field :extracted_at, :utc_datetime
    field :indexed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :knowledge_item, KnowledgeItem

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for source-file metadata rows.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source_file, attrs) do
    source_file
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:source_file_type, @types,
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_inclusion(:extraction_status, @statuses,
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_inclusion(:indexing_status, @indexing_statuses,
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_number(:size_bytes,
      greater_than: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:original_filename,
      min: 1,
      max: 255,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:content_type,
      min: 1,
      max: 255,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:storage_ref,
      min: 1,
      max: 2_000,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_metadata()
    |> assoc_constraint(:knowledge_item)
    |> unique_constraint(:knowledge_item_id,
      name: :knowledge_source_files_knowledge_item_id_index
    )
    |> check_constraint(:size_bytes, name: :knowledge_source_files_size_bytes_positive_check)
    |> check_constraint(:source_file_type, name: :knowledge_source_files_source_file_type_check)
    |> check_constraint(:extraction_status, name: :knowledge_source_files_extraction_status_check)
    |> check_constraint(:indexing_status, name: :knowledge_source_files_indexing_status_check)
  end

  @doc """
  Canonical source-file type values.
  """
  @spec types() :: [String.t()]
  def types, do: @types

  @doc """
  Canonical extraction status values.
  """
  @spec extraction_statuses() :: [String.t()]
  def extraction_statuses, do: @statuses

  @doc """
  Canonical indexing status values.
  """
  @spec indexing_statuses() :: [String.t()]
  def indexing_statuses, do: @indexing_statuses

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn
      :metadata, value when is_map(value) ->
        []

      :metadata, _value ->
        [metadata: dgettext("errors", ".invalid_value_type")]
    end)
  end
end
