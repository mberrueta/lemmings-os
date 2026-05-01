defmodule LemmingsOs.Artifacts.LocalStorageTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Artifacts.LocalStorage

  doctest LocalStorage

  setup do
    old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

    root_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_artifact_storage_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :artifact_storage, backend: :local, root_path: root_path)

    on_exit(fn ->
      if old_artifact_storage do
        Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
      else
        Application.delete_env(:lemmings_os, :artifact_storage)
      end

      File.rm_rf(root_path)
    end)

    {:ok, root_path: root_path}
  end

  describe "build_storage_ref/3" do
    test "builds a local artifact storage ref" do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      assert {:ok, storage_ref} =
               LocalStorage.build_storage_ref(world_id, artifact_id, "artifact.md")

      assert storage_ref == "local://artifacts/#{world_id}/#{artifact_id}/artifact.md"
    end

    test "rejects unsafe filenames" do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      for filename <- [
            "../secret.txt",
            "/tmp/secret.txt",
            "nested/file.txt",
            "C:\\temp\\secret.txt",
            "nested\\file.txt",
            "bad\0name.txt"
          ] do
        assert {:error, :invalid_filename} =
                 LocalStorage.build_storage_ref(world_id, artifact_id, filename)
      end
    end
  end

  describe "resolve_storage_ref/1" do
    test "resolves a trusted ref inside configured root", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      assert :ok = File.mkdir_p(Path.join([root_path, world_id, artifact_id]))
      storage_ref = "local://artifacts/#{world_id}/#{artifact_id}/artifact.md"

      assert {:ok, absolute_path} = LocalStorage.resolve_storage_ref(storage_ref)
      assert absolute_path == Path.join([root_path, world_id, artifact_id, "artifact.md"])
    end

    test "rejects malformed or unsafe refs" do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      for storage_ref <- [
            "local://artifacts/#{world_id}/#{artifact_id}",
            "local://artifacts/#{world_id}/#{artifact_id}/../secret.txt",
            "local://artifacts/#{world_id}/#{artifact_id}/nested/file.txt",
            "local://artifacts/#{world_id}/#{artifact_id}/C:\\temp\\file.txt",
            "local://artifacts/#{world_id}/#{artifact_id}/bad\0name.txt",
            "local://wrong/#{world_id}/#{artifact_id}/artifact.md",
            "s3://artifacts/#{world_id}/#{artifact_id}/artifact.md"
          ] do
        assert {:error, :invalid_storage_ref} = LocalStorage.resolve_storage_ref(storage_ref)
      end
    end
  end

  describe "store_copy/4" do
    test "copies file and returns storage ref, checksum, and size", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      source_path = Path.join(root_path, "workspace-source.md")
      content = "# Summary\n\nhello\n"
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, content)

      assert {:ok, stored} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.md")

      assert stored.storage_ref == "local://artifacts/#{world_id}/#{artifact_id}/artifact.md"
      assert stored.size_bytes == byte_size(content)

      expected_checksum =
        :sha256
        |> :crypto.hash(content)
        |> Base.encode16(case: :lower)

      assert stored.checksum == expected_checksum

      copied_path = Path.join([root_path, world_id, artifact_id, "artifact.md"])
      assert {:ok, copied_content} = File.read(copied_path)
      assert copied_content == content
    end

    test "rejects symlink escape in managed path", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      source_path = Path.join(root_path, "workspace-source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "safe")

      outside_path = Path.join(root_path, "outside")
      linked_world_path = Path.join(root_path, world_id)
      :ok = File.mkdir_p(outside_path)
      :ok = File.ln_s(outside_path, linked_world_path)

      assert {:error, :invalid_storage_ref} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.md")
    end
  end
end
