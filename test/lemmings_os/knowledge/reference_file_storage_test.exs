defmodule LemmingsOs.Knowledge.ReferenceFileStorageServiceTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Knowledge.ReferenceFile
  alias LemmingsOs.Knowledge.ReferenceFileStorageService

  doctest ReferenceFileStorageService

  setup do
    old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)

    root_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_reference_file_storage_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
      backend: :local,
      root_path: root_path,
      max_file_size_bytes: 10 * 1024 * 1024
    )

    on_exit(fn ->
      if old_storage do
        Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage)
      else
        Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      end

      File.rm_rf(root_path)
    end)

    {:ok, root_path: root_path}
  end

  describe "put/4 and ref boundary" do
    test "stores bytes with opaque internal ref, checksum, and size", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "upload.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "reference\n")

      assert {:ok, stored} =
               ReferenceFileStorageService.put(
                 world_id,
                 knowledge_item_id,
                 source_path,
                 "template.md"
               )

      assert stored.storage_ref ==
               "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/template.md"

      assert stored.size_bytes == 10
      assert stored.checksum == sha256("reference\n")
      refute String.contains?(stored.storage_ref, root_path)
      refute String.contains?(stored.storage_ref, source_path)
      assert {:ok, "reference\n"} = ReferenceFileStorageService.read_private(stored.storage_ref)
    end

    test "rejects unsafe filenames and path-shaped names", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "upload.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "reference")

      unsafe_filenames = [
        "",
        ".",
        "..",
        "../secret.txt",
        "nested/file.txt",
        "/tmp/secret.txt",
        "C:/secret.txt",
        "C:\\secret.txt",
        "secret.txt\0",
        "secret?.txt",
        "secret#.txt",
        "secret\n.txt",
        "~secret.txt"
      ]

      for filename <- unsafe_filenames do
        assert {:error, :invalid_filename} =
                 ReferenceFileStorageService.put(
                   world_id,
                   knowledge_item_id,
                   source_path,
                   filename
                 )
      end
    end

    test "rejects symlink source files", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      target_path = Path.join(root_path, "target.md")
      symlink_path = Path.join(root_path, "upload-link.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(target_path, "reference")
      :ok = File.ln_s(target_path, symlink_path)

      assert {:error, :invalid_source_path} =
               ReferenceFileStorageService.put(
                 world_id,
                 knowledge_item_id,
                 symlink_path,
                 "template.md"
               )
    end

    test "enforces configured max file size", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "oversized.bin")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, :binary.copy("a", 5))

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 4
      )

      assert {:error, :file_too_large} =
               ReferenceFileStorageService.put(
                 world_id,
                 knowledge_item_id,
                 source_path,
                 "payload.bin"
               )
    end
  end

  describe "public descriptors" do
    test "build_reference_ref/1 creates a stable safe descriptor ref" do
      knowledge_item_id = Ecto.UUID.generate()

      assert {:ok, "kref:" <> ^knowledge_item_id} =
               ReferenceFileStorageService.build_reference_ref(knowledge_item_id)

      assert {:error, :invalid_reference_ref} =
               ReferenceFileStorageService.build_reference_ref("../secret")
    end

    test "public_descriptor/1 omits internal storage metadata and paths", %{root_path: root_path} do
      reference_file = %ReferenceFile{
        reference_ref: "kref:template",
        reference_file_type: "quote_template",
        original_filename: "template.md",
        content_type: "text/markdown",
        size_bytes: 123,
        checksum: String.duplicate("a", 64),
        storage_ref: "local://knowledge_reference_files/world/item/template.md"
      }

      descriptor = ReferenceFileStorageService.public_descriptor(reference_file)

      assert descriptor == %{
               reference_ref: "kref:template",
               reference_file_type: "quote_template",
               original_filename: "template.md",
               content_type: "text/markdown"
             }

      refute Map.has_key?(descriptor, :storage_ref)
      refute Map.has_key?(descriptor, :checksum)
      refute Map.has_key?(descriptor, :size_bytes)
      refute inspect(descriptor) =~ root_path
      refute inspect(descriptor) =~ reference_file.storage_ref
    end
  end

  describe "private access operations" do
    test "open_stream/2 and with_temp_file/2 expose private bytes only internally", %{
      root_path: root_path
    } do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "upload.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "stream-me")

      {:ok, stored} =
        ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")

      assert {:ok, "stream-me"} =
               ReferenceFileStorageService.open_stream(stored.storage_ref, fn stream ->
                 stream |> Enum.to_list() |> IO.iodata_to_binary()
               end)

      assert {:ok, true} =
               ReferenceFileStorageService.with_temp_file(stored.storage_ref, fn path ->
                 Path.type(path) == :absolute and String.contains?(path, root_path)
               end)
    end

    test "missing private files return safe not_found errors without path leakage", %{
      root_path: root_path
    } do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "upload.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "ephemeral")

      {:ok, stored} =
        ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")

      assert {:ok, stored_path} =
               ReferenceFileStorageService.resolve_storage_ref(stored.storage_ref)

      :ok = File.rm(stored_path)

      assert {:error, :not_found} = ReferenceFileStorageService.read_private(stored.storage_ref)

      assert {:error, :not_found} =
               ReferenceFileStorageService.open_stream(stored.storage_ref, & &1)

      assert {:error, :not_found} =
               ReferenceFileStorageService.with_temp_file(stored.storage_ref, & &1)

      refute inspect({:error, :not_found}) =~ root_path
      refute inspect({:error, :not_found}) =~ stored.storage_ref
    end
  end

  describe "resolve_storage_ref/1" do
    test "rejects malformed refs" do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()

      for storage_ref <- [
            "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}",
            "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/../secret.txt",
            "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}//secret.txt",
            "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/secret.txt?x=1",
            "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/secret.txt#x",
            "local://knowledge_reference_files/not-a-uuid/#{knowledge_item_id}/ok.txt",
            "local://wrong/#{world_id}/#{knowledge_item_id}/ok.txt",
            "s3://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/ok.txt"
          ] do
        assert {:error, :invalid_storage_ref} =
                 ReferenceFileStorageService.resolve_storage_ref(storage_ref)
      end
    end

    test "rejects symlink traversal inside managed storage", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()
      outside_path = Path.join(root_path <> "_outside", "secret.txt")
      stored_dir = Path.join([root_path, world_id, knowledge_item_id])
      symlink_path = Path.join(stored_dir, "template.md")

      storage_ref =
        "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/template.md"

      :ok = File.mkdir_p(Path.dirname(outside_path))
      :ok = File.write(outside_path, "secret")
      :ok = File.mkdir_p(stored_dir)
      :ok = File.ln_s(outside_path, symlink_path)

      assert {:error, :invalid_storage_ref} =
               ReferenceFileStorageService.resolve_storage_ref(storage_ref)

      File.rm_rf(root_path <> "_outside")
    end

    test "rejects a symlink storage root", %{root_path: root_path} do
      real_root = root_path <> "_real"
      symlink_root = root_path <> "_link"
      world_id = Ecto.UUID.generate()
      knowledge_item_id = Ecto.UUID.generate()

      storage_ref =
        "local://knowledge_reference_files/#{world_id}/#{knowledge_item_id}/template.md"

      :ok = File.mkdir_p(real_root)
      :ok = File.ln_s(real_root, symlink_root)

      Application.put_env(:lemmings_os, :knowledge_reference_file_storage,
        backend: :local,
        root_path: symlink_root,
        max_file_size_bytes: 10 * 1024 * 1024
      )

      assert {:error, :storage_unavailable} =
               ReferenceFileStorageService.resolve_storage_ref(storage_ref)

      File.rm_rf(real_root)
      File.rm_rf(symlink_root)
    end
  end

  defp sha256(content) do
    :sha256
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end
end
