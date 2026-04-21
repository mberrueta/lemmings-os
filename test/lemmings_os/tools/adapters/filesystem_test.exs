defmodule LemmingsOs.Tools.Adapters.FilesystemTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Filesystem

  setup do
    old_workspace_root = Application.get_env(:lemmings_os, :runtime_workspace_root)

    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_filesystem_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :runtime_workspace_root, workspace_root)
    File.mkdir_p!(workspace_root)

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      department_id: Ecto.UUID.generate(),
      lemming_id: Ecto.UUID.generate()
    }

    work_area = Path.join([workspace_root, instance.department_id, instance.lemming_id])
    File.mkdir_p!(work_area)

    on_exit(fn ->
      if old_workspace_root do
        Application.put_env(:lemmings_os, :runtime_workspace_root, old_workspace_root)
      else
        Application.delete_env(:lemmings_os, :runtime_workspace_root)
      end

      File.rm_rf(workspace_root)
    end)

    {:ok, instance: instance, work_area: work_area}
  end

  test "S01: write_text_file writes content inside work area with normalized result", %{
    instance: instance
  } do
    assert {:ok, result} =
             Filesystem.write_text_file(instance, %{
               "path" => "reports/out.txt",
               "content" => "hello filesystem"
             })

    assert result.summary == "Wrote file reports/out.txt"
    assert result.result.path == "reports/out.txt"

    assert result.result.root_path ==
             "/workspace/#{instance.department_id}/#{instance.lemming_id}"

    assert result.result.workspace_path ==
             "/workspace/#{instance.department_id}/#{instance.lemming_id}/reports/out.txt"

    assert result.result.bytes == byte_size("hello filesystem")
    assert result.preview == "hello filesystem"
  end

  test "S02: read_text_file returns normalized content from work area", %{instance: instance} do
    assert {:ok, _write_result} =
             Filesystem.write_text_file(instance, %{"path" => "notes.txt", "content" => "hello"})

    assert {:ok, result} = Filesystem.read_text_file(instance, %{"path" => "notes.txt"})
    assert result.summary == "Read file notes.txt"
    assert result.result.path == "notes.txt"

    assert result.result.root_path ==
             "/workspace/#{instance.department_id}/#{instance.lemming_id}"

    assert result.result.workspace_path ==
             "/workspace/#{instance.department_id}/#{instance.lemming_id}/notes.txt"

    assert result.result.content == "hello"
    assert result.result.bytes == 5
    assert result.preview == "hello"
  end

  test "S03: read_text_file validates required args", %{instance: instance} do
    assert {:error, %{code: "tool.validation.invalid_args", details: %{required: ["path"]}}} =
             Filesystem.read_text_file(instance, %{})
  end

  test "S04: write_text_file rejects absolute paths", %{instance: instance} do
    assert {:error, %{code: "tool.fs.path_must_be_relative"}} =
             Filesystem.write_text_file(instance, %{
               "path" => "/etc/passwd",
               "content" => "blocked"
             })
  end

  test "S05: write_text_file rejects traversal outside workspace", %{
    instance: instance,
    work_area: work_area
  } do
    escaped_path = Path.expand("../outside.txt", work_area)

    assert {:error, %{code: "tool.fs.path_outside_workspace"}} =
             Filesystem.write_text_file(instance, %{
               "path" => "../outside.txt",
               "content" => "blocked"
             })

    refute File.exists?(escaped_path)
  end

  test "S06: read_text_file returns not_found error for missing file", %{instance: instance} do
    assert {:error, %{code: "tool.fs.not_found", details: %{path: "missing.txt"}}} =
             Filesystem.read_text_file(instance, %{"path" => "missing.txt"})
  end

  test "S07: filesystem adapters reject incomplete instance scope" do
    assert {:error, %{code: "tool.fs.invalid_instance_scope"}} =
             Filesystem.read_text_file(%LemmingInstance{}, %{"path" => "notes.txt"})
  end

  test "S08: read_text_file rejects symlink targets outside workspace", %{
    instance: instance,
    work_area: work_area
  } do
    outside_path = Path.join(Path.dirname(work_area), "outside-secret.txt")
    File.write!(outside_path, "do not read")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "secret-link.txt"))

    assert {:error, %{code: "tool.fs.path_outside_workspace"}} =
             Filesystem.read_text_file(instance, %{"path" => "secret-link.txt"})
  end

  test "S09: write_text_file rejects existing symlink file targets outside workspace", %{
    instance: instance,
    work_area: work_area
  } do
    outside_path = Path.join(Path.dirname(work_area), "outside-write.txt")
    File.write!(outside_path, "unchanged")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "write-link.txt"))

    assert {:error, %{code: "tool.fs.path_outside_workspace"}} =
             Filesystem.write_text_file(instance, %{
               "path" => "write-link.txt",
               "content" => "mutated"
             })

    assert File.read!(outside_path) == "unchanged"
  end

  test "S10: write_text_file rejects symlink parent directories outside workspace", %{
    instance: instance,
    work_area: work_area
  } do
    outside_dir = Path.join(Path.dirname(work_area), "outside-dir")
    File.mkdir_p!(outside_dir)
    assert :ok = File.ln_s(outside_dir, Path.join(work_area, "linked-dir"))

    assert {:error, %{code: "tool.fs.path_outside_workspace"}} =
             Filesystem.write_text_file(instance, %{
               "path" => "linked-dir/output.txt",
               "content" => "escaped"
             })

    refute File.exists?(Path.join(outside_dir, "output.txt"))
  end
end
