defmodule LemmingsOs.SeedsTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities
  alias LemmingsOs.Departments
  alias LemmingsOs.Lemmings
  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOs.WorldBootstrapTestHelpers
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  describe "priv/repo/seeds.exs" do
    test "rerunning seeds preserves the first bootstrap city and keeps seeded counts stable" do
      Repo.delete_all(World)

      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      assert {:ok, _result} = Importer.sync_default_world(path: path, source: "direct")

      world = Worlds.get_default_world()
      bootstrap_city = Cities.get_city_by_slug(world, "local_city")

      run_seeds!()

      world = Worlds.get_default_world()
      seeded_primary_city = Cities.get_city_by_slug(world, "local_city")
      seeded_counts = hierarchy_counts(world, seeded_primary_city)

      run_seeds!()

      world = Worlds.get_default_world()
      rerun_primary_city = Cities.get_city_by_slug(world, "local_city")

      assert rerun_primary_city.id == bootstrap_city.id
      assert hierarchy_counts(world, rerun_primary_city) == seeded_counts

      assert Enum.sort(Enum.map(Cities.list_cities(world), & &1.slug)) == [
               "beta-city",
               "local_city"
             ]

      assert slugs_for(Departments.list_departments(rerun_primary_city)) == [
               "it",
               "marketing",
               "platform",
               "sales",
               "support"
             ]
    end
  end

  defp run_seeds! do
    "priv/repo/seeds.exs"
    |> Path.expand(File.cwd!())
    |> Code.eval_file()
  end

  defp hierarchy_counts(world, primary_city) do
    %{
      city_count: length(Cities.list_cities(world)),
      primary_department_count: length(Departments.list_departments(primary_city)),
      primary_lemming_count: length(Lemmings.list_lemmings(primary_city)),
      total_lemming_count: length(Lemmings.list_lemmings(world))
    }
  end

  defp slugs_for(records) do
    records
    |> Enum.map(& &1.slug)
    |> Enum.sort()
  end
end
