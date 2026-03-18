defmodule LemmingsOs.Cities.CityTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig

  describe "changeset/2" do
    test "requires slug, name, node_name, and status" do
      changeset = City.changeset(%City{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.node_name
      assert "can't be blank" in errors.status
    end

    test "rejects node names that are not full beam identities" do
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

    test "rejects statuses outside the frozen admin taxonomy" do
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

    test "does not cast world_id from attrs" do
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

    test "casts shared config buckets through embeds" do
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

    test "exposes translated status helpers for ui usage" do
      assert City.statuses() == ~w(active disabled draining)
      assert City.translate_status("disabled") == "Disabled"
      assert City.translate_status(nil) == "Unknown"

      assert City.status_options() == [
               {"active", "Active"},
               {"disabled", "Disabled"},
               {"draining", "Draining"}
             ]
    end
  end

  describe "liveness/2" do
    test "returns unknown when no heartbeat has been observed" do
      city = build(:city, last_seen_at: nil)

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "unknown"
      assert City.livenesses() == ~w(alive stale unknown)
    end

    test "returns alive when the heartbeat is within the freshness threshold" do
      city = build(:city, last_seen_at: ~U[2026-03-18 17:59:30Z])

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "alive"
    end

    test "returns stale when the heartbeat is older than the freshness threshold" do
      city = build(:city, last_seen_at: ~U[2026-03-18 17:58:29Z])

      assert City.liveness(city, ~U[2026-03-18 18:00:00Z], 90) == "stale"
    end
  end

  describe "database constraints" do
    test "enforces unique node_name per world" do
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
  end
end
