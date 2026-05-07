defmodule LemmingsOs.Knowledge.SourceFiles.Embedders.OpenAiCompatible do
  @moduledoc """
  OpenAI-compatible embedding provider.
  """

  @behaviour LemmingsOs.Knowledge.SourceFiles.EmbeddingProvider

  @doc """
  Calls an OpenAI-compatible `/embeddings` endpoint and returns one vector per
  input text.

   Required opts:
   - `:base_url`
   - `:model`

   Optional opts:
   - `:api_key` (sent as a bearer token when present)

  ## Examples

      iex> alias LemmingsOs.Knowledge.SourceFiles.Embedders.OpenAiCompatible
      iex> OpenAiCompatible.embed_texts("not-a-list", [])
      {:error, :invalid_input}

      iex> alias LemmingsOs.Knowledge.SourceFiles.Embedders.OpenAiCompatible
      iex> OpenAiCompatible.embed_texts(["hello"], [])
      {:error, :provider_not_configured}
  """
  @spec embed_texts([String.t()], keyword()) ::
          {:ok, [[float()]]}
          | {:error,
             :invalid_input
             | :provider_not_configured
             | :provider_http_error
             | :provider_timeout
             | :provider_network_error
             | :provider_invalid_response}
  @impl true
  def embed_texts(texts, opts) when is_list(texts) and is_list(opts) do
    with {:ok, base_url} <- fetch_config(opts, :base_url),
         {:ok, model} <- fetch_config(opts, :model) do
      api_key = optional_config(opts, :api_key)

      req =
        Req.new(
          base_url: base_url,
          receive_timeout: Keyword.get(opts, :timeout_ms, 30_000),
          http_errors: :return,
          retry: false,
          redirect: false
        )

      case Req.post(req,
             url: "/embeddings",
             headers: auth_headers(api_key),
             json: %{"model" => model, "input" => texts}
           ) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          parse_embeddings(body)

        {:ok, %Req.Response{}} ->
          {:error, :provider_http_error}

        {:error, %Req.TransportError{reason: :timeout}} ->
          {:error, :provider_timeout}

        {:error, %Req.TransportError{}} ->
          {:error, :provider_network_error}

        {:error, _reason} ->
          {:error, :provider_network_error}
      end
    end
  end

  def embed_texts(_texts, _opts), do: {:error, :invalid_input}

  defp fetch_config(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :provider_not_configured}
    end
  end

  defp optional_config(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp auth_headers(api_key) when is_binary(api_key), do: [{"authorization", "Bearer #{api_key}"}]
  defp auth_headers(_api_key), do: []

  defp parse_embeddings(body) when is_map(body) do
    case Map.get(body, "data") do
      data when is_list(data) -> reduce_embeddings(data)
      _other -> {:error, :provider_invalid_response}
    end
  end

  defp parse_embeddings(_body), do: {:error, :provider_invalid_response}

  defp reduce_embeddings(data) do
    data
    |> Enum.reduce_while({:ok, []}, &reduce_embedding/2)
    |> case do
      {:ok, vectors} -> {:ok, Enum.reverse(vectors)}
      error -> error
    end
  end

  defp reduce_embedding(item, {:ok, acc}) do
    case parse_vector(Map.get(item, "embedding")) do
      {:ok, vector} -> {:cont, {:ok, [vector | acc]}}
      {:error, :provider_invalid_response} -> {:halt, {:error, :provider_invalid_response}}
    end
  end

  defp parse_vector(embedding) when is_list(embedding) do
    values =
      Enum.map(embedding, fn
        value when is_float(value) -> value
        value when is_integer(value) -> value * 1.0
        _other -> :invalid
      end)

    if Enum.any?(values, &(&1 == :invalid)) do
      {:error, :provider_invalid_response}
    else
      {:ok, values}
    end
  end

  defp parse_vector(_embedding), do: {:error, :provider_invalid_response}
end
