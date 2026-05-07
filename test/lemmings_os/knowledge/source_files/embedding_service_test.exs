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

  test "dimensions converts numeric string config into integer" do
    Application.put_env(:lemmings_os, :knowledge_embeddings, dimensions: "1536")
    assert EmbeddingService.dimensions() == 1536
  end
end
