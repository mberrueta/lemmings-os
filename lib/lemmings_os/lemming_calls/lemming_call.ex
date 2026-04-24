defmodule LemmingsOs.LemmingCalls.LemmingCall do
  @moduledoc """
  Durable lemming-to-lemming collaboration record.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(accepted running needs_more_context partial_result completed failed)
  @required ~w(
    world_id
    city_id
    caller_department_id
    callee_department_id
    caller_lemming_id
    callee_lemming_id
    caller_instance_id
    callee_instance_id
    request_text
    status
  )a
  @optional ~w(
    root_call_id
    previous_call_id
    result_summary
    error_summary
    recovery_status
    started_at
    completed_at
  )a
  @status_fields ~w(status result_summary error_summary recovery_status started_at completed_at)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          city_id: Ecto.UUID.t() | nil,
          city: City.t() | Ecto.Association.NotLoaded.t() | nil,
          caller_department_id: Ecto.UUID.t() | nil,
          caller_department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          callee_department_id: Ecto.UUID.t() | nil,
          callee_department: Department.t() | Ecto.Association.NotLoaded.t() | nil,
          caller_lemming_id: Ecto.UUID.t() | nil,
          caller_lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          callee_lemming_id: Ecto.UUID.t() | nil,
          callee_lemming: Lemming.t() | Ecto.Association.NotLoaded.t() | nil,
          caller_instance_id: Ecto.UUID.t() | nil,
          caller_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          callee_instance_id: Ecto.UUID.t() | nil,
          callee_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          root_call_id: Ecto.UUID.t() | nil,
          root_call: t() | Ecto.Association.NotLoaded.t() | nil,
          previous_call_id: Ecto.UUID.t() | nil,
          previous_call: t() | Ecto.Association.NotLoaded.t() | nil,
          request_text: String.t() | nil,
          status: String.t() | nil,
          result_summary: String.t() | nil,
          error_summary: String.t() | nil,
          recovery_status: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "lemming_instance_calls" do
    field :request_text, :string
    field :status, :string, default: "accepted"
    field :result_summary, :string
    field :error_summary, :string
    field :recovery_status, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :world, World
    belongs_to :city, City
    belongs_to :caller_department, Department
    belongs_to :callee_department, Department
    belongs_to :caller_lemming, Lemming
    belongs_to :callee_lemming, Lemming
    belongs_to :caller_instance, LemmingInstance
    belongs_to :callee_instance, LemmingInstance
    belongs_to :root_call, __MODULE__
    belongs_to :previous_call, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds changeset for creating durable collaboration call.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(call, attrs) do
    call
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_change(:request_text, &validate_present_text/2)
    |> validate_not_self_successor()
    |> apply_constraints()
  end

  @doc """
  Builds changeset for status and summary updates.
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(call, attrs) do
    call
    |> cast(attrs, @status_fields)
    |> validate_required([:status], message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
  end

  @doc """
  Canonical persisted call status values.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_present_text(:request_text, value) when is_binary(value) do
    if String.trim(value) == "" do
      [request_text: dgettext("errors", ".required")]
    else
      []
    end
  end

  defp validate_present_text(:request_text, _value),
    do: [request_text: dgettext("errors", ".required")]

  defp validate_not_self_successor(changeset) do
    id = get_field(changeset, :id)
    root_call_id = get_field(changeset, :root_call_id)
    previous_call_id = get_field(changeset, :previous_call_id)

    changeset
    |> validate_not_same_call(:root_call_id, id, root_call_id)
    |> validate_not_same_call(:previous_call_id, id, previous_call_id)
  end

  defp validate_not_same_call(changeset, _field, nil, _call_id), do: changeset
  defp validate_not_same_call(changeset, _field, _id, nil), do: changeset

  defp validate_not_same_call(changeset, field, id, id) do
    add_error(changeset, field, dgettext("errors", ".invalid_value"))
  end

  defp validate_not_same_call(changeset, _field, _id, _call_id), do: changeset

  defp apply_constraints(changeset) do
    changeset
    |> assoc_constraint(:world)
    |> assoc_constraint(:city)
    |> assoc_constraint(:caller_department)
    |> assoc_constraint(:callee_department)
    |> assoc_constraint(:caller_lemming)
    |> assoc_constraint(:callee_lemming)
    |> assoc_constraint(:caller_instance)
    |> assoc_constraint(:callee_instance)
  end
end
