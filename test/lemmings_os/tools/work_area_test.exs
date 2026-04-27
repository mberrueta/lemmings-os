defmodule LemmingsOs.Tools.WorkAreaTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Tools.WorkArea

  doctest WorkArea

  setup do
    old_work_areas_path = Application.get_env(:lemmings_os, :work_areas_path)

    work_areas_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_work_area_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :work_areas_path, work_areas_path)

    on_exit(fn ->
      if old_work_areas_path do
        Application.put_env(:lemmings_os, :work_areas_path, old_work_areas_path)
      else
        Application.delete_env(:lemmings_os, :work_areas_path)
      end

      File.rm_rf(work_areas_path)
    end)

    {:ok, work_areas_path: work_areas_path, work_area_ref: Ecto.UUID.generate()}
  end

  test "ensure/1 creates the WorkArea root and default subfolders", %{
    work_area_ref: work_area_ref
  } do
    assert :ok = WorkArea.ensure(work_area_ref)

    root = WorkArea.root_path(work_area_ref)
    assert File.dir?(root)
  end

  test "resolve/2 returns an absolute path inside the WorkArea", %{work_area_ref: work_area_ref} do
    assert :ok = WorkArea.ensure(work_area_ref)

    assert {:ok, resolved} = WorkArea.resolve(work_area_ref, "scratch/notes.txt")
    assert resolved.relative_path == "scratch/notes.txt"
    assert resolved.root_path == WorkArea.root_path(work_area_ref)
    assert String.starts_with?(resolved.absolute_path, resolved.root_path <> "/")
  end

  test "resolve/2 rejects unsafe paths", %{work_area_ref: work_area_ref} do
    assert :ok = WorkArea.ensure(work_area_ref)

    for path <- [
          "../secret",
          "scratch/../../secret",
          "/tmp/file",
          "C:\\tmp\\file",
          "scratch\\file",
          "~/file"
        ] do
      assert {:error, :invalid_path} = WorkArea.resolve(work_area_ref, path)
    end
  end

  test "resolve/2 returns work_area_unavailable when the root is missing", %{
    work_area_ref: work_area_ref
  } do
    assert {:error, :work_area_unavailable} = WorkArea.resolve(work_area_ref, "scratch/notes.txt")
  end
end
