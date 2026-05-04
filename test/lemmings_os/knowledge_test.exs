defmodule LemmingsOs.KnowledgeTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Events.Event
  alias LemmingsOs.Repo

  doctest LemmingsOs.Knowledge

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

    test "fails closed for invalid scope" do
      assert {:error, :invalid_scope} = Knowledge.list_effective_memories(%{})
    end
  end
end
