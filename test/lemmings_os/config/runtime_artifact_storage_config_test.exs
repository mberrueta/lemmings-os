defmodule LemmingsOs.Config.RuntimeArtifactStorageConfigTest do
  use ExUnit.Case, async: false

  @runtime_config_path Path.expand("../../../config/runtime.exs", __DIR__)

  describe "artifact storage runtime env contract" do
    test "uses LEMMINGS_ARTIFACT_STORAGE_ROOT when set" do
      with_env(
        %{
          "LEMMINGS_ARTIFACT_STORAGE_ROOT" => "/tmp/artifacts-root"
        },
        fn ->
          storage = runtime_artifact_storage_config()
          assert Keyword.get(storage, :root_path) == "/tmp/artifacts-root"
        end
      )
    end

    test "keeps the default max file size when not overridden" do
      storage = runtime_artifact_storage_config()
      assert Keyword.get(storage, :max_file_size_bytes) == 100 * 1024 * 1024
    end
  end

  defp runtime_artifact_storage_config do
    {config, _imports} = Config.Reader.read_imports!(@runtime_config_path, env: :test)
    lemmings_os_config = Keyword.get(config, :lemmings_os, [])
    Keyword.get(lemmings_os_config, :artifact_storage, [])
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
