defmodule LemmingsOs.Connections.Providers.MockCaller do
  @moduledoc """
  Deterministic mock connection caller.

  It resolves secret references from configured `config` keys just-in-time
  through Secret Bank and returns sanitized results only.
  """

  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.SecretBank

  @required_mode "echo"
  @secret_ref_keys ["api_key"]

  @type call_error ::
          :disabled
          | :invalid
          | :unsupported_type
          | :invalid_config
          | :missing_secret
          | :secret_resolution_failed

  @doc """
  Returns the stable type identifier handled by this caller.

  ## Examples

      iex> LemmingsOs.Connections.Providers.MockCaller.type_id()
      "mock"
  """
  @spec type_id() :: String.t()
  def type_id, do: "mock"

  @doc """
  Returns a human label for UI surfaces.

  ## Examples

      iex> LemmingsOs.Connections.Providers.MockCaller.label()
      "Mock"
  """
  @spec label() :: String.t()
  def label, do: "Mock"

  @doc """
  Returns an editable default config example.

  ## Examples

      iex> LemmingsOs.Connections.Providers.MockCaller.default_config_example()
      %{
        "mode" => "echo",
        "base_url" => "https://example.test/mock",
        "api_key" => "$MOCK_API_KEY"
      }
  """
  @spec default_config_example() :: map()
  def default_config_example do
    %{
      "mode" => "echo",
      "base_url" => "https://example.test/mock",
      "api_key" => "$MOCK_API_KEY"
    }
  end

  @doc """
  Indicates this type supports runtime test execution.

  ## Examples

      iex> LemmingsOs.Connections.Providers.MockCaller.test_supported?()
      true
  """
  @spec test_supported?() :: boolean()
  def test_supported?, do: true

  @doc """
  Validates mock config structure.

  ## Examples

      iex> LemmingsOs.Connections.Providers.MockCaller.validate_config(%{
      ...>   "mode" => "echo",
      ...>   "base_url" => "https://example.test/mock",
      ...>   "api_key" => "$MOCK_API_KEY"
      ...> })
      :ok

      iex> LemmingsOs.Connections.Providers.MockCaller.validate_config(%{
      ...>   "mode" => "echo",
      ...>   "base_url" => "https://example.test/mock",
      ...>   "api_key" => "raw-secret"
      ...> })
      {:error, :invalid_config}

      iex> LemmingsOs.Connections.Providers.MockCaller.validate_config(%{})
      {:error, :invalid_config}
  """
  @spec validate_config(map()) :: :ok | {:error, :invalid_config}
  def validate_config(config) when is_map(config) do
    with :ok <- validate_mode(config),
         :ok <- validate_base_url(config),
         :ok <- validate_secret_ref(config, "api_key") do
      :ok
    else
      _ -> {:error, :invalid_config}
    end
  end

  def validate_config(_config), do: {:error, :invalid_config}

  @doc """
  Executes deterministic mock behavior for connection tests.

  The caller resolves Secret Bank references at execution time. Invalid config
  fails before any secret resolution is attempted.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{
      ...>   type: "mock",
      ...>   config: %{
      ...>     "mode" => "echo",
      ...>     "base_url" => "https://example.test/mock",
      ...>     "api_key" => "raw-secret"
      ...>   }
      ...> }
      iex> LemmingsOs.Connections.Providers.MockCaller.call(%{}, connection)
      {:error, :invalid_config}

      iex> connection = %LemmingsOs.Connections.Connection{type: "unknown", config: %{}}
      iex> LemmingsOs.Connections.Providers.MockCaller.call(%{}, connection)
      {:error, :unsupported_type}
  """
  @spec call(map(), Connection.t()) :: {:ok, map()} | {:error, call_error()}
  def call(_scope, %Connection{status: "disabled"}), do: {:error, :disabled}
  def call(_scope, %Connection{status: "invalid"}), do: {:error, :invalid}

  def call(scope, %Connection{type: "mock", config: config}) when is_map(scope) do
    with :ok <- validate_config(config),
         {:ok, resolved_secret_keys} <- resolve_secret_refs(scope, config) do
      {:ok,
       %{
         outcome: "mock_echo_ok",
         mode: @required_mode,
         resolved_secret_keys: resolved_secret_keys
       }}
    end
  end

  def call(_scope, %Connection{}), do: {:error, :unsupported_type}

  defp resolve_secret_refs(scope, config) do
    Enum.reduce_while(@secret_ref_keys, {:ok, []}, fn key, {:ok, acc} ->
      resolve_secret_ref_key(scope, config, key, acc)
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.sort(keys)}
      error -> error
    end
  end

  defp resolve_secret_ref_key(scope, config, key, acc) do
    with ref when is_binary(ref) <- Map.get(config, key),
         :ok <- resolve_ref(scope, ref) do
      {:cont, {:ok, [key | acc]}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
      _ -> {:halt, {:error, :invalid_config}}
    end
  end

  defp resolve_ref(scope, ref) do
    case SecretBank.resolve_runtime_secret(scope, ref, tool_name: "connection_mock_test") do
      {:ok, _runtime_secret} -> :ok
      {:error, :missing_secret} -> {:error, :missing_secret}
      {:error, _reason} -> {:error, :secret_resolution_failed}
    end
  end

  defp validate_mode(%{"mode" => @required_mode}), do: :ok
  defp validate_mode(_config), do: {:error, :invalid_config}

  defp validate_base_url(%{"base_url" => base_url}) when is_binary(base_url) do
    if String.trim(base_url) == "", do: {:error, :invalid_config}, else: :ok
  end

  defp validate_base_url(_config), do: {:error, :invalid_config}

  defp validate_secret_ref(config, key) do
    case Map.get(config, key) do
      "$" <> bank_key when bank_key != "" -> :ok
      _ -> {:error, :invalid_config}
    end
  end
end
