defmodule LemmingsOs.Cities.Runtime do
  @moduledoc """
  Resolves and attaches the local runtime City identity at startup.

  This module keeps the startup contract narrow:

  - resolve the persisted default World
  - resolve the local runtime City identity from runtime configuration
  - upsert the matching City row for the local node

  It does not perform discovery, clustering, or remote node management.
  """

  require Logger

  alias Ecto.Changeset
  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds

  @type runtime_city_attrs :: %{
          required(:slug) => String.t(),
          required(:name) => String.t(),
          required(:node_name) => String.t(),
          required(:status) => String.t(),
          optional(:host) => String.t() | nil,
          optional(:distribution_port) => integer() | nil,
          optional(:epmd_port) => integer() | nil
        }

  @doc """
  Resolves runtime City attributes from application configuration.

  `node_name` is the canonical runtime identity and must be the full BEAM node
  name in `name@host` form. `slug` and `name` may be overridden explicitly, but
  default to values derived from `node_name`.
  """
  @spec runtime_city_attrs(keyword()) :: runtime_city_attrs()
  def runtime_city_attrs(opts \\ []) do
    config = Keyword.get(opts, :config, runtime_city_config())
    node_name = Map.fetch!(config, :node_name)
    slug = Map.get(config, :slug) || derive_slug(node_name)

    %{
      slug: slug,
      name: Map.get(config, :name) || derive_name(slug),
      node_name: node_name,
      host: Map.get(config, :host) || derive_host(node_name),
      distribution_port: Map.get(config, :distribution_port),
      epmd_port: Map.get(config, :epmd_port),
      status: "active"
    }
  end

  @doc """
  Creates or updates the local runtime City row for the default World.

  Returns `{:error, :default_world_not_found}` when no persisted World can be
  resolved at startup.
  """
  @spec sync_runtime_city(keyword()) ::
          {:ok, City.t()} | {:error, :default_world_not_found | Changeset.t()}
  def sync_runtime_city(opts \\ []) do
    case Worlds.get_default_world() do
      {:ok, %World{} = world} ->
        world
        |> Cities.upsert_runtime_city(runtime_city_attrs(opts))
        |> log_sync_result(world)

      {:error, :not_found} ->
        {:error, :default_world_not_found}
    end
  end

  @doc """
  Creates or updates the local runtime City row for the default World.

  Raises when startup cannot resolve a World or when the runtime City attrs are
  invalid for persistence.
  """
  @spec sync_runtime_city!(keyword()) :: City.t()
  def sync_runtime_city!(opts \\ []) do
    case sync_runtime_city(opts) do
      {:ok, city} ->
        city

      {:error, :default_world_not_found} ->
        raise "runtime city startup failed: no persisted default world could be resolved"

      {:error, %Changeset{} = changeset} ->
        raise "runtime city startup failed: #{inspect(changeset.errors)}"
    end
  end

  @doc """
  Fetches the persisted local runtime City row for the default World.

  Lookup is read-only and matches by the configured runtime `node_name`.
  """
  @spec fetch_runtime_city(keyword()) ::
          {:ok, City.t()} | {:error, :default_world_not_found | :runtime_city_not_found}
  def fetch_runtime_city(opts \\ []) do
    runtime_city_attrs = runtime_city_attrs(opts)

    case Worlds.get_default_world() do
      {:ok, %World{} = world} ->
        case Cities.list_cities(world, node_name: runtime_city_attrs.node_name) do
          [%City{} = city] -> {:ok, city}
          [] -> {:error, :runtime_city_not_found}
        end

      {:error, :not_found} ->
        {:error, :default_world_not_found}
    end
  end

  defp runtime_city_config do
    Application.get_env(:lemmings_os, :runtime_city, %{})
  end

  defp log_sync_result({:ok, %City{} = city}, %World{} = world) do
    Logger.info("runtime city attached",
      event: "runtime_city.attach",
      status: city.status,
      world_id: world.id,
      city_id: city.id,
      node_name: city.node_name
    )

    {:ok, city}
  end

  defp log_sync_result({:error, %Changeset{} = changeset}, _world), do: {:error, changeset}

  defp derive_slug(node_name) do
    node_name
    |> String.split("@")
    |> List.first()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp derive_name(slug) do
    slug
    |> String.split("-", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp derive_host(node_name) do
    case String.split(node_name, "@", parts: 2) do
      [_name, host] -> host
      _parts -> nil
    end
  end
end
