defmodule LemmingsOs.ModelRuntime.Response do
  @moduledoc """
  Validated model runtime response.
  """

  @enforce_keys [:action, :provider, :model, :raw]
  defstruct [
    :action,
    :reply,
    :tool_name,
    :tool_args,
    :provider,
    :model,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :usage,
    :raw
  ]

  @type t :: %__MODULE__{
          action: :reply | :tool_call,
          reply: String.t() | nil,
          tool_name: String.t() | nil,
          tool_args: map() | nil,
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
      ...>   action: :reply,
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
