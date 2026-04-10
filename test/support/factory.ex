defmodule LemmingsOs.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: LemmingsOs.Repo

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  def world_factory do
    unique_value = sequence(:world_unique, & &1)
    name = Faker.Company.name()
    slug_base = Helpers.slugify(name)

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
    slug_base = Helpers.slugify(name)

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

  def department_factory do
    unique_value = sequence(:department_unique, & &1)
    city = build(:city)

    name =
      "#{Faker.Company.bs()} #{unique_value}" |> String.replace(~r/\s+/u, " ") |> String.trim()

    slug_base = Helpers.slugify(name)

    %Department{
      world: city.world,
      city: city,
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "active",
      notes: "Department #{unique_value} notes",
      tags: ["ops", "priority-#{unique_value}"],
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  def lemming_factory do
    unique_value = sequence(:lemming_unique, & &1)
    department = build(:department)

    name =
      "Lemming #{unique_value} #{Faker.Company.bs()}"
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    slug_base = Helpers.slugify(name)

    %Lemming{
      world: department.world,
      city: department.city,
      department: department,
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "draft",
      description: "Lemming #{unique_value} description",
      instructions: "Follow the department instructions carefully.",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{},
      tools_config: %ToolsConfig{}
    }
  end

  def lemming_instance_factory do
    lemming = build(:lemming)

    %LemmingInstance{
      lemming: lemming,
      world: lemming.world,
      city: lemming.city,
      department: lemming.department,
      status: "created",
      config_snapshot: %{
        "models" => %{},
        "runtime" => %{}
      },
      started_at: nil,
      stopped_at: nil,
      last_activity_at: nil
    }
  end

  def lemming_instance_message_factory do
    instance = build(:lemming_instance)

    %Message{
      lemming_instance: instance,
      world: instance.world,
      role: "user",
      content: Faker.Lorem.sentence(),
      provider: nil,
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      usage: nil
    }
  end
end
