defmodule LemmingsOs.Artifacts.LocalStorageTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias LemmingsOs.Artifacts.LocalStorage

  @moduletag capture_log: true

  @storage_events [
    [:lemmings_os, :artifact_storage, :write, :start],
    [:lemmings_os, :artifact_storage, :write, :stop],
    [:lemmings_os, :artifact_storage, :write, :exception],
    [:lemmings_os, :artifact_storage, :open, :stop],
    [:lemmings_os, :artifact_storage, :open, :exception],
    [:lemmings_os, :artifact_storage, :health_check, :stop],
    [:lemmings_os, :artifact_storage, :health_check, :exception]
  ]

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
    test "storage adapter behavior exposes v1 callbacks without physical delete" do
      callbacks = LemmingsOs.Artifacts.Storage.Adapter.behaviour_info(:callbacks)

      assert {:put, 4} in callbacks
      assert {:open, 2} in callbacks
      assert {:path_for, 2} in callbacks
      assert {:exists?, 2} in callbacks
      assert {:health_check, 1} in callbacks
      refute Enum.any?(callbacks, fn {name, _arity} -> name == :delete end)
    end

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
            "line\nbreak.txt",
            "line\rbreak.txt",
            "bad\0name.txt",
            "",
            ".",
            "..",
            "~/.ssh"
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
            "local://artifacts/not-a-uuid/#{artifact_id}/artifact.md",
            "local://artifacts/#{world_id}/not-a-uuid/artifact.md",
            "local://artifacts/#{world_id}/#{artifact_id}/artifact.md?download=1",
            "local://artifacts/#{world_id}/#{artifact_id}/artifact.md#fragment",
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

    test "applies best-effort private permissions", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "workspace-source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "safe")

      assert {:ok, _stored} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.md")

      directory_path = Path.join([root_path, world_id, artifact_id])
      file_path = Path.join(directory_path, "artifact.md")

      assert {:ok, directory_stat} = File.stat(directory_path)
      assert {:ok, file_stat} = File.stat(file_path)

      assert permission_bits(directory_stat) == 0o700
      assert permission_bits(file_stat) == 0o600
    end

    test "rejects oversized source file and does not leave final or temp files", %{
      root_path: root_path
    } do
      old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

      Application.put_env(:lemmings_os, :artifact_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 4
      )

      on_exit(fn ->
        Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
      end)

      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()

      source_path = Path.join(root_path, "workspace-source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")

      assert {:error, :file_too_large} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.md")

      final_path = Path.join([root_path, world_id, artifact_id, "artifact.md"])
      refute File.exists?(final_path)

      assert [] == Path.wildcard(Path.join([root_path, world_id, artifact_id, ".*.tmp-*"]))
    end

    test "successful copy does not leave temp files", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "workspace-source.md")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")

      assert {:ok, _stored} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.md")

      assert [] == Path.wildcard(Path.join([root_path, world_id, artifact_id, ".*.tmp-*"]))
    end
  end

  describe "adapter callbacks" do
    test "put/4 delegates to storage copy", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")

      assert {:ok, stored} = LocalStorage.put(world_id, artifact_id, source_path, "artifact.txt")
      assert stored.storage_ref == "local://artifacts/#{world_id}/#{artifact_id}/artifact.txt"
    end

    test "path_for/2 and exists?/2 resolve trusted refs", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")
      {:ok, stored} = LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")

      assert {:ok, managed_path} = LocalStorage.path_for(stored.storage_ref)
      assert {:ok, true} = LocalStorage.exists?(stored.storage_ref)
      assert managed_path == Path.join([root_path, world_id, artifact_id, "artifact.txt"])
    end

    test "path_for/2, exists?/2, and open/2 reject symlink escapes", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      storage_ref = "local://artifacts/#{world_id}/#{artifact_id}/artifact.txt"

      outside_path = Path.join(root_path, "outside")
      linked_world_path = Path.join(root_path, world_id)
      :ok = File.mkdir_p(outside_path)
      :ok = File.ln_s(outside_path, linked_world_path)

      assert {:error, :invalid_storage_ref} = LocalStorage.path_for(storage_ref)
      assert {:error, :invalid_storage_ref} = LocalStorage.exists?(storage_ref)
      assert {:error, :invalid_storage_ref} = LocalStorage.open(storage_ref)
    end

    test "open/2 returns internal open shape", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")
      {:ok, stored} = LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")

      assert {:ok, result} =
               LocalStorage.open(stored.storage_ref,
                 filename: "artifact.txt",
                 content_type: "text/plain"
               )

      assert result.filename == "artifact.txt"
      assert result.content_type == "text/plain"
      assert result.size_bytes == 5
      assert result.path == Path.join([root_path, world_id, artifact_id, "artifact.txt"])
    end

    test "health_check/1 succeeds when root exists", %{root_path: root_path} do
      assert :ok = File.mkdir_p(root_path)
      assert :ok = LocalStorage.health_check()
    end

    test "health_check/1 creates missing root and verifies writable path", %{root_path: root_path} do
      refute File.exists?(root_path)
      assert :ok = LocalStorage.health_check()
      assert File.dir?(root_path)
    end

    test "open/2 returns not_found for missing managed file", %{root_path: root_path} do
      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      :ok = File.mkdir_p(root_path)

      assert {:ok, storage_ref} =
               LocalStorage.build_storage_ref(world_id, artifact_id, "artifact.txt")

      assert {:error, :not_found} = LocalStorage.open(storage_ref, filename: "artifact.txt")
    end
  end

  describe "config" do
    test "max_file_size_bytes/0 defaults to 100 MB" do
      assert LocalStorage.max_file_size_bytes() == 100 * 1024 * 1024
    end
  end

  describe "observability" do
    test "write emits safe start and stop telemetry", %{root_path: root_path} do
      attach_storage_telemetry()

      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")

      assert {:ok, stored} =
               LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :write, :start],
                      %{count: 1}, start_metadata}

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :write, :stop],
                      stop_measurements, stop_metadata}

      assert start_metadata.world_id == world_id
      assert start_metadata.artifact_id == artifact_id
      assert start_metadata.filename == "artifact.txt"
      assert start_metadata.operation == :write

      assert stop_metadata.checksum == stored.checksum
      assert stop_metadata.size_bytes == stored.size_bytes
      assert stop_measurements.size_bytes == stored.size_bytes

      metadata_text = inspect(stop_metadata)
      refute metadata_text =~ root_path
      refute metadata_text =~ source_path
      refute metadata_text =~ stored.storage_ref
    end

    test "open failure emits safe exception telemetry" do
      attach_storage_telemetry()

      assert {:error, :invalid_storage_ref} =
               LocalStorage.open("s3://bucket/path", filename: "artifact\r\n.txt")

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :open, :exception],
                      %{count: 1}, metadata}

      assert metadata.reason == "invalid_storage_ref"
      assert metadata.operation == :open
      assert metadata.filename == "artifact.txt"
      refute inspect(metadata) =~ "s3://bucket/path"
      refute inspect(metadata) =~ "\r"
      refute inspect(metadata) =~ "\n"
    end

    test "open telemetry sanitizes persisted filename metadata", %{root_path: root_path} do
      attach_storage_telemetry()

      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "hello")
      {:ok, stored} = LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")

      assert {:ok, _opened} =
               LocalStorage.open(stored.storage_ref,
                 filename: "safe\r\nname.txt",
                 content_type: "text/plain"
               )

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :write, :start], _, _}

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :write, :stop], _, _}

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :open, :stop], _,
                      metadata}

      assert metadata.filename == "safename.txt"
      refute inspect(metadata) =~ "\r"
      refute inspect(metadata) =~ "\n"
    end

    test "health check emits stop telemetry", %{root_path: root_path} do
      attach_storage_telemetry()
      assert :ok = File.mkdir_p(root_path)

      assert :ok = LocalStorage.health_check()

      assert_receive {:telemetry_event, [:lemmings_os, :artifact_storage, :health_check, :stop],
                      %{count: 1}, metadata}

      assert metadata.operation == :health_check
      assert metadata.status == :ok
      refute inspect(metadata) =~ root_path
    end

    test "failure logs omit storage roots, source paths, and file contents", %{
      root_path: root_path
    } do
      old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

      Application.put_env(:lemmings_os, :artifact_storage,
        backend: :local,
        root_path: root_path,
        max_file_size_bytes: 3
      )

      on_exit(fn ->
        Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
      end)

      world_id = Ecto.UUID.generate()
      artifact_id = Ecto.UUID.generate()
      source_path = Path.join(root_path, "source.txt")
      :ok = File.mkdir_p(root_path)
      :ok = File.write(source_path, "secret content")

      log =
        capture_log([level: :warning], fn ->
          assert {:error, :file_too_large} =
                   LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")
        end)

      assert log =~ "artifact storage write failed"
      assert log =~ "reason=file_too_large"
      refute log =~ root_path
      refute log =~ source_path
      refute log =~ "secret content"
    end
  end

  defp attach_storage_telemetry do
    test_pid = self()
    handler_id = "local-storage-telemetry-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @storage_events,
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp permission_bits(%File.Stat{mode: mode}), do: Bitwise.band(mode, 0o777)
end
