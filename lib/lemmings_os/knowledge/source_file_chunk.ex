defmodule LemmingsOs.Knowledge.SourceFileChunk do
  @moduledoc """
  Chunk rows used for source-file retrieval.

  Each row stores one ordered, searchable slice of extracted source-file text.
  This is the retrieval surface used by `knowledge.search` and `knowledge.read`
  (content, chunk ref, ordering, and optional embedding-backed indexing fields).

  `LemmingsOs.Knowledge.SourceFile` keeps document-level metadata and lifecycle
  state; this module keeps chunk-level retrieval data.

  Current defaults/status:
  - Chunk overlap/size behavior is planned but not implemented in this module yet.
    The MVP defaults are documented in
    `llms/tasks/0014_knowledge_source_files/plan.md` (chunk size `1200`,
    overlap `200`, max chunks `500`).
  - Vector dimension is currently defined at the DB layer in
    `priv/repo/migrations/20260506120000_add_knowledge_source_files_and_chunks.exs`
    as `embedding vector(1536)`.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required ~w(
    knowledge_item_id
    knowledge_source_file_id
    chunk_index
    chunk_ref
    content
    content_hash
    char_count
  )a

  @optional ~w(
    token_count
    metadata
  )a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          knowledge_item_id: Ecto.UUID.t() | nil,
          knowledge_item: KnowledgeItem.t() | Ecto.Association.NotLoaded.t() | nil,
          knowledge_source_file_id: Ecto.UUID.t() | nil,
          knowledge_source_file: SourceFile.t() | Ecto.Association.NotLoaded.t() | nil,
          chunk_index: integer() | nil,
          chunk_ref: String.t() | nil,
          content: String.t() | nil,
          content_hash: String.t() | nil,
          token_count: integer() | nil,
          char_count: integer() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "knowledge_source_file_chunks" do
    field :chunk_index, :integer
    field :chunk_ref, :string
    field :content, :string
    field :content_hash, :string
    field :token_count, :integer
    field :char_count, :integer
    field :metadata, :map, default: %{}

    belongs_to :knowledge_item, KnowledgeItem
    belongs_to :knowledge_source_file, SourceFile

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for source-file chunk rows.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_number(:chunk_index,
      greater_than_or_equal_to: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_number(:char_count,
      greater_than: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_number(:token_count,
      greater_than_or_equal_to: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:chunk_ref,
      min: 1,
      max: 255,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:content,
      min: 1,
      max: 10_000,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_length(:content_hash,
      min: 1,
      max: 255,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_metadata()
    |> assoc_constraint(:knowledge_item)
    |> assoc_constraint(:knowledge_source_file)
    |> unique_constraint(:chunk_ref, name: :knowledge_source_file_chunks_chunk_ref_index)
    |> unique_constraint(:chunk_index,
      name: :knowledge_source_file_chunks_source_file_chunk_index_index
    )
    |> check_constraint(:chunk_index,
      name: :knowledge_source_file_chunks_chunk_index_nonnegative_check
    )
    |> check_constraint(:char_count,
      name: :knowledge_source_file_chunks_char_count_positive_check
    )
    |> check_constraint(:token_count,
      name: :knowledge_source_file_chunks_token_count_nonnegative_check
    )
  end

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn
      :metadata, value when is_map(value) ->
        []

      :metadata, _value ->
        [metadata: dgettext("errors", ".invalid_value_type")]
    end)
  end
end
