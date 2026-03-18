defmodule LemmingsOs.Config.CostsConfig do
  @moduledoc """
  Shared cost configuration for World and City scopes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__.Budgets

  @primary_key false

  @type t :: %__MODULE__{
          budgets: Budgets.t() | nil
        }

  embedded_schema do
    embeds_one :budgets, Budgets, on_replace: :update
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(config, attrs) do
    config
    |> cast(attrs, [])
    |> cast_embed(:budgets, with: &Budgets.changeset/2)
  end

  defmodule Budgets do
    @moduledoc false

    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false
    @fields ~w(monthly_usd daily_tokens)a

    @type t :: %__MODULE__{
            monthly_usd: float() | nil,
            daily_tokens: integer() | nil
          }

    embedded_schema do
      field :monthly_usd, :float
      field :daily_tokens, :integer
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(config, attrs) do
      config
      |> cast(attrs, @fields)
    end
  end
end
