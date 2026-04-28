defmodule LemmingsOs.SecretBank.Secret do
  @moduledoc """
  Persisted encrypted Secret Bank value.

  The logical `:value` field is backed by the `value_encrypted` database column
  through `LemmingsOs.Encrypted.Binary`. Runtime structs may contain decrypted
  values, so context APIs return safe metadata instead of this schema.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @required ~w(bank_key value)a
  @optional ~w()a

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
          bank_key: String.t() | nil,
          value: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "secret_bank_secrets" do
    field :bank_key, :string
    field :value, LemmingsOs.SecretBank.EncryptedBinary, source: :value_encrypted, redact: true

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department
    belongs_to :lemming, Lemming

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for a local encrypted secret.

  Hierarchy ownership is assigned by `LemmingsOs.SecretBank`; IDs are not cast
  from arbitrary attrs.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(secret, attrs) do
    secret
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_scope_shape()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> assoc_constraint(:lemming)
    |> unique_constraint(:bank_key, name: :secret_bank_secrets_unique_world_scope_index)
    |> unique_constraint(:bank_key, name: :secret_bank_secrets_unique_city_scope_index)
    |> unique_constraint(:bank_key, name: :secret_bank_secrets_unique_department_scope_index)
    |> unique_constraint(:bank_key, name: :secret_bank_secrets_unique_lemming_scope_index)
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
