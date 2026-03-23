defmodule LemmingsOs.Departments.Department do
  @moduledoc """
  Persisted Department schema.

  Department configuration follows the same split-bucket contract as World and
  City and stores local overrides only.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Helpers
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @notes_max_length 280
  @statuses ~w(active disabled draining)
  @required ~w(slug name status)a
  @optional ~w(notes tags)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          notes: String.t() | nil,
          tags: [String.t()],
          limits_config: LimitsConfig.t() | nil,
          runtime_config: RuntimeConfig.t() | nil,
          costs_config: CostsConfig.t() | nil,
          models_config: ModelsConfig.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "departments" do
    field :slug, :string
    field :name, :string
    field :status, :string
    field :notes, :string
    field :tags, {:array, :string}, default: []
    embeds_one :limits_config, LimitsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :runtime_config, RuntimeConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :costs_config, CostsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :models_config, ModelsConfig, on_replace: :update, defaults_to_struct: true

    belongs_to :world, World
    belongs_to :city, City

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted department.

  Department ownership stays context-controlled, so `world_id` and `city_id`
  are not cast from arbitrary attrs.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(department, attrs) do
    department
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> update_change(:tags, &Helpers.normalize_tags/1)
    |> cast_embed(:limits_config, with: &LimitsConfig.changeset/2)
    |> cast_embed(:runtime_config, with: &RuntimeConfig.changeset/2)
    |> cast_embed(:costs_config, with: &CostsConfig.changeset/2)
    |> cast_embed(:models_config, with: &ModelsConfig.changeset/2)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:notes, max: @notes_max_length)
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> unique_constraint(:slug, name: :departments_city_id_slug_index)
  end

  @doc """
  Canonical persisted administrative status values for departments.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Returns department administrative status options suitable for form selects and filters.
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(@statuses, &{&1, translate_status(&1)})
  end

  @doc """
  Translates a department administrative status for UI usage such as badges and selects.
  """
  @spec translate_status(t() | String.t() | nil) :: String.t()
  def translate_status(%__MODULE__{} = department), do: translate_status(department.status)

  def translate_status("active"),
    do: dgettext("default", ".department_status_active")

  def translate_status("disabled"),
    do: dgettext("default", ".department_status_disabled")

  def translate_status("draining"),
    do: dgettext("default", ".department_status_draining")

  def translate_status(nil),
    do: dgettext("default", ".department_status_unknown")

  @doc """
  Returns the maximum allowed note length for operator-facing Department metadata.
  """
  @spec notes_max_length() :: pos_integer()
  def notes_max_length, do: @notes_max_length
end
