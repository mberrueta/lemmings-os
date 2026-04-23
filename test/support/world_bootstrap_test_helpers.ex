defmodule LemmingsOs.WorldBootstrapTestHelpers do
  @moduledoc false

  def valid_bootstrap_yaml do
    "priv/default.world.yaml"
    |> Path.expand(File.cwd!())
    |> File.read!()
  end

  def valid_bootstrap_config do
    {:ok, config} = YamlElixir.read_from_string(valid_bootstrap_yaml())
    config
  end

  def write_temp_file!(contents, suffix \\ ".yaml") do
    path =
      Path.join(
        System.tmp_dir!(),
        "world-bootstrap-#{System.unique_integer([:positive])}#{suffix}"
      )

    File.write!(path, contents)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end
end
