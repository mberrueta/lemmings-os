defmodule LemmingsOs.Lemmings.Lemming do
  @moduledoc """
  Persisted Lemming schema.

  Lemming configuration follows the same split-bucket contract as World, City,
  and Department, while adding a fifth tools bucket at the Lemming scope.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @description_max_length 280
  @statuses ~w(draft active archived)
  @collaboration_roles ~w(manager worker)
  @required ~w(slug name status)a
  @optional ~w(description instructions collaboration_role)a

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
          status: String.t() | nil,
          collaboration_role: String.t() | nil,
          description: String.t() | nil,
          instructions: String.t() | nil,
          limits_config: LimitsConfig.t() | nil,
          runtime_config: RuntimeConfig.t() | nil,
          costs_config: CostsConfig.t() | nil,
          models_config: ModelsConfig.t() | nil,
          tools_config: ToolsConfig.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "lemmings" do
    field :slug, :string
    field :name, :string
    field :status, :string
    field :collaboration_role, :string, default: "worker"
    field :description, :string
    field :instructions, :string
    embeds_one :limits_config, LimitsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :runtime_config, RuntimeConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :costs_config, CostsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :models_config, ModelsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :tools_config, ToolsConfig, on_replace: :update, defaults_to_struct: true

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted lemming.

  Lemming ownership stays context-controlled, so `world_id`, `city_id`, and
  `department_id` are not cast from arbitrary attrs.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(lemming, attrs) do
    lemming
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> cast_embed(:limits_config, with: &LimitsConfig.changeset/2)
    |> cast_embed(:runtime_config, with: &RuntimeConfig.changeset/2)
    |> cast_embed(:costs_config, with: &CostsConfig.changeset/2)
    |> cast_embed(:models_config, with: &ModelsConfig.changeset/2)
    |> cast_embed(:tools_config, with: &ToolsConfig.changeset/2)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:collaboration_role, @collaboration_roles,
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_length(:description, max: @description_max_length)
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> unique_constraint(:slug, name: :lemmings_department_id_slug_index)
  end

  @doc """
  Canonical persisted lifecycle status values for lemmings.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Canonical collaboration role values for lemmings.
  """
  @spec collaboration_roles() :: [String.t()]
  def collaboration_roles, do: @collaboration_roles

  @doc """
  Returns lemming lifecycle status options suitable for form selects and filters.
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(@statuses, &{translate_status(&1), &1})
  end

  @doc """
  Translates a lemming lifecycle status for UI usage such as badges and selects.
  """
  @spec translate_status(t() | String.t() | nil) :: String.t()
  def translate_status(%__MODULE__{} = lemming), do: translate_status(lemming.status)

  def translate_status("draft"),
    do: dgettext("default", ".lemming_status_draft")

  def translate_status("active"),
    do: dgettext("default", ".lemming_status_active")

  def translate_status("archived"),
    do: dgettext("default", ".lemming_status_archived")

  def translate_status(nil),
    do: dgettext("default", ".lemming_status_unknown")

  @doc """
  Returns the maximum allowed description length for operator-facing Lemming metadata.
  """
  @spec description_max_length() :: pos_integer()
  def description_max_length, do: @description_max_length
end
