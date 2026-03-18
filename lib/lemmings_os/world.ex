defmodule LemmingsOs.World do
  @moduledoc """
  Persisted World schema.

  The world-level declarative configuration is intentionally split into scoped
  JSONB-backed fields instead of a single catch-all `config_jsonb` dump. This
  keeps ownership and validation boundaries explicit for this implementation
  slice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(ok degraded unavailable invalid unknown)

  @required ~w(slug name status last_import_status)a
  @optional ~w(bootstrap_source bootstrap_path last_bootstrap_hash last_imported_at)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          status: String.t() | nil,
          bootstrap_source: String.t() | nil,
          bootstrap_path: String.t() | nil,
          last_bootstrap_hash: String.t() | nil,
          last_import_status: String.t() | nil,
          last_imported_at: DateTime.t() | nil,
          limits_config: LimitsConfig.t() | nil,
          runtime_config: RuntimeConfig.t() | nil,
          costs_config: CostsConfig.t() | nil,
          models_config: ModelsConfig.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "worlds" do
    field :slug, :string
    field :name, :string
    field :status, :string, default: "unknown"
    field :bootstrap_source, :string
    field :bootstrap_path, :string
    field :last_bootstrap_hash, :string
    field :last_import_status, :string, default: "unknown"
    field :last_imported_at, :utc_datetime
    embeds_one :limits_config, LimitsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :runtime_config, RuntimeConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :costs_config, CostsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :models_config, ModelsConfig, on_replace: :update, defaults_to_struct: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted world.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(world, attrs) do
    world
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> cast_embed(:limits_config, with: &LimitsConfig.changeset/2)
    |> cast_embed(:runtime_config, with: &RuntimeConfig.changeset/2)
    |> cast_embed(:costs_config, with: &CostsConfig.changeset/2)
    |> cast_embed(:models_config, with: &ModelsConfig.changeset/2)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:last_import_status, @statuses)
    |> unique_constraint(:slug)
    |> unique_constraint(:bootstrap_path)
  end

  @doc """
  Canonical persisted status values for worlds.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Translates a world status for UI usage such as badges and select options.
  """
  @spec translate_status(t() | String.t() | nil) :: String.t()
  def translate_status(%__MODULE__{} = world), do: translate_status(world.status)

  def translate_status("ok"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_ok")

  def translate_status("degraded"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_degraded")

  def translate_status("unavailable"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_unavailable")

  def translate_status("invalid"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_invalid")

  def translate_status("unknown"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_unknown")

  def translate_status(nil),
    do: Gettext.dgettext(LemmingsOs.Gettext, "world", ".world_status_unknown")

  @doc """
  Returns world status options suitable for form selects and filters.
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(@statuses, &{&1, translate_status(&1)})
  end
end
