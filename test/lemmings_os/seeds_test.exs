defmodule LemmingsOs.SeedsTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Cities
  alias LemmingsOs.Departments
  alias LemmingsOs.Lemmings
  alias LemmingsOs.WorldBootstrap.Importer
  alias LemmingsOs.WorldBootstrapTestHelpers
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.SecretBank.Secret

  describe "priv/repo/seeds.exs" do
    test "rerunning seeds preserves the first bootstrap city, keeps seeded counts stable, and keeps sample secret idempotent" do
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
      seeded_secret_count = secret_count(world, "GITHUB_TOKEN")
      seeded_secret = Repo.one(secret_query(world, "GITHUB_TOKEN"))

      run_seeds!()

      world = Worlds.get_default_world()
      rerun_primary_city = Cities.get_city_by_slug(world, "local_city")

      assert rerun_primary_city.id == bootstrap_city.id
      assert hierarchy_counts(world, rerun_primary_city) == seeded_counts
      assert secret_count(world, "GITHUB_TOKEN") == seeded_secret_count

      rerun_secret = Repo.one(secret_query(world, "GITHUB_TOKEN"))

      if seeded_secret do
        assert rerun_secret.id == seeded_secret.id
        assert is_binary(rerun_secret.value_encrypted)
        refute rerun_secret.value_encrypted == "dev_only_mock_github_token"

        assert :nomatch =
                 :binary.match(rerun_secret.value_encrypted, "dev_only_mock_github_token")
      else
        assert is_nil(rerun_secret)
      end

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

  defp secret_count(world, bank_key) do
    Repo.aggregate(secret_query(world, bank_key), :count)
  end

  defp secret_query(world, bank_key) do
    from(secret in Secret, where: secret.world_id == ^world.id and secret.bank_key == ^bank_key)
  end
end
