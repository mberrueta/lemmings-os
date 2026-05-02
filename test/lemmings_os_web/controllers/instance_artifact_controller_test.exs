defmodule LemmingsOsWeb.InstanceArtifactControllerTest do
  use LemmingsOsWeb.ConnCase, async: false

  import LemmingsOs.Factory

  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Repo

  @moduletag capture_log: true

  setup do
    old_artifact_storage = Application.get_env(:lemmings_os, :artifact_storage)

    test_root =
      Path.join(
        System.tmp_dir!(),
        "lemmings_instance_artifact_controller_#{System.unique_integer([:positive])}"
      )

    artifact_storage_root = Path.join(test_root, "artifact_storage")
    File.rm_rf!(test_root)
    File.mkdir_p!(artifact_storage_root)

    Application.put_env(:lemmings_os, :artifact_storage,
      backend: :local,
      root_path: artifact_storage_root
    )

    on_exit(fn ->
      File.rm_rf!(test_root)

      if old_artifact_storage do
        Application.put_env(:lemmings_os, :artifact_storage, old_artifact_storage)
      else
        Application.delete_env(:lemmings_os, :artifact_storage)
      end
    end)

    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Write artifact")

    %{world: world, instance: instance, test_root: test_root}
  end

  describe "download/2 durable artifact route" do
    test "DL01: serves durable artifact bytes with safe headers", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact, content: content} =
        insert_managed_artifact(instance, test_root, %{
          filename: "reports/summary.md",
          content_type: "text/markdown",
          type: "markdown",
          content: "# Summary artifact\nconfidential\n"
        })

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      assert response.status == 200
      assert response.resp_body == content
      assert get_resp_header(response, "content-type") == ["text/markdown"]
      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]

      assert get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="summary.md")
             ]
    end

    test "DL01b: strips control characters from content-disposition filename", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} =
        insert_managed_artifact(instance, test_root, %{filename: "header.md"})

      artifact =
        artifact
        |> Artifact.changeset(%{filename: "safe\r\nname.md"})
        |> Repo.update!()

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      [disposition] = get_resp_header(response, "content-disposition")
      assert response.status == 200
      assert disposition == ~s(attachment; filename="safename.md")
      refute String.contains?(disposition, "\r")
      refute String.contains?(disposition, "\n")
    end

    test "DL02: rejects wrong scope before storage resolution", %{
      conn: conn,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} =
        insert_managed_artifact(instance, test_root, %{storage_ref: "local://bad/ref"})

      other_world = insert(:world)

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: other_world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end

    test "DL02b: rejects artifact ids that belong to a different instance", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} = insert_managed_artifact(instance, test_root)

      other_city = insert(:city, world: world, status: "active")
      other_department = insert(:department, world: world, city: other_city)

      other_lemming =
        insert(:lemming,
          world: world,
          city: other_city,
          department: other_department,
          status: "active"
        )

      {:ok, other_instance} =
        LemmingInstances.spawn_instance(other_lemming, "Other instance request")

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{other_instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end

    test "DL03: blocks archived/deleted/error artifacts by default", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      for status <- ~w(archived deleted error) do
        %{artifact: artifact} =
          insert_managed_artifact(instance, test_root, %{status: status, filename: "#{status}.md"})

        response =
          conn
          |> get(
            ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
          )

        assert response.status == 404
        assert response.resp_body == "Artifact not found"
      end
    end

    test "DL04: missing physical file returns safe not found without path leakage", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} = insert_managed_artifact(instance, test_root)
      {:ok, stored_path} = LocalStorage.resolve_storage_ref(artifact.storage_ref)
      File.rm!(stored_path)

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      headers_blob =
        response.resp_headers
        |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{value}" end)

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
      refute response.resp_body =~ stored_path
      refute response.resp_body =~ artifact.storage_ref
      refute response.resp_body =~ "artifact_storage"
      refute headers_blob =~ stored_path
      refute headers_blob =~ artifact.storage_ref
      refute headers_blob =~ "artifact_storage"

      repaired = Repo.get!(Artifact, artifact.id)
      assert repaired.status == "error"
      assert repaired.metadata["source"] == "manual_promotion"
      assert repaired.metadata["storage_error_reason"] == "not_found"
      assert repaired.metadata["storage_error_operation"] == "open"
      assert is_binary(repaired.metadata["storage_error_at"])
    end

    test "DL05: invalid storage ref returns safe not found", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} =
        insert_managed_artifact(instance, test_root, %{storage_ref: "s3://bucket/artifact.md"})

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"

      repaired = Repo.get!(Artifact, artifact.id)
      assert repaired.status == "error"
      assert repaired.metadata["storage_error_reason"] == "invalid_storage_ref"
      assert repaired.metadata["storage_error_operation"] == "open"
    end

    test "returns world not found for unknown world", %{
      conn: conn,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} = insert_managed_artifact(instance, test_root)

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{artifact.id}/download?#{%{world: Ecto.UUID.generate()}}"
        )

      assert response.status == 404
      assert response.resp_body == "World not found"
    end

    test "returns artifact not found for unknown instance", %{
      conn: conn,
      world: world,
      instance: instance,
      test_root: test_root
    } do
      %{artifact: artifact} = insert_managed_artifact(instance, test_root)

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{Ecto.UUID.generate()}/artifacts/#{artifact.id}/download?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end

    test "falls back to artifact not found for non-download params", %{conn: conn} do
      response = LemmingsOsWeb.InstanceArtifactController.download(conn, %{})

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end
  end

  describe "show/2 workspace route compatibility" do
    test "DL06: existing workspace catch-all route still serves workspace file", %{
      conn: conn,
      world: world,
      instance: instance
    } do
      _absolute_path =
        write_workspace_file(instance, "reports/runtime.md", "# Runtime workspace artifact\n")

      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{["reports", "runtime.md"]}?#{%{world: world.id}}"
        )

      assert response.status == 200
      assert response.resp_body == "# Runtime workspace artifact\n"
      assert get_resp_header(response, "content-type") == ["application/octet-stream"]
      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    end

    test "returns world not found for unknown world", %{
      conn: conn,
      instance: instance
    } do
      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{["reports", "runtime.md"]}?#{%{world: Ecto.UUID.generate()}}"
        )

      assert response.status == 404
      assert response.resp_body == "World not found"
    end

    test "returns instance not found for unknown instance", %{
      conn: conn,
      world: world
    } do
      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{Ecto.UUID.generate()}/artifacts/#{["reports", "runtime.md"]}?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Instance not found"
    end

    test "returns artifact not found for missing workspace file", %{
      conn: conn,
      world: world,
      instance: instance
    } do
      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{["reports", "missing.md"]}?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end

    test "returns artifact not found for unsafe workspace traversal", %{
      conn: conn,
      world: world,
      instance: instance
    } do
      response =
        conn
        |> get(
          ~p"/lemmings/instances/#{instance.id}/artifacts/#{["..", "secret.md"]}?#{%{world: world.id}}"
        )

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end

    test "falls back to artifact not found for non-show params", %{conn: conn} do
      response = LemmingsOsWeb.InstanceArtifactController.show(conn, %{})

      assert response.status == 404
      assert response.resp_body == "Artifact not found"
    end
  end

  defp insert_managed_artifact(instance, test_root, attrs \\ %{}) do
    filename = Map.get(attrs, :filename, "report.md")
    content = Map.get(attrs, :content, "# Artifact content\n")
    status = Map.get(attrs, :status, "ready")
    type = Map.get(attrs, :type, "markdown")
    content_type = Map.get(attrs, :content_type, "text/markdown")

    source_path =
      Path.join([
        test_root,
        "sources",
        "#{System.unique_integer([:positive])}-#{Path.basename(filename)}"
      ])

    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, content)

    artifact_id = Ecto.UUID.generate()

    stored =
      case Map.get(attrs, :storage_ref) do
        storage_ref when is_binary(storage_ref) ->
          %{
            storage_ref: storage_ref,
            checksum: String.duplicate("f", 64),
            size_bytes: byte_size(content)
          }

        nil ->
          {:ok, stored} =
            LocalStorage.store_copy(
              instance.world_id,
              artifact_id,
              source_path,
              Path.basename(filename)
            )

          stored
      end

    artifact =
      %Artifact{id: artifact_id}
      |> Artifact.changeset(%{
        world_id: instance.world_id,
        city_id: instance.city_id,
        department_id: instance.department_id,
        lemming_id: instance.lemming_id,
        lemming_instance_id: instance.id,
        filename: Path.basename(filename),
        type: type,
        content_type: content_type,
        storage_ref: stored.storage_ref,
        size_bytes: stored.size_bytes,
        checksum: stored.checksum,
        status: status,
        metadata: %{"source" => "manual_promotion"}
      })
      |> Repo.insert!()

    %{artifact: artifact, content: content}
  end

  defp write_workspace_file(instance, relative_path, content) do
    {:ok, %{absolute_path: absolute_path}} =
      LemmingInstances.artifact_absolute_path(instance, relative_path)

    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, content)
    absolute_path
  end
end
