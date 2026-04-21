defmodule LemmingsOs.LemmingInstances.ToolExecution do
  @moduledoc """
  Persisted durable tool-execution record for a runtime instance.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(running ok error)
  @required ~w(lemming_instance_id world_id tool_name status args)a
  @optional ~w(result error summary preview started_at completed_at duration_ms)a
  @update_fields ~w(status result error summary preview started_at completed_at duration_ms)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          lemming_instance_id: Ecto.UUID.t() | nil,
          lemming_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          tool_name: String.t() | nil,
          status: String.t() | nil,
          args: map() | nil,
          result: map() | nil,
          error: map() | nil,
          summary: String.t() | nil,
          preview: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "lemming_instance_tool_executions" do
    field :tool_name, :string
    field :status, :string, default: "running"
    field :args, :map
    field :result, :map
    field :error, :map
    field :summary, :string
    field :preview, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :duration_ms, :integer

    belongs_to :lemming_instance, LemmingInstance
    belongs_to :world, World

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the changeset for creating a durable tool-execution record.

  ## Examples

      iex> changeset =
      ...>   LemmingsOs.LemmingInstances.ToolExecution.create_changeset(
      ...>     %LemmingsOs.LemmingInstances.ToolExecution{},
      ...>     %{
      ...>       lemming_instance_id: Ecto.UUID.generate(),
      ...>       world_id: Ecto.UUID.generate(),
      ...>       tool_name: "fs.read_text_file",
      ...>       status: "running",
      ...>       args: %{"path" => "notes.txt"}
      ...>     }
      ...>   )
      iex> changeset.valid?
      true
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(tool_execution, attrs) do
    tool_execution
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_maps()
    |> validate_number(:duration_ms,
      greater_than_or_equal_to: 0,
      message: dgettext("errors", ".invalid_value")
    )
    |> assoc_constraint(:lemming_instance)
    |> assoc_constraint(:world)
    |> foreign_key_constraint(:lemming_instance_id)
    |> foreign_key_constraint(:world_id)
  end

  @doc """
  Builds the changeset for updating a durable tool-execution record.

  ## Examples

      iex> changeset =
      ...>   LemmingsOs.LemmingInstances.ToolExecution.update_changeset(
      ...>     %LemmingsOs.LemmingInstances.ToolExecution{},
      ...>     %{status: "ok", result: %{"content" => "done"}, duration_ms: 12}
      ...>   )
      iex> changeset.valid?
      true
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(tool_execution, attrs) do
    tool_execution
    |> cast(attrs, @update_fields)
    |> validate_inclusion(:status, @statuses, message: dgettext("errors", ".invalid_choice"))
    |> validate_maps()
    |> validate_number(:duration_ms,
      greater_than_or_equal_to: 0,
      message: dgettext("errors", ".invalid_value")
    )
  end

  @doc """
  Canonical persisted status values for tool executions.
  """
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  defp validate_maps(changeset) do
    changeset
    |> validate_map_field(:args)
    |> validate_map_field(:result)
    |> validate_map_field(:error)
  end

  defp validate_map_field(changeset, field) do
    validate_change(changeset, field, &map_field_errors/2)
  end

  defp map_field_errors(_field, value) when is_map(value), do: []
  defp map_field_errors(_field, nil), do: []

  defp map_field_errors(field, _value) do
    [{field, dgettext("errors", ".invalid_value_type")}]
  end
end
