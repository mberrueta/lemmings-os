defmodule LemmingsOsWeb.InstanceArtifactController do
  @moduledoc """
  Serves workspace file downloads for a lemming instance.

  This controller handles path-based workspace artifacts from
  `/lemmings/instances/:id/artifacts/*path`, resolving the path through
  `LemmingInstances.artifact_absolute_path/2` to enforce world scoping and
  workspace path safety.

  It is intentionally separate from durable Artifact-record downloads; it
  streams files that exist in the runtime workspace.
  """
  use LemmingsOsWeb, :controller

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Worlds

  def show(conn, %{"id" => id, "path" => path_segments} = params) when is_list(path_segments) do
    with %{} = world <- resolve_world(params),
         {:ok, instance} <-
           LemmingsOs.LemmingInstances.get_instance(id, world: world, preload: [:lemming]),
         relative_path <- Path.join(path_segments),
         {:ok, %{absolute_path: absolute_path, relative_path: normalized_path}} <-
           LemmingInstances.artifact_absolute_path(instance, relative_path),
         {:ok, content} <- File.read(absolute_path) do
      conn
      |> put_resp_header("content-type", "application/octet-stream")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{Path.basename(normalized_path)}")
      )
      |> send_resp(200, content)
    else
      nil -> send_resp(conn, 404, "World not found")
      {:error, :not_found} -> send_resp(conn, 404, "Instance not found")
      {:error, :invalid_path} -> send_resp(conn, 404, "Artifact not found")
      {:error, :path_outside_workspace} -> send_resp(conn, 404, "Artifact not found")
      {:error, :enoent} -> send_resp(conn, 404, "Artifact not found")
      {:error, _reason} -> send_resp(conn, 404, "Artifact not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Artifact not found")

  defp resolve_world(%{"world" => world_id}) when is_binary(world_id) and world_id != "" do
    Worlds.get_world(world_id)
  end

  defp resolve_world(_params), do: Worlds.get_default_world()
end
