defmodule LemmingsOs.Tools.Adapters.KnowledgeTest do
  use LemmingsOs.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Events.Event
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Knowledge, as: KnowledgeAdapter

  doctest LemmingsOs.Tools.Adapters.Knowledge

  setup do
    old_reference_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)

    storage_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_reference_tool_adapter_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
      backend: :local,
      root_path: storage_root,
      max_file_size_bytes: 1024 * 1024
    )

    on_exit(fn ->
      if old_reference_storage do
        Application.put_env(
          :lemmings_os,
          :knowledge_reference_file_storage,
          old_reference_storage
        )
      else
        Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      end

      File.rm_rf(storage_root)
    end)

    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department)

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: world.id,
      city_id: city.id,
      department_id: department.id,
      lemming_id: lemming.id
    }

    %{
      world: world,
      city: city,
      department: department,
      lemming: lemming,
      instance: instance,
      storage_root: storage_root
    }
  end

  describe "knowledge.search reference files" do
    test "returns scoped safe descriptors without exposing storage internals", %{
      department: department,
      instance: instance,
      storage_root: storage_root
    } do
      {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} =
        create_reference_file_upload(
          department,
          storage_root,
          "quote-template.md",
          "Quote template body",
          %{
            title: "ACME Quote Template",
            content: "Reusable quote summary.",
            tags: ["customer:acme", "quote"],
            reference_file_type: "quote_template",
            content_type: "text/markdown"
          }
        )

      assert {:ok, result} =
               KnowledgeAdapter.search(instance, %{
                 "kind" => "reference_file",
                 "query" => "acme",
                 "reference_file_type" => "quote_template",
                 "tags" => ["customer:acme"],
                 "limit" => 5
               })

      assert result.result.kind == "reference_file"
      assert result.result.scope == "lemming"
      assert result.result.count == 1

      assert [
               %{
                 reference_ref: reference_ref,
                 knowledge_item_id: knowledge_item_id,
                 reference_file_type: "quote_template",
                 title: "ACME Quote Template"
               } = row
             ] = result.result.results

      assert reference_ref == reference_file.reference_ref
      assert knowledge_item_id == knowledge_item.id
      assert row.scope.type == "department"
      refute Map.has_key?(row, :storage_ref)
      refute Map.has_key?(row, :size_bytes)
      refute Map.has_key?(row, :checksum)
      refute inspect(result) =~ storage_root
      refute inspect(result) =~ reference_file.storage_ref

      search_event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.search_performed" and
                event.world_id == ^department.world_id,
            order_by: [desc: event.inserted_at],
            limit: 1
          )
        )

      assert fetch_map(search_event.payload, :result_count) == 1
      assert fetch_map(search_event.payload, :has_query) == true
      refute inspect(search_event.payload) =~ "acme"
    end

    test "rejects kind-specific field mismatches safely", %{instance: instance} do
      assert {:error, error} =
               KnowledgeAdapter.search(instance, %{
                 "kind" => "source_file",
                 "query" => "template",
                 "reference_file_type" => "quote_template"
               })

      assert error.code == "tool.validation.invalid_args"
      assert error.details.kind == "source_file"
      assert error.details.unsupported_fields == ["reference_file_type"]

      assert {:error, error} =
               KnowledgeAdapter.search(instance, %{
                 "kind" => "reference_file",
                 "query" => "template",
                 "source_file_type" => "policy"
               })

      assert error.code == "tool.validation.invalid_args"
      assert error.details.kind == "reference_file"
      assert error.details.unsupported_fields == ["source_file_type"]
    end
  end

  describe "knowledge.read reference files" do
    test "returns bounded direct text by reference_ref or knowledge_item_id", %{
      department: department,
      instance: instance,
      storage_root: storage_root
    } do
      {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} =
        create_reference_file_upload(
          department,
          storage_root,
          "template.md",
          "0123456789abcdef",
          %{
            title: "Readable template",
            content: "Readable template summary.",
            reference_file_type: "quote_template",
            content_type: "text/markdown"
          }
        )

      assert {:ok, result} =
               KnowledgeAdapter.read(instance, %{
                 "kind" => "reference_file",
                 "reference_ref" => reference_file.reference_ref,
                 "max_chars" => 6
               })

      assert result.result.kind == "reference_file"
      assert result.result.reference_ref == reference_file.reference_ref
      assert result.result.knowledge_item_id == knowledge_item.id
      assert result.result.content_status == "readable"
      assert result.result.content == "012345"
      assert result.result.content_length == 6
      assert result.result.truncated
      assert result.result.extraction_method == "direct"
      refute Map.has_key?(result.result, :storage_ref)
      refute Map.has_key?(result.result.descriptor, :storage_ref)
      refute inspect(result) =~ reference_file.storage_ref

      assert {:ok, by_id} =
               KnowledgeAdapter.read(instance, %{
                 "knowledge_item_id" => knowledge_item.id,
                 "max_chars" => 4
               })

      assert by_id.result.content == "0123"

      read_event =
        Repo.one!(
          from(event in Event,
            where:
              event.event_type == "knowledge.reference_file.read" and
                event.world_id == ^department.world_id,
            order_by: [desc: event.inserted_at],
            limit: 1
          )
        )

      assert fetch_map(read_event.payload, :knowledge_item_id) == knowledge_item.id
      assert fetch_map(read_event.payload, :reference_ref) == reference_file.reference_ref
      assert fetch_map(read_event.payload, :content_status) == "readable"
      refute inspect(read_event.payload) =~ "0123456789abcdef"
    end

    test "returns descriptor-only output for unsupported binary files", %{
      department: department,
      instance: instance,
      storage_root: storage_root
    } do
      {:ok, %{reference_file: reference_file}} =
        create_reference_file_upload(
          department,
          storage_root,
          "image.bin",
          <<0, 1, 2, 3, 4, 5>>,
          %{
            title: "Binary style asset",
            content: "Reusable binary asset.",
            reference_file_type: "style_asset",
            content_type: "application/octet-stream"
          }
        )

      assert {:ok, result} =
               KnowledgeAdapter.read(instance, %{
                 "reference_ref" => reference_file.reference_ref,
                 "max_chars" => 100
               })

      assert result.result.content_status == "unreadable"
      assert result.result.content == nil
      assert result.result.content_length == 0
      assert result.result.truncated == false
      assert result.result.reference_ref == reference_file.reference_ref
      refute Map.has_key?(result.result, :storage_ref)
      refute inspect(result) =~ reference_file.storage_ref
    end

    test "rejects mixed source-file and reference-file read identifiers", %{instance: instance} do
      assert {:error, error} =
               KnowledgeAdapter.read(instance, %{
                 "chunk_ref" => "ksf:chunk",
                 "reference_ref" => "kref:template"
               })

      assert error.code == "tool.validation.invalid_args"

      assert Enum.sort(error.details.required) == [
               "chunk_ref",
               "knowledge_item_id",
               "reference_ref"
             ]
    end
  end

  describe "knowledge.store memory boundary" do
    test "rejects reference-file mutation fields and creates no reference-file item", %{
      instance: instance
    } do
      assert {:error, error} =
               KnowledgeAdapter.store_memory(instance, %{
                 "title" => "Invalid reference mutation",
                 "content" => "Do not create a file.",
                 "reference_file_type" => "quote_template",
                 "reference_ref" => "kref:template",
                 "storage_ref" => "local://knowledge_reference_files/private/template.md",
                 "artifact_id" => Ecto.UUID.generate()
               })

      assert error.code == "tool.knowledge.unsupported_fields"

      assert Enum.sort(error.details.fields) == [
               "artifact_id",
               "reference_file_type",
               "reference_ref",
               "storage_ref"
             ]

      refute Repo.exists?(from item in KnowledgeItem, where: item.kind == "reference_file")
    end
  end

  defp create_reference_file_upload(scope, storage_root, filename, content, attrs) do
    source_path =
      Path.join(storage_root, "upload-#{System.unique_integer([:positive])}-#{filename}")

    File.mkdir_p!(storage_root)
    File.write!(source_path, content)

    attrs =
      attrs
      |> Map.put(:original_filename, filename)
      |> Map.put_new(:tags, [])

    Knowledge.create_reference_file_upload(scope, attrs, source_path)
  end

  defp fetch_map(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
