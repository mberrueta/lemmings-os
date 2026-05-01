defmodule LemmingsOsWeb.InstanceArtifactControllerTest do
  use LemmingsOsWeb.ConnCase, async: false

  import LemmingsOs.Factory

  alias LemmingsOs.LemmingInstances

  setup do
    world = insert(:world)
    city = insert(:city, world: world, status: "active")
    department = insert(:department, world: world, city: city)
    lemming = insert(:lemming, world: world, city: city, department: department, status: "active")

    {:ok, instance} = LemmingInstances.spawn_instance(lemming, "Write artifact")

    %{world: world, instance: instance}
  end

  test "DL01: serves workspace artifact bytes with safe headers", %{
    conn: conn,
    world: world,
    instance: instance
  } do
    _absolute_path =
      write_workspace_file(instance, "reports/summary.md", "# Summary artifact\nconfidential\n")

    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["reports", "summary.md"]}?#{%{world: world.id}}"
      )

    assert response.status == 200
    assert response.resp_body == "# Summary artifact\nconfidential\n"
    assert get_resp_header(response, "content-type") == ["application/octet-stream"]

    assert get_resp_header(response, "content-disposition") == [
             ~s(attachment; filename="summary.md")
           ]

    assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
  end

  test "DL02: rejects wrong scope before path resolution", %{conn: conn, instance: instance} do
    other_world = insert(:world)

    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["..", "secret.md"]}?#{%{world: other_world.id}}"
      )

    assert response.status == 404
    assert response.resp_body == "Instance not found"
  end

  test "DL03: rejects traversal path in artifact route", %{
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

  test "DL04: missing file returns safe not found without path leakage", %{
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
    refute response.resp_body =~ "reports/missing.md"
    refute response.resp_body =~ "workspace"
  end

  test "DL05: rejects symlink targets outside workspace", %{
    conn: conn,
    world: world,
    instance: instance
  } do
    {:ok, %{absolute_path: safe_path}} =
      LemmingInstances.artifact_absolute_path(instance, "safe.md")

    work_area = Path.dirname(safe_path)
    outside_path = Path.join(Path.dirname(work_area), "outside-artifact.md")
    File.mkdir_p!(work_area)
    File.mkdir_p!(Path.dirname(outside_path))
    File.write!(outside_path, "# Secret artifact\n")
    assert :ok = File.ln_s(outside_path, Path.join(work_area, "artifact-link.md"))

    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["artifact-link.md"]}?#{%{world: world.id}}"
      )

    assert response.status == 404
    assert response.resp_body == "Artifact not found"
  end

  test "DL06: unknown world returns world not found", %{conn: conn, instance: instance} do
    response =
      conn
      |> get(
        ~p"/lemmings/instances/#{instance.id}/artifacts/#{["summary.md"]}?#{%{world: Ecto.UUID.generate()}}"
      )

    assert response.status == 404
    assert response.resp_body == "World not found"
  end

  defp write_workspace_file(instance, relative_path, content) do
    {:ok, %{absolute_path: absolute_path}} =
      LemmingInstances.artifact_absolute_path(instance, relative_path)

    File.mkdir_p!(Path.dirname(absolute_path))
    File.write!(absolute_path, content)
    absolute_path
  end
end
