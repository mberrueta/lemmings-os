defmodule LemmingsOs.ModelRuntime.Response do
  @moduledoc """
  Validated model runtime response.
  """

  @enforce_keys [:reply, :provider, :model, :raw]
  defstruct [
    :reply,
    :provider,
    :model,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :usage,
    :raw
  ]

  @type t :: %__MODULE__{
          reply: String.t(),
          provider: String.t(),
          model: String.t() | nil,
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          total_tokens: integer() | nil,
          usage: map() | nil,
          raw: term()
        }

  @doc """
  Builds a validated runtime response struct.

  ## Examples

      iex> response = LemmingsOs.ModelRuntime.Response.new(
      ...>   reply: "hello",
      ...>   provider: "ollama",
      ...>   model: "llama3.2",
      ...>   raw: %{}
      ...> )
      iex> response.reply
      "hello"
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
