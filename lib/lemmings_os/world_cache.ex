defmodule LemmingsOs.WorldCache do
  @moduledoc """
  Narrow Cachex-backed cache for persisted World reads.

  This cache stores stable read results for the World domain only. It is not the
  source of truth and does not cache broader configuration resolution or page
  snapshots.
  """

  @cache_name __MODULE__
  @default_key :default_world

  @type cache_key :: :default_world | {:world, Ecto.UUID.t()}

  @doc """
  Starts the World cache process.
  """
  @spec start_link(keyword()) :: Supervisor.on_start_child()
  def start_link(opts \\ []), do: Cachex.start_link(@cache_name, opts)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: @cache_name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Returns the cached world lookup for the given id or computes it on miss.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.WorldCache.invalidate_all()
      iex> {:ok, fetched_world} =
      ...>   LemmingsOs.WorldCache.fetch_world(world.id, fn -> {:ok, world} end)
      iex> fetched_world.id == world.id
      true
  """
  @spec fetch_world(Ecto.UUID.t(), (-> term())) :: term()
  def fetch_world(id, loader) when is_binary(id) and is_function(loader, 0) do
    fetch({:world, id}, loader)
  end

  @doc """
  Returns the cached default world lookup or computes it on miss.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.WorldCache.invalidate_all()
      iex> {:ok, default_world} =
      ...>   LemmingsOs.WorldCache.fetch_default_world(fn -> {:ok, world} end)
      iex> default_world.id == world.id
      true
  """
  @spec fetch_default_world((-> term())) :: term()
  def fetch_default_world(loader) when is_function(loader, 0), do: fetch(@default_key, loader)

  @doc """
  Invalidates the cached value for the given world id.
  """
  @spec invalidate_world(Ecto.UUID.t()) :: :ok
  def invalidate_world(id) when is_binary(id), do: delete({:world, id})

  @doc """
  Invalidates the cached default world lookup.
  """
  @spec invalidate_default_world() :: :ok
  def invalidate_default_world, do: delete(@default_key)

  @doc """
  Clears the whole World cache.
  """
  @spec invalidate_all() :: :ok
  def invalidate_all do
    {:ok, _count} = Cachex.clear(@cache_name)
    :ok
  end

  defp fetch(key, loader) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        result = loader.()

        case result do
          {:ok, _} -> put_and_return(key, result)
          _ -> result
        end

      {:ok, value} ->
        value
    end
  end

  defp put_and_return(key, value) do
    {:ok, true} = Cachex.put(@cache_name, key, value)
    value
  end

  defp delete(key) do
    {:ok, _deleted?} = Cachex.del(@cache_name, key)
    :ok
  end
end
