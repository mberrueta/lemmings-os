defmodule LemmingsOsWeb.CityMapComponents do
  @moduledoc """
  Visual map components for the city page.
  """

  use LemmingsOsWeb, :html

  attr :department, :map, required: true
  attr :size, :integer, default: 100
  attr :show_label, :boolean, default: true
  attr :class, :string, default: ""

  def department_node(assigns) do
    assigns = assign(assigns, :lemming_count, length(Map.get(assigns.department, :lemmings, [])))

    assigns =
      assign(
        assigns,
        :running_count,
        Enum.count(Map.get(assigns.department, :lemmings, []), fn lemming ->
          Map.get(lemming, :status) == :running
        end)
      )

    ~H"""
    <div class={["dept-node", @class]} style={"--dept-accent: #{department_color(@department)};"}>
      <svg
        width={@size}
        height={@size}
        viewBox="0 0 50 55"
        xmlns="http://www.w3.org/2000/svg"
        class="dept-node__svg"
        role="img"
        aria-label={dgettext("world", ".aria_department_node", name: @department.name)}
      >
        <rect
          x="4"
          y="38"
          width="42"
          height="8"
          fill="#0c1a10"
          stroke={department_color(@department)}
          stroke-width="0.5"
        />
        <rect
          x="8"
          y="16"
          width="18"
          height="22"
          fill="#0a1610"
          stroke={department_color(@department)}
          stroke-width="0.5"
        />
        <rect
          x="28"
          y="24"
          width="10"
          height="14"
          fill="#0a1610"
          stroke={department_color(@department)}
          stroke-width="0.5"
        />

        <rect x="11" y="20" width="2" height="2" fill={department_color(@department)} opacity="0.5" />
        <rect x="15" y="20" width="2" height="2" fill={department_color(@department)} opacity="0.4" />
        <rect x="20" y="20" width="2" height="2" fill={department_color(@department)} opacity="0.6" />
        <rect x="11" y="26" width="2" height="2" fill={department_color(@department)} opacity="0.3" />
        <rect x="15" y="26" width="2" height="2" fill={department_color(@department)} opacity="0.5" />
        <rect x="20" y="26" width="2" height="2" fill={department_color(@department)} opacity="0.4" />
        <rect x="11" y="32" width="2" height="2" fill={department_color(@department)} opacity="0.5" />
        <rect x="15" y="32" width="2" height="2" fill={department_color(@department)} opacity="0.6" />

        <rect x="31" y="28" width="2" height="2" fill={department_color(@department)} opacity="0.4" />
        <rect x="31" y="34" width="2" height="2" fill={department_color(@department)} opacity="0.5" />

        <line
          x1="14"
          y1="8"
          x2="14"
          y2="16"
          stroke={department_color(@department)}
          stroke-width="0.5"
        />
        <rect x="15" y="8" width="6" height="4" fill={department_color(@department)} opacity="0.7" />
        <rect x="15" y="12" width="6" height="1" fill={department_color(@department)} opacity="0.3" />

        <rect
          x="30"
          y="10"
          width="14"
          height="9"
          fill="#0a1a10"
          stroke={department_color(@department)}
          stroke-width="0.5"
        />
        <text
          x="37"
          y="17"
          text-anchor="middle"
          fill={department_color(@department)}
          font-size="6"
          font-family="monospace"
        >
          {@lemming_count}
        </text>

        <rect
          :for={
            {_lemming, index} <- Enum.with_index(Enum.take(Map.get(@department, :lemmings, []), 3))
          }
          x={10 + index * 10}
          y="47"
          width="4"
          height="4"
          fill={department_color(@department)}
          opacity="0.5"
        >
          <animate
            attributeName="x"
            values={"#{10 + index * 10};#{12 + index * 10};#{10 + index * 10}"}
            dur={"#{2 + index}s"}
            repeatCount="indefinite"
          />
        </rect>
      </svg>

      <div :if={@show_label} class="dept-node__label">
        <span class="dept-node__name" style={"color: #{department_color(@department)};"}>
          {@department.name}
        </span>
        <small class="dept-node__meta">
          {dgettext("world", ".count_running_of_total",
            running: @running_count,
            total: @lemming_count
          )}
        </small>
      </div>
    </div>
    """
  end

  attr :city, :map, required: true
  attr :departments, :list, required: true
  attr :id, :string, default: "city-map"
  attr :class, :string, default: ""

  def city_map(assigns) do
    assigns = assign(assigns, :total_lemmings, count_lemmings(assigns.departments))

    ~H"""
    <div
      id={@id}
      class={["city-map-canvas", @class]}
      phx-hook="CityMapHook"
      phx-update="ignore"
      tabindex="0"
      aria-label={dgettext("world", ".aria_city_map", name: @city.name)}
      data-city={encode_city(@city)}
      data-departments={encode_departments(@departments)}
      data-labels={encode_labels()}
    >
      <canvas id={"#{@id}-canvas"}></canvas>

      <div class="city-map-canvas__hud">
        <span class="city-map-canvas__title">
          {@city.name} <span class="city-map-canvas__region">· {@city.region}</span>
        </span>
        <span class="city-map-canvas__stats">
          <span class="city-map-canvas__stat-label">{dgettext("world", ".metric_departments")}</span>
          <span class="city-map-canvas__stat-value">{length(@departments)}</span>
          <span class="city-map-canvas__stat-label">{dgettext("world", ".metric_lemmings")}</span>
          <span class="city-map-canvas__stat-value">{@total_lemmings}</span>
          <span class="city-map-canvas__stat-label">{dgettext("world", ".metric_status")}</span>
          <span class={"city-map-canvas__status city-map-canvas__status--#{@city.status}"}>
            {status_label(@city.status)}
          </span>
        </span>
      </div>

      <div class="city-map-canvas__hud-bottom">{dgettext("world", ".map_hint_department")}</div>
      <div id={"#{@id}-tooltip"} class="city-map-canvas__tooltip" hidden></div>
    </div>
    """
  end

  defp count_lemmings(departments) do
    Enum.reduce(departments, 0, fn department, count ->
      count + length(Map.get(department, :lemmings, []))
    end)
  end

  defp status_label(:online), do: dgettext("world", ".status_online")
  defp status_label(:degraded), do: dgettext("world", ".status_degraded")
  defp status_label(:offline), do: dgettext("world", ".status_offline")
  defp status_label("online"), do: dgettext("world", ".status_online")
  defp status_label("degraded"), do: dgettext("world", ".status_degraded")
  defp status_label("offline"), do: dgettext("world", ".status_offline")
  defp status_label(_status), do: dgettext("world", ".status_online")

  defp department_color(department),
    do: Map.get(department, :color) || Map.get(department, :accent, "#49f28e")

  defp encode_city(city) do
    %{
      id: city.id,
      name: city.name,
      region: city.region,
      color: Map.get(city, :color, "#49f28e"),
      status: city |> Map.get(:status, :online) |> to_string()
    }
    |> Jason.encode!()
  end

  defp encode_departments(departments) do
    departments
    |> Enum.map(fn department ->
      %{
        id: department.id,
        name: department.name,
        color: department_color(department),
        col: Map.get(department, :col),
        row: Map.get(department, :row),
        lemmings:
          Enum.map(Map.get(department, :lemmings, []), fn lemming ->
            %{
              id: lemming.id,
              name: lemming.name,
              status: lemming |> Map.get(:status, :idle) |> to_string()
            }
          end)
      }
    end)
    |> Jason.encode!()
  end

  defp encode_labels do
    %{
      department: dgettext("world", ".tooltip_department"),
      lemmings: dgettext("world", ".metric_lemmings"),
      running: dgettext("world", ".tooltip_running"),
      running_status: dgettext("lemmings", ".status_running"),
      idle_status: dgettext("lemmings", ".status_idle")
    }
    |> Jason.encode!()
  end
end
