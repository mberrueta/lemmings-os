defmodule LemmingsOs.KnowledgeTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFileChunk
  alias LemmingsOs.Events.Event
  alias LemmingsOs.Repo

  doctest LemmingsOs.Knowledge

  defmodule StubReferenceExtractorExecutor do
    def run(command, _args, _timeout_ms) do
      output =
        case command do
          "markitdown" ->
            Application.get_env(:lemmings_os, :knowledge_reference_markitdown_output, "")

          "pdftotext" ->
            Application.get_env(:lemmings_os, :knowledge_reference_pdftotext_output, "")

          _command ->
            ""
        end

      {:ok, %{stdout: output, exit_status: 0}}
    end
  end

  describe "create_memory/3" do
    test "persists user memory with runtime-owned defaults" do
      world = insert(:world)

      assert {:ok, memory} =
               Knowledge.create_memory(world, %{
                 title: "ACME - Language",
                 content: "Use Portuguese for outbound summaries.",
                 tags: ["customer:acme", "language:pt-BR"],
                 source: "llm",
                 status: "deleted",
                 kind: "file"
               })

      assert memory.world_id == world.id
      assert is_nil(memory.city_id)
      assert is_nil(memory.department_id)
      assert is_nil(memory.lemming_id)
      assert memory.kind == "memory"
      assert memory.source == "user"
      assert memory.status == "active"
      assert memory.title == "ACME - Language"
      assert memory.content == "Use Portuguese for outbound summaries."
      assert memory.tags == ["customer:acme", "language:pt-BR"]
    end

    test "returns invalid_scope for malformed scope input" do
      assert {:error, :invalid_scope} = Knowledge.create_memory(%{}, %{title: "A", content: "B"})
    end

    test "returns scope_mismatch when attrs attempt a different hierarchy path" do
      world = insert(:world)
      other_world = insert(:world)

      assert {:error, :scope_mismatch} =
               Knowledge.create_memory(world, %{
                 world_id: other_world.id,
                 title: "Mismatch",
                 content: "Should fail"
               })
    end

    test "accepts optional creator metadata" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      assert {:ok, memory} =
               Knowledge.create_memory(
                 lemming,
                 %{title: "Creator metadata", content: "Persist creator fields"},
                 creator: %{
                   creator_type: "user",
                   creator_id: "operator-123",
                   creator_lemming_id: lemming.id
                 }
               )

      assert memory.creator_type == "user"
      assert memory.creator_id == "operator-123"
      assert memory.creator_lemming_id == lemming.id
    end

    test "emits safe memory.created event payload" do
      world = insert(:world)

      assert {:ok, memory} =
               Knowledge.create_memory(world, %{
                 title: "ACME - Language",
                 content: "Use Portuguese for outbound summaries.",
                 tags: ["customer:acme", "language:pt-BR"]
               })

      event =
        Repo.one!(
          from(e in Event,
            where: e.event_type == "knowledge.memory.created" and e.resource_id == ^memory.id
          )
        )

      assert event.payload["knowledge_item_id"] == memory.id
      assert event.payload["world_id"] == world.id
      refute Map.has_key?(event.payload, "content")
      refute Map.has_key?(event.payload, "path")
    end
  end

  describe "get_memory/3 visibility" do
    test "enforces allowed visibility by hierarchy" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      sibling_department = insert(:department, world: world, city: city)

      sibling_lemming =
        insert(:lemming, world: world, city: city, department: sibling_department)

      world_memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          title: "World memory"
        )

      city_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: nil,
          lemming: nil,
          title: "City memory"
        )

      department_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: department,
          lemming: nil,
          title: "Department memory"
        )

      lemming_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: department,
          lemming: lemming,
          title: "Lemming memory"
        )

      sibling_lemming_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: sibling_department,
          lemming: sibling_lemming,
          title: "Sibling lemming memory"
        )

      assert %KnowledgeItem{id: id} = Knowledge.get_memory(world, world_memory.id)
      assert id == world_memory.id
      assert is_nil(Knowledge.get_memory(world, city_memory.id))

      assert %KnowledgeItem{id: id} = Knowledge.get_memory(department, world_memory.id)
      assert id == world_memory.id
      assert %KnowledgeItem{id: id} = Knowledge.get_memory(department, city_memory.id)
      assert id == city_memory.id
      assert %KnowledgeItem{id: id} = Knowledge.get_memory(department, department_memory.id)
      assert id == department_memory.id
      assert %KnowledgeItem{id: id} = Knowledge.get_memory(department, lemming_memory.id)
      assert id == lemming_memory.id
      assert is_nil(Knowledge.get_memory(department, sibling_lemming_memory.id))

      assert %KnowledgeItem{id: id} = Knowledge.get_memory(lemming, department_memory.id)
      assert id == department_memory.id
      assert %KnowledgeItem{id: id} = Knowledge.get_memory(lemming, lemming_memory.id)
      assert id == lemming_memory.id
      assert is_nil(Knowledge.get_memory(lemming, sibling_lemming_memory.id))
    end

    test "returns nil for non-binary ids and invalid scope" do
      world = insert(:world)

      assert is_nil(Knowledge.get_memory(world, 123))
      assert is_nil(Knowledge.get_memory(%{}, Ecto.UUID.generate()))
    end
  end

  describe "update_memory/3" do
    test "updates only user-editable fields at exact scope" do
      world = insert(:world)

      memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          source: "user",
          status: "active"
        )

      assert {:ok, updated} =
               Knowledge.update_memory(world, memory, %{
                 title: "Updated title",
                 content: "Updated content",
                 tags: ["updated"],
                 source: "llm",
                 status: "inactive"
               })

      assert updated.title == "Updated title"
      assert updated.content == "Updated content"
      assert updated.tags == ["updated"]
      assert updated.source == "user"
      assert updated.status == "active"
    end

    test "returns scope_mismatch when scope does not own the memory" do
      world = insert(:world)
      city = insert(:city, world: world)

      memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil
        )

      assert {:error, :scope_mismatch} =
               Knowledge.update_memory(city, memory, %{title: "Nope", content: "Nope"})
    end

    test "emits memory.updated event" do
      world = insert(:world)
      memory = insert(:knowledge_item, world: world, city: nil, department: nil, lemming: nil)

      assert {:ok, _updated} =
               Knowledge.update_memory(world, memory, %{title: "Updated", content: "Updated"})

      assert Repo.exists?(
               from(e in Event,
                 where: e.event_type == "knowledge.memory.updated" and e.resource_id == ^memory.id
               )
             )
    end
  end

  describe "delete_memory/2" do
    test "hard deletes local memory" do
      world = insert(:world)

      memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil
        )

      assert {:ok, deleted} = Knowledge.delete_memory(world, memory)
      assert deleted.id == memory.id
      assert is_nil(Repo.get(KnowledgeItem, memory.id))
    end

    test "returns scope_mismatch outside exact scope" do
      world = insert(:world)
      city = insert(:city, world: world)

      memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil
        )

      assert {:error, :scope_mismatch} = Knowledge.delete_memory(city, memory)
      assert Repo.get(KnowledgeItem, memory.id)
    end

    test "emits memory.deleted event" do
      world = insert(:world)
      memory = insert(:knowledge_item, world: world, city: nil, department: nil, lemming: nil)

      assert {:ok, deleted} = Knowledge.delete_memory(world, memory)

      assert Repo.exists?(
               from(e in Event,
                 where:
                   e.event_type == "knowledge.memory.deleted" and e.resource_id == ^deleted.id
               )
             )
    end
  end

  describe "list_effective_memories/2" do
    test "department view includes inherited world/city/department and local lemming memories" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)

      sibling_department = insert(:department, world: world, city: city)

      sibling_lemming =
        insert(:lemming, world: world, city: city, department: sibling_department)

      world_memory =
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          title: "World Memory"
        )

      city_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: nil,
          lemming: nil,
          title: "City Memory"
        )

      department_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: department,
          lemming: nil,
          title: "Department Memory"
        )

      lemming_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: department,
          lemming: lemming,
          title: "Lemming Memory"
        )

      _sibling_memory =
        insert(:knowledge_item,
          world: world,
          city: city,
          department: sibling_department,
          lemming: sibling_lemming,
          title: "Sibling Memory"
        )

      assert {:ok, page} = Knowledge.list_effective_memories(department)
      ids = Enum.map(page.entries, & &1.memory.id)

      assert world_memory.id in ids
      assert city_memory.id in ids
      assert department_memory.id in ids
      assert lemming_memory.id in ids
      refute Enum.any?(page.entries, &(&1.memory.title == "Sibling Memory"))

      world_row = Enum.find(page.entries, &(&1.memory.id == world_memory.id))
      city_row = Enum.find(page.entries, &(&1.memory.id == city_memory.id))
      department_row = Enum.find(page.entries, &(&1.memory.id == department_memory.id))
      lemming_row = Enum.find(page.entries, &(&1.memory.id == lemming_memory.id))

      assert world_row.owner_scope == "world"
      assert world_row.inherited?
      refute world_row.local?
      refute world_row.descendant?

      assert city_row.owner_scope == "city"
      assert city_row.inherited?
      refute city_row.local?
      refute city_row.descendant?

      assert department_row.owner_scope == "department"
      assert department_row.local?
      refute department_row.inherited?
      refute department_row.descendant?

      assert lemming_row.owner_scope == "lemming"
      refute lemming_row.local?
      refute lemming_row.inherited?
      assert lemming_row.descendant?
    end

    test "supports query, source and status filters with stable pagination defaults" do
      world = insert(:world)

      Enum.each(1..30, fn index ->
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          title: "World Memory #{index}",
          tags: ["tag:#{index}"],
          source: if(rem(index, 2) == 0, do: "llm", else: "user"),
          status: "active",
          inserted_at: DateTime.add(DateTime.utc_now(), index, :second)
        )
      end)

      assert {:ok, page_1} = Knowledge.list_effective_memories(world)
      assert page_1.limit == 25
      assert page_1.offset == 0
      assert page_1.total_count == 30
      assert length(page_1.entries) == 25

      assert {:ok, page_2} = Knowledge.list_effective_memories(world, offset: 25)
      assert page_2.total_count == 30
      assert length(page_2.entries) == 5

      page_1_ids = Enum.map(page_1.entries, & &1.memory.id) |> MapSet.new()
      page_2_ids = Enum.map(page_2.entries, & &1.memory.id) |> MapSet.new()
      assert MapSet.disjoint?(page_1_ids, page_2_ids)

      assert {:ok, filtered_by_source} = Knowledge.list_effective_memories(world, source: "llm")
      assert Enum.all?(filtered_by_source.entries, &(&1.memory.source == "llm"))

      assert {:ok, filtered_by_query} = Knowledge.list_effective_memories(world, q: "tag:12")

      assert Enum.all?(
               filtered_by_query.entries,
               &String.contains?(Enum.join(&1.memory.tags, " "), "tag:12")
             )
    end

    test "honors exact non-aligned offsets across memory list APIs" do
      world = insert(:world)

      Enum.each(1..6, fn index ->
        insert(:knowledge_item,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          title: "World Memory #{index}",
          inserted_at: DateTime.add(DateTime.utc_now(), index, :second)
        )
      end)

      assert {:ok, effective_page_0} =
               Knowledge.list_effective_memories(world, limit: 3, offset: 0)

      assert {:ok, effective_page_1} =
               Knowledge.list_effective_memories(world, limit: 2, offset: 1)

      assert effective_page_1.offset == 1

      assert effective_page_1.entries |> Enum.map(& &1.memory.id) ==
               effective_page_0.entries
               |> Enum.drop(1)
               |> Enum.take(2)
               |> Enum.map(& &1.memory.id)

      assert {:ok, scope_page_0} = Knowledge.list_scope_memories(world, limit: 3, offset: 0)
      assert {:ok, scope_page_1} = Knowledge.list_scope_memories(world, limit: 2, offset: 1)
      assert scope_page_1.offset == 1

      assert scope_page_1.entries |> Enum.map(& &1.memory.id) ==
               scope_page_0.entries |> Enum.drop(1) |> Enum.take(2) |> Enum.map(& &1.memory.id)

      assert {:ok, all_page_0} = Knowledge.list_all_memories(limit: 3, offset: 0)
      assert {:ok, all_page_1} = Knowledge.list_all_memories(limit: 2, offset: 1)
      assert all_page_1.offset == 1

      assert all_page_1.entries |> Enum.map(& &1.memory.id) ==
               all_page_0.entries |> Enum.drop(1) |> Enum.take(2) |> Enum.map(& &1.memory.id)
    end

    test "fails closed for invalid scope" do
      assert {:error, :invalid_scope} = Knowledge.list_effective_memories(%{})
    end
  end

  describe "create_source_file_upload/3" do
    test "stores upload and creates source-file knowledge item" do
      old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)
      storage_root = Path.join(System.tmp_dir!(), "knowledge_upload_test_#{Ecto.UUID.generate()}")
      source_path = Path.join(storage_root, "source.txt")

      on_exit(fn ->
        File.rm_rf!(storage_root)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
        end
      end)

      File.mkdir_p!(storage_root)
      File.write!(source_path, "hello source file upload")

      Application.put_env(:lemmings_os, :knowledge_source_file_storage,
        backend: :local,
        root_path: storage_root,
        max_file_size_bytes: 1024 * 1024
      )

      world = insert(:world)

      assert {:ok, %{knowledge_item: knowledge_item, source_file: source_file}} =
               Knowledge.create_source_file_upload(
                 world,
                 %{
                   title: "Uploaded Source",
                   content: "Source file registered for indexing.",
                   tags: ["customer:acme"],
                   source_file_type: "company_knowledge",
                   original_filename: "source.txt",
                   content_type: "text/plain"
                 },
                 source_path
               )

      assert knowledge_item.kind == "source_file"
      assert knowledge_item.status == "pending_index"
      assert source_file.knowledge_item_id == knowledge_item.id
      assert source_file.size_bytes > 0
      assert String.starts_with?(source_file.storage_ref, "local://knowledge_source_files/")
      assert source_file.extraction_status == "pending"
      assert source_file.indexing_status == "pending"
    end
  end

  describe "update_source_file_metadata/3" do
    test "updates editable source-file and knowledge item metadata at exact scope" do
      world = insert(:world)

      source_file =
        insert(:knowledge_source_file,
          knowledge_item:
            build(:knowledge_item,
              world: world,
              city: nil,
              department: nil,
              lemming: nil,
              kind: "source_file",
              status: "ready",
              title: "Old title",
              tags: ["old"]
            ),
          source_file_type: "company_knowledge",
          extraction_status: "ready",
          indexing_status: "ready"
        )

      assert {:ok, %{knowledge_item: updated_item, source_file: updated_source_file}} =
               Knowledge.update_source_file_metadata(world, source_file, %{
                 title: "New title",
                 tags: ["new", "customer:acme"],
                 source_file_type: "policy",
                 metadata: %{"origin" => "edited"}
               })

      assert updated_item.title == "New title"
      assert updated_item.tags == ["new", "customer:acme"]
      assert updated_source_file.source_file_type == "policy"
      assert updated_source_file.metadata == %{"origin" => "edited"}
    end
  end

  describe "reference file lifecycle APIs" do
    test "create_reference_file/2 persists reference file and keeps summary-only knowledge content" do
      world = insert(:world)
      content_sentinel = "SECRET_CONTENT_SHOULD_NOT_LEAK"

      assert {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} =
               Knowledge.create_reference_file(world, %{
                 title: "Quote template",
                 content: content_sentinel,
                 tags: ["quote", "template"],
                 reference_file_type: "quote_template",
                 original_filename: "quote.md",
                 content_type: "text/markdown",
                 size_bytes: 128,
                 checksum: String.duplicate("a", 64),
                 storage_ref:
                   "local://knowledge_reference_files/#{world.id}/#{Ecto.UUID.generate()}/quote.md"
               })

      assert knowledge_item.kind == "reference_file"
      assert knowledge_item.status == "active"
      assert knowledge_item.content == content_sentinel
      assert reference_file.knowledge_item_id == knowledge_item.id
      assert reference_file.reference_file_type == "quote_template"
      assert String.starts_with?(reference_file.reference_ref, "kref:")

      event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.created" and
                event.resource_id == ^reference_file.id and
                event.world_id == ^world.id
          )
        )

      assert fetch_map(event.payload, :knowledge_item_id) == knowledge_item.id
      assert fetch_map(event.payload, :reference_file_id) == reference_file.id
      assert fetch_map(event.payload, :reference_ref) == reference_file.reference_ref
      assert fetch_map(event.payload, :reference_file_type) == reference_file.reference_file_type
      assert fetch_map(event.payload, :status) == "active"
      refute Map.has_key?(event.payload, "content")
      refute inspect(event.payload) =~ content_sentinel
      refute inspect(event.payload) =~ reference_file.storage_ref
      refute inspect(event.payload) =~ "knowledge_reference_files"
    end

    test "create_reference_file_upload/3 stores bytes and creates managed rows" do
      old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      storage_root = Path.join(System.tmp_dir!(), "reference_upload_test_#{Ecto.UUID.generate()}")
      source_path = Path.join(storage_root, "template.md")

      on_exit(fn ->
        File.rm_rf!(storage_root)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
        end
      end)

      File.mkdir_p!(storage_root)
      File.write!(source_path, "hello reference file upload")

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: storage_root,
        max_file_size_bytes: 1024 * 1024
      )

      world = insert(:world)

      assert {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} =
               Knowledge.create_reference_file_upload(
                 world,
                 %{
                   title: "Uploaded template",
                   content: "Uploaded template summary.",
                   tags: ["template"],
                   reference_file_type: "quote_template",
                   original_filename: "template.md",
                   content_type: "text/markdown"
                 },
                 source_path
               )

      assert knowledge_item.kind == "reference_file"
      assert reference_file.size_bytes > 0
      assert String.starts_with?(reference_file.storage_ref, "local://knowledge_reference_files/")
    end

    test "update/archive/list/descriptor enforce scope and active availability" do
      world = insert(:world)
      city = insert(:city, world: world)

      reference_file =
        insert(:knowledge_reference_file,
          knowledge_item:
            build(:knowledge_item,
              world: world,
              city: nil,
              department: nil,
              lemming: nil,
              kind: "reference_file",
              status: "active",
              title: "Old title",
              tags: ["old"]
            ),
          storage_ref:
            "local://knowledge_reference_files/#{world.id}/#{Ecto.UUID.generate()}/reference.md"
        )

      assert {:ok, %{knowledge_item: updated_item, reference_file: updated_reference}} =
               Knowledge.update_reference_file_metadata(world, reference_file, %{
                 title: "New title",
                 content: "New summary",
                 tags: ["new"],
                 reference_file_type: "style_guide"
               })

      assert updated_item.title == "New title"
      assert updated_reference.reference_file_type == "style_guide"

      assert Repo.exists?(
               from(event in Event,
                 where:
                   event.event_type == "knowledge.reference_file.updated" and
                     event.resource_id == ^updated_reference.id and
                     event.world_id == ^world.id
               )
             )

      updated_event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.updated" and
                event.resource_id == ^updated_reference.id and
                event.world_id == ^world.id,
            order_by: [desc: event.inserted_at],
            limit: 1
          )
        )

      assert fetch_map(updated_event.payload, :knowledge_item_id) == updated_item.id
      assert fetch_map(updated_event.payload, :reference_file_id) == updated_reference.id
      refute Map.has_key?(updated_event.payload, "storage_ref")
      refute inspect(updated_event.payload) =~ updated_reference.storage_ref

      assert {:error, :scope_mismatch} =
               Knowledge.update_reference_file_metadata(city, reference_file, %{title: "nope"})

      descriptor = Knowledge.build_reference_file_descriptor(updated_reference)
      assert descriptor.knowledge_item_id == updated_item.id
      refute Map.has_key?(descriptor, :storage_ref)

      assert {:ok, effective_before_archive} = Knowledge.list_effective_reference_files(city)
      assert Enum.any?(effective_before_archive, &(&1.reference_file.id == reference_file.id))

      assert {:ok, %{knowledge_item: archived_item}} =
               Knowledge.archive_reference_file(world, updated_reference)

      assert archived_item.status == "archived"

      assert Repo.exists?(
               from(event in Event,
                 where:
                   event.event_type == "knowledge.reference_file.archived" and
                     event.resource_id == ^updated_reference.id and
                     event.world_id == ^world.id
               )
             )

      archived_event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.archived" and
                event.resource_id == ^updated_reference.id and
                event.world_id == ^world.id,
            order_by: [desc: event.inserted_at],
            limit: 1
          )
        )

      assert fetch_map(archived_event.payload, :status) == "archived"
      refute Map.has_key?(archived_event.payload, "content")
      refute inspect(archived_event.payload) =~ updated_reference.storage_ref

      assert {:ok, effective_after_archive} = Knowledge.list_effective_reference_files(city)
      refute Enum.any?(effective_after_archive, &(&1.reference_file.id == reference_file.id))
    end

    test "availability and search are scoped, filtered, and sorted by nearby scope" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)
      sibling_department = insert(:department, world: world, city: city)
      other_world = insert(:world)

      world_file =
        create_reference_file_for(world, %{
          title: "World quote template",
          tags: ["quote"],
          reference_file_type: "quote_template"
        })

      city_file =
        create_reference_file_for(city, %{
          title: "City quote template",
          tags: ["quote", "regional"],
          reference_file_type: "quote_template"
        })

      department_file =
        create_reference_file_for(department, %{
          title: "Department quote template",
          tags: ["quote", "preferred"],
          reference_file_type: "quote_template"
        })

      lemming_file =
        create_reference_file_for(lemming, %{
          title: "Lemming quote template",
          tags: ["quote", "variant"],
          reference_file_type: "quote_template"
        })

      _sibling_file =
        create_reference_file_for(sibling_department, %{
          title: "Sibling quote template",
          tags: ["quote"],
          reference_file_type: "quote_template"
        })

      _cross_world_file =
        create_reference_file_for(other_world, %{
          title: "Cross-world quote template",
          tags: ["quote"],
          reference_file_type: "quote_template"
        })

      archived_file =
        create_reference_file_for(department, %{
          title: "Archived quote template",
          tags: ["quote"],
          reference_file_type: "quote_template"
        })

      {:ok, %{knowledge_item: archived_item}} =
        Knowledge.archive_reference_file(department, archived_file)

      assert archived_item.status == "archived"

      assert {:ok, available} = Knowledge.list_available_reference_files(department)
      available_ids = Enum.map(available, & &1.reference_file.id)

      assert available_ids == [
               department_file.id,
               lemming_file.id,
               city_file.id,
               world_file.id
             ]

      assert {:ok, page} =
               Knowledge.search_reference_files(department,
                 type: "quote_template",
                 tags: ["quote"],
                 q: "quote",
                 limit: 10
               )

      ids = Enum.map(page.entries, & &1.reference_file.id)
      assert ids == available_ids
      refute archived_file.id in ids
      refute Enum.any?(page.entries, &(&1.reference_file.knowledge_item.title =~ "Sibling"))

      refute Enum.any?(
               page.entries,
               &(&1.reference_file.knowledge_item.world_id == other_world.id)
             )

      assert Enum.all?(page.entries, &Map.has_key?(&1, :descriptor))
      assert page.total_count == 4
    end

    test "scope enforcement keeps World/City/Department/Lemming views isolated from siblings and cross-world items" do
      world = insert(:world)
      city = insert(:city, world: world)
      department = insert(:department, world: world, city: city)
      lemming = insert(:lemming, world: world, city: city, department: department)
      sibling_department = insert(:department, world: world, city: city)
      other_world = insert(:world)

      world_file = create_reference_file_for(world, %{title: "World template"})
      city_file = create_reference_file_for(city, %{title: "City template"})
      department_file = create_reference_file_for(department, %{title: "Department template"})
      lemming_file = create_reference_file_for(lemming, %{title: "Lemming template"})

      sibling_file =
        create_reference_file_for(sibling_department, %{title: "Sibling department template"})

      other_world_file = create_reference_file_for(other_world, %{title: "Other world template"})

      assert {:ok, world_available} = Knowledge.list_available_reference_files(world)
      assert Enum.map(world_available, & &1.reference_file.id) == [world_file.id]

      assert {:ok, city_available} = Knowledge.list_available_reference_files(city)

      assert Enum.map(city_available, & &1.reference_file.id) == [city_file.id, world_file.id]

      assert {:ok, department_available} = Knowledge.list_available_reference_files(department)

      assert Enum.map(department_available, & &1.reference_file.id) == [
               department_file.id,
               lemming_file.id,
               city_file.id,
               world_file.id
             ]

      assert {:ok, lemming_available} = Knowledge.list_available_reference_files(lemming)

      assert Enum.map(lemming_available, & &1.reference_file.id) == [
               lemming_file.id,
               department_file.id,
               city_file.id,
               world_file.id
             ]

      assert {:ok, department_search} =
               Knowledge.search_reference_files(department, q: "template")

      department_ids = Enum.map(department_search.entries, & &1.reference_file.id)
      assert department_file.id in department_ids
      assert lemming_file.id in department_ids
      assert city_file.id in department_ids
      assert world_file.id in department_ids
      refute sibling_file.id in department_ids
      refute other_world_file.id in department_ids

      assert {:error, :not_found} =
               Knowledge.read_reference_file(department, sibling_file.reference_ref)

      assert {:error, :not_found} =
               Knowledge.read_reference_file(department, other_world_file.reference_ref)
    end

    test "read_reference_file/3 returns bounded direct text and safe descriptors" do
      old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      storage_root = Path.join(System.tmp_dir!(), "reference_read_test_#{Ecto.UUID.generate()}")
      source_path = Path.join(storage_root, "template.md")

      on_exit(fn ->
        File.rm_rf!(storage_root)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
        end
      end)

      File.mkdir_p!(storage_root)
      File.write!(source_path, "0123456789abcdef")

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: storage_root,
        max_file_size_bytes: 1024 * 1024
      )

      world = insert(:world)

      assert {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} =
               Knowledge.create_reference_file_upload(
                 world,
                 %{
                   title: "Readable template",
                   content: "Readable template summary.",
                   reference_file_type: "quote_template",
                   original_filename: "template.md",
                   content_type: "text/markdown"
                 },
                 source_path
               )

      assert {:ok, result} =
               Knowledge.read_reference_file(world, reference_file.reference_ref, max_chars: 6)

      assert result.content_status == "readable"
      assert result.content == "012345"
      assert result.truncated
      assert result.extraction_method == "direct"
      assert result.descriptor.reference_ref == reference_file.reference_ref
      assert result.descriptor.knowledge_item_id == knowledge_item.id
      refute Map.has_key?(result.descriptor, :storage_ref)

      assert {:ok, result_by_id} =
               Knowledge.read_reference_file(world, %{knowledge_item_id: knowledge_item.id},
                 max_chars: 4
               )

      assert result_by_id.content == "0123"
    end

    test "read_reference_file/3 converts supported non-text previews without RAG side effects" do
      old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])

      storage_root =
        Path.join(System.tmp_dir!(), "reference_convert_test_#{Ecto.UUID.generate()}")

      source_path = Path.join(storage_root, "template.pdf")

      on_exit(fn ->
        File.rm_rf!(storage_root)
        Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner)
        Application.delete_env(:lemmings_os, :knowledge_reference_markitdown_output)
        Application.delete_env(:lemmings_os, :knowledge_reference_pdftotext_output)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
        end
      end)

      File.mkdir_p!(storage_root)
      File.write!(source_path, "%PDF test")

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: storage_root,
        max_file_size_bytes: 1024 * 1024
      )

      Application.put_env(
        :lemmings_os,
        :knowledge_tools_runner,
        Keyword.merge(old_runner,
          executor_module: StubReferenceExtractorExecutor,
          capabilities: %{
            markitdown_extract_file: "markitdown",
            pdftotext_extract_file: "pdftotext",
            trafilatura_extract_url: "trafilatura"
          }
        )
      )

      Application.put_env(:lemmings_os, :knowledge_reference_markitdown_output, "")

      Application.put_env(
        :lemmings_os,
        :knowledge_reference_pdftotext_output,
        "converted pdf text with enough preview content"
      )

      world = insert(:world)
      chunks_before = Repo.aggregate(SourceFileChunk, :count, :id)

      assert {:ok, %{reference_file: reference_file}} =
               Knowledge.create_reference_file_upload(
                 world,
                 %{
                   title: "PDF template",
                   reference_file_type: "quote_template",
                   original_filename: "template.pdf",
                   content_type: "application/pdf"
                 },
                 source_path
               )

      assert {:ok, result} =
               Knowledge.read_reference_file(world, reference_file.reference_ref, max_chars: 9)

      assert result.content_status == "converted"
      assert result.content == "converted"
      assert result.truncated
      assert result.extraction_method == "pdftotext"
      assert Repo.aggregate(SourceFileChunk, :count, :id) == chunks_before
    end

    test "read_reference_file/3 returns descriptor-only output for unsupported binary files" do
      old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      storage_root = Path.join(System.tmp_dir!(), "reference_binary_test_#{Ecto.UUID.generate()}")
      source_path = Path.join(storage_root, "binary.bin")
      bytes_sentinel = <<0, 159, 250, 17, 198, 33, 44, 255>>

      on_exit(fn ->
        File.rm_rf!(storage_root)

        if old_storage do
          Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage)
        else
          Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
        end
      end)

      File.mkdir_p!(storage_root)
      File.write!(source_path, bytes_sentinel)

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: storage_root,
        max_file_size_bytes: 1024 * 1024
      )

      world = insert(:world)
      chunks_before = Repo.aggregate(SourceFileChunk, :count, :id)

      assert {:ok, %{reference_file: reference_file}} =
               Knowledge.create_reference_file_upload(
                 world,
                 %{
                   title: "Binary template",
                   content: "Descriptor only expected.",
                   reference_file_type: "binary_asset",
                   original_filename: "binary.bin",
                   content_type: "application/octet-stream"
                 },
                 source_path
               )

      assert {:ok, result} =
               Knowledge.read_reference_file(world, reference_file.reference_ref, max_chars: 128)

      assert result.content_status == "unreadable"
      assert result.content == nil
      assert result.content_length == 0
      refute result.truncated
      assert result.descriptor.reference_ref == reference_file.reference_ref
      refute Map.has_key?(result.descriptor, :storage_ref)
      refute inspect(result) =~ reference_file.storage_ref
      refute inspect(result) =~ storage_root
      refute inspect(result) =~ source_path
      assert Repo.aggregate(SourceFileChunk, :count, :id) == chunks_before
    end

    test "read_reference_file/3 fails closed for archived and inaccessible files" do
      world = insert(:world)
      city = insert(:city, world: world)
      sibling_city = insert(:city, world: world)
      other_world = insert(:world)

      archived_file =
        create_reference_file_for(city, %{
          title: "Archived template"
        })

      sibling_file =
        create_reference_file_for(sibling_city, %{
          title: "Sibling template"
        })

      cross_world_file =
        create_reference_file_for(other_world, %{
          title: "Cross world template"
        })

      {:ok, _archived} = Knowledge.archive_reference_file(city, archived_file)

      assert {:error, :not_found} =
               Knowledge.read_reference_file(city, archived_file.reference_ref)

      assert {:error, :not_found} =
               Knowledge.read_reference_file(city, sibling_file.reference_ref)

      assert {:error, :not_found} =
               Knowledge.read_reference_file(city, cross_world_file.reference_ref)
    end

    test "promote_artifact_to_reference_file/3 requires explicit approval and stores independent bytes" do
      old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)
      old_reference_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      root = Path.join(System.tmp_dir!(), "reference_artifact_promotion_#{Ecto.UUID.generate()}")
      artifact_source = Path.join(root, "artifact-source.md")

      on_exit(fn ->
        File.rm_rf!(root)

        if old_artifact_storage do
          Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
        else
          Application.delete_env(:lemmings_os, :artifact_storage)
        end

        if old_reference_storage do
          Application.put_env(
            :lemmings_os,
            :knowledge_reference_file_storage,
            old_reference_storage
          )
        else
          Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
        end
      end)

      File.mkdir_p!(root)
      File.write!(artifact_source, "artifact bytes for promotion")

      Application.put_env(:lemmings_os, :artifact_storage,
        backend: :local,
        root_path: Path.join(root, "artifact_storage"),
        max_file_size_bytes: 1024 * 1024
      )

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: Path.join(root, "reference_storage"),
        max_file_size_bytes: 1024 * 1024
      )

      world = insert(:world)
      artifact_id = Ecto.UUID.generate()

      {:ok, stored} =
        LemmingsOs.Artifacts.LocalStorage.store_copy(
          world.id,
          artifact_id,
          artifact_source,
          "promoted.md"
        )

      artifact =
        insert(:artifact,
          id: artifact_id,
          world: world,
          city: nil,
          department: nil,
          lemming: nil,
          storage_ref: stored.storage_ref,
          checksum: stored.checksum,
          size_bytes: stored.size_bytes,
          filename: "promoted.md",
          content_type: "text/markdown",
          status: "ready"
        )

      assert {:error, :operator_approval_required} =
               Knowledge.promote_artifact_to_reference_file(world, artifact.id, %{
                 title: "Promoted",
                 content: "Summary",
                 reference_file_type: "quote_template"
               })

      assert {:ok, %{knowledge_item: item, reference_file: reference_file}} =
               Knowledge.promote_artifact_to_reference_file(world, artifact.id, %{
                 operator_approved: true,
                 title: "Promoted",
                 content: "Summary",
                 reference_file_type: "quote_template"
               })

      assert item.artifact_id == artifact.id
      assert reference_file.original_filename == artifact.filename
      assert reference_file.content_type == artifact.content_type
      assert String.starts_with?(reference_file.storage_ref, "local://knowledge_reference_files/")

      assert Repo.exists?(
               from(event in Event,
                 where:
                   event.event_type == "knowledge.reference_file.artifact_promoted" and
                     event.resource_id == ^reference_file.id and
                     event.world_id == ^world.id
               )
             )

      promotion_event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.artifact_promoted" and
                event.resource_id == ^reference_file.id and
                event.world_id == ^world.id,
            order_by: [desc: event.inserted_at],
            limit: 1
          )
        )

      assert fetch_map(promotion_event.payload, :artifact_id) == artifact.id
      assert fetch_map(promotion_event.payload, :reference_file_id) == reference_file.id
      assert fetch_map(promotion_event.payload, :knowledge_item_id) == item.id
      refute Map.has_key?(promotion_event.payload, "content")
      refute Map.has_key?(promotion_event.payload, "storage_ref")
      refute inspect(promotion_event.payload) =~ "artifact bytes for promotion"
      refute inspect(promotion_event.payload) =~ artifact_source
      refute inspect(promotion_event.payload) =~ stored.storage_ref

      File.rm_rf!(Path.join(root, "artifact_storage"))

      assert {:ok, result} = Knowledge.read_reference_file(world, reference_file.reference_ref)
      assert result.content_status == "readable"
      assert result.content == "artifact bytes for promotion"
    end

    test "promote_artifact_to_reference_file/3 returns safe unavailable errors" do
      world = insert(:world)
      city = insert(:city, world: world)
      sibling_city = insert(:city, world: world)

      artifact =
        insert(:artifact, world: world, city: sibling_city, department: nil, lemming: nil)

      assert {:error, :artifact_unavailable} =
               Knowledge.promote_artifact_to_reference_file(city, artifact.id, %{
                 operator_approved: true,
                 title: "Scoped",
                 content: "Scoped summary",
                 reference_file_type: "quote_template"
               })

      assert {:error, :artifact_unavailable} =
               Knowledge.promote_artifact_to_reference_file(world, Ecto.UUID.generate(), %{
                 operator_approved: true,
                 title: "Missing",
                 content: "Missing summary",
                 reference_file_type: "quote_template"
               })
    end
  end

  defp create_reference_file_for(scope, attrs) do
    scope_data = reference_scope_data(scope)
    knowledge_item_id = Ecto.UUID.generate()
    filename = Map.get(attrs, :original_filename, "reference.md")

    {:ok, storage_ref} =
      LemmingsOs.Knowledge.ReferenceFileStorageService.build_storage_ref(
        scope_data.world_id,
        knowledge_item_id,
        filename
      )

    {:ok, %{reference_file: reference_file}} =
      Knowledge.create_reference_file(
        scope,
        Map.merge(
          %{
            title: "Reference file",
            content: "Reference file summary.",
            tags: [],
            reference_file_type: "quote_template",
            original_filename: filename,
            content_type: "text/markdown",
            size_bytes: 128,
            checksum: String.duplicate("e", 64),
            storage_ref: storage_ref,
            reference_ref: "kref:#{knowledge_item_id}"
          },
          attrs
        )
      )

    reference_file
  end

  defp reference_scope_data(%LemmingsOs.Worlds.World{id: world_id}) do
    %{world_id: world_id}
  end

  defp reference_scope_data(%LemmingsOs.Cities.City{world_id: world_id}) do
    %{world_id: world_id}
  end

  defp reference_scope_data(%LemmingsOs.Departments.Department{world_id: world_id}) do
    %{world_id: world_id}
  end

  defp reference_scope_data(%LemmingsOs.Lemmings.Lemming{world_id: world_id}) do
    %{world_id: world_id}
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
