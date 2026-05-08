defmodule LemmingsOs.Knowledge.SourceFiles.EmbeddingServiceTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Knowledge.SourceFiles.EmbeddingService

  setup do
    old = Application.get_env(:lemmings_os, :knowledge_embeddings, [])

    on_exit(fn ->
      Application.put_env(:lemmings_os, :knowledge_embeddings, old)
    end)

    :ok
  end

  test "fake provider is deterministic with 1536 dimensions" do
    Application.put_env(:lemmings_os, :knowledge_embeddings, provider: :fake, dimensions: 1536)

    assert {:ok, [first]} = EmbeddingService.embed_texts(["same text"])
    assert {:ok, [second]} = EmbeddingService.embed_texts(["same text"])

    assert first == second
    assert length(first) == 1536
  end

  test "openai-compatible provider requires configuration" do
    Application.put_env(:lemmings_os, :knowledge_embeddings,
      provider: :openai_compatible,
      base_url: nil,
      model: nil,
      api_key_env: nil
    )

    assert {:error, :provider_not_configured} = EmbeddingService.embed_texts(["hello"])
  end

  test "ollama provider alias uses openai-compatible configuration contract" do
    Application.put_env(:lemmings_os, :knowledge_embeddings,
      provider: :ollama,
      base_url: nil,
      model: nil,
      api_key_env: nil
    )

    assert {:error, :provider_not_configured} = EmbeddingService.embed_texts(["hello"])
  end

  test "ollama provider auto-aligns vector dimensions to configured size" do
    Application.put_env(:lemmings_os, :knowledge_embeddings,
      provider: :ollama,
      module: __MODULE__.MismatchEmbedder,
      dimensions: 5,
      base_url: "http://127.0.0.1:11434/v1",
      model: "nomic-embed-text",
      api_key_env: nil
    )

    assert {:ok, [vector]} = EmbeddingService.embed_texts(["hello"])
    assert length(vector) == 5
    assert Enum.take(vector, 3) == [0.1, 0.2, 0.3]
    assert Enum.drop(vector, 3) == [0.0, 0.0]
  end

  test "openai-compatible provider auto-aligns vector dimensions to configured size" do
    Application.put_env(:lemmings_os, :knowledge_embeddings,
      provider: :openai_compatible,
      module: __MODULE__.MismatchEmbedder,
      dimensions: 5,
      base_url: "http://127.0.0.1:11434/v1",
      model: "nomic-embed-text",
      api_key_env: nil
    )

    assert {:ok, [vector]} = EmbeddingService.embed_texts(["hello"])
    assert length(vector) == 5
    assert Enum.take(vector, 3) == [0.1, 0.2, 0.3]
    assert Enum.drop(vector, 3) == [0.0, 0.0]
  end

  test "dimensions converts numeric string config into integer" do
    Application.put_env(:lemmings_os, :knowledge_embeddings, dimensions: "1536")
    assert EmbeddingService.dimensions() == 1536
  end

  defmodule MismatchEmbedder do
    @spec embed_texts([String.t()], keyword()) ::
            {:ok, [[float()]]} | {:error, :provider_invalid_input}
    def embed_texts(texts, _opts) when is_list(texts) do
      {:ok, Enum.map(texts, fn _ -> [0.1, 0.2, 0.3] end)}
    end

    def embed_texts(_texts, _opts), do: {:error, :provider_invalid_input}
  end
end
