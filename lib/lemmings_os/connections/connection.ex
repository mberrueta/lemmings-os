defmodule LemmingsOs.Connections.Connection do
  @moduledoc """
  Persisted reusable Connection schema for world, city, and department scopes.

  A Connection stores non-secret integration config and may include Secret Bank
  references in `config` (for example `"$GITHUB_TOKEN"`).
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections.TypeRegistry
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(enabled disabled invalid)
  @required ~w(world_id type status config)a
  @optional ~w(city_id department_id)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          type: String.t() | nil,
          status: String.t() | nil,
          config: map() | nil,
          last_test: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "connections" do
    field :type, :string
    field :status, :string, default: "enabled"
    field :config, :map, default: %{}
    field :last_test, :string

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted connection.

  Scope is inferred from owner IDs:
  - world scope: `world_id` only
  - city scope: `world_id` + `city_id`
  - department scope: `world_id` + `city_id` + `department_id`
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_scope_shape()
    |> validate_map_field(:config)
    |> validate_registered_type()
    |> validate_type_config()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> check_constraint(:city_id, name: :connections_scope_shape_check)
    |> unique_constraint(:type, name: :connections_unique_world_scope_type_index)
    |> unique_constraint(:type, name: :connections_unique_city_scope_type_index)
    |> unique_constraint(:type, name: :connections_unique_department_scope_type_index)
  end

  @doc """
  Canonical persisted administrative status values for connections.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_scope_shape(changeset) do
    city_id = get_field(changeset, :city_id)
    department_id = get_field(changeset, :department_id)

    if valid_scope_shape?(city_id, department_id) do
      changeset
    else
      add_error(changeset, :city_id, dgettext("errors", ".invalid_value"))
    end
  end

  defp validate_registered_type(changeset) do
    validate_change(changeset, :type, fn :type, type ->
      if TypeRegistry.supported_type?(type) do
        []
      else
        [type: dgettext("errors", ".invalid_choice")]
      end
    end)
  end

  defp validate_type_config(changeset) do
    type = get_field(changeset, :type)
    config = get_field(changeset, :config)

    case TypeRegistry.validate_config(type, config) do
      :ok ->
        changeset

      {:error, _reason} ->
        add_error(changeset, :config, dgettext("errors", ".invalid_value"))
    end
  end

  defp valid_scope_shape?(nil, nil), do: true
  defp valid_scope_shape?(city_id, nil) when is_binary(city_id), do: true

  defp valid_scope_shape?(city_id, department_id)
       when is_binary(city_id) and is_binary(department_id),
       do: true

  defp valid_scope_shape?(_city_id, _department_id), do: false

  defp validate_map_field(changeset, field) do
    validate_change(changeset, field, fn
      _, value when is_map(value) -> []
      _, _ -> [{field, dgettext("errors", ".invalid_value_type")}]
    end)
  end
end
