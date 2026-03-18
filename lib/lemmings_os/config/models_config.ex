defmodule LemmingsOs.Config.ModelsConfig do
  @moduledoc """
  Shared model configuration for World and City scopes.

  The embed boundary is explicit, while `providers` and `profiles` stay map-backed
  for now because the keyed payload shape is already used elsewhere in the app.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @fields ~w(providers profiles)a

  @type t :: %__MODULE__{
          providers: map(),
          profiles: map()
        }

  embedded_schema do
    field :providers, :map, default: %{}
    field :profiles, :map, default: %{}
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, @fields)
  end
end
