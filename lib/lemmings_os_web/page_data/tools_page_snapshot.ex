defmodule LemmingsOsWeb.PageData.ToolsPageSnapshot do
  @moduledoc """
  Runtime-first read model for the Tools page.

  This snapshot prioritizes runtime capability facts and keeps policy
  reconciliation explicitly partial or deferred.
  """

  alias LemmingsOs.Worlds.World

  @type issue :: %{
          severity: String.t(),
          code: String.t(),
          summary: String.t(),
          detail: String.t(),
          source: String.t(),
          path: String.t() | nil,
          action_hint: String.t() | nil
        }

  @type tool_snapshot :: %{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          icon: String.t() | nil,
          category: String.t() | nil,
          risk: String.t() | nil,
          usage_count: integer() | nil,
          runtime: %{
            status: String.t(),
            status_label: String.t(),
            availability: String.t()
          },
          policy: %{
            status: String.t(),
            status_label: String.t(),
            mode: String.t()
          }
        }

  @type t :: %__MODULE__{
          status: String.t(),
          status_label: String.t(),
          runtime: map(),
          policy: map(),
          tools: [tool_snapshot()],
          issues: [issue()]
        }

  defstruct [:status, :status_label, :runtime, :policy, :tools, :issues]

  @doc """
  Builds the Tools page snapshot.

  Supported options:
  - `:runtime_fetcher` - module implementing `LemmingsOs.Tools.RuntimeFetcherBehaviour`
  - `:policy_fetcher` - module implementing `LemmingsOs.Tools.PolicyFetcherBehaviour`
  """
  @spec build(keyword()) :: t()
  def build(opts \\ []) do
    runtime_result =
      runtime_snapshot(
        Keyword.get(opts, :runtime_fetcher, LemmingsOs.Tools.DefaultRuntimeFetcher)
      )

    policy_result =
      policy_snapshot(
        runtime_result,
        Keyword.get(opts, :policy_fetcher, LemmingsOs.Tools.DefaultPolicyFetcher)
      )

    tools =
      runtime_result.tools
      |> Enum.map(&tool_snapshot(&1, policy_result.tool_statuses))

    issues =
      runtime_result.issues ++
        policy_result.issues

    status = aggregate_page_status(runtime_result.status, policy_result.status)

    %__MODULE__{
      status: status,
      status_label: status_label(status),
      runtime: Map.take(runtime_result, [:status, :status_label, :tool_count, :issues, :source]),
      policy: Map.take(policy_result, [:status, :status_label, :mode, :issues]),
      tools: tools,
      issues: issues
    }
  end

  defp runtime_snapshot(runtime_fetcher) do
    case runtime_fetcher.fetch() do
      {:ok, tools} when is_list(tools) ->
        %{
          status: "ok",
          status_label: status_label("ok"),
          tool_count: length(tools),
          tools: Enum.map(tools, &normalize_runtime_tool/1),
          issues: [],
          source: "runtime"
        }

      {:error, reason} ->
        %{
          status: runtime_error_status(reason),
          status_label: status_label(runtime_error_status(reason)),
          tool_count: 0,
          tools: [],
          issues: [runtime_issue(reason)],
          source: "runtime"
        }
    end
  end

  defp policy_snapshot(%{status: runtime_status} = runtime_result, _policy_fetcher)
       when runtime_status in ["unavailable", "invalid"] do
    %{
      status: "unknown",
      status_label: status_label("unknown"),
      mode: "deferred",
      tool_statuses: %{},
      issues: [],
      runtime_tool_count: runtime_result.tool_count
    }
  end

  defp policy_snapshot(runtime_result, policy_fetcher) do
    case policy_fetcher.fetch() do
      :deferred ->
        %{
          status: "unknown",
          status_label: status_label("unknown"),
          mode: "deferred",
          tool_statuses: %{},
          issues: [],
          runtime_tool_count: runtime_result.tool_count
        }

      {:ok, tool_statuses} when is_map(tool_statuses) ->
        missing_policy_count =
          runtime_result.tools
          |> Enum.reject(&Map.has_key?(tool_statuses, &1.id))
          |> length()

        status =
          cond do
            runtime_result.tools == [] ->
              "ok"

            missing_policy_count == 0 and
                Enum.all?(tool_statuses, fn {_id, state} -> state == "ok" end) ->
              "ok"

            true ->
              "degraded"
          end

        %{
          status: status,
          status_label: status_label(status),
          mode: if(status == "ok", do: "known", else: "partial"),
          tool_statuses: tool_statuses,
          issues: policy_issues(missing_policy_count),
          runtime_tool_count: runtime_result.tool_count
        }

      {:error, reason} ->
        %{
          status: "degraded",
          status_label: status_label("degraded"),
          mode: "partial",
          tool_statuses: %{},
          issues: [policy_issue(reason)],
          runtime_tool_count: runtime_result.tool_count
        }
    end
  end

  defp tool_snapshot(tool, policy_statuses) do
    policy_status = Map.get(policy_statuses, tool.id, "unknown")

    %{
      id: tool.id,
      name: tool.name,
      description: tool.description,
      icon: tool.icon,
      category: tool.category,
      risk: tool.risk,
      usage_count: tool.usage_count,
      runtime: %{
        status: "ok",
        status_label: status_label("ok"),
        availability: "registered"
      },
      policy: %{
        status: policy_status,
        status_label: status_label(policy_status),
        mode: if(policy_status == "unknown", do: "deferred", else: "known")
      }
    }
  end

  defp normalize_runtime_tool(tool) when is_map(tool) do
    %{
      id: map_value(tool, :id),
      name: map_value(tool, :name),
      description: map_value(tool, :description),
      icon: map_value(tool, :icon),
      category: map_value(tool, :category),
      risk: map_value(tool, :risk),
      usage_count: map_value(tool, :usage_count) || map_value(tool, :agents)
    }
  end

  defp aggregate_page_status(runtime_status, _policy_status)
       when runtime_status in ["unavailable", "invalid", "unknown"],
       do: runtime_status

  defp aggregate_page_status("ok", policy_status) when policy_status in ["degraded", "invalid"],
    do: policy_status

  defp aggregate_page_status(runtime_status, _policy_status), do: runtime_status

  defp runtime_error_status(:not_implemented), do: "unknown"
  defp runtime_error_status(:timeout), do: "unavailable"
  defp runtime_error_status(_reason), do: "unavailable"

  defp runtime_issue(reason) do
    %{
      severity: "warning",
      code: "tools_runtime_source_unavailable",
      summary: "Tools runtime source unavailable",
      detail: "Unable to obtain runtime tool capability data: #{inspect(reason)}",
      source: "runtime_tools",
      path: nil,
      action_hint: "Verify the runtime capability registry before relying on tool availability."
    }
  end

  defp policy_issues(0), do: []

  defp policy_issues(missing_policy_count) do
    [
      %{
        severity: "info",
        code: "tools_policy_partial",
        summary: "Tools policy reconciliation is partial",
        detail: "#{missing_policy_count} runtime tool entries have no policy reconciliation yet.",
        source: "tool_policy",
        path: nil,
        action_hint:
          "Treat policy state as partial until the hierarchy policy engine is implemented."
      }
    ]
  end

  defp policy_issue(reason) do
    %{
      severity: "warning",
      code: "tools_policy_unavailable",
      summary: "Tools policy state unavailable",
      detail: "Unable to reconcile runtime tools with policy state: #{inspect(reason)}",
      source: "tool_policy",
      path: nil,
      action_hint:
        "Use runtime capability data as primary until policy reconciliation is available."
    }
  end

  defp map_value(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp status_label(status), do: World.translate_status(status)
end
