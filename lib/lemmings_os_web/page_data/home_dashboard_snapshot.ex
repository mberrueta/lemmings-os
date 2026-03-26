defmodule LemmingsOsWeb.PageData.HomeDashboardSnapshot do
  @moduledoc """
  Trustworthy read model for the Home dashboard.

  This snapshot prefers fewer reliable cards over broader fake operational
  coverage. It surfaces persisted World identity, bootstrap health, runtime
  health, tool capability state, and real city counts only when those sources
  are real or honestly unavailable.
  """

  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.Cities
  alias LemmingsOs.Departments
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.PageData.ToolsPageSnapshot
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  @type alert :: map()

  @type card :: %{
          id: String.t(),
          status: String.t(),
          status_label: String.t(),
          source: String.t(),
          meta: map()
        }

  @type t :: %__MODULE__{
          status: String.t(),
          status_label: String.t(),
          world: %{
            available?: boolean(),
            name: String.t() | nil,
            slug: String.t() | nil,
            status: String.t(),
            status_label: String.t()
          },
          cards: [card()],
          alerts: [alert()],
          actions: [%{id: String.t(), to: String.t()}]
        }

  defstruct [:status, :status_label, :world, :cards, :alerts, :actions]

  @doc """
  Builds the Home dashboard snapshot.

  Supported options:

  - `:world_snapshot` - prebuilt `WorldPageSnapshot` for direct injection
  - `:world_snapshot_builder` - zero-arity function returning `{:ok, snapshot}` or `{:error, :not_found}`
  - `:tools_snapshot` - prebuilt `ToolsPageSnapshot` for direct injection
  - `:tools_snapshot_builder` - zero-arity function returning a `ToolsPageSnapshot`

  ## Examples

      iex> snapshot =
      ...>   LemmingsOsWeb.PageData.HomeDashboardSnapshot.build(
      ...>     world_snapshot_builder: fn -> {:error, :not_found} end
      ...>   )
      iex> {snapshot.status, snapshot.world.available?, Enum.map(snapshot.cards, & &1.id)}
      {"unavailable", false, ["world_identity"]}
  """
  @spec build(keyword()) :: t()
  def build(opts \\ []) when is_list(opts) do
    world_snapshot_result = resolve_world_snapshot(Keyword.get(opts, :world_snapshot), opts)
    tools_snapshot = resolve_tools_snapshot(world_snapshot_result, opts)
    cards = build_cards(world_snapshot_result, tools_snapshot)
    alerts = build_alerts(world_snapshot_result, tools_snapshot)
    status = aggregate_status(cards)

    %__MODULE__{
      status: status,
      status_label: status_label(status),
      world: world_section(world_snapshot_result),
      cards: cards,
      alerts: alerts,
      actions: actions()
    }
  end

  @doc false
  def build_topology_card_meta(world_id) when is_binary(world_id) do
    case Ecto.UUID.cast(world_id) do
      {:ok, valid_id} ->
        world = %World{id: valid_id}

        city_count =
          Cities.list_cities(world)
          |> length()

        %{department_count: department_count, active_department_count: active_department_count} =
          Departments.topology_summary(world)

        %{lemming_count: lemming_count, active_lemming_count: active_lemming_count} =
          Lemmings.topology_summary(%World{id: valid_id})

        %{
          city_count: city_count,
          department_count: department_count,
          active_department_count: active_department_count,
          lemming_count: lemming_count,
          active_lemming_count: active_lemming_count
        }

      :error ->
        %{
          city_count: 0,
          department_count: 0,
          active_department_count: 0,
          lemming_count: 0,
          active_lemming_count: 0
        }
    end
  end

  defp resolve_world_snapshot(snapshot, _opts) when not is_nil(snapshot), do: {:ok, snapshot}

  defp resolve_world_snapshot(nil, opts) do
    opts
    |> Keyword.get(:world_snapshot_builder, fn -> WorldPageSnapshot.build() end)
    |> then(& &1.())
  end

  defp resolve_tools_snapshot({:ok, _world_snapshot}, opts),
    do: resolve_tools_snapshot(Keyword.get(opts, :tools_snapshot), opts)

  defp resolve_tools_snapshot({:error, :not_found}, _opts), do: nil

  defp resolve_tools_snapshot(%ToolsPageSnapshot{} = snapshot, _opts), do: snapshot

  defp resolve_tools_snapshot(nil, opts) do
    opts
    |> Keyword.get(:tools_snapshot_builder, fn -> ToolsPageSnapshot.build() end)
    |> then(& &1.())
  end

  defp world_section({:ok, snapshot}) do
    %{
      available?: true,
      name: snapshot.world.name,
      slug: snapshot.world.slug,
      status: snapshot.world.status,
      status_label: snapshot.world.status_label
    }
  end

  defp world_section({:error, :not_found}) do
    %{
      available?: false,
      name: nil,
      slug: nil,
      status: "unavailable",
      status_label: status_label("unavailable")
    }
  end

  defp build_cards({:error, :not_found}, _tools_snapshot) do
    [
      %{
        id: "world_identity",
        status: "unavailable",
        status_label: status_label("unavailable"),
        source: "persisted_world",
        meta: %{name: nil, slug: nil}
      }
    ]
  end

  defp build_cards({:ok, world_snapshot}, tools_snapshot) do
    [
      world_identity_card(world_snapshot),
      bootstrap_health_card(world_snapshot),
      runtime_health_card(world_snapshot),
      tools_health_card(tools_snapshot),
      topology_summary_card(world_snapshot)
    ]
  end

  defp world_identity_card(world_snapshot) do
    %{
      id: "world_identity",
      status: world_snapshot.world.status,
      status_label: world_snapshot.world.status_label,
      source: "persisted_world",
      meta: %{
        name: world_snapshot.world.name,
        slug: world_snapshot.world.slug
      }
    }
  end

  defp bootstrap_health_card(world_snapshot) do
    %{
      id: "bootstrap_health",
      status: world_snapshot.bootstrap.status,
      status_label: world_snapshot.bootstrap.status_label,
      source: "bootstrap_config",
      meta: %{
        path: world_snapshot.bootstrap.path,
        issue_count: length(world_snapshot.bootstrap.issues)
      }
    }
  end

  defp runtime_health_card(world_snapshot) do
    %{
      id: "runtime_health",
      status: world_snapshot.runtime.status,
      status_label: world_snapshot.runtime.status_label,
      source: "runtime_checks",
      meta: runtime_breakdown(world_snapshot.runtime)
    }
  end

  defp tools_health_card(%ToolsPageSnapshot{} = tools_snapshot) do
    %{
      id: "tools_health",
      status: tools_snapshot.status,
      status_label: tools_snapshot.status_label,
      source: "tools_snapshot",
      meta: %{
        tool_count: tools_snapshot.runtime.tool_count,
        issue_count: length(tools_snapshot.issues),
        policy_mode: tools_snapshot.policy.mode,
        runtime_status: tools_snapshot.runtime.status,
        policy_status: tools_snapshot.policy.status
      }
    }
  end

  defp topology_summary_card(world_snapshot) do
    meta = build_topology_card_meta(world_snapshot.world.id)

    %{
      id: "topology_summary",
      status: topology_summary_status(meta),
      status_label: topology_summary_status_label(meta),
      source: "persisted_topology",
      meta: meta
    }
  end

  defp topology_summary_status(%{city_count: 0, department_count: 0}), do: "unknown"
  defp topology_summary_status(_meta), do: "ok"

  defp topology_summary_status_label(%{city_count: 0, department_count: 0}),
    do: status_label("unknown")

  defp topology_summary_status_label(_meta), do: status_label("ok")

  defp build_alerts({:error, :not_found}, _tools_snapshot) do
    [
      %{
        severity: "error",
        code: "home_world_unavailable",
        summary: dgettext("layout", ".home_world_unavailable_summary"),
        detail: dgettext("layout", ".home_world_unavailable_detail"),
        source: "persisted_world",
        path: nil,
        action_hint: dgettext("layout", ".home_world_unavailable_action")
      }
    ]
  end

  defp build_alerts({:ok, world_snapshot}, %ToolsPageSnapshot{} = tools_snapshot) do
    world_snapshot.bootstrap.issues ++ tools_snapshot.issues
  end

  defp runtime_breakdown(runtime_snapshot) do
    counts =
      Enum.reduce(runtime_snapshot.checks, status_counts(), fn check, acc ->
        Map.update!(acc, check.status, &(&1 + 1))
      end)

    Map.merge(counts, %{
      check_count: length(runtime_snapshot.checks),
      deferred_sources: runtime_snapshot.deferred_sources
    })
  end

  defp status_counts do
    %{"ok" => 0, "degraded" => 0, "unavailable" => 0, "invalid" => 0, "unknown" => 0}
  end

  defp aggregate_status(cards) do
    cards
    |> Enum.map(& &1.status)
    |> Enum.reject(&(&1 == "unknown"))
    |> aggregate_known_statuses()
  end

  defp aggregate_known_statuses([]), do: "unknown"

  defp aggregate_known_statuses(statuses) do
    cond do
      Enum.all?(statuses, &(&1 == "ok")) -> "ok"
      Enum.all?(statuses, &(&1 == "unavailable")) -> "unavailable"
      "invalid" in statuses -> "invalid"
      "degraded" in statuses -> "degraded"
      "unavailable" in statuses -> "degraded"
      true -> "unknown"
    end
  end

  defp actions do
    [
      %{id: "world", to: "/world"},
      %{id: "tools", to: "/tools"},
      %{id: "logs", to: "/logs"},
      %{id: "settings", to: "/settings"}
    ]
  end

  defp status_label(status), do: World.translate_status(status)
end
