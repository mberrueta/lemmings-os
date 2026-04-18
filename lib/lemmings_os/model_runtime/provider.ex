defmodule LemmingsOs.ModelRuntime.Provider do
  @moduledoc """
  Behaviour for model execution providers.
  """

  @type request :: %{
          model: String.t(),
          messages: [map()],
          format: String.t()
        }

  @type provider_response :: %{
          content: String.t(),
          provider: String.t(),
          model: String.t() | nil,
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          total_tokens: integer() | nil,
          usage: map() | nil,
          raw: term()
        }

  @callback chat(request(), keyword()) :: {:ok, provider_response()} | {:error, term()}
end
