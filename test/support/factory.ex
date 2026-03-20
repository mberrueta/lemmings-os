defmodule LemmingsOs.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: LemmingsOs.Repo

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Worlds.World

  def world_factory do
    unique_value = sequence(:world_unique, & &1)
    name = Faker.Company.name()
    slug_base = slugify(name)

    %World{
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "unknown",
      last_import_status: "unknown",
      bootstrap_path: "/tmp/worlds/#{slug_base}-#{unique_value}.default.world.yaml",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  def city_factory do
    unique_value = sequence(:city_unique, & &1)
    name = Faker.Address.city()
    slug_base = slugify(name)

    %City{
      world: build(:world),
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      node_name: "city#{unique_value}@localhost",
      status: "active",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
