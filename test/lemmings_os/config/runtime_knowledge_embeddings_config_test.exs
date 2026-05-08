defmodule LemmingsOs.Config.RuntimeKnowledgeEmbeddingsConfigTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Helpers

  @runtime_config_path Path.expand("../../../config/runtime.exs", __DIR__)

  describe "knowledge embeddings runtime env contract" do
    test "uses embedding env vars when set" do
      with_env(
        %{
          "LEMMINGS_KNOWLEDGE_EMBEDDING_PROVIDER" => "openai_compatible",
          "LEMMINGS_KNOWLEDGE_EMBEDDING_DIMENSIONS" => "2048",
          "LEMMINGS_KNOWLEDGE_EMBEDDING_TIMEOUT_MS" => "15000",
          "LEMMINGS_KNOWLEDGE_EMBEDDING_BASE_URL" => "http://localhost:11434/v1",
          "LEMMINGS_KNOWLEDGE_EMBEDDING_MODEL" => "text-embedding-3-large",
          "LEMMINGS_KNOWLEDGE_EMBEDDING_API_KEY_ENV" => "CUSTOM_API_KEY_ENV"
        },
        fn ->
          embeddings = runtime_embeddings_config()
          assert Keyword.get(embeddings, :provider) == "openai_compatible"
          assert Keyword.get(embeddings, :dimensions) == "2048"
          assert Keyword.get(embeddings, :timeout_ms) == "15000"
          assert Keyword.get(embeddings, :base_url) == "http://localhost:11434/v1"
          assert Keyword.get(embeddings, :model) == "text-embedding-3-large"
          assert Keyword.get(embeddings, :api_key_env) == "CUSTOM_API_KEY_ENV"
        end
      )
    end

    test "keeps defaults when env vars are not set" do
      with_env(
        %{
          "LEMMINGS_KNOWLEDGE_EMBEDDING_PROVIDER" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_DIMENSIONS" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_TIMEOUT_MS" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_BASE_URL" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_MODEL" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_API_KEY_ENV" => nil,
          "LEMMINGS_KNOWLEDGE_EMBEDDING_API_KEY" => nil
        },
        fn ->
          embeddings = runtime_embeddings_config()

          assert Keyword.get(embeddings, :provider) in [
                   "ollama",
                   :ollama,
                   "openai_compatible",
                   :openai_compatible
                 ]

          assert {:ok, 1536} =
                   Helpers.parse_positive_integer(Keyword.get(embeddings, :dimensions))

          assert {:ok, 30_000} =
                   Helpers.parse_positive_integer(Keyword.get(embeddings, :timeout_ms))

          assert Keyword.get(embeddings, :base_url) == "http://127.0.0.1:11434/v1"
          assert Keyword.get(embeddings, :model) == "nomic-embed-text"
          assert Keyword.get(embeddings, :api_key_env) == "OPENAI_API_KEY"
        end
      )
    end
  end

  defp runtime_embeddings_config do
    {config, _imports} = Config.Reader.read_imports!(@runtime_config_path, env: :test)
    lemmings_os_config = Keyword.get(config, :lemmings_os, [])
    Keyword.get(lemmings_os_config, :knowledge_embeddings, [])
  end

  defp with_env(changes, fun) do
    previous = Map.new(changes, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(changes, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
