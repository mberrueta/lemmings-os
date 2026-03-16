defmodule LemmingsOs.WorldBootstrap.PathResolver do
  @moduledoc """
  Resolves the bootstrap YAML path for the World bootstrap layer.

  `LEMMINGS_WORLD_BOOTSTRAP_PATH` takes precedence. When the env var is missing
  or blank, the resolver falls back to the shipped `priv/default.world.yaml`.
  """

  @bootstrap_env_var "LEMMINGS_WORLD_BOOTSTRAP_PATH"
  @default_filename "default.world.yaml"

  @type resolved_path :: %{path: String.t(), source: String.t()}

  @doc """
  Resolves the bootstrap YAML path.

  ## Examples

      iex> LemmingsOs.WorldBootstrap.PathResolver.resolve(
      ...>   env: "/tmp/custom.world.yaml",
      ...>   priv_dir: "/tmp/priv"
      ...> )
      %{path: "/tmp/custom.world.yaml", source: "env_override"}

      iex> LemmingsOs.WorldBootstrap.PathResolver.resolve(env: nil, priv_dir: "/tmp/priv")
      %{path: "/tmp/priv/default.world.yaml", source: "default_file"}
  """
  @spec resolve(keyword()) :: resolved_path()
  def resolve(opts \\ []) do
    opts
    |> env_override()
    |> resolve_path(opts)
  end

  defp env_override(opts),
    do: Keyword.get_lazy(opts, :env, fn -> System.get_env(@bootstrap_env_var) end)

  defp resolve_path(path, _opts) when is_binary(path) and path != "",
    do: %{path: path, source: "env_override"}

  defp resolve_path(_, opts), do: %{path: default_path(opts), source: "default_file"}

  defp default_path(opts), do: Path.join(priv_dir(opts), @default_filename)

  defp priv_dir(opts), do: Keyword.get_lazy(opts, :priv_dir, &default_priv_dir/0)

  defp default_priv_dir do
    :lemmings_os
    |> :code.priv_dir()
    |> List.to_string()
  end
end
