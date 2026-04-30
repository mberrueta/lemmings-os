defmodule LemmingsOs.Connections.TypeRegistry do
  @moduledoc """
  Catalog of supported Connection types and their configuration contracts.

  This module answers "how do I configure this Connection type?" for UI forms,
  schema validation, and runtime test dispatch. Each registered type delegates
  its label, default config example, config validation, test support, and caller
  implementation to its provider caller module.
  """

  alias LemmingsOs.Connections.Providers.MockCaller

  @entries [
    %{id: "mock", module: MockCaller}
  ]

  @doc """
  Lists registered connection type metadata for UI forms and validation.

  ## Examples

      iex> [type] = LemmingsOs.Connections.TypeRegistry.list_types()
      iex> type.id
      "mock"

      iex> [type] = LemmingsOs.Connections.TypeRegistry.list_types()
      iex> type.label
      "Mock"
  """
  @spec list_types() :: [map()]
  def list_types do
    Enum.map(@entries, fn %{id: id, module: module} ->
      %{
        id: id,
        label: module.label(),
        default_config: module.default_config_example(),
        test_supported?: module.test_supported?(),
        module: module
      }
    end)
  end

  @doc """
  Returns whether a type id is supported.

  ## Examples

      iex> LemmingsOs.Connections.TypeRegistry.supported_type?("mock")
      true

      iex> LemmingsOs.Connections.TypeRegistry.supported_type?("unknown")
      false

      iex> LemmingsOs.Connections.TypeRegistry.supported_type?(nil)
      false
  """
  @spec supported_type?(String.t() | nil) :: boolean()
  def supported_type?(type) when is_binary(type), do: not is_nil(module_for_type(type))
  def supported_type?(_type), do: false

  @doc """
  Returns the caller module for a type id.

  ## Examples

      iex> LemmingsOs.Connections.TypeRegistry.module_for_type("mock")
      LemmingsOs.Connections.Providers.MockCaller

      iex> LemmingsOs.Connections.TypeRegistry.module_for_type("unknown")
      nil
  """
  @spec module_for_type(String.t() | nil) :: module() | nil
  def module_for_type(type) when is_binary(type) do
    @entries
    |> Enum.find_value(fn %{id: id, module: module} -> if id == type, do: module end)
  end

  def module_for_type(_type), do: nil

  @doc """
  Validates a config map using the registered type module.

  ## Examples

      iex> LemmingsOs.Connections.TypeRegistry.validate_config("mock", %{
      ...>   "mode" => "echo",
      ...>   "base_url" => "https://example.test/mock",
      ...>   "api_key" => "$MOCK_API_KEY"
      ...> })
      :ok

      iex> LemmingsOs.Connections.TypeRegistry.validate_config("unknown", %{})
      {:error, :unsupported_type}

      iex> LemmingsOs.Connections.TypeRegistry.validate_config("mock", %{})
      {:error, :invalid_config}
  """
  @spec validate_config(String.t() | nil, map() | nil) :: :ok | {:error, atom()}
  def validate_config(type, config) when is_binary(type) and is_map(config) do
    case module_for_type(type) do
      nil -> {:error, :unsupported_type}
      module -> module.validate_config(config)
    end
  end

  def validate_config(_type, _config), do: {:error, :invalid_config}

  @doc """
  Returns default config for the given type.

  ## Examples

      iex> LemmingsOs.Connections.TypeRegistry.default_config_for("mock")
      %{
        "mode" => "echo",
        "base_url" => "https://example.test/mock",
        "api_key" => "$MOCK_API_KEY"
      }

      iex> LemmingsOs.Connections.TypeRegistry.default_config_for("unknown")
      %{}
  """
  @spec default_config_for(String.t()) :: map()
  def default_config_for(type) do
    case module_for_type(type) do
      nil -> %{}
      module -> module.default_config_example()
    end
  end
end
