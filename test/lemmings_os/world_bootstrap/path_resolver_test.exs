defmodule LemmingsOs.WorldBootstrap.PathResolverTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.WorldBootstrap.PathResolver

  describe "resolve/1" do
    test "prefers the env override when present" do
      assert PathResolver.resolve(env: "/tmp/custom.world.yaml", priv_dir: "/tmp/app_priv") == %{
               path: "/tmp/custom.world.yaml",
               source: "env_override"
             }
    end

    test "falls back to the shipped default file when the env override is missing" do
      assert PathResolver.resolve(env: nil, priv_dir: "/tmp/app_priv") == %{
               path: "/tmp/app_priv/default.world.yaml",
               source: "default_file"
             }
    end

    test "falls back to the shipped default file when the env override is blank" do
      assert PathResolver.resolve(env: "", priv_dir: "/tmp/app_priv") == %{
               path: "/tmp/app_priv/default.world.yaml",
               source: "default_file"
             }
    end
  end
end
