defmodule LemmingsOs.Knowledge.SourceFiles.EmbeddingService do
  @moduledoc """
  Source-file embedding boundary with swappable providers.
  """

  alias LemmingsOs.Helpers
  alias LemmingsOs.Knowledge.SourceFiles.Embedders.Fake
  alias LemmingsOs.Knowledge.SourceFiles.Embedders.OpenAiCompatible

  @default_dimensions 1536
  @default_timeout_ms 30_000
  @default_provider :fake
  @type vector :: [float()]
  @type embed_error ::
          :provider_not_configured
          | :provider_http_error
          | :provider_timeout
          | :provider_network_error
          | :provider_invalid_response
          | :provider_invalid_dimension
          | :provider_invalid_input
  @type embed_result :: {:ok, [vector()]} | {:error, embed_error()}

  @doc """
  Returns one embedding vector for each text input.
  """
  @spec embed_texts([String.t()]) :: embed_result()
  def embed_texts(texts) when is_list(texts) do
    with {:ok, config} <- provider_config(),
         {:ok, provider_opts} <- provider_opts(config),
         {:ok, vectors} <- config.module.embed_texts(texts, provider_opts),
         :ok <- validate_dimensions(vectors, config.dimensions),
         true <- length(vectors) == length(texts) do
      {:ok, vectors}
    else
      false -> {:error, :provider_invalid_response}
      {:error, :invalid_input} -> {:error, :provider_invalid_input}
      {:error, :provider_not_configured} -> {:error, :provider_not_configured}
      {:error, :provider_timeout} -> {:error, :provider_timeout}
      {:error, :provider_network_error} -> {:error, :provider_network_error}
      {:error, :provider_http_error} -> {:error, :provider_http_error}
      {:error, :provider_invalid_response} -> {:error, :provider_invalid_response}
      {:error, :provider_invalid_dimension} -> {:error, :provider_invalid_dimension}
      _other -> {:error, :provider_invalid_response}
    end
  end

  def embed_texts(_texts), do: {:error, :provider_invalid_input}

  @doc """
  Configured embedding dimensions.
  """
  @spec dimensions() :: pos_integer()
  def dimensions do
    Application.get_env(:lemmings_os, :knowledge_embeddings, [])
    |> Keyword.get(:dimensions, @default_dimensions)
    |> parse_positive_integer(@default_dimensions)
  end

  defp provider_config do
    config = Application.get_env(:lemmings_os, :knowledge_embeddings, [])
    provider = Keyword.get(config, :provider, @default_provider)
    module = provider_module(provider)

    {:ok,
     %{
       provider: provider,
       module: Keyword.get(config, :module, module),
       dimensions: dimensions(),
       timeout_ms:
         parse_positive_integer(
           Keyword.get(config, :timeout_ms, @default_timeout_ms),
           @default_timeout_ms
         ),
       base_url: Keyword.get(config, :base_url),
       model: Keyword.get(config, :model),
       api_key_env: Keyword.get(config, :api_key_env),
       api_key: Keyword.get(config, :api_key)
     }}
  end

  defp provider_opts(%{provider: :fake, dimensions: dimensions}),
    do: {:ok, [dimensions: dimensions]}

  defp provider_opts(%{provider: :openai_compatible} = config) do
    api_key =
      case config.api_key do
        value when is_binary(value) and value != "" -> value
        _other -> fetch_env(config.api_key_env)
      end

    with {:ok, base_url} <- present(config.base_url),
         {:ok, model} <- present(config.model),
         {:ok, api_key} <- present(api_key) do
      {:ok,
       [
         base_url: base_url,
         model: model,
         api_key: api_key,
         timeout_ms: config.timeout_ms
       ]}
    else
      _ -> {:error, :provider_not_configured}
    end
  end

  defp provider_opts(_config), do: {:error, :provider_not_configured}

  defp provider_module(:fake), do: Fake
  defp provider_module("fake"), do: Fake
  defp provider_module(:openai_compatible), do: OpenAiCompatible
  defp provider_module("openai_compatible"), do: OpenAiCompatible
  defp provider_module(_other), do: Fake

  defp validate_dimensions(vectors, dimensions) do
    if Enum.all?(vectors, &(is_list(&1) and length(&1) == dimensions)) do
      :ok
    else
      {:error, :provider_invalid_dimension}
    end
  end

  defp parse_positive_integer(value, fallback) do
    case Helpers.parse_positive_integer(value) do
      {:ok, parsed} -> parsed
      :error -> fallback
    end
  end

  defp fetch_env(env_var) when is_binary(env_var) and env_var != "" do
    System.get_env(env_var)
  end

  defp fetch_env(_env_var), do: nil

  defp present(value) when is_binary(value) and value != "", do: {:ok, value}
  defp present(_value), do: :error
end
