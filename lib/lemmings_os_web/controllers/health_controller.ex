defmodule LemmingsOsWeb.HealthController do
  @moduledoc """
  Liveness probe endpoint.

  Returns the runtime health of the world node and the last-known liveness of
  each registered city, derived from heartbeat freshness.

  Used by Docker Compose health checks (startup ordering) and operators who
  want a quick system-wide liveness snapshot without opening the UI.

  HTTP status is 200 as long as the world node is up and can reach the database.
  City liveness is informational in the response body — a stale city does not
  make the world node itself unhealthy.
  """

  use LemmingsOsWeb, :controller

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Worlds

  @stale_threshold_seconds Application.compile_env(
                             :lemmings_os,
                             [:runtime_city_heartbeat, :stale_threshold_seconds],
                             90
                           )

  def check(conn, _params) do
    node = System.get_env("LEMMINGS_CITY_NODE_NAME", "unknown")

    case city_liveness_summary() do
      {:ok, cities} ->
        json(conn, %{status: "ok", node: node, cities: cities})

      {:error, reason} ->
        conn
        |> put_status(503)
        |> json(%{status: "error", node: node, error: reason})
    end
  end

  defp city_liveness_summary do
    try do
      case Worlds.get_default_world() do
        %{} = world ->
          cities =
            Cities.list_cities(world)
            |> Enum.map(fn city ->
              %{
                node_name: city.node_name,
                name: city.name,
                status: city.status,
                liveness: City.liveness(city, @stale_threshold_seconds)
              }
            end)

          {:ok, cities}

        nil ->
          {:ok, []}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
