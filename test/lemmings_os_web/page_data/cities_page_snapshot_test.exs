defmodule LemmingsOsWeb.PageData.CitiesPageSnapshotTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  setup do
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "build/1" do
    test "builds real city cards, derived liveness, effective config, and mock previews" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      world =
        insert(:world,
          name: "City World",
          slug: "city-world",
          status: "ok",
          runtime_config: %{idle_ttl_seconds: 3600, cross_city_communication: false},
          limits_config: %{
            max_cities: 4,
            max_departments_per_city: 6,
            max_lemmings_per_department: 12
          },
          costs_config: %{budgets: %{monthly_usd: 12.5, daily_tokens: 1_000}},
          models_config: %{
            providers: %{"ollama" => %{enabled: true}},
            profiles: %{"default" => %{provider: "ollama", model: "llama3.2"}}
          }
        )

      fresh_city =
        insert(:city,
          world: world,
          name: "Alpha City",
          slug: "alpha-city",
          node_name: "alpha@127.0.0.1",
          host: "127.0.0.1",
          distribution_port: 25_672,
          epmd_port: 4369,
          status: "active",
          last_seen_at: now,
          runtime_config: %{idle_ttl_seconds: 120}
        )

      stale_city =
        insert(:city,
          world: world,
          name: "Beta City",
          slug: "beta-city",
          node_name: "beta@127.0.0.2",
          host: "127.0.0.2",
          distribution_port: 25_673,
          epmd_port: 4370,
          status: "draining",
          last_seen_at: DateTime.add(now, -300, :second),
          runtime_config: %{idle_ttl_seconds: 120}
        )

      assert {:ok, snapshot} =
               CitiesPageSnapshot.build(
                 world: world,
                 city_id: stale_city.id,
                 now: now,
                 freshness_threshold_seconds: 90
               )

      assert snapshot.world.city_count == 2

      assert MapSet.new(Enum.map(snapshot.cities, & &1.id)) ==
               MapSet.new([fresh_city.id, stale_city.id])

      assert Enum.find(snapshot.cities, &(&1.id == fresh_city.id)).liveness == "alive"
      assert Enum.find(snapshot.cities, &(&1.id == stale_city.id)).liveness == "stale"
      assert snapshot.selected_city.id == stale_city.id
      assert snapshot.selected_city.status == "draining"
      assert snapshot.selected_city.effective_config.runtime_config.idle_ttl_seconds == 120
      assert snapshot.selected_city.effective_config.limits_config.max_cities == 4
      assert snapshot.selected_city.mock_children.source == "mock"
      assert snapshot.selected_city.mock_children.departments != []
      assert snapshot.selected_city.mock_children.lemmings != []
    end

    test "falls back to the first city when the requested city_id is missing" do
      world = insert(:world, name: "Fallback World", slug: "fallback-world", status: "ok")

      city =
        insert(:city,
          world: world,
          name: "Fallback City",
          slug: "fallback-city",
          status: "active"
        )

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world, city_id: "missing")
      assert snapshot.selected_city.id == city.id
      assert Enum.find(snapshot.cities, & &1.selected?).id == city.id
    end
  end
end
