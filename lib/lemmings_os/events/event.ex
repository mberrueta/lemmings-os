defmodule LemmingsOs.Events.Event do
  @moduledoc """
  Generic durable event envelope persisted in the canonical `events` store.
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

  @event_families ~w(audit telemetry)

  @required ~w(
    event_family
    event_type
    occurred_at
    correlation_id
    message
    payload
  )a

  @optional ~w(
    world_id
    city_id
    department_id
    lemming_id
    actor_type
    actor_id
    actor_role
    resource_type
    resource_id
    causation_id
    request_id
    tool_invocation_id
    approval_request_id
    action
    status
  )a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_family: String.t() | nil,
          event_type: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          lemming_id: Ecto.UUID.t() | nil,
          lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          actor_type: String.t() | nil,
          actor_id: String.t() | nil,
          actor_role: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          request_id: String.t() | nil,
          tool_invocation_id: String.t() | nil,
          approval_request_id: String.t() | nil,
          action: String.t() | nil,
          status: String.t() | nil,
          message: String.t() | nil,
          payload: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "events" do
    field :event_family, :string
    field :event_type, :string
    field :occurred_at, :utc_datetime

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :department, Department
    belongs_to :lemming, Lemming

    field :actor_type, :string
    field :actor_id, :string
    field :actor_role, :string
    field :resource_type, :string
    field :resource_id, :string
    field :correlation_id, :string
    field :causation_id, :string
    field :request_id, :string
    field :tool_invocation_id, :string
    field :approval_request_id, :string
    field :action, :string
    field :status, :string
    field :message, :string
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds an insert-only changeset for one durable event row.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(event, attrs) do
    event
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:event_family, @event_families,
      message: dgettext("errors", ".invalid_choice")
    )
    |> validate_change(:payload, &map_field_errors/2)
    |> validate_scope_shape()
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:department)
    |> assoc_constraint(:lemming)
  end

  defp map_field_errors(_field, value) when is_map(value), do: []

  defp map_field_errors(field, _value) do
    [{field, dgettext("errors", ".invalid_value_type")}]
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
