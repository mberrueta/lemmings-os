defmodule LemmingsOs.Config.RuntimeConfig do
  @moduledoc """
  Shared runtime configuration for World and City scopes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fields ~w(idle_ttl_seconds cross_city_communication)a

  @type t :: %__MODULE__{
          idle_ttl_seconds: integer() | nil,
          cross_city_communication: boolean() | nil
        }

  embedded_schema do
    field :idle_ttl_seconds, :integer
    field :cross_city_communication, :boolean
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields)
  end
end
