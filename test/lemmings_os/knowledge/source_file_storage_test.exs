defmodule LemmingsOs.Knowledge.SourceFileStorageTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Knowledge.SourceFileStorage

  doctest SourceFileStorage

  setup do
    old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)

    root_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_knowledge_storage_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :knowledge_source_file_storage,
      backend: :local,
      root_path: root_path,
      max_file_size_bytes: 10 * 1024 * 1024
    )

    on_exit(fn ->
      if old_storage do
        Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
      else
        Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
      end

      File.rm_rf(root_path)
    end)

    {:ok, root_path: root_path}
  end

  describe "put/4 and ref boundary" do
    test "stores bytes with opaque ref and checksum", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello\n")

      assert {:ok, stored} =
               SourceFileStorage.put(world_id, knowledge_item_id, source_path, "policy.txt")

      assert stored.storage_ref ==
               "local://knowledge_source_files/#{world_id}/#{knowledge_item_id}/policy.txt"

      assert stored.size_bytes == 6
      refute String.contains?(stored.storage_ref, root_path)
      refute String.contains?(stored.storage_ref, source_path)
    end

    test "rejects unsafe filename/path inputs", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")

      assert {:error, :invalid_filename} =
               SourceFileStorage.put(world_id, knowledge_item_id, source_path, "../secret.txt")

      assert {:error, :invalid_filename} =
               SourceFileStorage.put(world_id, knowledge_item_id, source_path, "nested/file.txt")
    end

    test "enforces max file size (10 MB default)", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "oversized.bin")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, :binary.copy("a", 5))

      Application.put_env(:lemmings_os, :knowledge_source_file_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 4
      )

      assert {:error, :file_too_large} =
               SourceFileStorage.put(world_id, knowledge_item_id, source_path, "payload.bin")
    end
  end

  describe "private access operations" do
    test "read_private/1 returns bytes", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "source-content")

      {:ok, stored} =
        SourceFileStorage.put(world_id, knowledge_item_id, source_path, "policy.txt")

      assert {:ok, "source-content"} = SourceFileStorage.read_private(stored.storage_ref)
    end

    test "open_stream/2 and with_temp_file/2 expose private path only inside callback", %{
      root_path: root_path
    } do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "stream-me")

      {:ok, stored} =
        SourceFileStorage.put(world_id, knowledge_item_id, source_path, "policy.txt")

      assert {:ok, "stream-me"} =
               SourceFileStorage.open_stream(stored.storage_ref, fn stream ->
                 stream |> Enum.to_list() |> IO.iodata_to_binary()
               end)

      assert {:ok, true} =
               SourceFileStorage.with_temp_file(stored.storage_ref, fn path ->
                 Path.type(path) == :absolute and String.contains?(path, root_path)
               end)
    end
  end

  describe "resolve_storage_ref/1" do
    test "rejects malformed refs" do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()

      for storage_ref <- [
            "local://knowledge_source_files/#{world_id}/#{knowledge_item_id}",
            "local://knowledge_source_files/#{world_id}/#{knowledge_item_id}/../secret.txt",
            "local://knowledge_source_files/not-a-uuid/#{knowledge_item_id}/ok.txt",
            "local://wrong/#{world_id}/#{knowledge_item_id}/ok.txt",
            "s3://knowledge_source_files/#{world_id}/#{knowledge_item_id}/ok.txt"
          ] do
        assert {:error, :invalid_storage_ref} = SourceFileStorage.resolve_storage_ref(storage_ref)
      end
    end
  end
end
