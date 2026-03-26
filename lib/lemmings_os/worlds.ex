defmodule LemmingsOs.Worlds do
  @moduledoc """
  World domain boundary.

  This context owns persisted World retrieval and the minimal bootstrap-facing
  upsert contract needed by the world-management implementation.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  @doc """
  Returns all persisted worlds.

  Accepts an optional keyword list for filtering.
  """
  @spec list_worlds(keyword()) :: [World.t()]
  def list_worlds(opts \\ []) do
    World
    |> filter_query(opts)
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the world for the given persisted ID, or `nil` when missing.

  Results are served from `Worlds.Cache`. The cache is invalidated automatically
  on upsert, so callers may receive a cached value until the next write or
  explicit `Worlds.Cache.invalidate_world/1` call.
  """
  @spec get_world(Ecto.UUID.t()) :: World.t() | nil
  def get_world(id) do
    case Cache.fetch_world(id, fn -> Repo.get(World, id) |> normalize_world_result() end) do
      {:ok, world} -> world
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Returns the default world for the current node, or `nil` when none exists.

  This keeps the default-world contract minimal by selecting the oldest
  persisted world when one exists.
  """
  @spec get_default_world() :: World.t() | nil
  def get_default_world do
    case Cache.fetch_default_world(fn ->
           query =
             World
             |> order_by([world], asc: world.inserted_at, asc: world.id)
             |> limit(1)

           query
           |> Repo.one()
           |> normalize_world_result()
         end) do
      {:ok, world} -> world
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Creates or updates a world from persisted or bootstrap-facing attributes.

  Upsert matching prefers persisted `id`, then `bootstrap_path`, then `slug`.
  """
  @spec upsert_world(map()) :: {:ok, World.t()} | {:error, Ecto.Changeset.t()}
  def upsert_world(attrs) when is_map(attrs) do
    attrs
    |> bootstrap_lookup_target()
    |> World.changeset(attrs)
    |> Repo.insert_or_update()
    |> invalidate_cached_reads()
  end

  @doc """
  Creates or updates a world using the bootstrap sync contract.
  """
  @spec upsert_bootstrap_world(map()) :: {:ok, World.t()} | {:error, Ecto.Changeset.t()}
  def upsert_bootstrap_world(attrs), do: upsert_world(attrs)

  @doc """
  Updates an existing world located by the bootstrap lookup chain.

  Unlike `upsert_world/1`, this function never inserts a new record.
  """
  @spec update_existing_world(map()) ::
          {:ok, World.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_existing_world(attrs) when is_map(attrs) do
    case lookup_world(attrs) do
      nil ->
        {:error, :not_found}

      existing_world ->
        existing_world
        |> World.changeset(attrs)
        |> Repo.update()
        |> invalidate_cached_reads()
    end
  end

  defp bootstrap_lookup_target(attrs), do: lookup_world(attrs) || %World{}

  defp invalidate_cached_reads({:ok, %World{id: id} = world}) do
    Cache.invalidate_world(id)
    Cache.invalidate_default_world()
    {:ok, world}
  end

  defp invalidate_cached_reads({:error, _changeset} = error), do: error

  defp normalize_world_result(%World{} = world), do: {:ok, world}
  defp normalize_world_result(nil), do: {:error, :not_found}

  defp lookup_world(attrs), do: lookup_world_by_id(attr_value(attrs, :id), attrs)

  defp lookup_world_by_id(id, attrs) when is_binary(id),
    do: lookup_world_by_id_cast(Ecto.UUID.cast(id), attrs)

  defp lookup_world_by_id(_, attrs), do: lookup_world_by_bootstrap_path(attrs)

  defp lookup_world_by_id_cast({:ok, persisted_id}, attrs),
    do: Repo.get(World, persisted_id) || lookup_world_by_bootstrap_path(attrs)

  defp lookup_world_by_id_cast(:error, attrs), do: lookup_world_by_bootstrap_path(attrs)

  defp attr_value(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp lookup_world_by_bootstrap_path(attrs),
    do: lookup_world_by_bootstrap_path_value(attr_value(attrs, :bootstrap_path), attrs)

  defp lookup_world_by_bootstrap_path_value(path, _attrs) when is_binary(path) and path != "",
    do: Repo.get_by(World, bootstrap_path: path)

  defp lookup_world_by_bootstrap_path_value(_, attrs), do: lookup_world_by_slug(attrs)

  defp lookup_world_by_slug(attrs), do: lookup_world_by_slug_value(attr_value(attrs, :slug))

  defp lookup_world_by_slug_value(slug) when is_binary(slug) and slug != "",
    do: Repo.get_by(World, slug: slug)

  defp lookup_world_by_slug_value(_), do: nil

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(w in query, where: w.status == ^status), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
