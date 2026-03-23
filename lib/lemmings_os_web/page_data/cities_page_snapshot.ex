defmodule LemmingsOsWeb.PageData.CitiesPageSnapshot do
  @moduledoc """
  Operator-facing Cities page read model.

  The top-level city list is built from persisted City rows and derived
  liveness. The selected city surface exposes compact persisted Department
  cards only; Department detail ownership stays on the dedicated Departments
  page.
  """

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Helpers
  alias LemmingsOs.Gettext, as: AppGettext
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @type city_card :: %{
          id: String.t(),
          path: String.t(),
          name: String.t(),
          slug: String.t(),
          node_name: String.t(),
          host: String.t() | nil,
          distribution_port: integer() | nil,
          epmd_port: integer() | nil,
          status: String.t(),
          liveness: String.t(),
          liveness_label: String.t(),
          liveness_tone: String.t(),
          last_seen_at: DateTime.t() | nil,
          last_seen_at_label: String.t(),
          selected?: boolean()
        }

  @type city_detail :: map()
  @type department_card :: %{
          id: String.t(),
          path: String.t(),
          name: String.t(),
          status: String.t(),
          status_label: String.t(),
          tags: [String.t()],
          notes_preview: String.t() | nil
        }

  @type t :: %__MODULE__{
          world: %{
            id: String.t(),
            slug: String.t(),
            name: String.t(),
            status: String.t(),
            status_label: String.t(),
            city_count: non_neg_integer()
          },
          cities: [city_card()],
          selected_city: city_detail() | nil,
          empty?: boolean()
        }

  defstruct [:world, :cities, :selected_city, :empty?]

  @doc """
  Builds the Cities page snapshot from persisted world and city data.

  Supported options:

  - `:world` - direct `%World{}` to snapshot
  - `:world_id` - persisted world ID used when a direct struct is not provided
  - `:city_id` - selected city ID from the query string
  - `:now` - explicit reference time for deterministic liveness calculations
  - `:freshness_threshold_seconds` - override for heartbeat freshness
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, :not_found}
  def build(opts \\ []) when is_list(opts) do
    with {:ok, world} <- fetch_world(opts) do
      {:ok, build_snapshot(world, opts)}
    end
  end

  defp build_snapshot(%World{} = world, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now() |> DateTime.truncate(:second))
    freshness_threshold_seconds = freshness_threshold_seconds(opts)

    cities = Cities.list_cities(world, preload: [:world])
    selected_city = select_city(cities, Keyword.get(opts, :city_id))

    %__MODULE__{
      world: world_snapshot(world, cities),
      cities: Enum.map(cities, &city_card(&1, selected_city, now, freshness_threshold_seconds)),
      selected_city:
        if(selected_city,
          do: selected_city_snapshot(selected_city, now, freshness_threshold_seconds),
          else: nil
        ),
      empty?: cities == []
    }
  end

  defp fetch_world(opts), do: fetch_world(Keyword.get(opts, :world), opts)
  defp fetch_world(%World{} = world, _opts), do: {:ok, world}

  defp fetch_world(nil, opts),
    do: fetch_world_by_id(Keyword.get(opts, :world_id))

  defp fetch_world_by_id(world_id) when is_binary(world_id),
    do: Worlds.fetch_world(world_id)

  defp fetch_world_by_id(_world_id), do: Worlds.get_default_world()

  defp world_snapshot(%World{} = world, cities) do
    %{
      id: world.id,
      slug: world.slug,
      name: world.name,
      status: world.status,
      status_label: World.translate_status(world),
      city_count: length(cities)
    }
  end

  defp select_city([], _city_id), do: nil

  defp select_city(cities, nil), do: List.first(cities)

  defp select_city(cities, city_id) when is_binary(city_id) do
    Enum.find(cities, &(&1.id == city_id)) || List.first(cities)
  end

  defp select_city(cities, _city_id), do: List.first(cities)

  defp city_card(%City{} = city, selected_city, now, freshness_threshold_seconds) do
    selected? = not is_nil(selected_city) and selected_city.id == city.id

    base_city_snapshot(city, now, freshness_threshold_seconds)
    |> Map.put(:selected?, selected?)
  end

  defp selected_city_snapshot(%City{} = city, now, freshness_threshold_seconds) do
    departments = city_departments_snapshot(city)

    city
    |> base_city_snapshot(now, freshness_threshold_seconds)
    |> Map.put(:effective_config, Resolver.resolve(city))
    |> Map.put(:departments, departments)
    |> Map.put(:department_count, length(departments))
    |> Map.put(:departments_path, "/departments?city=#{city.id}")
  end

  defp base_city_snapshot(%City{} = city, now, freshness_threshold_seconds) do
    liveness = City.liveness(city, now, freshness_threshold_seconds)

    %{
      id: city.id,
      path: "/cities?city=#{city.id}",
      name: city.name,
      slug: city.slug,
      node_name: city.node_name,
      host: city.host,
      distribution_port: city.distribution_port,
      epmd_port: city.epmd_port,
      status: city.status,
      liveness: liveness,
      liveness_label: liveness_label(liveness),
      liveness_tone: liveness_tone(liveness),
      last_seen_at: city.last_seen_at,
      last_seen_at_label: Helpers.format_datetime(city.last_seen_at),
      selected?: false
    }
  end

  defp city_departments_snapshot(%City{} = city) do
    city.world_id
    |> Departments.list_departments(city.id)
    |> Enum.map(&department_card/1)
  end

  defp department_card(%Department{} = department) do
    %{
      id: department.id,
      path: "/departments?city=#{department.city_id}&dept=#{department.id}",
      name: department.name,
      status: department.status,
      status_label: Department.translate_status(department),
      tags: department.tags || [],
      notes_preview: truncate_notes(department.notes)
    }
  end

  defp truncate_notes(nil), do: nil
  defp truncate_notes(""), do: nil

  defp truncate_notes(notes) when is_binary(notes) do
    Helpers.truncate_value(notes, max_length: 96, unavailable_label: nil)
  end

  defp freshness_threshold_seconds(opts) do
    Keyword.get(opts, :freshness_threshold_seconds) ||
      Application.get_env(:lemmings_os, :runtime_city_heartbeat, [])
      |> Keyword.get(:freshness_threshold_seconds, 90)
  end

  defp liveness_tone("alive"), do: "success"
  defp liveness_tone("stale"), do: "warning"
  defp liveness_tone("unknown"), do: "default"
  defp liveness_tone(_status), do: "default"

  defp liveness_label("alive"),
    do: Gettext.dgettext(AppGettext, "default", ".city_liveness_alive")

  defp liveness_label("stale"),
    do: Gettext.dgettext(AppGettext, "default", ".city_liveness_stale")

  defp liveness_label("unknown"),
    do: Gettext.dgettext(AppGettext, "default", ".city_liveness_unknown")

  defp liveness_label(_status),
    do: Gettext.dgettext(AppGettext, "default", ".city_liveness_unknown")
end
