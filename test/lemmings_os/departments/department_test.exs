defmodule LemmingsOs.Departments.DepartmentTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers

  describe "changeset/2" do
    test "S01: requires slug, name, and status" do
      changeset = Department.changeset(%Department{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.status
    end

    test "S02: rejects statuses outside the frozen admin taxonomy" do
      changeset =
        Department.changeset(%Department{}, %{
          slug: "support",
          name: "Support",
          status: "paused"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "S03: does not cast world_id or city_id from attrs" do
      changeset =
        Department.changeset(%Department{}, %{
          world_id: Ecto.UUID.generate(),
          city_id: Ecto.UUID.generate(),
          slug: "support",
          name: "Support",
          status: "active"
        })

      refute Map.has_key?(changeset.changes, :world_id)
      refute Map.has_key?(changeset.changes, :city_id)
    end

    test "S04: normalizes tags by trimming, collapsing separators, removing blanks, and deduplicating" do
      changeset =
        Department.changeset(%Department{}, %{
          slug: "support",
          name: "Support",
          status: "active",
          tags: [
            " Customer Support ",
            "High-Priority",
            "high priority",
            "---",
            "Ops__Desk",
            "ops   desk",
            ""
          ]
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_field(changeset, :tags) == [
               "customer-support",
               "high-priority",
               "ops-desk"
             ]
    end

    test "S05: validates notes length as bounded operator metadata" do
      changeset =
        Department.changeset(%Department{}, %{
          slug: "support",
          name: "Support",
          status: "active",
          notes: String.duplicate("a", Department.notes_max_length() + 1)
        })

      refute changeset.valid?

      assert "should be at most #{Department.notes_max_length()} character(s)" in errors_on(
               changeset
             ).notes
    end

    test "S06: casts shared config buckets through embeds" do
      changeset =
        Department.changeset(%Department{}, %{
          slug: "support",
          name: "Support",
          status: "active",
          limits_config: %{"max_lemmings_per_department" => 12},
          runtime_config: %{"idle_ttl_seconds" => 90},
          costs_config: %{"budgets" => %{"monthly_usd" => 120.5}},
          models_config: %{"profiles" => %{"fast" => %{"provider" => "ollama"}}}
        })

      assert changeset.valid?

      department = apply_changes(changeset)

      assert %LimitsConfig{} = department.limits_config
      assert department.limits_config.max_lemmings_per_department == 12
      assert %RuntimeConfig{} = department.runtime_config
      assert department.runtime_config.idle_ttl_seconds == 90
      assert %CostsConfig{} = department.costs_config
      assert department.costs_config.budgets.monthly_usd == 120.5
      assert %ModelsConfig{} = department.models_config
      assert department.models_config.profiles["fast"]["provider"] == "ollama"
    end

    test "S07: exposes translated status helpers for ui usage" do
      assert Department.statuses() == ~w(active disabled draining)
      assert Department.translate_status("disabled") == "Disabled"
      assert Department.translate_status(nil) == "Unknown"

      assert Department.status_options() == [
               {"active", "Active"},
               {"disabled", "Disabled"},
               {"draining", "Draining"}
             ]
    end

    test "S08: translate_status/1 works with a Department struct" do
      department = build(:department, status: "draining")

      assert Department.translate_status(department) == "Draining"
    end
  end

  describe "database constraints" do
    test "S09: enforces unique slug per city" do
      world = insert(:world)
      city = insert(:city, world: world)

      insert(:department, world: world, city: city, slug: "support")

      changeset =
        %Department{world_id: world.id, city_id: city.id}
        |> Department.changeset(%{
          slug: "support",
          name: "Support 2",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "S10: allows same slug in different cities" do
      world = insert(:world)
      city_a = insert(:city, world: world, slug: "alpha", node_name: "alpha@localhost")
      city_b = insert(:city, world: world, slug: "beta", node_name: "beta@localhost")

      insert(:department, world: world, city: city_a, slug: "support")

      changeset =
        %Department{world_id: world.id, city_id: city_b.id}
        |> Department.changeset(%{
          slug: "support",
          name: "Support B",
          status: "active"
        })

      assert {:ok, department} = Repo.insert(changeset)
      assert department.slug == "support"
      assert department.city_id == city_b.id
    end

    test "S11: enforces associated world existence" do
      changeset =
        %Department{world_id: Ecto.UUID.generate(), city_id: insert(:city).id}
        |> Department.changeset(%{
          slug: "support",
          name: "Support",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).world
    end

    test "S12: enforces associated city existence" do
      changeset =
        %Department{world_id: insert(:world).id, city_id: Ecto.UUID.generate()}
        |> Department.changeset(%{
          slug: "support",
          name: "Support",
          status: "active"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).city
    end
  end

  describe "helpers integration" do
    test "S13: uses shared helpers normalization semantics" do
      assert Ecto.Changeset.get_field(
               Department.changeset(%Department{}, %{
                 slug: "support",
                 name: "Support",
                 status: "active",
                 tags: ["Ops Desk", "ops_desk", "OPS-DESK", "QA"]
               }),
               :tags
             ) == Helpers.normalize_tags(["Ops Desk", "ops_desk", "OPS-DESK", "QA"])
    end
  end
end
