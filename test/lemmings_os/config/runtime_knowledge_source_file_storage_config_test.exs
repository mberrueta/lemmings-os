defmodule LemmingsOs.Config.RuntimeKnowledgeSourceFileStorageConfigTest do
  use ExUnit.Case, async: false

  @runtime_config_path Path.expand("../../../config/runtime.exs", __DIR__)

  describe "knowledge source-file storage runtime env contract" do
    test "uses LEMMINGS_KNOWLEDGE_SOURCE_FILE_STORAGE_ROOT when set" do
      with_env(
        %{
          "LEMMINGS_KNOWLEDGE_SOURCE_FILE_STORAGE_ROOT" => "/tmp/knowledge-storage-root"
        },
        fn ->
          storage = runtime_storage_config()
          assert Keyword.get(storage, :root_path) == "/tmp/knowledge-storage-root"
        end
      )
    end

    test "keeps the default max file size when not overridden" do
      storage = runtime_storage_config()
      assert Keyword.get(storage, :max_file_size_bytes) == 10 * 1024 * 1024
    end
  end

  defp runtime_storage_config do
    {config, _imports} = Config.Reader.read_imports!(@runtime_config_path, env: :test)
    lemmings_os_config = Keyword.get(config, :lemmings_os, [])
    Keyword.get(lemmings_os_config, :knowledge_source_file_storage, [])
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
