defmodule LemmingsOs.Connections do
  @moduledoc """
  Connection domain boundary.

  This context owns exact-scope connection CRUD, hierarchy visibility, and
  type-based runtime test execution.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Connections.TypeRegistry
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @test_succeeded "succeeded"
  @safe_test_error_reasons ~w(
    disabled
    invalid
    unsupported_type
    invalid_config
    missing_secret
    secret_resolution_failed
  )a

  @doc """
  Lists registered connection types for UI selection.

  ## Examples

      iex> [type] = LemmingsOs.Connections.list_connection_types()
      iex> type.id
      "mock"
  """
  @spec list_connection_types() :: [map()]
  def list_connection_types, do: TypeRegistry.list_types()

  @doc """
  Lists persisted connections at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.list_connections(%{})
      []
  """
  @spec list_connections(World.t() | City.t() | Department.t(), keyword()) :: [Connection.t()]
  def list_connections(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        Connection
        |> filter_query(scope_filters(scope_data) ++ opts)
        |> order_by([connection], asc: connection.inserted_at, asc: connection.id)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Returns one persisted local connection by id at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.get_connection(%{}, "connection-id")
      nil
  """
  @spec get_connection(World.t() | City.t() | Department.t(), Ecto.UUID.t(), keyword()) ::
          Connection.t() | nil
  def get_connection(scope, id, opts \\ []) when is_binary(id) and is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        Connection
        |> filter_query([{:id, id} | scope_filters(scope_data)] ++ opts)
        |> Repo.one()

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Returns one persisted local connection by type at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.get_connection_by_type(%{}, "mock")
      nil
  """
  @spec get_connection_by_type(
          World.t() | City.t() | Department.t(),
          String.t(),
          keyword()
        ) :: Connection.t() | nil
  def get_connection_by_type(scope, type, opts \\ []) when is_binary(type) and is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        Connection
        |> filter_query([{:type, type} | scope_filters(scope_data)] ++ opts)
        |> Repo.one()

      {:error, _reason} ->
        nil
    end
  end

  @doc """
  Lists visible connections for the caller scope using nearest-wins semantics.

  Read model rows contain:
  - `:connection` the persisted connection record
  - `:source_scope` one of `"world"`, `"city"`, `"department"`
  - `:local?` whether source matches caller exact scope
  - `:inherited?` inverse of `:local?`
  - `:scope_depth` lower is nearer (`0` local, then parents)

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.list_visible_connections(%{})
      []
  """
  @spec list_visible_connections(World.t() | City.t() | Department.t(), keyword()) :: [
          map()
        ]
  def list_visible_connections(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        scope_data
        |> visible_candidates(opts)
        |> Enum.reduce(%{}, fn candidate, acc ->
          Map.put_new(acc, candidate.connection.type, candidate)
        end)
        |> Map.values()
        |> Enum.sort_by(fn candidate -> {candidate.connection.type, candidate.scope_depth} end)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Resolves one visible connection read model by type with nearest-wins semantics.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.resolve_visible_connection(%{}, "mock")
      nil
  """
  @spec resolve_visible_connection(
          World.t() | City.t() | Department.t(),
          String.t(),
          keyword()
        ) :: map() | nil
  def resolve_visible_connection(scope, type, opts \\ [])
      when is_binary(type) and is_list(opts) do
    scope
    |> list_visible_connections(opts)
    |> Enum.find(fn candidate -> candidate.connection.type == type end)
  end

  @doc """
  Creates a connection at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> LemmingsOs.Connections.create_connection(%{}, %{})
      {:error, :invalid_scope}
  """
  @spec create_connection(World.t() | City.t() | Department.t(), map()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope}
  def create_connection(scope, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope) do
      changeset =
        %Connection{}
        |> Connection.changeset(connection_attrs(attrs, scope_data))

      Multi.new()
      |> Multi.insert(:connection, changeset)
      |> Multi.run(:event, fn _repo, %{connection: inserted_connection} ->
        Events.record_event(
          "connection.created",
          scope_data,
          created_message(inserted_connection),
          event_opts(inserted_connection, :created)
        )
      end)
      |> Repo.transaction()
      |> transaction_result()
    end
  end

  @doc """
  Updates a local connection at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{}
      iex> LemmingsOs.Connections.update_connection(%{}, connection, %{})
      {:error, :invalid_scope}
  """
  @spec update_connection(World.t() | City.t() | Department.t(), Connection.t(), map()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def update_connection(scope, %Connection{} = connection, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(connection, scope_data) do
      connection
      |> Connection.changeset(connection_attrs(attrs, scope_data))
      |> persist_with_event(scope_data, "connection.updated", &updated_message/1)
    end
  end

  @doc """
  Deletes a local connection at the exact requested scope.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{}
      iex> LemmingsOs.Connections.delete_connection(%{}, connection)
      {:error, :invalid_scope}
  """
  @spec delete_connection(World.t() | City.t() | Department.t(), Connection.t()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def delete_connection(scope, %Connection{} = connection) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(connection, scope_data) do
      Multi.new()
      |> Multi.delete(:connection, connection)
      |> Multi.run(:event, fn _repo, %{connection: deleted_connection} ->
        Events.record_event(
          "connection.deleted",
          scope_data,
          deleted_message(deleted_connection),
          event_opts(deleted_connection, :deleted)
        )
      end)
      |> Repo.transaction()
      |> transaction_result()
    end
  end

  @doc """
  Marks a local connection as enabled.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{}
      iex> LemmingsOs.Connections.enable_connection(%{}, connection)
      {:error, :invalid_scope}
  """
  @spec enable_connection(World.t() | City.t() | Department.t(), Connection.t()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def enable_connection(scope, %Connection{} = connection) do
    set_connection_status(scope, connection, "enabled", "connection.enabled", &enabled_message/1)
  end

  @doc """
  Marks a local connection as disabled.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{}
      iex> LemmingsOs.Connections.disable_connection(%{}, connection)
      {:error, :invalid_scope}
  """
  @spec disable_connection(World.t() | City.t() | Department.t(), Connection.t()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def disable_connection(scope, %Connection{} = connection) do
    set_connection_status(
      scope,
      connection,
      "disabled",
      "connection.disabled",
      &disabled_message/1
    )
  end

  @doc """
  Marks a local connection as invalid.

  Accepts `%World{}`, `%City{}`, or `%Department{}` scopes.

  ## Examples

      iex> connection = %LemmingsOs.Connections.Connection{}
      iex> LemmingsOs.Connections.mark_connection_invalid(%{}, connection)
      {:error, :invalid_scope}
  """
  @spec mark_connection_invalid(World.t() | City.t() | Department.t(), Connection.t()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def mark_connection_invalid(scope, %Connection{} = connection) do
    set_connection_status(
      scope,
      connection,
      "invalid",
      "connection.marked_invalid",
      &marked_invalid_message/1
    )
  end

  @doc """
  Tests one visible connection by type using the registered caller module.

  The resolved source connection row is always updated with `last_test`.

  ## Examples

      iex> LemmingsOs.Connections.test_connection(%{}, "mock")
      {:error, :invalid_scope}

      iex> LemmingsOs.Connections.test_connection(%{}, nil)
      {:error, :invalid_type}
  """
  @spec test_connection(World.t() | City.t() | Department.t(), String.t()) ::
          {:ok, %{connection: Connection.t(), result: map()}}
          | {:error,
             :invalid_scope
             | :invalid_type
             | :missing
             | :disabled
             | :invalid
             | :unsupported_type
             | :invalid_config
             | :missing_secret
             | :secret_resolution_failed
             | :provider_test_failed
             | Ecto.Changeset.t()}
  def test_connection(%World{} = scope, type) when is_binary(type) do
    do_test_connection(scope, type)
  end

  def test_connection(%City{} = scope, type) when is_binary(type) do
    do_test_connection(scope, type)
  end

  def test_connection(%Department{} = scope, type) when is_binary(type) do
    do_test_connection(scope, type)
  end

  def test_connection(_scope, type) when is_binary(type), do: {:error, :invalid_scope}
  def test_connection(_scope, _type), do: {:error, :invalid_type}

  defp do_test_connection(scope, type) do
    with {:ok, scope_data} <- scope_data(scope),
         {:ok, visible_row} <- visible_connection(scope, type),
         :ok <- record_test_started(visible_row.connection) do
      run_connection_test(scope_struct(scope_data), visible_row.connection)
    end
  end

  defp set_connection_status(scope, %Connection{} = connection, status, event_type, message_fun) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(connection, scope_data) do
      connection
      |> Connection.changeset(%{status: status})
      |> persist_with_event(scope_data, event_type, message_fun)
    end
  end

  defp persist_with_event(%Ecto.Changeset{} = changeset, scope_data, event_type, message_fun) do
    Multi.new()
    |> Multi.update(:connection, changeset)
    |> Multi.run(:event, fn _repo, %{connection: connection} ->
      Events.record_event(
        event_type,
        scope_data,
        message_fun.(connection),
        event_opts(connection, :updated)
      )
    end)
    |> Repo.transaction()
    |> transaction_result()
  end

  defp transaction_result({:ok, %{connection: %Connection{} = connection}}), do: {:ok, connection}
  defp transaction_result({:error, :connection, reason, _changes}), do: {:error, reason}
  defp transaction_result({:error, :event, reason, _changes}), do: {:error, reason}

  defp visible_connection(scope, type) do
    case resolve_visible_connection(scope, type) do
      %{connection: %Connection{}} = visible_row -> {:ok, visible_row}
      nil -> {:error, :missing}
    end
  end

  defp run_connection_test(secret_scope, %Connection{} = connection) do
    case provider_result(secret_scope, connection) do
      {:ok, %{} = result} ->
        persist_test_success(connection, result)

      {:error, reason} ->
        persist_test_failure(connection, reason)
    end
  end

  defp provider_result(_scope, %Connection{status: "disabled"}), do: {:error, :disabled}
  defp provider_result(_scope, %Connection{status: "invalid"}), do: {:error, :invalid}

  defp provider_result(scope, %Connection{type: type} = connection) do
    case TypeRegistry.module_for_type(type) do
      nil -> {:error, :unsupported_type}
      module -> module.call(scope, connection)
    end
  end

  defp persist_test_success(%Connection{} = connection, result) do
    safe_result = safe_test_result(result)

    summary =
      "#{@test_succeeded}: #{Map.get(safe_result, :outcome, "ok")}" |> sanitize_test_text()

    with {:ok, updated_connection} <-
           persist_test_outcome(connection, summary, "connection.test.succeeded", %{
             test_result: safe_result
           }) do
      {:ok, %{connection: updated_connection, result: safe_result}}
    end
  end

  defp persist_test_failure(%Connection{} = connection, reason) do
    safe_reason = safe_test_reason(reason)
    safe_error = safe_test_error(safe_reason)

    case persist_test_outcome(
           connection,
           "failed: #{safe_error}",
           "connection.test.failed",
           %{reason: safe_error}
         ) do
      {:ok, _updated_connection} -> {:error, safe_reason}
      {:error, persist_reason} -> {:error, persist_reason}
    end
  end

  defp persist_test_outcome(%Connection{} = connection, summary, event_type, payload) do
    changeset = Ecto.Changeset.change(connection, %{last_test: sanitize_test_text(summary)})

    Multi.new()
    |> Multi.update(:connection, changeset)
    |> Multi.run(:event, fn _repo, %{connection: updated_connection} ->
      Events.record_event(
        event_type,
        connection_scope_data(updated_connection),
        test_message(updated_connection),
        test_event_opts(updated_connection, payload)
      )
    end)
    |> Repo.transaction()
    |> transaction_result()
  end

  defp record_test_started(%Connection{} = connection) do
    case Events.record_event(
           "connection.test.started",
           connection_scope_data(connection),
           "Connection #{connection.type} test started",
           test_event_opts(connection, %{})
         ) do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_test_result(%{} = result) do
    %{
      outcome:
        safe_result_string(Map.get(result, :outcome) || Map.get(result, "outcome") || "ok"),
      mode: safe_result_string(Map.get(result, :mode) || Map.get(result, "mode")),
      resolved_secret_keys:
        safe_string_list(
          Map.get(result, :resolved_secret_keys) || Map.get(result, "resolved_secret_keys")
        )
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp safe_result_string(value) when is_binary(value), do: sanitize_test_text(value)
  defp safe_result_string(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_result_string(_value), do: nil

  defp safe_string_list(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&sanitize_test_text/1)
    |> Enum.sort()
  end

  defp safe_string_list(_values), do: nil

  defp safe_test_reason(reason) when reason in @safe_test_error_reasons, do: reason
  defp safe_test_reason(_reason), do: :provider_test_failed

  defp safe_test_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp sanitize_test_text(text) when is_binary(text), do: String.slice(text, 0, 500)

  defp validate_exact_scope(%Connection{} = connection, scope_data) do
    if connection_in_scope?(connection, scope_data) do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp connection_in_scope?(%Connection{} = connection, scope_data) do
    connection.world_id == scope_data.world_id and
      connection.city_id == scope_data.city_id and
      connection.department_id == scope_data.department_id
  end

  defp connection_attrs(attrs, scope_data) do
    attrs
    |> Map.put(:world_id, scope_data.world_id)
    |> Map.put(:city_id, scope_data.city_id)
    |> Map.put(:department_id, scope_data.department_id)
  end

  defp scope_filters(scope_data) do
    [
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id
    ]
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

  defp event_opts(%Connection{} = connection, action) do
    [
      action: Atom.to_string(action),
      status: connection.status,
      resource_type: "connection",
      resource_id: connection.id,
      payload: safe_payload(connection)
    ]
  end

  defp safe_payload(%Connection{} = connection) do
    %{
      connection_id: connection.id,
      connection_type: connection.type,
      status: connection.status,
      world_id: connection.world_id,
      city_id: connection.city_id,
      department_id: connection.department_id,
      config_keys: Map.keys(connection.config || %{}) |> Enum.map(&to_string/1) |> Enum.sort(),
      last_test: connection.last_test
    }
  end

  defp created_message(%Connection{} = connection),
    do: "Connection #{connection.type} created"

  defp updated_message(%Connection{} = connection),
    do: "Connection #{connection.type} updated"

  defp deleted_message(%Connection{} = connection),
    do: "Connection #{connection.type} deleted"

  defp enabled_message(%Connection{} = connection),
    do: "Connection #{connection.type} enabled"

  defp disabled_message(%Connection{} = connection),
    do: "Connection #{connection.type} disabled"

  defp marked_invalid_message(%Connection{} = connection),
    do: "Connection #{connection.type} marked invalid"

  defp test_message(%Connection{} = connection),
    do: "Connection #{connection.type} test recorded"

  defp test_event_opts(%Connection{} = connection, payload) do
    [
      action: "test",
      status: connection.status,
      resource_type: "connection",
      resource_id: connection.id,
      event_family: "telemetry",
      payload:
        Map.merge(
          safe_payload(connection),
          Map.merge(payload, %{last_test: connection.last_test})
        )
    ]
  end

  defp connection_scope_data(%Connection{} = connection) do
    %{
      world_id: connection.world_id,
      city_id: connection.city_id,
      department_id: connection.department_id
    }
  end

  defp scope_struct(%{world_id: world_id, city_id: nil, department_id: nil}),
    do: %World{id: world_id}

  defp scope_struct(%{world_id: world_id, city_id: city_id, department_id: nil}),
    do: %City{id: city_id, world_id: world_id}

  defp scope_struct(%{world_id: world_id, city_id: city_id, department_id: department_id}),
    do: %Department{id: department_id, city_id: city_id, world_id: world_id}

  defp visible_candidates(scope_data, opts) do
    scope_chain(scope_data)
    |> Enum.with_index()
    |> Enum.flat_map(fn {scope_entry, depth} ->
      Connection
      |> filter_query(scope_filters(scope_entry) ++ opts)
      |> Repo.all()
      |> Enum.map(&to_visible_candidate(&1, scope_data, depth))
    end)
    |> Enum.sort_by(fn candidate -> {candidate.scope_depth, candidate.connection.inserted_at} end)
  end

  defp to_visible_candidate(%Connection{} = connection, caller_scope_data, depth) do
    local? = connection_in_scope?(connection, caller_scope_data)

    %{
      connection: connection,
      source_scope: source_scope(connection),
      local?: local?,
      inherited?: not local?,
      scope_depth: depth
    }
  end

  defp source_scope(%Connection{city_id: nil, department_id: nil}), do: "world"

  defp source_scope(%Connection{city_id: city_id, department_id: nil}) when is_binary(city_id),
    do: "city"

  defp source_scope(%Connection{city_id: city_id, department_id: department_id})
       when is_binary(city_id) and is_binary(department_id),
       do: "department"

  defp scope_chain(%{world_id: world_id, city_id: nil, department_id: nil}) do
    [%{world_id: world_id, city_id: nil, department_id: nil}]
  end

  defp scope_chain(%{world_id: world_id, city_id: city_id, department_id: nil}) do
    [
      %{world_id: world_id, city_id: city_id, department_id: nil},
      %{world_id: world_id, city_id: nil, department_id: nil}
    ]
  end

  defp scope_chain(%{world_id: world_id, city_id: city_id, department_id: department_id}) do
    [
      %{world_id: world_id, city_id: city_id, department_id: department_id},
      %{world_id: world_id, city_id: city_id, department_id: nil},
      %{world_id: world_id, city_id: nil, department_id: nil}
    ]
  end

  defp filter_query(query, [{:id, id} | rest]),
    do: filter_query(from(connection in query, where: connection.id == ^id), rest)

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(connection in query, where: connection.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]) when is_binary(city_id),
    do: filter_query(from(connection in query, where: connection.city_id == ^city_id), rest)

  defp filter_query(query, [{:city_id, nil} | rest]),
    do: filter_query(from(connection in query, where: is_nil(connection.city_id)), rest)

  defp filter_query(query, [{:department_id, department_id} | rest])
       when is_binary(department_id),
       do:
         filter_query(
           from(connection in query, where: connection.department_id == ^department_id),
           rest
         )

  defp filter_query(query, [{:department_id, nil} | rest]),
    do: filter_query(from(connection in query, where: is_nil(connection.department_id)), rest)

  defp filter_query(query, [{:type, type} | rest]),
    do: filter_query(from(connection in query, where: connection.type == ^type), rest)

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(connection in query, where: connection.status == ^status), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(connection in query, where: connection.id in ^ids), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
