defmodule LemmingsOs.Config.LimitsConfig do
  @moduledoc """
  Shared limits configuration for World and City scopes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fields ~w(max_cities max_departments_per_city max_lemmings_per_department)a

  @type t :: %__MODULE__{
          max_cities: integer() | nil,
          max_departments_per_city: integer() | nil,
          max_lemmings_per_department: integer() | nil
        }

  embedded_schema do
    field :max_cities, :integer
    field :max_departments_per_city, :integer
    field :max_lemmings_per_department, :integer
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields)
  end
end
