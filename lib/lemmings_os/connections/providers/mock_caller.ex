defmodule LemmingsOs.Connections.Providers.MockCaller do
  @moduledoc """
  Deterministic mock provider caller used for connection validation tests.

  This caller resolves `secret_refs` just-in-time through Secret Bank and
  returns only sanitized test results.
  """

  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.SecretBank

  @required_mode "echo"

  @type call_error ::
          :unsupported_provider
          | :invalid_config
          | :missing_secret
          | :secret_resolution_failed

  @doc """
  Executes a deterministic mock validation for a connection.

  Success requires:
  - `type: "mock"`
  - `provider: "mock"`
  - `config["mode"] == "echo"`
  - `config["base_url"]` to be a non-empty string
  - `secret_refs` to include a resolvable `"api_key"` reference

  Returns sanitized metadata only.

  ## Examples

      iex> world = insert(:world)
      iex> {:ok, _metadata} = LemmingsOs.SecretBank.upsert_secret(world, "MOCK_API_KEY", "dev_only_value")
      iex> connection =
      ...>   build(:world_connection,
      ...>     world: world,
      ...>     type: "mock",
      ...>     provider: "mock",
      ...>     config: %{"mode" => "echo", "base_url" => "https://example.test"},
      ...>     secret_refs: %{"api_key" => "$MOCK_API_KEY"}
      ...>   )
      iex> {:ok, result} = LemmingsOs.Connections.Providers.MockCaller.call(world, connection)
      iex> result.outcome
      "mock_echo_ok"

      iex> world = insert(:world)
      iex> connection = build(:world_connection, world: world, type: "other", provider: "other")
      iex> LemmingsOs.Connections.Providers.MockCaller.call(world, connection)
      {:error, :unsupported_provider}
  """
  @spec call(map(), Connection.t()) :: {:ok, map()} | {:error, call_error()}
  def call(scope, %Connection{type: "mock", provider: "mock"} = connection) when is_map(scope) do
    with :ok <- validate_config(connection.config, connection.secret_refs),
         {:ok, resolved_count} <- resolve_secret_refs(scope, connection.secret_refs) do
      {:ok,
       %{
         mode: @required_mode,
         outcome: "mock_echo_ok",
         resolved_secret_count: resolved_count,
         secret_ref_keys: secret_ref_keys(connection.secret_refs)
       }}
    end
  end

  def call(_scope, %Connection{}), do: {:error, :unsupported_provider}

  defp validate_config(config, secret_refs) when is_map(config) and is_map(secret_refs) do
    with :ok <- validate_mode(config),
         :ok <- validate_base_url(config) do
      validate_required_secret_ref(secret_refs)
    end
  end

  defp validate_config(_config, _secret_refs), do: {:error, :invalid_config}

  defp validate_mode(%{"mode" => @required_mode}), do: :ok
  defp validate_mode(_config), do: {:error, :invalid_config}

  defp validate_base_url(%{"base_url" => base_url}) when is_binary(base_url) do
    case String.trim(base_url) do
      "" -> {:error, :invalid_config}
      _non_empty -> :ok
    end
  end

  defp validate_base_url(_config), do: {:error, :invalid_config}

  defp validate_required_secret_ref(secret_refs) do
    case Map.get(secret_refs, "api_key") || Map.get(secret_refs, :api_key) do
      ref when is_binary(ref) -> :ok
      _missing -> {:error, :invalid_config}
    end
  end

  defp resolve_secret_refs(scope, secret_refs) when is_map(secret_refs) do
    secret_refs
    |> Map.values()
    |> Enum.reduce_while({:ok, 0}, fn ref, {:ok, count} ->
      case resolve_ref(scope, ref) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_secret_refs(_scope, _secret_refs), do: {:error, :invalid_config}

  defp resolve_ref(scope, ref) when is_binary(ref) do
    case SecretBank.resolve_runtime_secret(scope, ref, tool_name: "connection_mock_test") do
      {:ok, _runtime_secret} -> :ok
      {:error, :missing_secret} -> {:error, :missing_secret}
      {:error, _reason} -> {:error, :secret_resolution_failed}
    end
  end

  defp resolve_ref(_scope, _ref), do: {:error, :invalid_config}

  defp secret_ref_keys(secret_refs) when is_map(secret_refs) do
    secret_refs
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp secret_ref_keys(_secret_refs), do: []
end
