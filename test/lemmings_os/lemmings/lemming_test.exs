defmodule LemmingsOs.Lemmings.LemmingTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Lemmings.Lemming

  describe "changeset/2" do
    test "S01: requires slug, name, and status" do
      changeset = Lemming.changeset(%Lemming{}, %{})

      refute changeset.valid?

      errors = errors_on(changeset)

      assert "can't be blank" in errors.slug
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.status
    end

    test "S02: rejects statuses outside the frozen lifecycle taxonomy" do
      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "disabled"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "S03: does not cast world_id, city_id, or department_id from attrs" do
      changeset =
        Lemming.changeset(%Lemming{}, %{
          world_id: Ecto.UUID.generate(),
          city_id: Ecto.UUID.generate(),
          department_id: Ecto.UUID.generate(),
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft"
        })

      refute Map.has_key?(changeset.changes, :world_id)
      refute Map.has_key?(changeset.changes, :city_id)
      refute Map.has_key?(changeset.changes, :department_id)
    end

    test "S04: allows active status without instructions at the schema layer" do
      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "active"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :instructions) == nil
    end

    test "S05: validates description length as bounded operator metadata" do
      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft",
          description: String.duplicate("a", Lemming.description_max_length() + 1)
        })

      refute changeset.valid?

      assert "should be at most #{Lemming.description_max_length()} character(s)" in errors_on(
               changeset
             ).description
    end

    test "S15: accepts instructions as operator-authored free text" do
      instructions = String.duplicate("Review the queue and escalate when needed. ", 40)

      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft",
          instructions: instructions
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :instructions) == instructions
    end

    test "S16: accepts description at the exact maximum length boundary" do
      description = String.duplicate("a", Lemming.description_max_length())

      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft",
          description: description
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :description) == description
    end

    test "S06: casts all five config buckets through embeds" do
      changeset =
        Lemming.changeset(%Lemming{}, %{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft",
          limits_config: %{"max_lemmings_per_department" => 12},
          runtime_config: %{"idle_ttl_seconds" => 90},
          costs_config: %{"budgets" => %{"monthly_usd" => 120.5}},
          models_config: %{"profiles" => %{"fast" => %{"provider" => "ollama"}}},
          tools_config: %{"allowed_tools" => ["github"], "denied_tools" => ["shell"]}
        })

      assert changeset.valid?

      lemming = apply_changes(changeset)

      assert %LimitsConfig{} = lemming.limits_config
      assert lemming.limits_config.max_lemmings_per_department == 12
      assert %RuntimeConfig{} = lemming.runtime_config
      assert lemming.runtime_config.idle_ttl_seconds == 90
      assert %CostsConfig{} = lemming.costs_config
      assert lemming.costs_config.budgets.monthly_usd == 120.5
      assert %ModelsConfig{} = lemming.models_config
      assert lemming.models_config.profiles["fast"]["provider"] == "ollama"
      assert %ToolsConfig{} = lemming.tools_config
      assert lemming.tools_config.allowed_tools == ["github"]
      assert lemming.tools_config.denied_tools == ["shell"]
    end

    test "S07: exposes translated status helpers for ui usage" do
      assert Lemming.statuses() == ~w(draft active archived)
      assert Lemming.translate_status("draft") == "Draft"
      assert Lemming.translate_status("archived") == "Archived"
      assert Lemming.translate_status(nil) == "Unknown"

      assert Lemming.status_options() == [
               {"Draft", "draft"},
               {"Active", "active"},
               {"Archived", "archived"}
             ]
    end

    test "S08: translate_status/1 works with a Lemming struct" do
      lemming = build(:lemming, status: "active")

      assert Lemming.translate_status(lemming) == "Active"
    end
  end

  describe "database constraints" do
    test "S09: enforces unique slug per department" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      insert(:lemming,
        department: department,
        city: city,
        world: world,
        slug: "code-reviewer"
      )

      changeset =
        %Lemming{
          world_id: department.world_id,
          city_id: department.city_id,
          department_id: department.id
        }
        |> Lemming.changeset(%{
          slug: "code-reviewer",
          name: "Code Reviewer 2",
          status: "draft"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "S10: allows same slug in different departments" do
      world = insert(:world)
      city = insert(:city, world: world)
      department_a = insert(:department, world: world, city: city, slug: "ops")
      department_b = insert(:department, world: world, city: city, slug: "qa")

      insert(:lemming,
        world: world,
        city: city,
        department: department_a,
        slug: "code-reviewer"
      )

      changeset =
        %Lemming{
          world_id: world.id,
          city_id: city.id,
          department_id: department_b.id
        }
        |> Lemming.changeset(%{
          slug: "code-reviewer",
          name: "Code Reviewer B",
          status: "draft"
        })

      assert {:ok, lemming} = Repo.insert(changeset)
      assert lemming.slug == "code-reviewer"
      assert lemming.department_id == department_b.id
    end

    test "S11: enforces associated world existence" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      changeset =
        %Lemming{
          world_id: Ecto.UUID.generate(),
          city_id: department.city_id,
          department_id: department.id
        }
        |> Lemming.changeset(%{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).world
    end

    test "S12: enforces associated city existence" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      changeset =
        %Lemming{
          world_id: department.world_id,
          city_id: Ecto.UUID.generate(),
          department_id: department.id
        }
        |> Lemming.changeset(%{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).city
    end

    test "S13: enforces associated department existence" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      changeset =
        %Lemming{
          world_id: department.world_id,
          city_id: department.city_id,
          department_id: Ecto.UUID.generate()
        }
        |> Lemming.changeset(%{
          slug: "code-reviewer",
          name: "Code Reviewer",
          status: "draft"
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset).department
    end
  end

  describe "factory" do
    test "S14: builds a valid lemming with inherited hierarchy ownership" do
      lemming = build(:lemming)

      assert lemming.status == "draft"
      assert lemming.world == lemming.department.world
      assert lemming.city == lemming.department.city
      assert %ToolsConfig{} = lemming.tools_config
    end
  end
end
