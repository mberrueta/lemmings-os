defmodule LemmingsOsWeb.InstanceArtifactController do
  @moduledoc """
  Serves instance-scoped artifact downloads.

  It supports:

  - Durable Artifact-record downloads from
    `/lemmings/instances/:instance_id/artifacts/:artifact_id/download`
  - Legacy workspace artifact path downloads from
    `/lemmings/instances/:instance_id/artifacts/*path`
  """
  use LemmingsOsWeb, :controller

  alias LemmingsOs.Artifacts
  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.Worlds

  def download(conn, %{"artifact_id" => artifact_id} = params) when is_binary(artifact_id) do
    with %{} = world <- resolve_world(params),
         {:ok, instance_id} <- fetch_instance_id(params),
         {:ok, instance} <- LemmingInstances.get_instance(instance_id, world: world),
         {:ok, artifact} <- Artifacts.get_artifact_download(instance, artifact_id),
         {:ok, absolute_path} <- LocalStorage.resolve_storage_ref(artifact.storage_ref),
         {:ok, content} <- File.read(absolute_path) do
      conn
      |> put_resp_header("content-type", artifact.content_type)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-disposition", content_disposition(artifact.filename))
      |> send_resp(200, content)
    else
      nil -> send_resp(conn, 404, "World not found")
      {:error, :missing_instance_id} -> send_resp(conn, 404, "Artifact not found")
      {:error, :not_found} -> send_resp(conn, 404, "Artifact not found")
      {:error, :invalid_storage_ref} -> send_resp(conn, 404, "Artifact not found")
      {:error, :storage_unavailable} -> send_resp(conn, 404, "Artifact not found")
      {:error, :enoent} -> send_resp(conn, 404, "Artifact not found")
      {:error, _reason} -> send_resp(conn, 404, "Artifact not found")
    end
  end

  def download(conn, _params), do: send_resp(conn, 404, "Artifact not found")

  def show(conn, %{"path" => path_segments} = params) when is_list(path_segments) do
    with %{} = world <- resolve_world(params),
         {:ok, instance_id} <- fetch_instance_id(params),
         {:ok, instance} <-
           LemmingInstances.get_instance(instance_id, world: world, preload: [:lemming]),
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
      {:error, :missing_instance_id} -> send_resp(conn, 404, "Artifact not found")
      {:error, :not_found} -> send_resp(conn, 404, "Instance not found")
      {:error, :invalid_path} -> send_resp(conn, 404, "Artifact not found")
      {:error, :path_outside_workspace} -> send_resp(conn, 404, "Artifact not found")
      {:error, :enoent} -> send_resp(conn, 404, "Artifact not found")
      {:error, _reason} -> send_resp(conn, 404, "Artifact not found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Artifact not found")

  defp fetch_instance_id(%{"instance_id" => instance_id})
       when is_binary(instance_id) and instance_id != "",
       do: {:ok, instance_id}

  defp fetch_instance_id(%{"id" => instance_id})
       when is_binary(instance_id) and instance_id != "",
       do: {:ok, instance_id}

  defp fetch_instance_id(_params), do: {:error, :missing_instance_id}

  defp content_disposition(filename) when is_binary(filename) do
    basename =
      filename
      |> Path.basename()
      |> String.replace("\"", "")
      |> String.replace(~r/[\x00-\x1F\x7F]/, "")

    ~s(attachment; filename="#{basename}")
  end

  defp resolve_world(%{"world" => world_id}) when is_binary(world_id) and world_id != "" do
    Worlds.get_world(world_id)
  end

  defp resolve_world(_params), do: Worlds.get_default_world()
end
