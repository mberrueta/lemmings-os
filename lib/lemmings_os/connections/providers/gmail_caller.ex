defmodule LemmingsOs.Connections.Providers.GmailCaller do
  @moduledoc """
  Gmail connection config contract for OAuth-backed draft creation.
  """

  alias LemmingsOs.Connections.Connection

  @compose_scope "https://www.googleapis.com/auth/gmail.compose"
  @required_keys ~w(provider scopes client_id client_secret)
  @optional_keys ~w(account_email refresh_token)
  @allowed_keys @required_keys ++ @optional_keys
  @secret_ref_keys ~w(client_id client_secret refresh_token)

  @doc """
  Returns the stable type identifier handled by this provider.

  ## Examples

      iex> LemmingsOs.Connections.Providers.GmailCaller.type_id()
      "gmail"
  """
  @spec type_id() :: String.t()
  def type_id, do: "gmail"

  @doc """
  Returns a human label for UI surfaces.
  """
  @spec label() :: String.t()
  def label, do: "Gmail"

  @doc """
  Returns an editable default config example.
  """
  @spec default_config_example() :: map()
  def default_config_example do
    %{
      "provider" => "gmail",
      "account_email" => "",
      "scopes" => [@compose_scope],
      "client_id" => "$GMAIL_CLIENT_ID",
      "client_secret" => "$GMAIL_CLIENT_SECRET"
    }
  end

  @doc """
  Indicates this type does not support generic runtime connection tests.
  """
  @spec test_supported?() :: boolean()
  def test_supported?, do: false

  @doc """
  Validates Gmail config structure and secret references.
  """
  @spec validate_config(map()) :: :ok | {:error, :invalid_config}
  def validate_config(config) when is_map(config) do
    with :ok <- validate_keys(config),
         :ok <- validate_provider(config),
         :ok <- validate_scopes(config),
         :ok <- validate_secret_refs(config),
         :ok <- validate_account_email(config) do
      :ok
    else
      _ -> {:error, :invalid_config}
    end
  end

  def validate_config(_config), do: {:error, :invalid_config}

  @doc """
  Gmail is exercised through dedicated OAuth and draft APIs.
  """
  @spec call(map(), Connection.t()) :: {:error, :unsupported_type}
  def call(_scope, %Connection{}), do: {:error, :unsupported_type}

  @spec compose_scope() :: String.t()
  def compose_scope, do: @compose_scope

  defp validate_keys(config) do
    keys = Map.keys(config)

    with true <- Enum.all?(@required_keys, &Map.has_key?(config, &1)),
         true <- Enum.all?(keys, &(&1 in @allowed_keys)) do
      :ok
    else
      _ -> {:error, :invalid_config}
    end
  end

  defp validate_provider(%{"provider" => "gmail"}), do: :ok
  defp validate_provider(_config), do: {:error, :invalid_config}

  defp validate_scopes(%{"scopes" => [@compose_scope]}), do: :ok
  defp validate_scopes(_config), do: {:error, :invalid_config}

  defp validate_secret_refs(config) do
    config
    |> Map.take(@secret_ref_keys)
    |> Enum.reduce_while(:ok, fn {_key, value}, :ok ->
      case value do
        "$" <> rest when rest != "" -> {:cont, :ok}
        _ -> {:halt, {:error, :invalid_config}}
      end
    end)
  end

  defp validate_account_email(%{"account_email" => email}) when is_binary(email), do: :ok
  defp validate_account_email(%{}), do: :ok
end
