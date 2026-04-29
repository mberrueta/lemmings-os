defmodule LemmingsOs.Connections do
  @moduledoc """
  Connection domain boundary.

  This context owns exact-scope connection CRUD and explicit status transitions.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Lists persisted connections at the exact requested scope.

  Supports `%World{}`, `%City{}`, `%Department{}`, or scope maps with
  `world_id`, `city_id`, and `department_id` keys.

  ## Examples

      iex> LemmingsOs.Connections.list_connections(%{})
      []
  """
  @spec list_connections(World.t() | City.t() | Department.t() | map(), keyword()) ::
          [Connection.t()]
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
  """
  @spec get_connection(World.t() | City.t() | Department.t() | map(), Ecto.UUID.t(), keyword()) ::
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
  Returns one persisted local connection by slug at the exact requested scope.
  """
  @spec get_connection_by_slug(
          World.t() | City.t() | Department.t() | map(),
          String.t(),
          keyword()
        ) ::
          Connection.t() | nil
  def get_connection_by_slug(scope, slug, opts \\ []) when is_binary(slug) and is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        Connection
        |> filter_query([{:slug, slug} | scope_filters(scope_data)] ++ opts)
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
  """
  @spec list_visible_connections(World.t() | City.t() | Department.t() | map(), keyword()) :: [
          map()
        ]
  def list_visible_connections(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        scope_data
        |> visible_candidates(opts)
        |> Enum.reduce(%{}, fn candidate, acc ->
          Map.put_new(acc, candidate.connection.slug, candidate)
        end)
        |> Map.values()
        |> Enum.sort_by(fn candidate -> {candidate.connection.slug, candidate.scope_depth} end)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Resolves one visible connection read model by slug with nearest-wins semantics.
  """
  @spec resolve_visible_connection(
          World.t() | City.t() | Department.t() | map(),
          String.t(),
          keyword()
        ) :: map() | nil
  def resolve_visible_connection(scope, slug, opts \\ [])
      when is_binary(slug) and is_list(opts) do
    scope
    |> list_visible_connections(opts)
    |> Enum.find(fn candidate -> candidate.connection.slug == slug end)
  end

  @doc """
  Creates a connection at the exact requested scope.
  """
  @spec create_connection(World.t() | City.t() | Department.t() | map(), map()) ::
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
  """
  @spec update_connection(World.t() | City.t() | Department.t() | map(), Connection.t(), map()) ::
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
  """
  @spec delete_connection(World.t() | City.t() | Department.t() | map(), Connection.t()) ::
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
  """
  @spec enable_connection(World.t() | City.t() | Department.t() | map(), Connection.t()) ::
          {:ok, Connection.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def enable_connection(scope, %Connection{} = connection) do
    set_connection_status(scope, connection, "enabled", "connection.enabled", &enabled_message/1)
  end

  @doc """
  Marks a local connection as disabled.
  """
  @spec disable_connection(World.t() | City.t() | Department.t() | map(), Connection.t()) ::
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
  """
  @spec mark_connection_invalid(World.t() | City.t() | Department.t() | map(), Connection.t()) ::
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
      connection_slug: connection.slug,
      connection_name: connection.name,
      connection_type: connection.type,
      provider: connection.provider,
      status: connection.status,
      world_id: connection.world_id,
      city_id: connection.city_id,
      department_id: connection.department_id,
      config_keys: Map.keys(connection.config || %{}) |> Enum.sort(),
      secret_ref_keys: Map.keys(connection.secret_refs || %{}) |> Enum.sort(),
      metadata_keys: Map.keys(connection.metadata || %{}) |> Enum.sort()
    }
  end

  defp created_message(%Connection{} = connection),
    do: "Connection #{connection.slug} created"

  defp updated_message(%Connection{} = connection),
    do: "Connection #{connection.slug} updated"

  defp deleted_message(%Connection{} = connection),
    do: "Connection #{connection.slug} deleted"

  defp enabled_message(%Connection{} = connection),
    do: "Connection #{connection.slug} enabled"

  defp disabled_message(%Connection{} = connection),
    do: "Connection #{connection.slug} disabled"

  defp marked_invalid_message(%Connection{} = connection),
    do: "Connection #{connection.slug} marked invalid"

  defp fetch(scope, key) when is_map(scope) do
    Map.get(scope, key) || Map.get(scope, Atom.to_string(key))
  end

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

  defp filter_query(query, [{:slug, slug} | rest]),
    do: filter_query(from(connection in query, where: connection.slug == ^slug), rest)

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(connection in query, where: connection.status == ^status), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(connection in query, where: connection.id in ^ids), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
