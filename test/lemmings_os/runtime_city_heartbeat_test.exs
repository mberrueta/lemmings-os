defmodule LemmingsOs.Cities.HeartbeatTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Cities.Heartbeat
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds

  setup do
    Repo.delete_all(City)
    Repo.delete_all(World)
    Cache.invalidate_all()
    :ok
  end

  describe "heartbeat/1" do
    test "updates only last_seen_at for the local runtime city" do
      world = insert(:world)

      city =
        insert(:city,
          world: world,
          node_name: "primary@localhost",
          status: "disabled",
          last_seen_at: nil
        )

      {:ok, pid} =
        start_supervised(
          {Heartbeat,
           [
             name: :runtime_city_heartbeat_test,
             interval_ms: :manual,
             now_fun: fn -> ~U[2026-03-18 18:00:00Z] end,
             current_city: city
           ]}
        )

      assert :ok = Heartbeat.heartbeat(pid)

      updated_city = Repo.get!(City, city.id)

      assert updated_city.last_seen_at == ~U[2026-03-18 18:00:00Z]
      assert updated_city.status == "disabled"
    end

    test "creates the runtime city when no local row exists yet" do
      insert(:world)

      previous_config = Application.get_env(:lemmings_os, :runtime_city)
      Application.put_env(:lemmings_os, :runtime_city, %{node_name: "primary@localhost"})

      on_exit(fn ->
        Application.put_env(:lemmings_os, :runtime_city, previous_config)
      end)

      {:ok, pid} =
        start_supervised(
          {Heartbeat,
           [
             name: :runtime_city_heartbeat_bootstrap_test,
             interval_ms: :manual,
             now_fun: fn -> ~U[2026-03-18 18:00:00Z] end
           ]}
        )

      assert :ok = Heartbeat.heartbeat(pid)

      assert {:ok, world} = Worlds.get_default_world()
      [city] = Cities.list_cities(world)

      assert city.node_name == "primary@localhost"
      assert city.last_seen_at == ~U[2026-03-18 18:00:00Z]
    end

    test "returns an honest error when no default world exists" do
      previous_config = Application.get_env(:lemmings_os, :runtime_city)
      Application.put_env(:lemmings_os, :runtime_city, %{node_name: "primary@localhost"})

      on_exit(fn ->
        Application.put_env(:lemmings_os, :runtime_city, previous_config)
      end)

      {:ok, pid} =
        start_supervised(
          {Heartbeat,
           [
             name: :runtime_city_heartbeat_missing_world_test,
             interval_ms: :manual
           ]}
        )

      assert {:error, :default_world_not_found} = Heartbeat.heartbeat(pid)
    end
  end
end
