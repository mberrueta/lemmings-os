defmodule LemmingsOsWeb.InstanceRawSnapshotController do
  use LemmingsOsWeb, :controller

  alias LemmingsOsWeb.PageData.InstanceRawSnapshot
  alias LemmingsOs.Worlds

  def show(conn, %{"id" => id} = params) do
    case resolve_world(params) do
      nil ->
        send_resp(conn, 404, "World not found")

      world ->
        case InstanceRawSnapshot.build(instance_id: id, world: world) do
          {:ok, snapshot} ->
            conn
            |> put_resp_content_type("text/markdown")
            |> send_resp(200, InstanceRawSnapshot.to_markdown(snapshot))

          {:error, :not_found} ->
            send_resp(conn, 404, "Instance not found")
        end
    end
  end

  defp resolve_world(%{"world" => world_id}) when is_binary(world_id) and world_id != "" do
    Worlds.get_world(world_id)
  end

  defp resolve_world(_params), do: nil
end
