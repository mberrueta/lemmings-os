defmodule LemmingsOs.LemmingInstances.ConfigSnapshot do
  @moduledoc """
  Helpers for reading normalized values from persisted runtime config snapshots.
  """

  @doc """
  Extracts the selected `provider:model` resource key from a config snapshot.

  It prefers the `default` profile when present and otherwise falls back to the
  first profile name in sorted order.

  ## Examples

      iex> LemmingsOs.LemmingInstances.ConfigSnapshot.resource_key(%{
      ...>   models_config: %{profiles: %{default: %{provider: "ollama", model: "qwen2.5:7b"}}}
      ...> })
      "ollama:qwen2.5:7b"

      iex> LemmingsOs.LemmingInstances.ConfigSnapshot.resource_key(%{
      ...>   "models_config" => %{
      ...>     "profiles" => %{"secondary" => %{"provider" => "openai", "model" => "gpt-4.1-mini"}}
      ...>   }
      ...> })
      "openai:gpt-4.1-mini"

      iex> LemmingsOs.LemmingInstances.ConfigSnapshot.resource_key(%{})
      nil
  """
  @spec resource_key(map()) :: String.t() | nil
  def resource_key(config_snapshot) when is_map(config_snapshot) do
    config_snapshot
    |> snapshot_profiles()
    |> selected_profile()
    |> profile_resource_key()
  end

  def resource_key(_config_snapshot), do: nil

  defp snapshot_profiles(config_snapshot) do
    models_config =
      Map.get(config_snapshot, :models_config) ||
        Map.get(config_snapshot, "models_config") ||
        %{}

    Map.get(models_config, :profiles) ||
      Map.get(models_config, "profiles") ||
      %{}
  end

  defp selected_profile(profiles) when is_map(profiles) do
    Map.get(profiles, :default) ||
      Map.get(profiles, "default") ||
      first_profile(profiles)
  end

  defp selected_profile(_profiles), do: nil

  defp first_profile(profiles) do
    profiles
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> List.first()
    |> elem_or_nil(1)
  end

  defp profile_resource_key(%{} = profile) do
    provider = Map.get(profile, :provider) || Map.get(profile, "provider")
    model = Map.get(profile, :model) || Map.get(profile, "model")

    if is_binary(provider) and is_binary(model), do: "#{provider}:#{model}", else: nil
  end

  defp profile_resource_key(_profile), do: nil

  defp elem_or_nil(nil, _index), do: nil
  defp elem_or_nil(tuple, index), do: elem(tuple, index)
end
