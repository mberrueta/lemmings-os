defmodule LemmingsOs.Worlds do
  @moduledoc """
  World domain boundary.

  This context owns persisted World retrieval and the minimal bootstrap-facing
  upsert contract needed by the world-management implementation.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.{Repo, World}

  @doc """
  Returns the world for the given persisted ID.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> fetched_world = LemmingsOs.Worlds.get_world!(world.id)
      iex> fetched_world.id == world.id
      true
  """
  @spec get_world!(Ecto.UUID.t()) :: World.t()
  def get_world!(id), do: Repo.get!(World, id)

  @doc """
  Fetches a world by persisted ID.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> {:ok, fetched_world} = LemmingsOs.Worlds.fetch_world(world.id)
      iex> fetched_world.slug == world.slug
      true

      iex> LemmingsOs.Worlds.fetch_world(Ecto.UUID.generate())
      {:error, :not_found}
  """
  @spec fetch_world(Ecto.UUID.t()) :: {:ok, World.t()} | {:error, :not_found}
  def fetch_world(id), do: fetch_world_result(Repo.get(World, id))

  @doc """
  Returns the default world for the current node.

  This task keeps the default-world contract minimal by selecting the oldest
  persisted world when one exists.

  ## Examples

      iex> LemmingsOs.Repo.delete_all(LemmingsOs.World)
      iex> world = LemmingsOs.Factory.insert(:world)
      iex> {:ok, default_world} = LemmingsOs.Worlds.get_default_world()
      iex> default_world.id == world.id
      true
  """
  @spec get_default_world() :: {:ok, World.t()} | {:error, :not_found}
  def get_default_world do
    query =
      World
      |> order_by([world], asc: world.inserted_at, asc: world.id)
      |> limit(1)

    query
    |> Repo.one()
    |> fetch_world_result()
  end

  @doc """
  Creates or updates a world from persisted or bootstrap-facing attributes.

  Upsert matching prefers persisted `id`, then `bootstrap_path`, then `slug`.
  That keeps bootstrap sync idempotent without treating the bootstrap payload
  as the persisted source of truth.

  ## Examples

      iex> attrs = LemmingsOs.Factory.params_for(:world, name: "Doc World")
      iex> {:ok, world} = LemmingsOs.Worlds.upsert_world(attrs)
      iex> {world.name, world.status, world.last_import_status}
      {"Doc World", "unknown", "unknown"}

      iex> attrs = LemmingsOs.Factory.params_for(:world, name: "Before")
      iex> {:ok, world} = LemmingsOs.Worlds.upsert_world(attrs)
      iex> {:ok, updated_world} =
      ...>   LemmingsOs.Worlds.upsert_world(%{
      ...>     "slug" => world.slug,
      ...>     "bootstrap_path" => world.bootstrap_path,
      ...>     "name" => "After"
      ...>   })
      iex> updated_world.id == world.id and updated_world.name == "After"
      true
  """
  @spec upsert_world(map()) :: {:ok, World.t()} | {:error, Ecto.Changeset.t()}
  def upsert_world(attrs) when is_map(attrs) do
    attrs
    |> bootstrap_lookup_target()
    |> World.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Creates or updates a world using the bootstrap sync contract.

  ## Examples

      iex> attrs = LemmingsOs.Factory.params_for(:world, name: "Bootstrap World")
      iex> {:ok, world} = LemmingsOs.Worlds.upsert_bootstrap_world(attrs)
      iex> world.name
      "Bootstrap World"
  """
  @spec upsert_bootstrap_world(map()) :: {:ok, World.t()} | {:error, Ecto.Changeset.t()}
  def upsert_bootstrap_world(attrs), do: upsert_world(attrs)

  defp bootstrap_lookup_target(attrs), do: lookup_world(attrs) || %World{}

  defp fetch_world_result(%World{} = world), do: {:ok, world}
  defp fetch_world_result(nil), do: {:error, :not_found}

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
end
