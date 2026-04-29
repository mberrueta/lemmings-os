defmodule LemmingsOs.Connections.Connection do
  @moduledoc """
  Persisted reusable Connection schema for world, city, and department scopes.

  A Connection stores safe integration metadata and Secret Bank-compatible
  secret references. It does not store raw credentials.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(enabled disabled invalid)
  # slug example: "github-main" (lowercase kebab-case)
  @slug_pattern ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  # type example: "mock" or "github_app" (lowercase snake-case)
  @type_pattern ~r/^[a-z0-9_]+$/
  # provider example: "mock" or "openai_api" (lowercase snake-case)
  @provider_pattern ~r/^[a-z0-9_]+$/
  # logical secret key example: "api_key" (starts lowercase, snake-case)
  @logical_secret_name_pattern ~r/^[a-z][a-z0-9_]*$/
  @secret_ref_prefix "$"
  # Secret Bank key example: "$GITHUB_TOKEN" -> "GITHUB_TOKEN"
  @secret_bank_key_pattern ~r/^[A-Z_][A-Z0-9_]*$/

  @required ~w(world_id slug name type provider status config secret_refs metadata)a
  @optional ~w(city_id department_id last_tested_at last_test_status last_test_error)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          type: String.t() | nil,
          provider: String.t() | nil,
          status: String.t() | nil,
          config: map() | nil,
          secret_refs: map() | nil,
          metadata: map() | nil,
          last_tested_at: DateTime.t() | nil,
          last_test_status: String.t() | nil,
          last_test_error: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "connections" do
    field :slug, :string
    field :name, :string
    field :type, :string
    field :provider, :string
    field :status, :string, default: "enabled"
    field :config, :map, default: %{}
    field :secret_refs, :map, default: %{}
    field :metadata, :map, default: %{}
    field :last_tested_at, :utc_datetime
    field :last_test_status, :string
    field :last_test_error, :string

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

  `secret_refs` must map logical names to Secret Bank-compatible references,
  for example `%{"api_key" => "$GITHUB_TOKEN"}`.

  ## Examples

      iex> attrs = %{
      ...>   world_id: Ecto.UUID.generate(),
      ...>   slug: "github-main",
      ...>   name: "GitHub Main",
      ...>   type: "mock",
      ...>   provider: "mock",
      ...>   status: "enabled",
      ...>   config: %{},
      ...>   secret_refs: %{"api_key" => "$GITHUB_TOKEN"},
      ...>   metadata: %{}
      ...> }
      iex> changeset = LemmingsOs.Connections.Connection.changeset(%LemmingsOs.Connections.Connection{}, attrs)
      iex> changeset.valid?
      true
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_format(:slug, @slug_pattern, message: dgettext("errors", ".invalid_value"))
    |> validate_format(:type, @type_pattern, message: dgettext("errors", ".invalid_value"))
    |> validate_format(:provider, @provider_pattern,
      message: dgettext("errors", ".invalid_value")
    )
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_scope_shape()
    |> validate_map_field(:config)
    |> validate_map_field(:metadata)
    |> validate_secret_refs()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> unique_constraint(:slug, name: :connections_unique_world_scope_slug_index)
    |> unique_constraint(:slug, name: :connections_unique_city_scope_slug_index)
    |> unique_constraint(:slug, name: :connections_unique_department_scope_slug_index)
  end

  @doc """
  Canonical persisted administrative status values for connections.

  ## Examples

      iex> LemmingsOs.Connections.Connection.statuses()
      ["enabled", "disabled", "invalid"]
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

  defp validate_secret_refs(changeset) do
    changeset
    |> validate_change(:secret_refs, &secret_refs_errors/2)
  end

  defp secret_refs_errors(:secret_refs, secret_refs) when is_map(secret_refs) do
    Enum.flat_map(secret_refs, &secret_ref_entry_errors/1)
  end

  defp secret_refs_errors(:secret_refs, _value) do
    [secret_refs: dgettext("errors", ".invalid_value_type")]
  end

  defp secret_ref_entry_errors({logical_name, ref})
       when is_binary(logical_name) and is_binary(ref) do
    logical_name_errors(logical_name) ++ ref_errors(ref)
  end

  defp secret_ref_entry_errors({_logical_name, _ref}) do
    [secret_refs: dgettext("errors", ".invalid_value")]
  end

  defp logical_name_errors(logical_name) do
    if String.match?(logical_name, @logical_secret_name_pattern) do
      []
    else
      [secret_refs: dgettext("errors", ".invalid_value")]
    end
  end

  defp ref_errors(ref) do
    case String.trim_leading(ref, @secret_ref_prefix) do
      ^ref -> [secret_refs: dgettext("errors", ".invalid_value")]
      bank_key -> bank_key_errors(bank_key)
    end
  end

  defp bank_key_errors(bank_key) do
    if String.match?(bank_key, @secret_bank_key_pattern) do
      []
    else
      [secret_refs: dgettext("errors", ".invalid_value")]
    end
  end
end
