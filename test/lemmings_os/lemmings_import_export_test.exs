defmodule LemmingsOs.LemmingsImportExportTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.ImportExport

  describe "export_lemming/1" do
    test "exports the portable lemming shape without identity fields" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      lemming =
        insert(:lemming,
          world: world,
          city: city,
          department: department,
          name: "Code Reviewer",
          slug: "code-reviewer",
          description: "Reviews code",
          instructions: "Review pull requests carefully.",
          status: "active",
          limits_config: %LimitsConfig{max_lemmings_per_department: 2},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 30},
          costs_config: %CostsConfig{budgets: %Budgets{monthly_usd: 15.0}},
          models_config: %ModelsConfig{profiles: %{"fast" => %{"provider" => "ollama"}}},
          tools_config: %ToolsConfig{allowed_tools: ["github"], denied_tools: ["shell"]}
        )

      export = ImportExport.export_lemming(lemming)

      assert export["schema_version"] == 1
      assert export["name"] == "Code Reviewer"
      assert export["slug"] == "code-reviewer"
      assert export["description"] == "Reviews code"
      assert export["instructions"] == "Review pull requests carefully."
      assert export["status"] == "active"
      assert export["limits_config"] == %{"max_lemmings_per_department" => 2}
      assert export["runtime_config"] == %{"idle_ttl_seconds" => 30}
      assert export["costs_config"] == %{"budgets" => %{"monthly_usd" => 15.0}}
      assert export["models_config"] == %{"profiles" => %{"fast" => %{"provider" => "ollama"}}}

      assert export["tools_config"] == %{
               "allowed_tools" => ["github"],
               "denied_tools" => ["shell"]
             }

      refute Map.has_key?(export, "id")
      refute Map.has_key?(export, "world_id")
      refute Map.has_key?(export, "city_id")
      refute Map.has_key?(export, "department_id")
      refute Map.has_key?(export, "inserted_at")
      refute Map.has_key?(export, "updated_at")
    end

    test "exports empty config buckets as empty maps" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      export = ImportExport.export_lemming(lemming)

      assert export["limits_config"] == %{}
      assert export["runtime_config"] == %{}
      assert export["costs_config"] == %{}
      assert export["models_config"] == %{}
      assert export["tools_config"] == %{}
    end
  end

  describe "import_lemmings/4" do
    test "imports a valid single lemming definition" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, [lemming]} =
               ImportExport.import_lemmings(world, city, department, %{
                 "schema_version" => 1,
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft",
                 "tools_config" => %{"allowed_tools" => ["github"]}
               })

      assert lemming.world_id == world.id
      assert lemming.city_id == city.id
      assert lemming.department_id == department.id
      assert lemming.tools_config.allowed_tools == ["github"]
    end

    test "imports a valid batch atomically" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, lemmings} =
               ImportExport.import_lemmings(world, city, department, [
                 %{"slug" => "code-reviewer", "name" => "Code Reviewer", "status" => "draft"},
                 %{
                   "slug" => "qa-reviewer",
                   "name" => "QA Reviewer",
                   "status" => "active",
                   "instructions" => "Review QA output."
                 }
               ])

      assert Enum.map(lemmings, & &1.slug) == ["code-reviewer", "qa-reviewer"]
      assert length(Lemmings.list_lemmings(department)) == 2
    end

    test "returns validation errors per record and does not partially commit on failure" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:error, [%{index: 1, error: changeset}]} =
               ImportExport.import_lemmings(world, city, department, [
                 %{"slug" => "code-reviewer", "name" => "Code Reviewer", "status" => "draft"},
                 %{"slug" => "missing-name", "status" => "draft"}
               ])

      assert "can't be blank" in errors_on(changeset).name
      assert Lemmings.list_lemmings(department) == []
    end

    test "returns validation error on slug conflict" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      insert(:lemming, world: world, city: city, department: department, slug: "code-reviewer")

      assert {:error, [%{index: 0, error: changeset}]} =
               ImportExport.import_lemmings(world, city, department, %{
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft"
               })

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "rejects unsupported schema_version values" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:error, :unsupported_schema_version} =
               ImportExport.import_lemmings(world, city, department, %{
                 "schema_version" => 2,
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft"
               })
    end

    test "rejects a city that does not belong to the target world" do
      world = insert(:world)
      other_world = insert(:world)
      city = insert(:city, world: other_world)
      department = insert(:department, world: other_world, city: city)

      assert {:error, :department_not_in_city_world} =
               ImportExport.import_lemmings(world, city, department, %{
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft"
               })
    end

    test "rejects a department that does not belong to the target city and world" do
      world = insert(:world)
      city = insert(:city, world: world)
      other_world = insert(:world)
      other_city = insert(:city, world: other_world)
      department = insert(:department, world: other_world, city: other_city)

      assert {:error, :department_not_in_city_world} =
               ImportExport.import_lemmings(world, city, department, %{
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft"
               })
    end

    test "accepts missing schema_version" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, [lemming]} =
               ImportExport.import_lemmings(world, city, department, %{
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft"
               })

      assert lemming.slug == "code-reviewer"
    end

    test "ignores unknown extra keys" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, [lemming]} =
               ImportExport.import_lemmings(world, city, department, %{
                 "slug" => "code-reviewer",
                 "name" => "Code Reviewer",
                 "status" => "draft",
                 "extra_field" => "ignored"
               })

      assert lemming.slug == "code-reviewer"
    end

    test "rejects invalid payload shapes" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:error, [%{index: nil, error: :invalid_import_payload}]} =
               ImportExport.import_lemmings(world, city, department, "not-json")

      assert {:error, [%{index: nil, error: :invalid_import_payload}]} =
               ImportExport.import_lemmings(world, city, department, 123)
    end

    test "rejects list payloads containing non-map entries" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:error, [%{index: nil, error: :invalid_import_payload}]} =
               ImportExport.import_lemmings(world, city, department, [
                 %{"slug" => "code-reviewer", "name" => "Code Reviewer", "status" => "draft"},
                 "bad-entry"
               ])
    end

    test "returns ok for an empty import list" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)

      assert {:ok, []} = ImportExport.import_lemmings(world, city, department, [])
    end

    test "roundtrips through export and import" do
      world = insert(:world)
      city = insert(:city, world: world)
      source_department = insert(:department, world: world, city: city)
      target_department = insert(:department, world: world, city: city, slug: "qa")

      source =
        insert(:lemming,
          world: world,
          city: city,
          department: source_department,
          slug: "code-reviewer",
          name: "Code Reviewer",
          description: "Reviews code",
          instructions: "Review pull requests carefully.",
          status: "active",
          limits_config: %LimitsConfig{max_lemmings_per_department: 2},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 30},
          costs_config: %CostsConfig{budgets: %Budgets{monthly_usd: 15.0}},
          models_config: %ModelsConfig{profiles: %{"fast" => %{"provider" => "ollama"}}},
          tools_config: %ToolsConfig{allowed_tools: ["github"], denied_tools: ["shell"]}
        )

      export = ImportExport.export_lemming(source)

      assert {:ok, [imported]} =
               ImportExport.import_lemmings(world, city, target_department, export)

      assert imported.slug == source.slug
      assert imported.name == source.name
      assert imported.description == source.description
      assert imported.instructions == source.instructions
      assert imported.status == source.status
      assert imported.department_id == target_department.id
      assert imported.tools_config.allowed_tools == ["github"]
      assert imported.tools_config.denied_tools == ["shell"]
    end
  end
end
