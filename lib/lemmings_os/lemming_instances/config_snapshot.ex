defmodule LemmingsOs.LemmingInstances.ConfigSnapshot do
  @moduledoc """
  Helpers for reading normalized values from persisted runtime config snapshots.

  Phase 1 keeps model-selection rules centralized here so the scheduler,
  executor, and `ModelRuntime` all reason about the same active provider/model
  choice.
  """

  @type model_selection :: %{
          profile: String.t() | nil,
          provider: String.t(),
          model: String.t(),
          resource_key: String.t()
        }

  @doc """
  Enriches a persisted config snapshot with the normalized active model contract.

  When an active selection can be derived, the snapshot gains a `model_runtime`
  sub-map with the selected profile, provider, model, and resource key. This
  gives downstream runtime components a stable contract to read from.
  """
  @spec enrich(map()) :: map()
  def enrich(config_snapshot) when is_map(config_snapshot) do
    case selection(config_snapshot) do
      %{profile: profile, provider: provider, model: model, resource_key: resource_key} ->
        model_runtime =
          config_snapshot
          |> direct_field(:model_runtime)
          |> normalize_model_runtime_map()
          |> Map.put(:provider, provider)
          |> Map.put(:model, model)
          |> Map.put(:resource_key, resource_key)
          |> maybe_put_profile(profile)

        Map.put(config_snapshot, :model_runtime, model_runtime)

      _ ->
        config_snapshot
    end
  end

  def enrich(config_snapshot), do: config_snapshot

  @doc """
  Returns the active provider/model selection for a config snapshot.

  Resolution precedence is:

  1. explicit normalized runtime fields (`resource_key`, `provider`, `model`,
     including nested `model_runtime`)
  2. `models_config.profiles.default`
  3. deterministic fallback to the first profile by sorted key

  This keeps the Phase 1 contract explicit and shared across runtime
  components until the resolver grows a dedicated active-profile field.
  """
  @spec selection(map()) :: model_selection() | nil
  def selection(config_snapshot) when is_map(config_snapshot) do
    explicit_selection(config_snapshot) || profile_selection(config_snapshot)
  end

  def selection(_config_snapshot), do: nil

  @doc """
  Extracts the selected provider name from a config snapshot.
  """
  @spec provider(map()) :: String.t() | nil
  def provider(config_snapshot) when is_map(config_snapshot),
    do: selection_value(selection(config_snapshot), :provider)

  def provider(_config_snapshot), do: nil

  @doc """
  Extracts the selected model name from a config snapshot.
  """
  @spec model(map()) :: String.t() | nil
  def model(config_snapshot) when is_map(config_snapshot),
    do: selection_value(selection(config_snapshot), :model) || direct_model(config_snapshot)

  def model(_config_snapshot), do: nil

  @doc """
  Extracts the selected `provider:model` resource key from a config snapshot.

  It uses the same centralized selection contract consumed by the runtime
  scheduler and `ModelRuntime`.

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
  def resource_key(config_snapshot) when is_map(config_snapshot),
    do: selection_value(selection(config_snapshot), :resource_key)

  def resource_key(_config_snapshot), do: nil

  defp explicit_selection(config_snapshot) do
    resource_key =
      direct_field(config_snapshot, :resource_key) ||
        nested_field(config_snapshot, [:model_runtime, :resource_key])

    provider =
      direct_field(config_snapshot, :provider) ||
        nested_field(config_snapshot, [:model_runtime, :provider])

    model =
      direct_field(config_snapshot, :model) ||
        nested_field(config_snapshot, [:model_runtime, :model])

    build_selection(provider, model, resource_key, nil)
  end

  defp profile_selection(config_snapshot) do
    config_snapshot
    |> snapshot_profiles()
    |> selected_profile()
    |> profile_selection_value()
  end

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
    case Map.get(profiles, :default) || Map.get(profiles, "default") do
      nil -> first_profile(profiles)
      default_profile -> {"default", default_profile}
    end
  end

  defp selected_profile(_profiles), do: nil

  defp first_profile(profiles) do
    profiles
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> List.first()
  end

  defp profile_selection_value({profile_name, %{} = profile}) do
    provider = Map.get(profile, :provider) || Map.get(profile, "provider")
    model = Map.get(profile, :model) || Map.get(profile, "model")

    build_selection(provider, model, nil, to_string(profile_name))
  end

  defp profile_selection_value(_profile), do: nil

  defp build_selection(provider, model, _resource_key, profile)
       when is_binary(provider) and is_binary(model) do
    %{
      profile: profile,
      provider: provider,
      model: model,
      resource_key: "#{provider}:#{model}"
    }
  end

  defp build_selection(_provider, _model, resource_key, profile) when is_binary(resource_key) do
    case String.split(resource_key, ":", parts: 2) do
      [provider, model] when provider != "" and model != "" ->
        %{
          profile: profile,
          provider: provider,
          model: model,
          resource_key: resource_key
        }

      _ ->
        nil
    end
  end

  defp build_selection(_provider, _model, _resource_key, _profile), do: nil

  defp direct_model(config_snapshot) do
    direct_field(config_snapshot, :default_model) ||
      nested_field(config_snapshot, [:model_runtime, :default_model])
  end

  defp selection_value(%{provider: provider}, :provider), do: provider
  defp selection_value(%{model: model}, :model), do: model
  defp selection_value(%{resource_key: resource_key}, :resource_key), do: resource_key
  defp selection_value(_selection, _field), do: nil

  defp normalize_model_runtime_map(%{} = model_runtime) do
    Map.new(model_runtime, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_model_runtime_map(_model_runtime), do: %{}

  defp maybe_put_profile(map, nil), do: map
  defp maybe_put_profile(map, profile), do: Map.put(map, :profile, profile)

  defp direct_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp nested_field(map, [key]) when is_map(map), do: direct_field(map, key)

  defp nested_field(map, [key | rest]) when is_map(map) do
    case direct_field(map, key) do
      nested when is_map(nested) -> nested_field(nested, rest)
      _ -> nil
    end
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key("profile"), do: :profile
  defp normalize_key("provider"), do: :provider
  defp normalize_key("model"), do: :model
  defp normalize_key("resource_key"), do: :resource_key
  defp normalize_key(key), do: key
end
