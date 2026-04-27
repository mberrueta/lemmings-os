defmodule LemmingsOs.Tools.Adapters.FilesystemTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Filesystem
  alias LemmingsOs.Tools.WorkArea

  setup do
    old_work_areas_path = Application.get_env(:lemmings_os, :work_areas_path)

    work_areas_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_filesystem_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :work_areas_path, work_areas_path)

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      department_id: Ecto.UUID.generate(),
      lemming_id: Ecto.UUID.generate()
    }

    work_area_ref = Ecto.UUID.generate()
    :ok = WorkArea.ensure(work_area_ref)
    work_area = WorkArea.root_path(work_area_ref)
    runtime_meta = %{actor_instance_id: instance.id, work_area_ref: work_area_ref}

    on_exit(fn ->
      if old_work_areas_path do
        Application.put_env(:lemmings_os, :work_areas_path, old_work_areas_path)
      else
        Application.delete_env(:lemmings_os, :work_areas_path)
      end

      File.rm_rf(work_areas_path)
    end)

    {:ok, instance: instance, runtime_meta: runtime_meta, work_area: work_area}
  end

  test "S01: write_text_file writes content inside shared WorkArea", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    assert {:ok, result} =
             Filesystem.write_text_file(
               instance,
               %{"path" => "reports/out.txt", "content" => "hello filesystem"},
               runtime_meta
             )

    assert result.summary == "Wrote file reports/out.txt"
    assert result.result.path == "reports/out.txt"
    assert result.result.bytes == byte_size("hello filesystem")
    assert result.preview == "hello filesystem"
    refute Map.has_key?(result.result, :root_path)
    refute Map.has_key?(result.result, :workspace_path)
    assert File.read!(Path.join(work_area, "reports/out.txt")) == "hello filesystem"
  end

  test "S02: read_text_file returns normalized content from shared WorkArea", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    assert {:ok, _write_result} =
             Filesystem.write_text_file(
               instance,
               %{"path" => "notes.txt", "content" => "hello"},
               runtime_meta
             )

    assert {:ok, result} =
             Filesystem.read_text_file(instance, %{"path" => "notes.txt"}, runtime_meta)

    assert result.summary == "Read file notes.txt"
    assert result.result.path == "notes.txt"
    assert result.result.content == "hello"
    assert result.result.bytes == 5
    assert result.preview == "hello"
  end

  test "S03: multiple instances can use the same WorkArea", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    child_instance = %{instance | id: Ecto.UUID.generate()}
    child_meta = %{runtime_meta | actor_instance_id: child_instance.id}

    assert {:ok, _write_result} =
             Filesystem.write_text_file(
               instance,
               %{"path" => "scratch/shared.txt", "content" => "shared"},
               runtime_meta
             )

    assert {:ok, result} =
             Filesystem.read_text_file(
               child_instance,
               %{"path" => "scratch/shared.txt"},
               child_meta
             )

    assert result.result.content == "shared"
  end

  test "S04: read_text_file validates required args", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    assert {:error, %{code: "tool.validation.invalid_args", details: %{required: ["path"]}}} =
             Filesystem.read_text_file(instance, %{}, runtime_meta)
  end

  test "S05: filesystem adapters reject unsafe paths", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    for path <- [
          "../secret",
          "scratch/../../secret",
          "/tmp/file",
          "C:\\tmp\\file",
          "scratch\\file",
          "~/file"
        ] do
      assert {:error, %{code: "tool.validation.invalid_path"}} =
               Filesystem.write_text_file(
                 instance,
                 %{"path" => path, "content" => "blocked"},
                 runtime_meta
               )
    end
  end

  test "S06: read_text_file returns not_found error for missing file", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    assert {:error, %{code: "tool.fs.not_found", details: %{path: "missing.txt"}}} =
             Filesystem.read_text_file(instance, %{"path" => "missing.txt"}, runtime_meta)
  end

  test "S07: file tool returns structured error when WorkArea is unavailable", %{
    instance: instance
  } do
    assert {:error, %{code: "tool.fs.work_area_unavailable"}} =
             Filesystem.read_text_file(instance, %{"path" => "notes.txt"}, %{
               work_area_ref: Ecto.UUID.generate()
             })
  end

  test "S08: read_text_file rejects symlink targets outside workspace", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    outside_path = Path.join(Path.dirname(work_area), "outside-secret.txt")
    File.write!(outside_path, "do not read")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "secret-link.txt"))

    assert {:error, %{code: "tool.validation.invalid_path"}} =
             Filesystem.read_text_file(instance, %{"path" => "secret-link.txt"}, runtime_meta)
  end

  test "S09: write_text_file rejects existing symlink file targets outside workspace", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    outside_path = Path.join(Path.dirname(work_area), "outside-write.txt")
    File.write!(outside_path, "unchanged")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "write-link.txt"))

    assert {:error, %{code: "tool.validation.invalid_path"}} =
             Filesystem.write_text_file(
               instance,
               %{"path" => "write-link.txt", "content" => "mutated"},
               runtime_meta
             )

    assert File.read!(outside_path) == "unchanged"
  end

  test "S10: write_text_file rejects symlink parent directories outside workspace", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    outside_dir = Path.join(Path.dirname(work_area), "outside-dir")
    File.mkdir_p!(outside_dir)
    assert :ok = File.ln_s(outside_dir, Path.join(work_area, "linked-dir"))

    assert {:error, %{code: "tool.validation.invalid_path"}} =
             Filesystem.write_text_file(
               instance,
               %{"path" => "linked-dir/output.txt", "content" => "escaped"},
               runtime_meta
             )

    refute File.exists?(Path.join(outside_dir, "output.txt"))
  end
end
