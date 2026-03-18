defmodule LemmingsOs.Cities do
  @moduledoc """
  City domain boundary.

  This context owns persisted City retrieval, World-scoped CRUD APIs, and the
  narrow runtime presence helpers used by startup and heartbeat flows.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.City
  alias LemmingsOs.Repo
  alias LemmingsOs.World

  @doc """
  Returns persisted cities for the given World scope.

  Accepts an optional keyword list for filtering and explicit preloads.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.Factory.insert(:city, world: world, status: "active")
      iex> cities = LemmingsOs.Cities.list_cities(world)
      iex> length(cities)
      1
  """
  @spec list_cities(World.t() | Ecto.UUID.t(), keyword()) :: [City.t()]
  def list_cities(world_or_world_id, opts \\ [])

  def list_cities(%World{} = world, opts) do
    world
    |> list_cities_query(opts)
    |> Repo.all()
  end

  def list_cities(world_id, opts) when is_binary(world_id) do
    world_id
    |> list_cities_query(opts)
    |> Repo.all()
  end

  @doc """
  Returns the base City query for the given World scope.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.Cities.list_cities_query(world) |> Ecto.Query.exclude(:preload) |> Map.has_key?(:from)
      true
  """
  @spec list_cities_query(World.t() | Ecto.UUID.t(), keyword()) :: Ecto.Query.t()
  def list_cities_query(%World{id: world_id}, opts), do: list_cities_query(world_id, opts)

  def list_cities_query(world_id, opts) when is_binary(world_id) do
    City
    |> where([city], city.world_id == ^world_id)
    |> filter_query(opts)
    |> order_by([city], asc: city.inserted_at, asc: city.id)
  end

  @doc """
  Returns the City for the given World-scoped persisted ID.

  Raises `Ecto.NoResultsError` if no City exists in that World.
  """
  @spec get_city!(World.t(), Ecto.UUID.t()) :: City.t()
  def get_city!(%World{} = world, id) do
    case fetch_city(world, id) do
      {:ok, city} -> city
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: City
    end
  end

  @doc """
  Fetches a City by World-scoped persisted ID.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> {:ok, fetched_city} = LemmingsOs.Cities.fetch_city(world, city.id)
      iex> fetched_city.id == city.id
      true
  """
  @spec fetch_city(World.t(), Ecto.UUID.t()) :: {:ok, City.t()} | {:error, :not_found}
  def fetch_city(%World{id: world_id}, id) when is_binary(id) do
    City
    |> where([city], city.world_id == ^world_id and city.id == ^id)
    |> Repo.one()
    |> fetch_city_result()
  end

  @doc """
  Returns a City by World-scoped slug, or `nil` when it does not exist.
  """
  @spec get_city_by_slug(World.t(), String.t()) :: City.t() | nil
  def get_city_by_slug(%World{id: world_id}, slug) when is_binary(slug) do
    Repo.get_by(City, world_id: world_id, slug: slug)
  end

  @doc """
  Creates a City scoped to the given World.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> {:ok, city} = LemmingsOs.Cities.create_city(world, %{slug: "ops", name: "Ops", node_name: "ops@localhost", status: "active"})
      iex> city.world_id == world.id
      true
  """
  @spec create_city(World.t(), map()) :: {:ok, City.t()} | {:error, Ecto.Changeset.t()}
  def create_city(%World{id: world_id}, attrs) when is_map(attrs) do
    %City{world_id: world_id}
    |> City.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a persisted City through the operator-facing CRUD contract.
  """
  @spec update_city(City.t(), map()) :: {:ok, City.t()} | {:error, Ecto.Changeset.t()}
  def update_city(%City{} = city, attrs) when is_map(attrs) do
    city
    |> City.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a persisted City record.
  """
  @spec delete_city(City.t()) :: {:ok, City.t()} | {:error, Ecto.Changeset.t()}
  def delete_city(%City{} = city), do: Repo.delete(city)

  @doc """
  Creates or updates the runtime-owned City row for the given World.

  Lookup prefers persisted `id`, then `node_name`, then `slug`. This keeps the
  runtime presence contract narrow without reshaping the normal CRUD API.
  """
  @spec upsert_runtime_city(World.t(), map()) :: {:ok, City.t()} | {:error, Ecto.Changeset.t()}
  def upsert_runtime_city(%World{} = world, attrs) when is_map(attrs) do
    world
    |> runtime_lookup_target(attrs)
    |> City.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Persists the latest heartbeat timestamp for a City.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> seen_at = DateTime.utc_now() |> DateTime.truncate(:second)
      iex> {:ok, updated_city} = LemmingsOs.Cities.heartbeat_city(city, seen_at)
      iex> updated_city.last_seen_at == seen_at
      true
  """
  @spec heartbeat_city(City.t(), DateTime.t()) :: {:ok, City.t()} | {:error, Ecto.Changeset.t()}
  def heartbeat_city(%City{} = city, seen_at \\ DateTime.utc_now()) do
    city
    |> Ecto.Changeset.change(last_seen_at: DateTime.truncate(seen_at, :second))
    |> Repo.update()
  end

  @doc """
  Returns Cities whose heartbeat is older than the given cutoff.
  """
  @spec stale_cities(World.t(), DateTime.t()) :: [City.t()]
  def stale_cities(%World{id: world_id}, cutoff) do
    City
    |> where([city], city.world_id == ^world_id)
    |> where([city], not is_nil(city.last_seen_at) and city.last_seen_at < ^cutoff)
    |> order_by([city], asc: city.last_seen_at, asc: city.id)
    |> Repo.all()
  end

  defp fetch_city_result(%City{} = city), do: {:ok, city}
  defp fetch_city_result(nil), do: {:error, :not_found}

  defp runtime_lookup_target(%World{id: world_id}, attrs) do
    lookup_runtime_city_by_id(world_id, attr_value(attrs, :id)) ||
      lookup_runtime_city_by_node_name(world_id, attr_value(attrs, :node_name)) ||
      lookup_runtime_city_by_slug(world_id, attr_value(attrs, :slug)) ||
      %City{world_id: world_id}
  end

  defp lookup_runtime_city_by_id(_world_id, id) when not is_binary(id), do: nil

  defp lookup_runtime_city_by_id(world_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, persisted_id} ->
        Repo.get_by(City, id: persisted_id, world_id: world_id)

      :error ->
        nil
    end
  end

  defp lookup_runtime_city_by_node_name(_world_id, node_name)
       when not is_binary(node_name) or node_name == "",
       do: nil

  defp lookup_runtime_city_by_node_name(world_id, node_name) do
    Repo.get_by(City, world_id: world_id, node_name: node_name)
  end

  defp lookup_runtime_city_by_slug(_world_id, slug) when not is_binary(slug) or slug == "",
    do: nil

  defp lookup_runtime_city_by_slug(world_id, slug) do
    Repo.get_by(City, world_id: world_id, slug: slug)
  end

  defp attr_value(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(city in query, where: city.status == ^status), rest)

  defp filter_query(query, [{:node_name, node_name} | rest]),
    do: filter_query(from(city in query, where: city.node_name == ^node_name), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(city in query, where: city.id in ^ids), rest)

  defp filter_query(query, [{:stale_before, %DateTime{} = cutoff} | rest]) do
    filter_query(
      from(city in query, where: not is_nil(city.last_seen_at) and city.last_seen_at < ^cutoff),
      rest
    )
  end

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
