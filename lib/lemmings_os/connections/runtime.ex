defmodule LemmingsOs.Connections.Runtime do
  @moduledoc """
  Runtime-facing connection resolver that returns safe descriptors only.

  This module resolves visibility and usability policy for a connection type.
  It does not resolve Secret Bank references and never returns raw credentials.
  """

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.Worlds.World

  @type resolve_error :: :missing | :inaccessible | :disabled | :invalid

  @derive {Inspect,
           only: [
             :connection_id,
             :type,
             :status,
             :source_scope,
             :local?,
             :inherited?
           ]}
  defstruct [
    :connection_id,
    :type,
    :status,
    :source_scope,
    :local?,
    :inherited?,
    :config
  ]

  @type descriptor :: %__MODULE__{
          connection_id: Ecto.UUID.t(),
          type: String.t(),
          status: String.t(),
          source_scope: String.t(),
          local?: boolean(),
          inherited?: boolean(),
          config: map()
        }

  @doc """
  Resolves one visible and usable connection descriptor for trusted execution.

  Returns:
  - `{:ok, descriptor}` for usable connections
  - `{:error, :missing | :inaccessible | :disabled | :invalid}` otherwise
  """
  @spec resolve_connection(World.t() | City.t() | Department.t(), String.t(), keyword()) ::
          {:ok, descriptor()} | {:error, resolve_error()}
  def resolve_connection(scope, type, opts \\ [])

  def resolve_connection(scope, type, opts) when is_binary(type) and is_list(opts) do
    scope_data = scope_data(scope)

    _ =
      record_event(
        "connection.resolve.started",
        scope_data,
        "Connection #{type} resolve started",
        %{connection_type: type}
      )

    case scope_data do
      {:error, :invalid_scope} = error ->
        record_resolve_failed(scope, type, :inaccessible)
        error_reason(error)

      {:ok, _} ->
        resolve_visible_connection(scope, type)
    end
  end

  def resolve_connection(_scope, _type, _opts), do: {:error, :inaccessible}

  defp resolve_visible_connection(scope, type) do
    case Connections.resolve_visible_connection(scope, type) do
      nil ->
        record_resolve_failed(scope, type, :missing)
        {:error, :missing}

      %{connection: %Connection{status: "disabled"} = connection} ->
        record_resolve_failed(scope, type, :disabled, connection)
        {:error, :disabled}

      %{connection: %Connection{status: "invalid"} = connection} ->
        record_resolve_failed(scope, type, :invalid, connection)
        {:error, :invalid}

      %{} = visible_row ->
        descriptor = to_descriptor(visible_row)

        record_resolve_succeeded(scope, descriptor)
        {:ok, descriptor}
    end
  end

  defp to_descriptor(%{connection: %Connection{} = connection} = visible_row) do
    %__MODULE__{
      connection_id: connection.id,
      type: connection.type,
      status: connection.status,
      source_scope: visible_row.source_scope,
      local?: visible_row.local?,
      inherited?: visible_row.inherited?,
      config: connection.config || %{}
    }
  end

  defp record_resolve_succeeded(scope, descriptor) do
    record_event(
      "connection.resolve.succeeded",
      scope_data(scope),
      "Connection #{descriptor.type} resolve succeeded",
      %{
        connection_id: descriptor.connection_id,
        connection_type: descriptor.type,
        status: descriptor.status,
        source_scope: descriptor.source_scope,
        local?: descriptor.local?
      }
    )
  end

  defp record_resolve_failed(scope, type, reason),
    do: record_resolve_failed(scope, type, reason, nil)

  defp record_resolve_failed(scope, type, reason, connection) do
    record_event(
      "connection.resolve.failed",
      scope_data(scope),
      "Connection #{type} resolve failed",
      resolve_failed_payload(type, reason, connection)
    )
  end

  defp resolve_failed_payload(_type, reason, %Connection{} = connection) do
    %{
      connection_id: connection.id,
      connection_type: connection.type,
      status: connection.status,
      reason: Atom.to_string(reason)
    }
  end

  defp resolve_failed_payload(type, reason, nil) do
    %{
      connection_id: nil,
      connection_type: type,
      status: nil,
      reason: Atom.to_string(reason)
    }
  end

  defp error_reason({:error, :invalid_scope}), do: {:error, :inaccessible}

  defp record_event(_event_type, {:error, :invalid_scope}, _message, _payload), do: :ok

  defp record_event(event_type, {:ok, scope_data}, message, payload) do
    Events.record_event(event_type, scope_data, message,
      payload: payload,
      event_family: "telemetry"
    )
  end

  defp scope_data(%World{id: world_id}) when is_binary(world_id),
    do: {:ok, %{world_id: world_id, city_id: nil, department_id: nil}}

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id),
       do: {:ok, %{world_id: world_id, city_id: city_id, department_id: nil}}

  defp scope_data(%Department{id: department_id, city_id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id),
       do: {:ok, %{world_id: world_id, city_id: city_id, department_id: department_id}}

  defp scope_data(_scope), do: {:error, :invalid_scope}
end
