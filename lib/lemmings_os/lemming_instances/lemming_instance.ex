defmodule LemmingsOs.LemmingInstances.LemmingInstance do
  @moduledoc """
  Persisted runtime execution record for a spawned lemming session.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(created queued processing retrying idle failed expired)
  @create_required ~w(lemming_id world_id city_id department_id config_snapshot)a
  @create_optional ~w(status started_at stopped_at last_activity_at)a
  @status_fields ~w(status started_at stopped_at last_activity_at)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          lemming_id: Ecto.UUID.t() | nil,
          lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          status: String.t() | nil,
          config_snapshot: map() | nil,
          started_at: DateTime.t() | nil,
          stopped_at: DateTime.t() | nil,
          last_activity_at: DateTime.t() | nil,
          messages: [Message.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "lemming_instances" do
    field :status, :string, default: "created"
    field :config_snapshot, :map
    field :started_at, :utc_datetime
    field :stopped_at, :utc_datetime
    field :last_activity_at, :utc_datetime

    belongs_to :lemming, Lemming
    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for creating a persisted runtime instance.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(instance, attrs) do
    instance
    |> cast(attrs, @create_required ++ @create_optional)
    |> validate_required(@create_required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_change(:config_snapshot, fn :config_snapshot, snapshot ->
      validate_config_snapshot(snapshot)
    end)
    |> assoc_constraint(:lemming)
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
  end

  @doc """
  Builds the status transition changeset for a persisted runtime instance.
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(instance, attrs) do
    instance
    |> cast(attrs, @status_fields)
    |> validate_required([:status], message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
  end

  @doc """
  Canonical persisted runtime status values for instances.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_config_snapshot(snapshot) when is_map(snapshot), do: []

  defp validate_config_snapshot(_snapshot) do
    [config_snapshot: dgettext("errors", ".invalid_value_type")]
  end
end
