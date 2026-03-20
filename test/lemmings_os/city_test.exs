defmodule LemmingsOs.Cities.CityTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig

  describe "changeset/2" do
    test "S01: requires slug, name, node_name, and status" do
      changeset = City.changeset(%City{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.node_name
      assert "can't be blank" in errors.status
    end

    test "S02: rejects node names that are not full beam identities" do
      changeset =
        City.changeset(%City{}, %{
          slug: "primary",
          name: "Primary",
          node_name: "primary",
          status: "active"
        })

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "has invalid format" in errors.node_name
    end

    test "S03: rejects statuses outside the frozen admin taxonomy" do
      changeset =
        City.changeset(%City{}, %{
          slug: "primary",
          name: "Primary",
          node_name: "primary@localhost",
          status: "alive"
        })

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "is invalid" in errors.status
    end

    test "S04: does not cast world_id from attrs" do
      changeset =
        City.changeset(%City{}, %{
          world_id: Ecto.UUID.generate(),
          slug: "primary",
          name: "Primary",
          node_name: "primary@localhost",
          status: "active"
        })

      refute Map.has_key?(changeset.changes, :world_id)
    end

    test "S04b: does not cast last_seen_at from attrs" do
      changeset =
        City.changeset(%City{}, %{
          last_seen_at: ~U[2099-01-01 00:00:00Z],
          slug: "primary",
          name: "Primary",
          node_name: "primary@localhost",
          status: "active"
        })

      refute Map.has_key?(changeset.changes, :last_seen_at)
    end

    test "S05: casts shared config buckets through embeds" do
      changeset =
        City.changeset(%City{}, %{
          slug: "primary",
          name: "Primary",
          node_name: "primary@localhost",
          status: "active",
          limits_config: %{"max_cities" => 2, "max_lemmings_per_department" => 10},
          runtime_config: %{"cross_city_communication" => false},
          costs_config: %{"budgets" => %{"daily_tokens" => 5000}},
          models_config: %{"providers" => %{"ollama" => %{"enabled" => true}}}
        })

      assert changeset.valid?

      city = apply_changes(changeset)

      assert %LimitsConfig{} = city.limits_config
      assert city.limits_config.max_cities == 2
      assert city.limits_config.max_lemmings_per_department == 10
      assert %RuntimeConfig{} = city.runtime_config
      assert city.runtime_config.cross_city_communication == false
      assert %CostsConfig{} = city.costs_config
      assert city.costs_config.budgets.daily_tokens == 5000
      assert %ModelsConfig{} = city.models_config
      assert city.models_config.providers["ollama"]["enabled"] == true
    end

    test "S06: exposes translated status helpers for ui usage" do
      assert City.statuses() == ~w(active disabled draining)
      assert City.translate_status("disabled") == "Disabled"
      assert City.translate_status(nil) == "Unknown"

      assert City.status_options() == [
               {"active", "Active"},
               {"disabled", "Disabled"},
               {"draining", "Draining"}
             ]
    end

    test "S07: accepts valid optional fields host, distribution_port, epmd_port" do
      changeset =
        City.changeset(%City{}, %{
          slug: "ops",
          name: "Ops",
          node_name: "ops@example.local",
          status: "active",
          host: "example.local",
          distribution_port: 9000,
          epmd_port: 4369
        })

      assert changeset.valid?

      city = apply_changes(changeset)

      assert city.host == "example.local"
      assert city.distribution_port == 9000
      assert city.epmd_port == 4369
    end

    test "S08: rejects non-positive distribution_port and epmd_port" do
      changeset =
        City.changeset(%City{}, %{
          slug: "ops",
          name: "Ops",
          node_name: "ops@localhost",
          status: "active",
          distribution_port: 0,
          epmd_port: -1
        })

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "must be greater than 0" in errors.distribution_port
      assert "must be greater than 0" in errors.epmd_port
    end

    test "S09: translate_status/1 works with a City struct" do
      city = build(:city, status: "draining")

      assert City.translate_status(city) == "Draining"
    end
  end

  describe "liveness/3" do
    test "S10: returns unknown when no heartbeat has been observed" do
      city = build(:city, last_seen_at: nil)

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "unknown"
      assert City.livenesses() == ~w(alive stale unknown)
    end

    test "S11: returns alive when the heartbeat is within the freshness threshold" do
      city = build(:city, last_seen_at: ~U[2026-03-18 17:59:30Z])

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "alive"
    end

    test "S12: returns stale when the heartbeat is older than the freshness threshold" do
      city = build(:city, last_seen_at: ~U[2026-03-18 17:58:29Z])

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "stale"
    end

    test "S13: returns alive at exact threshold boundary (last_seen_at == now - threshold)" do
      # Exactly at threshold: now is 18:00:00, threshold is 90s, so stale_before is 17:58:30.
      # last_seen_at == 17:58:30 means DateTime.compare == :eq, which maps to "alive".
      city = build(:city, last_seen_at: ~U[2026-03-18 17:58:30Z])

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "alive"
    end

    test "S14: liveness/2 (without explicit now) uses DateTime.utc_now internally" do
      # A city seen very recently should be alive regardless of wall clock
      city = build(:city, last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second))

      assert City.liveness(city, 90) == "alive"
    end
  end

  describe "database constraints" do
    test "S15: enforces unique node_name per world" do
      world = insert(:world)
      insert(:city, world: world, node_name: "primary@localhost")

      changeset =
        %City{world_id: world.id}
        |> City.changeset(%{
          slug: "secondary",
          name: "Secondary",
          node_name: "primary@localhost",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).node_name
    end

    test "S16: enforces unique slug per world" do
      world = insert(:world)
      insert(:city, world: world, slug: "ops")

      changeset =
        %City{world_id: world.id}
        |> City.changeset(%{
          slug: "ops",
          name: "Another Ops",
          node_name: "another@localhost",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "S17: allows same slug in different worlds" do
      world_a = insert(:world)
      world_b = insert(:world)
      insert(:city, world: world_a, slug: "ops", node_name: "ops-a@localhost")

      changeset =
        %City{world_id: world_b.id}
        |> City.changeset(%{
          slug: "ops",
          name: "Ops B",
          node_name: "ops-b@localhost",
          status: "active"
        })

      assert {:ok, city_b} = Repo.insert(changeset)
      assert city_b.slug == "ops"
      assert city_b.world_id == world_b.id
    end
  end
end
