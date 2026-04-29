defmodule LemmingsOs.Connections.Runtime do
  @moduledoc """
  Runtime-facing connection resolver that returns safe descriptors only.

  This module resolves visibility and usability policy for a connection slug.
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
             :slug,
             :name,
             :type,
             :provider,
             :status,
             :source_scope,
             :local?,
             :inherited?,
             :config,
             :metadata,
             :secret_ref_keys
           ]}
  defstruct [
    :connection_id,
    :slug,
    :name,
    :type,
    :provider,
    :status,
    :source_scope,
    :local?,
    :inherited?,
    :config,
    :metadata,
    :secret_ref_keys
  ]

  @type descriptor :: %__MODULE__{
          connection_id: Ecto.UUID.t(),
          slug: String.t(),
          name: String.t(),
          type: String.t(),
          provider: String.t(),
          status: String.t(),
          source_scope: String.t(),
          local?: boolean(),
          inherited?: boolean(),
          config: map(),
          metadata: map(),
          secret_ref_keys: [String.t()]
        }

  @doc """
  Resolves one visible and usable connection descriptor for trusted execution.

  Emits safe events:
  - `connection.resolve.started`
  - `connection.resolve.succeeded`
  - `connection.resolve.failed`

  Returns:
  - `{:ok, descriptor}` for usable connections
  - `{:error, :missing | :inaccessible | :disabled | :invalid}` otherwise

  ## Examples

      iex> LemmingsOs.Connections.Runtime.resolve_connection(%{}, "github-main")
      {:error, :inaccessible}

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.Connections.Runtime.resolve_connection(world, "missing-slug")
      {:error, :missing}
  """
  @spec resolve_connection(World.t() | City.t() | Department.t() | map(), String.t(), keyword()) ::
          {:ok, descriptor()} | {:error, resolve_error()}
  def resolve_connection(scope, slug, opts \\ [])

  def resolve_connection(scope, slug, opts) when is_binary(slug) and is_list(opts) do
    scope_data = scope_data(scope)

    _ =
      record_event(
        "connection.resolve.started",
        scope_data,
        "Connection #{slug} resolve started",
        %{connection_slug: slug}
      )

    case scope_data do
      {:error, :invalid_scope} = error ->
        record_resolve_failed(scope, slug, :inaccessible)
        error_reason(error)

      {:ok, _} ->
        resolve_visible_connection(scope, slug)
    end
  end

  def resolve_connection(_scope, _slug, _opts), do: {:error, :inaccessible}

  defp resolve_visible_connection(scope, slug) do
    case Connections.resolve_visible_connection(scope, slug) do
      nil ->
        record_resolve_failed(scope, slug, :missing)
        {:error, :missing}

      %{connection: %Connection{status: "disabled"}} ->
        record_resolve_failed(scope, slug, :disabled)
        {:error, :disabled}

      %{connection: %Connection{status: "invalid"}} ->
        record_resolve_failed(scope, slug, :invalid)
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
      slug: connection.slug,
      name: connection.name,
      type: connection.type,
      provider: connection.provider,
      status: connection.status,
      source_scope: visible_row.source_scope,
      local?: visible_row.local?,
      inherited?: visible_row.inherited?,
      config: connection.config || %{},
      metadata: connection.metadata || %{},
      secret_ref_keys: Map.keys(connection.secret_refs || %{}) |> Enum.sort()
    }
  end

  defp record_resolve_succeeded(scope, descriptor) do
    record_event(
      "connection.resolve.succeeded",
      scope_data(scope),
      "Connection #{descriptor.slug} resolve succeeded",
      %{
        connection_id: descriptor.connection_id,
        connection_slug: descriptor.slug,
        connection_type: descriptor.type,
        provider: descriptor.provider,
        status: descriptor.status,
        source_scope: descriptor.source_scope,
        local?: descriptor.local?
      }
    )
  end

  defp record_resolve_failed(scope, slug, reason) do
    record_event(
      "connection.resolve.failed",
      scope_data(scope),
      "Connection #{slug} resolve failed",
      %{connection_slug: slug, reason: Atom.to_string(reason)}
    )
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

  defp scope_data(%{} = scope) do
    world_id = fetch(scope, :world_id)
    city_id = fetch(scope, :city_id)
    department_id = fetch(scope, :department_id)

    if valid_scope_shape?(world_id, city_id, department_id) do
      {:ok, %{world_id: world_id, city_id: city_id, department_id: department_id}}
    else
      {:error, :invalid_scope}
    end
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp valid_scope_shape?(world_id, nil, nil) when is_binary(world_id), do: true

  defp valid_scope_shape?(world_id, city_id, nil) when is_binary(world_id) and is_binary(city_id),
    do: true

  defp valid_scope_shape?(world_id, city_id, department_id)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id),
       do: true

  defp valid_scope_shape?(_world_id, _city_id, _department_id), do: false

  defp fetch(scope, key) when is_map(scope) do
    Map.get(scope, key) || Map.get(scope, Atom.to_string(key))
  end
end
