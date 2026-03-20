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
    test "S01: returns error when no world can be resolved" do
      assert {:error, :not_found} = CitiesPageSnapshot.build([])
    end

    test "S02: builds an empty snapshot when the world has no cities" do
      world = insert(:world, name: "Empty World", slug: "empty-world", status: "ok")

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world)

      assert snapshot.empty? == true
      assert snapshot.cities == []
      assert snapshot.selected_city == nil
      assert snapshot.world.id == world.id
      assert snapshot.world.city_count == 0
    end

    test "S03: builds real city cards with derived liveness, effective config, and mock previews" do
      now = ~U[2026-03-18 18:00:00Z]

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

    test "S04: maps liveness_tone correctly for each liveness state" do
      now = ~U[2026-03-18 18:00:00Z]
      world = insert(:world)

      # alive: last_seen_at within threshold
      alive_city =
        insert(:city,
          world: world,
          last_seen_at: now,
          status: "active"
        )

      # stale: last_seen_at beyond threshold
      stale_city =
        insert(:city,
          world: world,
          last_seen_at: DateTime.add(now, -300, :second),
          status: "active"
        )

      # unknown: no heartbeat
      unknown_city =
        insert(:city,
          world: world,
          last_seen_at: nil,
          status: "active"
        )

      assert {:ok, snapshot} =
               CitiesPageSnapshot.build(
                 world: world,
                 now: now,
                 freshness_threshold_seconds: 90
               )

      alive_card = Enum.find(snapshot.cities, &(&1.id == alive_city.id))
      stale_card = Enum.find(snapshot.cities, &(&1.id == stale_city.id))
      unknown_card = Enum.find(snapshot.cities, &(&1.id == unknown_city.id))

      assert alive_card.liveness == "alive"
      assert alive_card.liveness_tone == "success"
      assert alive_card.liveness_label != ""

      assert stale_card.liveness == "stale"
      assert stale_card.liveness_tone == "warning"
      assert stale_card.liveness_label != ""

      assert unknown_card.liveness == "unknown"
      assert unknown_card.liveness_tone == "default"
      assert unknown_card.liveness_label != ""
    end

    test "S05: selected_city defaults to first city when no city_id param" do
      world = insert(:world)
      insert(:city, world: world, slug: "first")
      insert(:city, world: world, slug: "second")

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world)

      # The selected city should be one of the cities (the first in sort order)
      assert snapshot.selected_city != nil
      first_city = hd(snapshot.cities)
      assert snapshot.selected_city.id == first_city.id
      assert Enum.find(snapshot.cities, & &1.selected?).id == first_city.id
    end

    test "S06: selected_city matches the requested city_id" do
      world = insert(:world)
      insert(:city, world: world, slug: "first")
      city_b = insert(:city, world: world, slug: "second")

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world, city_id: city_b.id)

      assert snapshot.selected_city.id == city_b.id
    end

    test "S07: falls back to the first city when the requested city_id is missing" do
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

    test "S08: resolves world by world_id when no struct is provided" do
      world = insert(:world)
      insert(:city, world: world, slug: "test-city")

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world_id: world.id)

      assert snapshot.world.id == world.id
      assert length(snapshot.cities) == 1
    end

    test "S09: world snapshot includes status_label from translate_status" do
      world = insert(:world, status: "ok")

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world)

      assert snapshot.world.status == "ok"
      assert snapshot.world.status_label != ""
    end

    test "S10: city cards include path for navigation" do
      world = insert(:world)
      city = insert(:city, world: world)

      assert {:ok, snapshot} = CitiesPageSnapshot.build(world: world)

      [card] = snapshot.cities
      assert card.path == "/cities?city=#{city.id}"
    end
  end
end
