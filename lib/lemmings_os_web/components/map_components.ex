defmodule LemmingsOsWeb.MapComponents do
  @moduledoc """
  Visual map components for the world and city pages.
  """

  use LemmingsOsWeb, :html

  attr :city, :map, required: true
  attr :id, :string, default: nil
  attr :size, :integer, default: 120
  attr :show_label, :boolean, default: true
  attr :class, :string, default: ""

  def city_node(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        assigns.id || "city-node-#{Map.get(assigns.city, :id, "unknown")}"
      )

    ~H"""
    <div
      id={@id}
      class={["city-node", @class]}
      style={"--city-accent: #{city_color(@city)};"}
    >
      <svg
        width={@size}
        height={@size}
        viewBox="0 0 60 60"
        xmlns="http://www.w3.org/2000/svg"
        class="city-node__svg"
        role="img"
        aria-label={dgettext("world", ".aria_city_node", name: Map.get(@city, :name))}
      >
        <rect
          x="8"
          y="40"
          width="44"
          height="8"
          fill="#0c1a10"
          stroke={city_color(@city)}
          stroke-width="0.5"
        />
        <rect
          x="14"
          y="18"
          width="8"
          height="22"
          fill="#0a1610"
          stroke={city_color(@city)}
          stroke-width="0.5"
        />
        <rect x="16" y="21" width="2" height="2" fill={city_color(@city)} opacity="0.5" />
        <rect x="19" y="21" width="2" height="2" fill={city_color(@city)} opacity="0.4" />
        <rect x="16" y="27" width="2" height="2" fill={city_color(@city)} opacity="0.6" />
        <rect x="19" y="27" width="2" height="2" fill={city_color(@city)} opacity="0.3" />
        <rect x="16" y="33" width="2" height="2" fill={city_color(@city)} opacity="0.5" />

        <rect
          x="24"
          y="24"
          width="10"
          height="16"
          fill="#0a1610"
          stroke={city_color(@city)}
          stroke-width="0.5"
        />
        <rect x="26" y="27" width="2" height="2" fill={city_color(@city)} opacity="0.6" />
        <rect x="30" y="27" width="2" height="2" fill={city_color(@city)} opacity="0.4" />
        <rect x="26" y="33" width="2" height="2" fill={city_color(@city)} opacity="0.5" />
        <rect x="30" y="33" width="2" height="2" fill={city_color(@city)} opacity="0.3" />

        <rect
          x="36"
          y="30"
          width="7"
          height="10"
          fill="#0a1610"
          stroke={city_color(@city)}
          stroke-width="0.5"
        />
        <rect x="38" y="33" width="2" height="2" fill={city_color(@city)} opacity="0.5" />

        <line x1="18" y1="14" x2="18" y2="18" stroke={city_color(@city)} stroke-width="0.5" />
        <rect
          x="17"
          y="12"
          width="2"
          height="2"
          fill={beacon_color(Map.get(@city, :status))}
          opacity="0.8"
        >
          <animate attributeName="opacity" values="0.8;0.2;0.8" dur="2s" repeatCount="indefinite" />
        </rect>

        <circle cx="30" cy="40" r="20" fill={city_color(@city)} opacity="0.04" />

        <rect
          x="38"
          y="14"
          width="14"
          height="9"
          fill="#0a1a10"
          stroke={city_color(@city)}
          stroke-width="0.5"
        />
        <text
          x="45"
          y="21"
          text-anchor="middle"
          fill={city_color(@city)}
          font-size="6"
          font-family="monospace"
        >
          {Map.get(@city, :agents, 0)}
        </text>
      </svg>

      <div :if={@show_label} class="city-node__label">
        <span class="city-node__name" style={"color: #{city_color(@city)};"}>
          {Map.get(@city, :name)}
        </span>
        <small class="city-node__region">{Map.get(@city, :region)}</small>
      </div>
    </div>
    """
  end

  attr :cities, :list, required: true
  attr :id, :string, default: "world-map"
  attr :class, :string, default: ""

  def world_map(assigns) do
    ~H"""
    <div
      id={@id}
      class={["world-map-canvas", @class]}
      phx-hook="WorldMapHook"
      data-cities={encode_cities(@cities)}
    >
      <canvas id={"#{@id}-canvas"}></canvas>

      <div class="world-map-canvas__hud">
        <span class="world-map-canvas__title">{dgettext("world", ".title_world_map")}</span>
        <span class="world-map-canvas__stats">
          <span class="world-map-canvas__stat-label">{dgettext("world", ".metric_nodes")}</span>
          <span class="world-map-canvas__stat-value">{length(@cities)}</span>
          <span class="world-map-canvas__stat-label">{dgettext("world", ".metric_online")}</span>
          <span class="world-map-canvas__stat-value">{count_online(@cities)}</span>
          <span class="world-map-canvas__stat-label">{dgettext("world", ".metric_agents")}</span>
          <span class="world-map-canvas__stat-value">{total_agents(@cities)}</span>
        </span>
      </div>

      <div id={"#{@id}-tooltip"} class="world-map-canvas__tooltip" hidden></div>
    </div>
    """
  end

  defp beacon_color(status) when status in [:online, "online"], do: "#3ddc84"
  defp beacon_color(status) when status in [:degraded, "degraded"], do: "#ff9b54"
  defp beacon_color(status) when status in [:offline, "offline"], do: "#ff4444"
  defp beacon_color(_status), do: "#3ddc84"

  defp city_color(city), do: Map.get(city, :color, "#49f28e")

  defp count_online(cities) do
    Enum.count(cities, fn city -> Map.get(city, :status) in [:online, "online"] end)
  end

  defp total_agents(cities) do
    Enum.reduce(cities, 0, fn city, acc -> acc + Map.get(city, :agents, 0) end)
  end

  defp encode_cities(cities) do
    cities
    |> Enum.map(fn city ->
      %{
        id: Map.get(city, :id),
        name: Map.get(city, :name),
        region: Map.get(city, :region),
        color: city_color(city),
        status: city |> Map.get(:status) |> to_string(),
        agents: Map.get(city, :agents, 0),
        depts: Map.get(city, :depts, 0),
        col: Map.get(city, :col),
        row: Map.get(city, :row)
      }
    end)
    |> Jason.encode!()
  end
end
