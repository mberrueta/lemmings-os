defmodule LemmingsOs.Cities.City do
  @moduledoc """
  Persisted City schema.

  City configuration follows the same split-bucket contract as World and stores
  local overrides only.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @node_name_regex ~r/^[^@\s]+@[^@\s]+$/u
  @statuses ~w(active disabled draining)
  @livenesses ~w(alive stale unknown)

  @required ~w(slug name node_name status)a
  @optional ~w(host distribution_port epmd_port)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          slug: String.t() | nil,
          name: String.t() | nil,
          node_name: String.t() | nil,
          host: String.t() | nil,
          distribution_port: integer() | nil,
          epmd_port: integer() | nil,
          status: String.t() | nil,
          last_seen_at: DateTime.t() | nil,
          limits_config: LimitsConfig.t() | nil,
          runtime_config: RuntimeConfig.t() | nil,
          costs_config: CostsConfig.t() | nil,
          models_config: ModelsConfig.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "cities" do
    field :slug, :string
    field :name, :string
    field :node_name, :string
    field :host, :string
    field :distribution_port, :integer
    field :epmd_port, :integer
    field :status, :string
    field :last_seen_at, :utc_datetime
    embeds_one :limits_config, LimitsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :runtime_config, RuntimeConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :costs_config, CostsConfig, on_replace: :update, defaults_to_struct: true
    embeds_one :models_config, ModelsConfig, on_replace: :update, defaults_to_struct: true

    belongs_to :world, World

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for a persisted city.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(city, attrs) do
    city
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> cast_embed(:limits_config, with: &LimitsConfig.changeset/2)
    |> cast_embed(:runtime_config, with: &RuntimeConfig.changeset/2)
    |> cast_embed(:costs_config, with: &CostsConfig.changeset/2)
    |> cast_embed(:models_config, with: &ModelsConfig.changeset/2)
    |> validate_format(:node_name, @node_name_regex)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:distribution_port, greater_than: 0)
    |> validate_number(:epmd_port, greater_than: 0)
    |> assoc_constraint(:world)
    |> unique_constraint(:slug, name: :cities_world_id_slug_index)
    |> unique_constraint(:node_name, name: :cities_world_id_node_name_index)
  end

  @doc """
  Canonical persisted administrative status values for cities.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  Translates a city administrative status for UI usage such as badges and selects.
  """
  @spec translate_status(t() | String.t() | nil) :: String.t()
  def translate_status(%__MODULE__{} = city), do: translate_status(city.status)

  def translate_status("active"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "default", ".city_status_active")

  def translate_status("disabled"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "default", ".city_status_disabled")

  def translate_status("draining"),
    do: Gettext.dgettext(LemmingsOs.Gettext, "default", ".city_status_draining")

  def translate_status(nil),
    do: Gettext.dgettext(LemmingsOs.Gettext, "default", ".city_status_unknown")

  @doc """
  Returns city administrative status options suitable for form selects and filters.
  """
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options do
    Enum.map(@statuses, &{&1, translate_status(&1)})
  end

  @doc """
  Derived runtime liveness for the City based on heartbeat freshness.
  """
  @spec liveness(t(), pos_integer()) :: String.t()
  def liveness(%__MODULE__{} = city, freshness_threshold_seconds)
      when is_integer(freshness_threshold_seconds) and freshness_threshold_seconds > 0 do
    liveness(city, DateTime.utc_now(), freshness_threshold_seconds)
  end

  @doc """
  Derived runtime liveness for the City using an explicit reference time.
  """
  @spec liveness(t(), DateTime.t(), pos_integer()) :: String.t()
  def liveness(%__MODULE__{last_seen_at: nil}, %DateTime{}, freshness_threshold_seconds)
      when is_integer(freshness_threshold_seconds) and freshness_threshold_seconds > 0,
      do: "unknown"

  def liveness(
        %__MODULE__{last_seen_at: last_seen_at},
        %DateTime{} = now,
        freshness_threshold_seconds
      )
      when is_integer(freshness_threshold_seconds) and freshness_threshold_seconds > 0 do
    stale_before = DateTime.add(now, -freshness_threshold_seconds, :second)

    case DateTime.compare(last_seen_at, stale_before) do
      :lt -> "stale"
      :eq -> "alive"
      :gt -> "alive"
    end
  end

  @doc """
  Canonical derived liveness values for runtime freshness.
  """
  @spec livenesses() :: [String.t()]
  def livenesses, do: @livenesses
end
