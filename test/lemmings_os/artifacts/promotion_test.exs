defmodule LemmingsOs.Artifacts.PromotionTest do
  use LemmingsOs.DataCase, async: false

  import LemmingsOs.Factory

  alias LemmingsOs.Artifacts
  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.Artifacts.Promotion
  alias LemmingsOs.Repo

  doctest Promotion

  setup do
    old_workspace_root = Application.get_env(:lemmings_os, :runtime_workspace_root)
    old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

    test_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_artifacts_promotion_#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(test_root, "workspace")
    artifact_storage_root = Path.join(test_root, "artifact_storage")

    Application.put_env(:lemmings_os, :runtime_workspace_root, workspace_root)

    Application.put_env(:lemmings_os, :artifact_storage,
      backend: :local,
      root_path: artifact_storage_root
    )

    on_exit(fn ->
      if old_workspace_root do
        Application.put_env(:lemmings_os, :runtime_workspace_root, old_workspace_root)
      else
        Application.delete_env(:lemmings_os, :runtime_workspace_root)
      end

      if old_artifact_storage do
        Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
      else
        Application.delete_env(:lemmings_os, :artifact_storage)
      end

      File.rm_rf(test_root)
    end)

    {:ok, workspace_root: workspace_root}
  end

  describe "promote_workspace_file/2" do
    test "promotes workspace file into managed storage as ready artifact", %{
      workspace_root: workspace_root
    } do
      instance = insert_scoped_instance()
      relative_path = "reports/summary.md"
      source_path = write_workspace_file(workspace_root, instance, relative_path, "# Summary\n")

      assert {:ok, descriptor} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: relative_path, lemming_instance_id: instance.id}
               )

      assert descriptor.status == "ready"
      assert descriptor.filename == "summary.md"
      assert descriptor.type == "markdown"
      refute Map.has_key?(descriptor, :storage_ref)
      refute Map.has_key?(descriptor, :absolute_path)

      assert File.exists?(source_path)

      persisted = Repo.get!(Artifact, descriptor.id)
      assert persisted.status == "ready"
      assert persisted.lemming_instance_id == instance.id
      assert persisted.storage_ref =~ "local://artifacts/"
      refute persisted.storage_ref =~ workspace_root
      refute persisted.storage_ref =~ source_path

      assert {:ok, managed_path} = LocalStorage.resolve_storage_ref(persisted.storage_ref)
      assert {:ok, managed_content} = File.read(managed_path)
      assert managed_content == "# Summary\n"
    end

    test "returns error for missing workspace file" do
      instance = insert_scoped_instance()

      assert {:error, :source_not_found} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: "reports/missing.md", lemming_instance_id: instance.id}
               )
    end

    test "returns error for unsafe workspace path traversal" do
      instance = insert_scoped_instance()

      assert {:error, :path_outside_workspace} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: "../secret.md", lemming_instance_id: instance.id}
               )
    end

    test "requires explicit mode when same-scope filename already exists", %{
      workspace_root: workspace_root
    } do
      instance = insert_scoped_instance()
      relative_path = "reports/update.md"
      _source_path = write_workspace_file(workspace_root, instance, relative_path, "v1")

      assert {:ok, first} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: relative_path, lemming_instance_id: instance.id}
               )

      first_row = Repo.get!(Artifact, first.id)

      _source_path = write_workspace_file(workspace_root, instance, relative_path, "v2")

      assert {:error, :mode_required} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: relative_path, lemming_instance_id: instance.id}
               )

      reloaded = Repo.get!(Artifact, first.id)
      assert reloaded.checksum == first_row.checksum
      assert reloaded.size_bytes == first_row.size_bytes
    end

    test "mode update_existing overwrites managed file and keeps same row id", %{
      workspace_root: workspace_root
    } do
      instance = insert_scoped_instance()
      relative_path = "reports/plan.txt"
      _source_path = write_workspace_file(workspace_root, instance, relative_path, "old")

      assert {:ok, first} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: relative_path, lemming_instance_id: instance.id}
               )

      _source_path = write_workspace_file(workspace_root, instance, relative_path, "new content")

      assert {:ok, updated} =
               Promotion.promote_workspace_file(promotion_scope(instance), %{
                 relative_path: relative_path,
                 lemming_instance_id: instance.id,
                 mode: :update_existing
               })

      assert updated.id == first.id
      refute updated.checksum == first.checksum
      refute updated.size_bytes == first.size_bytes

      persisted = Repo.get!(Artifact, updated.id)
      assert {:ok, managed_path} = LocalStorage.resolve_storage_ref(persisted.storage_ref)
      assert {:ok, managed_content} = File.read(managed_path)
      assert managed_content == "new content"
    end

    test "mode promote_as_new keeps existing row and creates new artifact", %{
      workspace_root: workspace_root
    } do
      instance = insert_scoped_instance()
      relative_path = "reports/new-copy.md"
      _source_path = write_workspace_file(workspace_root, instance, relative_path, "alpha")

      assert {:ok, first} =
               Promotion.promote_workspace_file(
                 promotion_scope(instance),
                 %{relative_path: relative_path, lemming_instance_id: instance.id}
               )

      _source_path = write_workspace_file(workspace_root, instance, relative_path, "beta")

      assert {:ok, second} =
               Promotion.promote_workspace_file(promotion_scope(instance), %{
                 relative_path: relative_path,
                 lemming_instance_id: instance.id,
                 mode: :promote_as_new
               })

      refute second.id == first.id

      scope = %{
        world_id: instance.world_id,
        city_id: instance.city_id,
        department_id: instance.department_id,
        lemming_id: instance.lemming_id
      }

      assert {:ok, listed} = Artifacts.list_artifacts_for_scope(scope)
      ids = MapSet.new(Enum.map(listed, & &1.id))
      assert ids == MapSet.new([first.id, second.id])
    end
  end

  defp insert_scoped_instance do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department)

    insert(:lemming_instance,
      world: world,
      city: city,
      department: department,
      lemming: lemming
    )
  end

  defp write_workspace_file(workspace_root, instance, relative_path, content) do
    base_path = Path.join([workspace_root, instance.department_id, instance.lemming_id])
    absolute_path = Path.join(base_path, relative_path)
    :ok = File.mkdir_p(Path.dirname(absolute_path))
    :ok = File.write(absolute_path, content)
    absolute_path
  end

  defp promotion_scope(instance) do
    %{
      world_id: instance.world_id,
      city_id: nil,
      department_id: nil,
      lemming_id: nil,
      lemming_instance_id: nil
    }
  end
end
