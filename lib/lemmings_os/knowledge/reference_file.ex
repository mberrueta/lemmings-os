defmodule LemmingsOs.Knowledge.ReferenceFile do
  @moduledoc """
  Reference-file metadata for Knowledge-managed reusable files.

  Reference files are fixed templates, examples, headers, footers, styles, or
  similar reusable inputs selected by metadata. They do not participate in the
  source-file chunking, embedding, or background indexing lifecycle.

  `knowledge_reference_files` stores the managed-file metadata that is specific
  to `KnowledgeItem` rows with `kind = "reference_file"`. The shared Knowledge
  item owns scope, title, description/content, tags, source, status, and optional
  Artifact provenance.

  Field defaults:
  - `metadata` defaults to `%{}`.
  - `safe_to_read` defaults to `true`.
  - `safe_to_pass_to_tools` defaults to `true`.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Knowledge.KnowledgeItem

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required ~w(
    knowledge_item_id
    reference_ref
    reference_file_type
    original_filename
    content_type
    size_bytes
    storage_ref
    safe_to_read
    safe_to_pass_to_tools
  )a

  @optional ~w(
    checksum
    metadata
  )a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          knowledge_item_id: Ecto.UUID.t() | nil,
          knowledge_item: KnowledgeItem.t() | Ecto.Association.NotLoaded.t() | nil,
          reference_ref: String.t() | nil,
          reference_file_type: String.t() | nil,
          original_filename: String.t() | nil,
          content_type: String.t() | nil,
          size_bytes: integer() | nil,
          checksum: String.t() | nil,
          storage_ref: String.t() | nil,
          metadata: map() | nil,
          safe_to_read: boolean() | nil,
          safe_to_pass_to_tools: boolean() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "knowledge_reference_files" do
    field :reference_ref, :string
    field :reference_file_type, :string
    field :original_filename, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :checksum, :string
    field :storage_ref, :string
    field :metadata, :map, default: %{}
    field :safe_to_read, :boolean, default: true
    field :safe_to_pass_to_tools, :boolean, default: true

    belongs_to :knowledge_item, KnowledgeItem

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for reference-file metadata rows.

  ## Parameters

  - `reference_file` - an existing `%#{inspect(__MODULE__)}{}` struct or a new
    empty struct.
  - `attrs` - map of reference-file metadata attributes. Both atom and string
    keys are accepted by `Ecto.Changeset.cast/4`.

  ## Required Attributes

  - `:knowledge_item_id` - UUID of a `KnowledgeItem` row with
    `kind = "reference_file"`.
  - `:reference_ref` - stable, safe descriptor identifier. It must be 1 to 255
    characters, start with an alphanumeric character, and contain only
    alphanumerics, `:`, `_`, or `-`.
  - `:reference_file_type` - flexible non-empty type text, 1 to 100 characters.
    This is intentionally not a closed enum.
  - `:original_filename` - original user-facing filename, 1 to 255 characters.
  - `:content_type` - MIME/content type text, 1 to 255 characters.
  - `:size_bytes` - positive file size in bytes.
  - `:storage_ref` - internal managed-storage reference, 1 to 2,000 characters.
  - `:safe_to_read` - boolean descriptor flag.
  - `:safe_to_pass_to_tools` - boolean descriptor flag.

  ## Optional Attributes

  - `:checksum` - optional checksum string captured by the storage boundary.
  - `:metadata` - arbitrary metadata map for future lookup/filtering. Defaults
    to `%{}` when omitted from the struct.

  ## Examples

      iex> attrs = %{
      ...>   knowledge_item_id: Ecto.UUID.generate(),
      ...>   reference_ref: "kref:quote_template_default",
      ...>   reference_file_type: "quote_template",
      ...>   original_filename: "quote-template.md",
      ...>   content_type: "text/markdown",
      ...>   size_bytes: 2048,
      ...>   storage_ref: "knowledge://local/reference_files/template.md",
      ...>   safe_to_read: true,
      ...>   safe_to_pass_to_tools: true
      ...> }
      iex> changeset = LemmingsOs.Knowledge.ReferenceFile.changeset(%LemmingsOs.Knowledge.ReferenceFile{}, attrs)
      iex> changeset.valid?
      true

      iex> attrs = %{
      ...>   knowledge_item_id: Ecto.UUID.generate(),
      ...>   reference_ref: "../unsafe ref",
      ...>   reference_file_type: "",
      ...>   original_filename: "quote-template.md",
      ...>   content_type: "text/markdown",
      ...>   size_bytes: 2048,
      ...>   storage_ref: "knowledge://local/reference_files/template.md",
      ...>   safe_to_read: true,
      ...>   safe_to_pass_to_tools: true
      ...> }
      iex> changeset = LemmingsOs.Knowledge.ReferenceFile.changeset(%LemmingsOs.Knowledge.ReferenceFile{}, attrs)
      iex> changeset.valid?
      false
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reference_file, attrs) do
    reference_file
    |> cast(attrs, @required ++ @optional, message: &invalid_cast_message/2)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_reference_ref()
    |> validate_bounded_text(:reference_file_type, 1, 100)
    |> validate_bounded_text(:original_filename, 1, 255)
    |> validate_bounded_text(:content_type, 1, 255)
    |> validate_bounded_text(:storage_ref, 1, 2_000)
    |> validate_number(:size_bytes,
      greater_than: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_inclusion(:safe_to_read, [true, false],
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_inclusion(:safe_to_pass_to_tools, [true, false],
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_metadata()
    |> assoc_constraint(:knowledge_item)
    |> unique_constraint(:knowledge_item_id,
      name: :knowledge_reference_files_knowledge_item_id_index
    )
    |> unique_constraint(:reference_ref, name: :knowledge_reference_files_reference_ref_index)
  end

  defp validate_reference_ref(changeset) do
    changeset
    |> validate_bounded_text(:reference_ref, 1, 255)
    |> validate_format(:reference_ref, ~r/\A[A-Za-z0-9][A-Za-z0-9:_-]*\z/,
      message: dgettext("errors", ".invalid_value")
    )
  end

  defp invalid_cast_message(_field, _metadata), do: dgettext("errors", ".invalid_value_type")

  defp validate_bounded_text(changeset, field, min, max) do
    validate_length(changeset, field,
      min: min,
      max: max,
      message: dgettext("errors", ".invalid_value")
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
