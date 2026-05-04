defmodule LemmingsOs.Knowledge.KnowledgeItem do
  @moduledoc """
  Persisted Knowledge item schema for memory-backed entries.

  This schema is shared-ready for future knowledge families, but this phase only
  allows memory items (`kind = "memory"`) without artifact references.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds ~w(memory)
  @sources ~w(user llm)
  @statuses ~w(active)

  @required ~w(world_id kind title content source status)a

  @optional ~w(
    city_id
    department_id
    lemming_id
    artifact_id
    tags
    creator_type
    creator_id
    creator_lemming_id
    creator_lemming_instance_id
    creator_tool_execution_id
  )a

  @user_update_fields ~w(title content tags)a

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
          artifact_id: Ecto.UUID.t() | nil,
          artifact: Artifact.t() | Ecto.Association.NotLoaded.t() | nil,
          kind: String.t() | nil,
          title: String.t() | nil,
          content: String.t() | nil,
          tags: [String.t()] | nil,
          source: String.t() | nil,
          status: String.t() | nil,
          creator_type: String.t() | nil,
          creator_id: String.t() | nil,
          creator_lemming_id: Ecto.UUID.t() | nil,
          creator_lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          creator_lemming_instance_id: Ecto.UUID.t() | nil,
          creator_lemming_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          creator_tool_execution_id: Ecto.UUID.t() | nil,
          creator_tool_execution: ToolExecution.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "knowledge_items" do
    field :kind, :string, default: "memory"
    field :title, :string
    field :content, :string
    field :tags, {:array, :string}, default: []
    field :source, :string, default: "user"
    field :status, :string, default: "active"
    field :creator_type, :string
    field :creator_id, :string

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department
    belongs_to :lemming, Lemming
    belongs_to :artifact, Artifact

    belongs_to :creator_lemming, Lemming
    belongs_to :creator_lemming_instance, LemmingInstance
    belongs_to :creator_tool_execution, ToolExecution

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the internal create/update changeset for a knowledge item.

  Runtime-owned fields like hierarchy IDs, source, status, kind, and creator
  metadata are expected to be assigned by the context, not directly by users.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(knowledge_item, attrs) do
    knowledge_item
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:kind, @kinds, message: dgettext("errors", ".invalid_choice"))
    |> validate_inclusion(:source, @sources, message: dgettext("errors", ".invalid_choice"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_length(:title, min: 1, max: 200, message: dgettext("errors", ".invalid_value"))
    |> validate_length(:content,
      min: 1,
      max: 10_000,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_tags()
    |> validate_memory_artifact_rule()
    |> validate_scope_shape()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> assoc_constraint(:lemming)
    |> assoc_constraint(:artifact)
    |> assoc_constraint(:creator_lemming)
    |> assoc_constraint(:creator_lemming_instance)
    |> assoc_constraint(:creator_tool_execution)
    |> check_constraint(:city_id, name: :knowledge_items_scope_shape_check)
  end

  @doc """
  Builds a user-facing edit changeset.

  User updates are intentionally limited to mutable memory fields.
  """
  @spec user_update_changeset(t(), map()) :: Ecto.Changeset.t()
  def user_update_changeset(knowledge_item, attrs) do
    knowledge_item
    |> cast(attrs, @user_update_fields)
    |> validate_required([:title, :content], message: dgettext("errors", ".required"))
    |> validate_length(:title, min: 1, max: 200, message: dgettext("errors", ".invalid_value"))
    |> validate_length(:content,
      min: 1,
      max: 10_000,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_tags()
  end

  @doc """
  Canonical persisted knowledge `kind` values.
  """
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  Canonical persisted knowledge `source` values.
  """
  @spec sources() :: [String.t()]
  def sources, do: @sources

  @doc """
  Canonical persisted knowledge `status` values.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_tags(changeset) do
    validate_change(changeset, :tags, fn
      :tags, value when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          []
        else
          [tags: dgettext("errors", ".invalid_value_type")]
        end

      :tags, _value ->
        [tags: dgettext("errors", ".invalid_value_type")]
    end)
  end

  defp validate_memory_artifact_rule(changeset) do
    kind = get_field(changeset, :kind)
    artifact_id = get_field(changeset, :artifact_id)

    case {kind, artifact_id} do
      {"memory", nil} ->
        changeset

      {"memory", _artifact_id} ->
        add_error(changeset, :artifact_id, dgettext("errors", ".invalid_value"))

      _other ->
        changeset
    end
  end

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
end
