# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     LemmingsOs.Repo.insert!(%LemmingsOs.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias LemmingsOs.Cities
alias LemmingsOs.Departments
alias LemmingsOs.Helpers
alias LemmingsOs.Worlds

world_attrs = %{
  slug: "local-world",
  name: "Local World",
  status: "ok",
  last_import_status: "ok",
  bootstrap_source: "seed",
  bootstrap_path: "/tmp/lemmings_os/local-world.seed.world.yaml"
}

city_seeds = [
  %{
    slug: "alpha-city",
    name: "Alpha City",
    node_name: "alpha@localhost",
    host: "127.0.0.1",
    distribution_port: 9101,
    epmd_port: 4369,
    status: "active"
  },
  %{
    slug: "beta-city",
    name: "Beta City",
    node_name: "beta@localhost",
    host: "127.0.0.1",
    distribution_port: 9102,
    epmd_port: 4370,
    status: "active"
  },
  %{
    slug: "gamma-city",
    name: "Gamma City",
    node_name: "gamma@localhost",
    host: "127.0.0.1",
    distribution_port: 9103,
    epmd_port: 4371,
    status: "draining"
  },
  %{
    slug: "delta-city",
    name: "Delta City",
    node_name: "delta@localhost",
    host: "127.0.0.1",
    distribution_port: 9104,
    epmd_port: 4372,
    status: "active"
  }
]

department_name_groups = [
  "Support",
  "Platform",
  "Ops",
  "Finance",
  "Research",
  "Growth",
  "Security",
  "Quality",
  "Automation",
  "Infra"
]

department_statuses = ["active", "active", "active", "draining", "disabled"]

department_tag_groups = [
  ["customer-care", "tier-1"],
  ["platform", "backend"],
  ["ops", "incident"],
  ["finance", "budget"],
  ["research", "experiments"],
  ["growth", "funnels"],
  ["security", "guardrails"],
  ["quality", "testing"],
  ["automation", "pipelines"],
  ["infra", "runtime"]
]

{:ok, world} = Worlds.upsert_world(world_attrs)

city_seeds
|> Enum.with_index()
|> Enum.each(fn {city_attrs, city_index} ->
  {:ok, city} = Cities.create_city(world, city_attrs)

  department_count = 5 + rem(city_index, 4)

  1..department_count
  |> Enum.each(fn offset ->
    name_seed_index = rem(city_index * 3 + offset - 1, length(department_name_groups))
    base_name = Enum.at(department_name_groups, name_seed_index)
    name = "#{base_name} #{city.name}"
    slug = Helpers.slugify(name)
    status = Enum.at(department_statuses, rem(offset - 1, length(department_statuses)))
    tags = Enum.at(department_tag_groups, name_seed_index) ++ [city.slug]

    attrs = %{
      slug: slug,
      name: name,
      status: status,
      notes: "Seeded #{base_name} department for #{city.name}.",
      tags: tags
    }

    case Departments.create_department(world, city, attrs) do
      {:ok, _department} ->
        :ok

      {:error, changeset} ->
        raise """
        failed to seed department #{inspect(name)} for #{inspect(city.slug)}
        #{inspect(changeset.errors)}
        """
    end
  end)
end)

IO.puts(
  "Seeded world #{world.slug} with #{length(city_seeds)} cities and 5-8 departments per city."
)
