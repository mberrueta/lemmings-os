defmodule LemmingsOsWeb.PageData.CitiesPageSnapshotTest do
  use LemmingsOs.DataCase, async: true

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

      assert [%{id: id, path: path, name: "Support", status: "active", tags: tags}] =
               snapshot.selected_city.departments

      assert id == department.id
      assert path == "/departments?city=#{city.id}&dept=#{department.id}"
      assert tags == ["customer-care", "tier-1"]
      assert snapshot.selected_city.departments |> hd() |> Map.fetch!(:notes_preview) =~ "..."
    end
  end
end
