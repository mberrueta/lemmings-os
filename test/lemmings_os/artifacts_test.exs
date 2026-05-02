defmodule LemmingsOs.ArtifactsTest do
  use LemmingsOs.DataCase, async: false

  import LemmingsOs.Factory

  alias LemmingsOs.Artifacts
  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.Repo

  @moduletag capture_log: true

  doctest Artifacts

  setup do
    old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

    root_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_artifacts_context_test_#{System.unique_integer([:positive])}"
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

  describe "create_artifact/2" do
    test "creates an artifact descriptor in explicit world scope" do
      world = insert(:world)

      attrs = %{
        filename: "report.md",
        type: "markdown",
        content_type: "text/markdown",
        storage_ref: "local://artifacts/#{world.id}/#{Ecto.UUID.generate()}/report.md",
        size_bytes: 64,
        checksum: String.duplicate("a", 64),
        status: "ready",
        metadata: %{"source" => "manual_promotion"}
      }

      assert {:ok, descriptor} = Artifacts.create_artifact(world, attrs)
      refute Map.has_key?(descriptor, :storage_ref)
      assert descriptor.world_id == world.id
      assert descriptor.status == "ready"
      assert descriptor.filename == "report.md"
    end

    test "rejects scope mismatches from attrs" do
      world = insert(:world)
      other_world = insert(:world)

      attrs = %{
        world_id: other_world.id,
        filename: "report.md",
        type: "markdown",
        content_type: "text/markdown",
        storage_ref: "local://artifacts/#{world.id}/#{Ecto.UUID.generate()}/report.md",
        size_bytes: 64,
        checksum: String.duplicate("a", 64),
        status: "ready",
        metadata: %{"source" => "manual_promotion"}
      }

      assert {:error, :scope_mismatch} = Artifacts.create_artifact(world, attrs)
    end
  end

  describe "get_artifact/2 and get_artifact/3" do
    test "enforces world scope and defaults to ready artifacts only" do
      lemming = insert_scoped_lemming()
      ready_artifact = insert_artifact_for_lemming(lemming, status: "ready")
      archived_artifact = insert_artifact_for_lemming(lemming, status: "archived")

      assert {:ok, found} = Artifacts.get_artifact(ready_artifact.world, ready_artifact.id)
      assert found.id == ready_artifact.id

      assert {:error, :not_found} =
               Artifacts.get_artifact(ready_artifact.world, archived_artifact.id)

      assert {:ok, archived} =
               Artifacts.get_artifact(
                 ready_artifact.world,
                 archived_artifact.id,
                 include_non_ready: true
               )

      assert archived.id == archived_artifact.id

      other_world = insert(:world)
      assert {:error, :not_found} = Artifacts.get_artifact(other_world, ready_artifact.id)
    end
  end

  describe "open_artifact_download/2" do
    test "opens a ready artifact after scope checks", %{root_path: root_path} do
      instance = insert_scoped_instance(insert_scoped_lemming())
      artifact = insert_managed_artifact(instance, root_path, "artifact.txt", "hello")

      assert {:ok, opened} = Artifacts.open_artifact_download(instance, artifact.id)
      assert opened.filename == "artifact.txt"
      assert opened.content_type == "text/plain"
      assert opened.size_bytes == 5
      assert String.starts_with?(opened.path, Path.expand(root_path) <> "/")
    end

    test "does not open non-ready artifacts", %{root_path: root_path} do
      instance = insert_scoped_instance(insert_scoped_lemming())
      artifact = insert_managed_artifact(instance, root_path, "artifact.txt", "hello")

      assert {:ok, _descriptor} =
               Artifacts.update_artifact_status(instance, artifact.id, "archived")

      assert {:error, :not_found} = Artifacts.open_artifact_download(instance, artifact.id)
    end

    test "marks missing ready storage as error with safe metadata", %{root_path: root_path} do
      instance = insert_scoped_instance(insert_scoped_lemming())
      artifact = insert_managed_artifact(instance, root_path, "artifact.txt", "hello")
      {:ok, managed_path} = LocalStorage.resolve_storage_ref(artifact.storage_ref)
      File.rm!(managed_path)

      assert {:error, :not_found} = Artifacts.open_artifact_download(instance, artifact.id)

      repaired = Repo.get!(Artifact, artifact.id)
      assert repaired.status == "error"
      assert repaired.metadata["storage_error_reason"] == "not_found"
      assert repaired.metadata["storage_error_operation"] == "open"
      refute inspect(repaired.metadata) =~ root_path
      refute inspect(repaired.metadata) =~ managed_path
    end
  end

  describe "list_artifacts_for_scope/2" do
    test "returns only ready by default and supports explicit status filters" do
      lemming = insert_scoped_lemming()
      ready_artifact = insert_artifact_for_lemming(lemming, status: "ready")
      archived_artifact = insert_artifact_for_lemming(lemming, status: "archived")
      _deleted_artifact = insert_artifact_for_lemming(lemming, status: "deleted")

      assert {:ok, listed} = Artifacts.list_artifacts_for_scope(lemming)
      assert Enum.map(listed, & &1.id) == [ready_artifact.id]

      assert {:ok, listed_with_archived} =
               Artifacts.list_artifacts_for_scope(lemming, statuses: ["ready", "archived"])

      assert MapSet.new(Enum.map(listed_with_archived, & &1.id)) ==
               MapSet.new([archived_artifact.id, ready_artifact.id])
    end

    test "returns invalid_scope for malformed map scope" do
      assert {:error, :invalid_scope} =
               Artifacts.list_artifacts_for_scope(%{city_id: Ecto.UUID.generate()})
    end
  end

  describe "list_artifacts_for_instance/2 and /3" do
    test "returns scoped instance artifacts and defaults to ready only" do
      lemming = insert_scoped_lemming()
      instance = insert_scoped_instance(lemming)

      ready_artifact =
        insert_artifact_for_instance(instance, status: "ready")

      archived_artifact =
        insert_artifact_for_instance(instance, status: "archived")

      other_instance = insert_scoped_instance(lemming)

      _other_instance_artifact = insert_artifact_for_instance(other_instance, status: "ready")

      assert {:ok, listed} = Artifacts.list_artifacts_for_instance(instance.lemming, instance.id)
      assert Enum.map(listed, & &1.id) == [ready_artifact.id]

      assert {:ok, listed_with_archived} =
               Artifacts.list_artifacts_for_instance(
                 instance.lemming,
                 instance.id,
                 include_non_ready: true
               )

      assert MapSet.new(Enum.map(listed_with_archived, & &1.id)) ==
               MapSet.new([archived_artifact.id, ready_artifact.id])
    end
  end

  describe "update_artifact_status/3" do
    test "updates status in scope and supports non-ready fetch with explicit option" do
      artifact = insert_artifact_for_lemming(insert_scoped_lemming(), status: "ready")

      assert {:ok, updated} =
               Artifacts.update_artifact_status(artifact.world, artifact.id, "archived")

      assert updated.status == "archived"
      assert {:error, :not_found} = Artifacts.get_artifact(artifact.world, artifact.id)

      assert {:ok, fetched} =
               Artifacts.get_artifact(artifact.world, artifact.id, include_non_ready: true)

      assert fetched.status == "archived"
    end

    test "returns not_found outside of scope" do
      artifact = insert_artifact_for_lemming(insert_scoped_lemming(), status: "ready")
      other_world = insert(:world)

      assert {:error, :not_found} =
               Artifacts.update_artifact_status(other_world, artifact.id, "archived")
    end

    test "rejects invalid status values" do
      artifact = insert_artifact_for_lemming(insert_scoped_lemming(), status: "ready")

      assert {:error, :invalid_status} =
               Artifacts.update_artifact_status(artifact.world, artifact.id, "pending")
    end

    test "soft delete does not physically delete managed storage", %{root_path: root_path} do
      instance = insert_scoped_instance(insert_scoped_lemming())
      artifact = insert_managed_artifact(instance, root_path, "artifact.txt", "hello")
      {:ok, managed_path} = LocalStorage.resolve_storage_ref(artifact.storage_ref)

      assert {:ok, descriptor} =
               Artifacts.update_artifact_status(instance, artifact.id, "deleted")

      assert descriptor.status == "deleted"
      assert File.exists?(managed_path)
    end
  end

  describe "artifact_descriptor/1" do
    test "omits storage_ref from read model" do
      artifact = insert_artifact_for_lemming(insert_scoped_lemming())
      descriptor = Artifacts.artifact_descriptor(artifact)

      refute Map.has_key?(descriptor, :storage_ref)
      assert descriptor.id == artifact.id
      assert descriptor.filename == artifact.filename
    end
  end

  describe "database behavior through context" do
    test "create_artifact/2 persists row and keeps storage_ref internal-only" do
      world = insert(:world)
      artifact_id = Ecto.UUID.generate()

      attrs = %{
        filename: "internal.md",
        type: "markdown",
        content_type: "text/markdown",
        storage_ref: "local://artifacts/#{world.id}/#{artifact_id}/internal.md",
        size_bytes: 11,
        checksum: String.duplicate("b", 64),
        status: "ready",
        metadata: %{"source" => "manual_promotion"}
      }

      assert {:ok, descriptor} = Artifacts.create_artifact(world, attrs)
      assert %Artifact{} = persisted = Repo.get(Artifact, descriptor.id)
      assert persisted.storage_ref == attrs.storage_ref
      refute Map.has_key?(descriptor, :storage_ref)
    end
  end

  defp insert_scoped_lemming do
    world = insert(:world)
    city = insert(:city, world: world)
    department = insert(:department, world: world, city: city)
    insert(:lemming, world: world, city: city, department: department)
  end

  defp insert_scoped_instance(lemming) do
    insert(:lemming_instance,
      lemming: lemming,
      world: lemming.world,
      city: lemming.city,
      department: lemming.department
    )
  end

  defp insert_managed_artifact(instance, root_path, filename, content) do
    artifact_id = Ecto.UUID.generate()
    source_path = Path.join(root_path, "source-#{artifact_id}.txt")
    :ok = File.mkdir_p(root_path)
    :ok = File.write(source_path, content)

    {:ok, stored} =
      LocalStorage.store_copy(instance.world_id, artifact_id, source_path, filename)

    %Artifact{id: artifact_id}
    |> Artifact.changeset(%{
      world_id: instance.world_id,
      city_id: instance.city_id,
      department_id: instance.department_id,
      lemming_id: instance.lemming_id,
      lemming_instance_id: instance.id,
      filename: filename,
      type: "text",
      content_type: "text/plain",
      storage_ref: stored.storage_ref,
      size_bytes: stored.size_bytes,
      checksum: stored.checksum,
      status: "ready",
      metadata: %{"source" => "manual_promotion"}
    })
    |> Repo.insert!()
  end

  defp insert_artifact_for_lemming(lemming, attrs \\ []) do
    insert(
      :artifact,
      [world: lemming.world, city: lemming.city, department: lemming.department, lemming: lemming] ++
        attrs
    )
  end

  defp insert_artifact_for_instance(instance, attrs) do
    insert(
      :artifact,
      [
        world: instance.world,
        city: instance.city,
        department: instance.department,
        lemming: instance.lemming,
        lemming_instance: instance
      ] ++ attrs
    )
  end
end
