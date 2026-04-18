defmodule LemmingsOs.Config.Resolver do
  @moduledoc """
  Resolves effective configuration for persisted World, City, Department, and
  Lemming scopes.

  The resolver is intentionally pure and in-memory. Callers must provide any
  required parent chain, such as `%City{world: %World{}}` or
  `%Department{city: %City{world: %World{}}}` or
  `%Lemming{department: %Department{city: %City{world: %World{}}}}`, before
  calling it.
  """

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  @type resolved_config :: %{
          limits_config: LimitsConfig.t(),
          runtime_config: RuntimeConfig.t(),
          costs_config: CostsConfig.t(),
          models_config: ModelsConfig.t()
        }

  @type resolved_lemming_config :: %{
          limits_config: LimitsConfig.t(),
          runtime_config: RuntimeConfig.t(),
          costs_config: CostsConfig.t(),
          models_config: ModelsConfig.t(),
          tools_config: ToolsConfig.t()
        }

  @doc """
  Returns the effective configuration for a World, City, Department, or
  Lemming scope.

  For `%World{}`, the resolver returns the persisted config buckets as-is.

  For `%City{world: %World{}}`, the resolver performs an in-memory
  child-overrides-parent merge. The parent World must already be loaded on the
  City struct; the resolver performs no database access.

  For `%Department{city: %City{world: %World{}}}`, the resolver performs an
  additive in-memory merge in `World -> City -> Department` order. The full
  parent chain must already be loaded on the Department struct; the resolver
  performs no database access.

  ## Examples

      iex> world = LemmingsOs.Factory.build(:world)
      iex> resolved = LemmingsOs.Config.Resolver.resolve(world)
      iex> match?(%{limits_config: %LemmingsOs.Config.LimitsConfig{}}, resolved)
      true
  """
  @spec resolve(World.t() | City.t() | Department.t()) :: resolved_config()
  @spec resolve(Lemming.t()) :: resolved_lemming_config()
  def resolve(scope)

  @spec resolve(World.t()) :: resolved_config()
  def resolve(%World{} = world) do
    %{
      limits_config: world.limits_config || %LimitsConfig{},
      runtime_config: world.runtime_config || %RuntimeConfig{},
      costs_config: world.costs_config || %CostsConfig{budgets: %Budgets{}},
      models_config: world.models_config || %ModelsConfig{}
    }
  end

  @spec resolve(City.t()) :: resolved_config()
  def resolve(%City{world: %World{} = world} = city) do
    world_config = resolve(world)

    %{
      limits_config: merge_bucket(world_config.limits_config, city.limits_config, LimitsConfig),
      runtime_config:
        merge_bucket(world_config.runtime_config, city.runtime_config, RuntimeConfig),
      costs_config: merge_bucket(world_config.costs_config, city.costs_config, CostsConfig),
      models_config: merge_bucket(world_config.models_config, city.models_config, ModelsConfig)
    }
  end

  @spec resolve(Department.t()) :: resolved_config()
  def resolve(
        %Department{
          world: %World{} = world,
          city: %City{world: %Ecto.Association.NotLoaded{}} = city
        } = department
      ) do
    resolve(%{department | city: %{city | world: world}})
  end

  def resolve(%Department{world: %World{} = world, city: %City{world: nil} = city} = department) do
    resolve(%{department | city: %{city | world: world}})
  end

  def resolve(%Department{city: %City{world: %World{}} = city} = department) do
    city_config = resolve(city)

    %{
      limits_config:
        merge_bucket(city_config.limits_config, department.limits_config, LimitsConfig),
      runtime_config:
        merge_bucket(city_config.runtime_config, department.runtime_config, RuntimeConfig),
      costs_config: merge_bucket(city_config.costs_config, department.costs_config, CostsConfig),
      models_config:
        merge_bucket(city_config.models_config, department.models_config, ModelsConfig)
    }
  end

  @spec resolve(Lemming.t()) :: resolved_lemming_config()
  def resolve(
        %Lemming{
          world: %World{} = world,
          city: %City{world: %Ecto.Association.NotLoaded{}} = city,
          department: %Department{city: %Ecto.Association.NotLoaded{}} = department
        } = lemming
      ) do
    resolve(%{
      lemming
      | city: %{city | world: world},
        department: %{department | city: %{city | world: world}}
    })
  end

  def resolve(
        %Lemming{
          world: %World{} = world,
          city: %City{world: nil} = city,
          department: %Department{city: %Ecto.Association.NotLoaded{}} = department
        } = lemming
      ) do
    resolve(%{
      lemming
      | city: %{city | world: world},
        department: %{department | city: %{city | world: world}}
    })
  end

  def resolve(
        %Lemming{
          world: %World{} = world,
          city: %City{world: %Ecto.Association.NotLoaded{}} = city,
          department: %Department{city: %City{world: nil}} = department
        } = lemming
      ) do
    resolve(%{
      lemming
      | city: %{city | world: world},
        department: %{department | city: %{department.city | world: world}}
    })
  end

  def resolve(
        %Lemming{
          world: %World{} = world,
          city: %City{world: nil} = city,
          department: %Department{city: %City{world: nil}} = department
        } = lemming
      ) do
    resolve(%{
      lemming
      | city: %{city | world: world},
        department: %{department | city: %{department.city | world: world}}
    })
  end

  def resolve(
        %Lemming{department: %Department{city: %City{world: %World{}}} = department} = lemming
      ) do
    department_config = resolve(department)

    %{
      limits_config:
        merge_bucket(department_config.limits_config, lemming.limits_config, LimitsConfig),
      runtime_config:
        merge_bucket(department_config.runtime_config, lemming.runtime_config, RuntimeConfig),
      costs_config:
        merge_bucket(department_config.costs_config, lemming.costs_config, CostsConfig),
      models_config:
        merge_bucket(department_config.models_config, lemming.models_config, ModelsConfig),
      tools_config: merge_bucket(%ToolsConfig{}, lemming.tools_config, ToolsConfig)
    }
  end

  defp merge_bucket(parent, nil, _module), do: parent

  defp merge_bucket(parent, child, module) do
    parent
    |> embed_to_map()
    |> deep_merge_maps(prune_nil_values(embed_to_map(child)))
    |> map_to_embed(module)
  end

  defp map_to_embed(map, LimitsConfig), do: struct(LimitsConfig, map)
  defp map_to_embed(map, RuntimeConfig), do: struct(RuntimeConfig, map)
  defp map_to_embed(map, ModelsConfig), do: struct(ModelsConfig, map)
  defp map_to_embed(map, ToolsConfig), do: struct(ToolsConfig, map)

  defp map_to_embed(map, CostsConfig) do
    budgets =
      map
      |> Map.get(:budgets, %{})
      |> map_to_embed(Budgets)

    struct(CostsConfig, Map.put(map, :budgets, budgets))
  end

  defp map_to_embed(map, Budgets), do: struct(Budgets, map)

  defp embed_to_map(nil), do: %{}

  defp embed_to_map(%CostsConfig{} = config) do
    config
    |> Map.from_struct()
    |> Map.update(:budgets, %{}, &embed_to_map/1)
  end

  defp embed_to_map(%_{} = config), do: Map.from_struct(config)

  defp prune_nil_values(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        case prune_nil_values(value) do
          empty when empty == %{} -> acc
          pruned_value -> Map.put(acc, key, pruned_value)
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp deep_merge_maps(parent, child) when is_map(parent) and is_map(child) do
    Map.merge(parent, child, fn _key, parent_value, child_value ->
      merge_map_value(parent_value, child_value)
    end)
  end

  defp merge_map_value(parent_value, child_value)
       when is_map(parent_value) and is_map(child_value),
       do: deep_merge_maps(parent_value, child_value)

  defp merge_map_value(_parent_value, child_value), do: child_value
end
