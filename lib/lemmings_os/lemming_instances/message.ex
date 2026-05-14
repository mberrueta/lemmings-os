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
  @internal_visibility "internal"
  @runtime_context_sources ~w(runtime_context lemming_call_callback)

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

  @doc """
  Returns true for durable runtime-history rows that should be sent to the
  model but not rendered as user-facing transcript replies.
  """
  @spec internal_context?(t() | map()) :: boolean()
  def internal_context?(message)

  def internal_context?(%__MODULE__{} = message) do
    internal_context_usage?(message.usage) or callback_context_content?(message.content)
  end

  def internal_context?(%{} = message) do
    usage = Map.get(message, :usage) || Map.get(message, "usage")
    content = Map.get(message, :content) || Map.get(message, "content")

    internal_context_usage?(usage) or callback_context_content?(content)
  end

  def internal_context?(_message), do: false

  @doc """
  Returns true when a persisted message is user-visible transcript content.
  """
  @spec visible_transcript?(t() | map()) :: boolean()
  def visible_transcript?(message), do: not internal_context?(message)

  defp internal_context_usage?(usage) when is_map(usage) do
    visibility = Map.get(usage, "visibility") || Map.get(usage, :visibility)
    source = Map.get(usage, "source") || Map.get(usage, :source)

    visibility == @internal_visibility or source in @runtime_context_sources
  end

  defp internal_context_usage?(_usage), do: false

  defp callback_context_content?(content) when is_binary(content) do
    String.contains?(content, "Lemming call result: status=")
  end

  defp callback_context_content?(_content), do: false
end
