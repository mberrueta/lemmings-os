defmodule LemmingsOs.SeedsTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Cities
  alias LemmingsOs.Connections
  alias LemmingsOs.Departments
  alias LemmingsOs.Knowledge
  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor.CommunicationRuntime
  alias LemmingsOs.Lemmings
  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  describe "priv/repo/seeds.exs" do
    test "rerunning seeds keeps demo hierarchy idempotent and prunes non-demo topology" do
      Repo.delete_all(World)

      run_seeds!()

      world = fetch_demo_world!()
      city = fetch_demo_city!(world)
      department = fetch_demo_department!(city)

      seeded_counts = hierarchy_counts(world, city, department)
      seeded_lemming_tools = lemming_tools_by_slug(department)
      seeded_lemmings = Lemmings.list_lemmings(department)
      seeded_source_files = source_files_by_filename(department)
      seeded_reference_refs = reference_refs(world)
      seeded_customer_memories = customer_memories_by_email(department)
      seeded_gmail = Connections.get_connection_by_type(world, "gmail")

      assert is_map(seeded_lemming_tools)

      assert Map.keys(seeded_lemming_tools) |> Enum.sort() == [
               "sales_knowledge_librarian",
               "sales_manager",
               "sales_quote_specialist",
               "sales_web_researcher"
             ]

      assert seeded_source_files == %{
               "company_profile.md" => %{
                 source_file_type: "company_knowledge",
                 title: "Company Profile"
               },
               "price_list.md" => %{source_file_type: "price_list", title: "Price List"}
             }

      assert seeded_reference_refs == [
               "kref:sales_demo_email_examples",
               "kref:sales_demo_quote_template"
             ]

      assert seeded_customer_memories == %{
               "carlos.pereira@example.com" => 5,
               "joao.silva@example.com" => 5,
               "mariana.costa@example.com" => 5
             }

      assert seeded_gmail.status == "enabled"

      sales_manager =
        Enum.find(seeded_lemmings, fn lemming ->
          lemming.slug == "sales_manager"
        end)

      refute is_nil(sales_manager)
      assert sales_manager.status == "active"
      assert sales_manager.collaboration_role == "manager"
      assert "lemming.call" in (sales_manager.tools_config.allowed_tools || [])
      refute String.contains?(sales_manager.instructions, "Available specialists:")

      assert String.contains?(
               sales_manager.instructions,
               "Use the Available Lemming Calls section provided by the runtime"
             )

      assert String.contains?(
               sales_manager.instructions,
               "Never ask sales_knowledge_librarian for current external data"
             )

      assert String.contains?(
               sales_manager.instructions,
               "Use sales_web_researcher for exchange rates"
             )

      specialist_lemmings =
        seeded_lemmings
        |> Enum.filter(fn lemming ->
          lemming.slug in [
            "sales_knowledge_librarian",
            "sales_web_researcher",
            "sales_quote_specialist"
          ]
        end)

      assert length(specialist_lemmings) == 3

      assert Enum.all?(specialist_lemmings, fn lemming ->
               lemming.status == "active" and lemming.collaboration_role == "worker" and
                 lemming.department_id == sales_manager.department_id
             end)

      assert {:ok, manager_instance} =
               LemmingInstances.spawn_instance(sales_manager, "Prepare quote")

      targets = LemmingCalls.available_targets(manager_instance)

      assert Enum.map(targets, & &1.slug) == [
               "sales_knowledge_librarian",
               "sales_quote_specialist",
               "sales_web_researcher"
             ]

      runtime_snapshot =
        CommunicationRuntime.model_config_snapshot(
          manager_instance.config_snapshot,
          LemmingCalls,
          manager_instance
        )

      assert Map.has_key?(runtime_snapshot, :lemming_call_targets)

      assert {:ok, %{request: request}} =
               ModelRuntime.debug_request(runtime_snapshot, [], %{
                 content: "Prepare a customer quote"
               })

      assert %{role: "system", content: system_prompt} = Enum.at(request.messages, 0)
      assert String.contains?(system_prompt, "Lemming Instructions:")
      assert String.contains?(system_prompt, "Manager Planning Rules:")
      refute String.contains?(system_prompt, "Available Tools:")
      assert String.contains?(system_prompt, "Available Lemming Calls:")
      assert String.contains?(system_prompt, "sales_knowledge_librarian")
      assert String.contains?(system_prompt, "sales_web_researcher")
      assert String.contains?(system_prompt, "sales_quote_specialist")
      assert String.contains?(system_prompt, "\"action\":\"reply\"")
      assert String.contains?(system_prompt, "\"action\":\"lemming_call\"")
      refute String.contains?(system_prompt, "\"action\":\"tool_call\"")
      refute String.contains?(system_prompt, "continue_call_id")
      refute String.contains?(system_prompt, "slug-or-capability")
      refute String.contains?(system_prompt, "Available specialists:")

      create_non_demo_data!()
      run_seeds!()

      world = fetch_demo_world!()
      city = fetch_demo_city!(world)
      department = fetch_demo_department!(city)
      rerun_gmail = Connections.get_connection_by_type(world, "gmail")

      assert hierarchy_counts(world, city, department) == seeded_counts
      assert length(Worlds.list_worlds()) == 1
      assert Enum.map(Cities.list_cities(world), & &1.slug) == ["demo_city"]
      assert Enum.map(Departments.list_departments(city), & &1.slug) == ["sales_demo"]

      assert lemming_tools_by_slug(department) == seeded_lemming_tools
      assert source_files_by_filename(department) == seeded_source_files
      assert reference_refs(world) == seeded_reference_refs
      assert customer_memories_by_email(department) == seeded_customer_memories
      assert rerun_gmail.id == seeded_gmail.id
    end
  end

  defp run_seeds! do
    "priv/repo/seeds.exs"
    |> Path.expand(File.cwd!())
    |> Code.eval_file()
  end

  defp fetch_demo_world! do
    world = Worlds.get_default_world()
    assert world.slug == "demo_world"
    world
  end

  defp fetch_demo_city!(world) do
    city = Cities.get_city_by_slug(world, "demo_city")
    assert city.name == "Demo City"
    city
  end

  defp fetch_demo_department!(city) do
    department = Departments.get_department_by_slug(city, "sales_demo")
    assert department.name == "Sales Demo"
    department
  end

  defp hierarchy_counts(world, city, department) do
    %{
      world_count: length(Worlds.list_worlds()),
      city_count: length(Cities.list_cities(world)),
      department_count: length(Departments.list_departments(city)),
      department_lemming_count: length(Lemmings.list_lemmings(department)),
      world_lemming_count: length(Lemmings.list_lemmings(world))
    }
  end

  defp lemming_tools_by_slug(department) do
    department
    |> Lemmings.list_lemmings()
    |> Map.new(fn lemming ->
      allowed_tools = Enum.sort(lemming.tools_config.allowed_tools || [])
      denied_tools = Enum.sort(lemming.tools_config.denied_tools || [])
      {lemming.slug, %{allowed_tools: allowed_tools, denied_tools: denied_tools}}
    end)
  end

  defp reference_refs(world) do
    world
    |> Knowledge.list_reference_files(status: "active")
    |> Enum.map(& &1.reference_ref)
    |> Enum.sort()
  end

  defp source_files_by_filename(department) do
    department
    |> Knowledge.list_source_files()
    |> Enum.filter(fn source_file ->
      source_file.original_filename in ["company_profile.md", "price_list.md"]
    end)
    |> Map.new(fn source_file ->
      {
        source_file.original_filename,
        %{
          source_file_type: source_file.source_file_type,
          title: source_file.knowledge_item.title
        }
      }
    end)
  end

  defp customer_memories_by_email(department) do
    department
    |> Knowledge.list_memories(status: "active", source: "user")
    |> Enum.filter(fn memory ->
      String.starts_with?(memory.title, "[demo_seed][sales_demo][customer_memory]")
    end)
    |> Enum.reduce(%{}, fn memory, acc ->
      email_tag =
        Enum.find(memory.tags, fn tag ->
          String.starts_with?(tag, "customer_email:")
        end)

      email = String.replace_prefix(email_tag || "customer_email:unknown", "customer_email:", "")
      Map.update(acc, email, 1, &(&1 + 1))
    end)
  end

  defp create_non_demo_data! do
    {:ok, extra_world} =
      Worlds.upsert_world(%{
        slug: "extra_world",
        name: "Extra World",
        status: "ok",
        last_import_status: "ok",
        bootstrap_source: "seed",
        bootstrap_path: "priv/extra.world.yaml"
      })

    {:ok, extra_city} =
      Cities.create_city(extra_world, %{
        slug: "extra_city",
        name: "Extra City",
        node_name: "extra_city@localhost",
        host: "127.0.0.1",
        distribution_port: 9120,
        epmd_port: 4372,
        status: "active"
      })

    {:ok, extra_department} =
      Departments.create_department(extra_city, %{
        slug: "extra_department",
        name: "Extra Department",
        status: "active",
        notes: "Should be pruned",
        tags: ["extra"]
      })

    {:ok, _extra_lemming} =
      Lemmings.create_lemming(extra_world, extra_city, extra_department, %{
        slug: "extra_lemming",
        name: "Extra Lemming",
        status: "active",
        collaboration_role: "worker",
        description: "Should be pruned",
        instructions: "Temporary seeded helper."
      })
  end
end
