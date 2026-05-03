defmodule LemmingsOsWeb.PageData.CitiesPageSnapshotTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOsWeb.PageData.CitiesPageSnapshot

  describe "build/1" do
    test "loads persisted departments for the selected city only" do
      world = insert(:world, name: "Ops World", slug: "ops-world", status: "ok")
      city = insert(:city, world: world, name: "Alpha City", slug: "alpha-city", status: "active")

      other_city =
        insert(:city, world: world, name: "Beta City", slug: "beta-city", status: "active")

      department =
        insert(:department,
          world: world,
          city: city,
          name: "Support",
          slug: "support",
          status: "active",
          tags: ["customer-care", "tier-1"],
          notes: String.duplicate("notes ", 30)
        )

      insert(:lemming, world: world, city: city, department: department, status: "active")
      insert(:lemming, world: world, city: city, department: department, status: "draft")

      _other_department =
        insert(:department,
          world: world,
          city: other_city,
          name: "Platform",
          slug: "platform",
          status: "disabled"
        )

      {:ok, snapshot} = CitiesPageSnapshot.build(world: world, city_id: city.id)

      assert snapshot.selected_city.department_count == 1
      assert snapshot.selected_city.departments_path == "/departments?city=#{city.id}"

      assert [
               %{
                 id: id,
                 path: path,
                 name: "Support",
                 status: "active",
                 lemming_count: lemming_count,
                 tags: tags
               }
             ] =
               snapshot.selected_city.departments

      assert id == department.id
      assert path == "/departments?city=#{city.id}&dept=#{department.id}"
      assert lemming_count == 2
      assert tags == ["customer-care", "tier-1"]
      assert snapshot.selected_city.departments |> hd() |> Map.fetch!(:notes_preview) =~ "..."
    end

    test "parses string heartbeat freshness config before deriving liveness" do
      previous_config = Application.get_env(:lemmings_os, :runtime_city_heartbeat)

      Application.put_env(:lemmings_os, :runtime_city_heartbeat,
        interval_ms: 30_000,
        freshness_threshold_seconds: "180"
      )

      on_exit(fn ->
        Application.put_env(:lemmings_os, :runtime_city_heartbeat, previous_config)
      end)

      world = insert(:world)

      city =
        insert(:city,
          world: world,
          last_seen_at: DateTime.utc_now() |> DateTime.add(-120, :second)
        )

      {:ok, snapshot} = CitiesPageSnapshot.build(world: world, city_id: city.id)

      assert snapshot.selected_city.liveness == "alive"
    end
  end
end
