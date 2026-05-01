defmodule LemmingsOs.Artifacts.Artifact do
  @moduledoc """
  Persisted Artifact domain record promoted from runtime outputs.

  A simple file only represents bytes on disk. An Artifact represents those
  bytes plus durable domain semantics: scope ownership (`world/city/department/
  lemming`), optional provenance, lifecycle status, metadata contract, and a
  storage reference that points to managed storage.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(markdown pdf json csv email html image text other)
  @statuses ~w(ready archived deleted error)
  @required ~w(world_id filename type content_type storage_ref size_bytes checksum status metadata)a
  @optional ~w(city_id department_id lemming_id lemming_instance_id created_by_tool_execution_id notes)a
  @allowed_metadata_sources ~w(manual_promotion)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          lemming_id: Ecto.UUID.t() | nil,
          lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          lemming_instance_id: Ecto.UUID.t() | nil,
          lemming_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          created_by_tool_execution_id: Ecto.UUID.t() | nil,
          created_by_tool_execution: ToolExecution.t() | Ecto.Association.NotLoaded.t() | nil,
          type: String.t() | nil,
          filename: String.t() | nil,
          content_type: String.t() | nil,
          storage_ref: String.t() | nil,
          size_bytes: integer() | nil,
          checksum: String.t() | nil,
          status: String.t() | nil,
          notes: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "artifacts" do
    field :type, :string
    field :filename, :string
    field :content_type, :string
    field :storage_ref, :string
    field :size_bytes, :integer
    field :checksum, :string
    field :status, :string
    field :notes, :string
    field :metadata, :map, default: %{}

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department
    belongs_to :lemming, Lemming
    belongs_to :lemming_instance, LemmingInstance
    belongs_to :created_by_tool_execution, ToolExecution

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted artifact.

  ## Examples

      iex> attrs = %{
      ...>   world_id: Ecto.UUID.generate(),
      ...>   filename: "artifact.md",
      ...>   type: "markdown",
      ...>   content_type: "text/markdown",
      ...>   storage_ref: "local://artifacts/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/artifact.md",
      ...>   size_bytes: 12,
      ...>   checksum: String.duplicate("a", 64),
      ...>   status: "ready",
      ...>   metadata: %{"source" => "manual_promotion"}
      ...> }
      iex> changeset = LemmingsOs.Artifacts.Artifact.changeset(%LemmingsOs.Artifacts.Artifact{}, attrs)
      iex> changeset.valid?
      true
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:type, @types, message: dgettext("errors", ".invalid_choice"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_number(:size_bytes,
      greater_than_or_equal_to: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_scope_shape()
    |> validate_metadata_contract()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> assoc_constraint(:lemming)
    |> assoc_constraint(:lemming_instance)
    |> assoc_constraint(:created_by_tool_execution)
  end

  @doc """
  Canonical persisted artifact type values.

  ## Examples

      iex> LemmingsOs.Artifacts.Artifact.types()
      ["markdown", "pdf", "json", "csv", "email", "html", "image", "text", "other"]
  """
  @spec types() :: [String.t()]
  def types, do: @types

  @doc """
  Canonical persisted artifact status values.

  ## Examples

      iex> LemmingsOs.Artifacts.Artifact.statuses()
      ["ready", "archived", "deleted", "error"]
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_scope_shape(changeset) do
    city_id = get_field(changeset, :city_id)
    department_id = get_field(changeset, :department_id)
    lemming_id = get_field(changeset, :lemming_id)

    if valid_scope_shape?(city_id, department_id, lemming_id) do
      changeset
    else
      add_error(changeset, :city_id, dgettext("errors", ".invalid_value"))
    end
  end

  defp valid_scope_shape?(nil, nil, nil), do: true
  defp valid_scope_shape?(city_id, nil, nil) when is_binary(city_id), do: true

  defp valid_scope_shape?(city_id, department_id, nil)
       when is_binary(city_id) and is_binary(department_id),
       do: true

  defp valid_scope_shape?(city_id, department_id, lemming_id)
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id),
       do: true

  defp valid_scope_shape?(_city_id, _department_id, _lemming_id), do: false

  defp validate_metadata_contract(changeset) do
    validate_change(changeset, :metadata, &metadata_errors/2)
  end

  defp metadata_errors(:metadata, metadata) when is_map(metadata) do
    metadata
    |> normalize_metadata_keys()
    |> metadata_contract_errors()
  end

  defp metadata_errors(:metadata, _metadata) do
    [metadata: dgettext("errors", ".invalid_value_type")]
  end

  defp normalize_metadata_keys(metadata) do
    Enum.reduce(metadata, %{}, fn
      {key, value}, acc when is_binary(key) -> Map.put(acc, key, value)
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {_key, _value}, acc -> acc
    end)
  end

  defp metadata_contract_errors(%{} = metadata) do
    with :ok <- validate_metadata_keys(metadata),
         :ok <- validate_metadata_source(metadata) do
      []
    else
      {:error, reason} -> [metadata: reason]
    end
  end

  defp validate_metadata_keys(metadata) do
    case Map.keys(metadata) do
      [] -> :ok
      ["source"] -> :ok
      _keys -> {:error, dgettext("errors", ".invalid_value")}
    end
  end

  defp validate_metadata_source(%{"source" => source}) when source in @allowed_metadata_sources,
    do: :ok

  defp validate_metadata_source(%{"source" => _source}),
    do: {:error, dgettext("errors", ".invalid_choice")}

  defp validate_metadata_source(%{}), do: :ok
end
