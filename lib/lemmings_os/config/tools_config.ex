defmodule LemmingsOs.Config.ToolsConfig do
  @moduledoc """
  Shared tools configuration for Lemming scope.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fields ~w(allowed_tools denied_tools)a

  @type t :: %__MODULE__{
          allowed_tools: [String.t()],
          denied_tools: [String.t()]
        }

  embedded_schema do
    field :allowed_tools, {:array, :string}, default: []
    field :denied_tools, {:array, :string}, default: []
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields)
  end
end
