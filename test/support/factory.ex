defmodule LemmingsOs.Factory do
  @moduledoc false

  use ExMachina.Ecto, repo: LemmingsOs.Repo

  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.CostsConfig.Budgets
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.ReferenceFile
  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileChunk
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World

  def world_factory do
    unique_value = sequence(:world_unique, & &1)
    name = Faker.Company.name()
    slug_base = Helpers.slugify(name)

    %World{
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "unknown",
      last_import_status: "unknown",
      bootstrap_path: "/tmp/worlds/#{slug_base}-#{unique_value}.default.world.yaml",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  def city_factory do
    unique_value = sequence(:city_unique, & &1)
    name = Faker.Address.city()
    slug_base = Helpers.slugify(name)

    %City{
      world: build(:world),
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      node_name: "city#{unique_value}@localhost",
      status: "active",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  def department_factory do
    unique_value = sequence(:department_unique, & &1)
    city = build(:city)

    name =
      "#{Faker.Company.bs()} #{unique_value}" |> String.replace(~r/\s+/u, " ") |> String.trim()

    slug_base = Helpers.slugify(name)

    %Department{
      world: city.world,
      city: city,
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "active",
      notes: "Department #{unique_value} notes",
      tags: ["ops", "priority-#{unique_value}"],
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{}
    }
  end

  def lemming_factory do
    unique_value = sequence(:lemming_unique, & &1)
    department = build(:department)

    name =
      "Lemming #{unique_value} #{Faker.Company.bs()}"
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    slug_base = Helpers.slugify(name)

    %Lemming{
      world: department.world,
      city: department.city,
      department: department,
      slug: "#{slug_base}-#{unique_value}",
      name: name,
      status: "draft",
      collaboration_role: "worker",
      description: "Lemming #{unique_value} description",
      instructions: "Follow the department instructions carefully.",
      limits_config: %LimitsConfig{},
      runtime_config: %RuntimeConfig{},
      costs_config: %CostsConfig{budgets: %Budgets{}},
      models_config: %ModelsConfig{},
      tools_config: %ToolsConfig{}
    }
  end

  def manager_lemming_factory do
    struct!(
      lemming_factory(),
      collaboration_role: "manager",
      name: "Manager #{sequence(:manager_lemming_unique, & &1)}"
    )
  end

  def lemming_instance_factory do
    lemming = build(:lemming)

    %LemmingInstance{
      lemming: lemming,
      world: lemming.world,
      city: lemming.city,
      department: lemming.department,
      status: "created",
      config_snapshot: %{
        "models" => %{},
        "runtime" => %{}
      },
      started_at: nil,
      stopped_at: nil,
      last_activity_at: nil
    }
  end

  def lemming_instance_message_factory do
    instance = build(:lemming_instance)

    %Message{
      lemming_instance: instance,
      world: instance.world,
      role: "user",
      content: Faker.Lorem.sentence(),
      provider: nil,
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      usage: nil
    }
  end

  def tool_execution_factory do
    instance = build(:lemming_instance)

    %ToolExecution{
      lemming_instance: instance,
      world: instance.world,
      tool_name: "fs.read_text_file",
      status: "running",
      args: %{"path" => "notes.txt"},
      result: nil,
      error: nil,
      summary: nil,
      preview: nil,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      completed_at: nil,
      duration_ms: nil
    }
  end

  def lemming_call_factory do
    caller_instance = build(:lemming_instance)

    callee_department =
      build(:department, world: caller_instance.world, city: caller_instance.city)

    callee_lemming =
      build(:lemming,
        world: caller_instance.world,
        city: caller_instance.city,
        department: callee_department
      )

    callee_instance =
      build(:lemming_instance,
        lemming: callee_lemming,
        world: caller_instance.world,
        city: caller_instance.city,
        department: callee_lemming.department
      )

    %LemmingCall{
      world: caller_instance.world,
      city: caller_instance.city,
      caller_department: caller_instance.department,
      callee_department: callee_instance.department,
      caller_lemming: caller_instance.lemming,
      callee_lemming: callee_instance.lemming,
      caller_instance: caller_instance,
      callee_instance: callee_instance,
      request_text: Faker.Lorem.sentence(),
      status: "accepted",
      result_summary: nil,
      error_summary: nil,
      recovery_status: nil,
      started_at: nil,
      completed_at: nil
    }
  end

  def connection_factory do
    world = build(:world)

    %Connection{
      world: world,
      city: nil,
      department: nil,
      type: "mock",
      status: "enabled",
      config: %{
        "mode" => "echo",
        "base_url" => "https://example.test/mock",
        "api_key" => "$MOCK_API_KEY"
      },
      last_test: nil
    }
  end

  def world_connection_factory do
    build(:connection)
  end

  def city_connection_factory do
    city = build(:city)

    build(:connection, world: city.world, city: city, department: nil)
  end

  def department_connection_factory do
    department = build(:department)

    build(:connection,
      world: department.world,
      city: department.city,
      department: department
    )
  end

  def artifact_factory do
    lemming = build(:lemming)

    %Artifact{
      world: lemming.world,
      city: lemming.city,
      department: lemming.department,
      lemming: lemming,
      lemming_instance: nil,
      created_by_tool_execution: nil,
      type: "markdown",
      filename: "artifact-#{sequence(:artifact_unique, & &1)}.md",
      content_type: "text/markdown",
      storage_ref:
        "local://artifacts/#{Ecto.UUID.generate()}/#{Ecto.UUID.generate()}/artifact.md",
      size_bytes: 128,
      checksum: String.duplicate("a", 64),
      status: "ready",
      notes: nil,
      metadata: %{"source" => "manual_promotion"}
    }
  end

  def knowledge_item_factory do
    lemming = build(:lemming)

    %KnowledgeItem{
      world: lemming.world,
      city: lemming.city,
      department: lemming.department,
      lemming: nil,
      artifact: nil,
      kind: "memory",
      title: "Memory #{sequence(:knowledge_item_unique, & &1)}",
      content: "Stored knowledge content",
      tags: ["memory", "ops"],
      source: "user",
      status: "active",
      creator_type: "user",
      creator_id: "operator"
    }
  end

  def knowledge_source_file_factory do
    knowledge_item = build(:knowledge_item, kind: "source_file", status: "pending_index")
    unique_value = sequence(:knowledge_source_file_unique, & &1)

    %SourceFile{
      knowledge_item: knowledge_item,
      source_file_type: "company_knowledge",
      original_filename: "knowledge-#{unique_value}.md",
      content_type: "text/markdown",
      size_bytes: 1_024,
      checksum: String.duplicate("b", 64),
      storage_ref: "knowledge://local/source_files/#{Ecto.UUID.generate()}/document.md",
      extraction_status: "pending",
      indexing_status: "pending",
      failure_reason: nil,
      extracted_at: nil,
      indexed_at: nil,
      metadata: %{"origin" => "upload"}
    }
  end

  def knowledge_reference_file_factory do
    knowledge_item = build(:knowledge_item, kind: "reference_file", status: "active")
    unique_value = sequence(:knowledge_reference_file_unique, & &1)

    %ReferenceFile{
      knowledge_item: knowledge_item,
      reference_ref: "kref:#{Ecto.UUID.generate()}",
      reference_file_type: "quote_template",
      original_filename: "reference-#{unique_value}.md",
      content_type: "text/markdown",
      size_bytes: 1_024,
      checksum: String.duplicate("d", 64),
      storage_ref: "knowledge://local/reference_files/#{Ecto.UUID.generate()}/reference.md",
      metadata: %{"origin" => "upload"},
      safe_to_read: true,
      safe_to_pass_to_tools: true
    }
  end

  def knowledge_source_file_chunk_factory do
    source_file = build(:knowledge_source_file)

    %SourceFileChunk{
      knowledge_item: source_file.knowledge_item,
      knowledge_source_file: source_file,
      chunk_index: 0,
      chunk_ref: "chunk-#{sequence(:knowledge_source_file_chunk_unique, & &1)}",
      content: "Chunk content for retrieval.",
      content_hash: String.duplicate("c", 64),
      token_count: 20,
      char_count: 28,
      metadata: %{"section" => "intro"}
    }
  end
end
