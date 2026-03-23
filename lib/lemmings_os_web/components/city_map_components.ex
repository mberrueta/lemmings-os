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
    <div
      class={["inline-flex flex-col items-center gap-1.5", @class]}
      style={"--dept-accent: #{department_color(@department)};"}
    >
      <svg
        width={@size}
        height={@size}
        viewBox="0 0 50 55"
        xmlns="http://www.w3.org/2000/svg"
        class="block image-pixelated"
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

      <div :if={@show_label} class="flex flex-col items-center gap-0.5">
        <span
          class="font-mono text-[11px] uppercase tracking-wider"
          style={"color: #{department_color(@department)};"}
        >
          {@department.name}
        </span>
        <small class="font-mono text-[9px] uppercase tracking-widest text-zinc-500">
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
      class={[
        "relative w-full max-w-6xl mx-auto border-2 border-zinc-800 overflow-hidden bg-zinc-950/95",
        @class
      ]}
      phx-hook="CityMapHook"
      phx-update="ignore"
      tabindex="0"
      aria-label={dgettext("world", ".aria_city_map", name: @city.name)}
      data-city={encode_city(@city)}
      data-departments={encode_departments(@departments)}
      data-labels={encode_labels()}
    >
      <canvas id={"#{@id}-canvas"} class="block w-full h-auto image-pixelated"></canvas>

      <div class="absolute top-0 left-0 right-0 p-3 flex justify-between items-center gap-3 bg-gradient-to-b from-zinc-950/90 to-transparent pointer-events-none z-10">
        <span class="text-emerald-400 font-mono text-[11px] uppercase tracking-wider">
          {@city.name} <span class="text-zinc-500">· {@city.region}</span>
        </span>
        <span class="flex flex-wrap gap-2 justify-end font-mono text-[11px]">
          <span class="text-zinc-500 uppercase tracking-widest">
            {dgettext("world", ".metric_departments")}
          </span>
          <span class="text-emerald-400 mr-2">{length(@departments)}</span>
          <span class="text-zinc-500 uppercase tracking-widest">
            {dgettext("world", ".metric_lemmings")}
          </span>
          <span class="text-emerald-400 mr-2">{@total_lemmings}</span>
          <span class="text-zinc-500 uppercase tracking-widest">
            {dgettext("world", ".metric_status")}
          </span>
          <.status kind={:city} value={@city.status} class="text-[10px]" />
        </span>
      </div>

      <div class="absolute bottom-0 left-0 right-0 p-2 bg-gradient-to-t from-zinc-950/90 to-transparent pointer-events-none z-10 text-zinc-600 font-mono text-[9px] uppercase tracking-widest text-center">
        {dgettext("world", ".map_hint_department")}
      </div>
      <div
        id={"#{@id}-tooltip"}
        class="absolute bg-zinc-950/95 border border-emerald-400/40 p-2.5 pointer-events-none z-20 font-mono text-[10px] text-emerald-400 uppercase tracking-wider leading-relaxed shadow-2xl"
        hidden
      >
      </div>
    </div>
    """
  end

  defp count_lemmings(departments) do
    Enum.reduce(departments, 0, fn department, count ->
      count + length(Map.get(department, :lemmings, []))
    end)
  end

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
