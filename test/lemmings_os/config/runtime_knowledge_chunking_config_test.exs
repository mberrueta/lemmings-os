defmodule LemmingsOs.Config.RuntimeKnowledgeChunkingConfigTest do
  use ExUnit.Case, async: false

  @runtime_config_path Path.expand("../../../config/runtime.exs", __DIR__)

  describe "knowledge chunking runtime env contract" do
    test "uses chunking env vars when set" do
      with_env(
        %{
          "LEMMINGS_KNOWLEDGE_CHUNK_SIZE" => "1400",
          "LEMMINGS_KNOWLEDGE_CHUNK_OVERLAP" => "250",
          "LEMMINGS_KNOWLEDGE_MAX_CHUNKS" => "321"
        },
        fn ->
          chunking = runtime_chunking_config()
          assert Keyword.get(chunking, :chunk_size) == "1400"
          assert Keyword.get(chunking, :overlap) == "250"
          assert Keyword.get(chunking, :max_chunks) == "321"
        end
      )
    end

    test "keeps defaults when env vars are not set" do
      chunking = runtime_chunking_config()
      assert Keyword.get(chunking, :chunk_size) == 1_200
      assert Keyword.get(chunking, :overlap) == 200
      assert Keyword.get(chunking, :max_chunks) == 500
    end
  end

  defp runtime_chunking_config do
    {config, _imports} = Config.Reader.read_imports!(@runtime_config_path, env: :test)
    lemmings_os_config = Keyword.get(config, :lemmings_os, [])
    Keyword.get(lemmings_os_config, :knowledge_chunking, [])
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
