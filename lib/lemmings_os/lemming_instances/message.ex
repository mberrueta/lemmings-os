defmodule LemmingsOs.LemmingInstances.Message do
  @moduledoc """
  Persisted immutable transcript entry for a runtime instance.
  """

  use Ecto.Schema
  use Gettext, backend: LemmingsOs.Gettext

  import Ecto.Changeset

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Worlds.World

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(user assistant)
  @required ~w(lemming_instance_id world_id role content)a
  @optional ~w(provider model input_tokens output_tokens total_tokens usage)a

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          lemming_instance_id: Ecto.UUID.t() | nil,
          lemming_instance: LemmingInstance.t() | Ecto.Association.NotLoaded.t() | nil,
          world_id: Ecto.UUID.t() | nil,
          world: World.t() | Ecto.Association.NotLoaded.t() | nil,
          role: String.t() | nil,
          content: String.t() | nil,
          provider: String.t() | nil,
          model: String.t() | nil,
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          total_tokens: integer() | nil,
          usage: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "lemming_instance_messages" do
    field :role, :string
    field :content, :string
    field :provider, :string
    field :model, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :usage, :map

    belongs_to :lemming_instance, LemmingInstance
    belongs_to :world, World

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds the changeset for a persisted transcript message.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required, message: dgettext("errors", ".required"))
    |> validate_inclusion(:role, @roles, message: dgettext("errors", ".invalid_choice"))
    |> assoc_constraint(:lemming_instance)
    |> assoc_constraint(:world)
    |> foreign_key_constraint(:lemming_instance_id)
    |> foreign_key_constraint(:world_id)
  end

  @doc """
  Canonical transcript role values.
  """
  @spec roles() :: [String.t()]
  def roles, do: @roles
end
