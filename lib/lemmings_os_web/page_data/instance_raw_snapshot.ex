defmodule LemmingsOsWeb.PageData.InstanceRawSnapshot do
  @moduledoc """
  Shared read model for the instance raw-context surface.

  This snapshot reconstructs the same operator-facing interaction timeline used
  by the raw-context LiveView and can also render a Markdown form for CLI and
  agent tooling.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @max_live_steps 40
  @lemming_call_preloads [:caller_lemming, :callee_lemming]

  @type timeline_entry :: %{
          id: String.t(),
          kind: atom(),
          title: String.t(),
          summary: String.t() | nil,
          body: String.t() | nil,
          timestamp: DateTime.t() | nil,
          meta: [String.t()],
          status: String.t() | nil,
          raw_sections: [map()]
        }

  @type t :: %__MODULE__{
          world: World.t(),
          instance: LemmingInstance.t(),
          runtime_state: map(),
          model_steps: [map()],
          lemming_calls: [LemmingCall.t()],
          delegation_state: map() | nil,
          interaction_timeline: [timeline_entry()],
          interaction_timeline_source: atom() | nil,
          model_request: map(),
          model_request_source: atom() | nil
        }

  defstruct [
    :world,
    :instance,
    :runtime_state,
    :model_steps,
    :lemming_calls,
    :delegation_state,
    :interaction_timeline,
    :interaction_timeline_source,
    :model_request,
    :model_request_source
  ]

  @doc """
  Builds the raw-context snapshot for an instance.

  Supported options:
  - `:instance_id` - required instance id
  - `:world` - optional `%World{}` scope
  - `:world_id` - optional world id when `%World{}` is not provided
  """
  @spec build(keyword()) :: {:ok, t()} | {:error, :not_found}
  def build(opts) when is_list(opts) do
    with {:ok, instance_id} <- fetch_instance_id(opts),
         {:ok, world} <- fetch_world(opts, instance_id),
         {:ok, instance} <-
           LemmingInstances.get_instance(instance_id, world: world, preload: [:lemming]) do
      runtime_state = load_runtime_state(instance, world)
      messages = load_messages(instance, world)
      tool_executions = load_tool_executions(instance, world)
      lemming_calls = load_lemming_calls(instance, messages)
      model_steps = load_model_steps(instance)

      {interaction_timeline, interaction_timeline_source} =
        build_interaction_timeline(model_steps, messages, tool_executions, lemming_calls)

      {model_request, model_request_source} =
        load_model_request(instance, runtime_state, model_steps, messages)

      delegation_state = build_delegation_state(runtime_state, instance, lemming_calls)

      {:ok,
       %__MODULE__{
         world: world,
         instance: instance,
         runtime_state: runtime_state,
         model_steps: model_steps,
         lemming_calls: lemming_calls,
         delegation_state: delegation_state,
         interaction_timeline: interaction_timeline,
         interaction_timeline_source: interaction_timeline_source,
         model_request: model_request,
         model_request_source: model_request_source
       }}
    else
      _other -> {:error, :not_found}
    end
  end

  @doc """
  Renders the snapshot as Markdown with the same operator-facing content shown
  by the raw-context page.
  """
  @spec to_markdown(t()) :: String.t()
  def to_markdown(%__MODULE__{} = snapshot) do
    [
      "# Instance Raw Context",
      execution_summary_markdown(snapshot),
      trace_provenance_markdown(snapshot),
      timeline_markdown(snapshot),
      delegation_state_markdown(snapshot),
      model_input_summary_markdown(snapshot),
      runtime_state_summary_markdown(snapshot),
      diagnostics_markdown(snapshot),
      raw_details_markdown(snapshot)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp execution_summary_markdown(snapshot) do
    bullets = [
      "Instance: #{snapshot.instance.id}",
      "World: #{snapshot.world.id}",
      "Lemming: #{snapshot.instance.lemming_id}",
      "Outcome: #{outcome_label(snapshot)}",
      "Trace source: #{trace_class_label(snapshot)}",
      "Final action: #{final_action_label(snapshot)}",
      "Files created: #{format_list(files_created(snapshot))}",
      "Tools used: #{format_list(tools_used(snapshot))}",
      "Delegations used: #{format_list(delegations_used(snapshot))}",
      "Last model/provider: #{last_model_provider_label(snapshot)}",
      "Likely issue: #{likely_issue_label(snapshot)}"
    ]

    ["## Execution Summary", bullet_list(bullets)]
    |> Enum.join("\n\n")
  end

  defp format_list(values), do: list_label(values)

  defp trace_provenance_markdown(snapshot) do
    bullets = [
      "Primary timeline source: #{interaction_timeline_source_copy(snapshot.interaction_timeline_source)}",
      "Model input source: #{model_request_source_copy(snapshot.model_request_source)}",
      "Runtime state source: #{runtime_state_source_label(snapshot)}",
      "Transcript rows: persisted and readable",
      "Tool rows: persisted tool executions",
      "Raw payloads: available below"
    ]

    [
      "## Why this trace is trustworthy / partial / reconstructed",
      bullet_list(bullets)
    ]
    |> Enum.join("\n\n")
  end

  defp timeline_markdown(snapshot) do
    body =
      case snapshot.interaction_timeline do
        [] ->
          "No interaction trace is available yet."

        entries ->
          entries
          |> Enum.map_join("\n\n", &timeline_entry_summary_markdown/1)
      end

    warning = persisted_history_warning(snapshot.interaction_timeline_source)

    [
      "## Timeline",
      "Source: #{interaction_timeline_source_copy(snapshot.interaction_timeline_source)}",
      warning,
      body
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp timeline_entry_summary_markdown(entry) do
    [
      "### #{entry.title}",
      entry_meta_markdown(entry),
      entry_preview_markdown(entry)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp entry_meta_markdown(entry) do
    lines =
      [
        entry.summary && "Summary: #{humanize_text(entry.summary)}",
        entry.status && "Status: #{entry.status}",
        timeline_timestamp(entry.timestamp) && "Time: #{timeline_timestamp(entry.timestamp)}",
        entry.meta != [] && "Meta: #{Enum.map_join(entry.meta, ", ", &"`#{&1}`")}"
      ]
      |> Enum.reject(&nil_or_false?/1)

    case lines do
      [] -> nil
      _lines -> bullet_list(lines)
    end
  end

  defp entry_preview_markdown(%{body: body} = entry) do
    preview = timeline_body_text(body)

    cond do
      blank?(preview) ->
        nil

      entry.kind in [:llm_request, :llm_response, :tool_call, :tool_result, :final_reply] ->
        ["Preview:", quoted_block(preview)]
        |> Enum.join("\n\n")

      true ->
        ["Preview:", quoted_block(preview)]
        |> Enum.join("\n\n")
    end
  end

  defp timeline_body_text(nil), do: nil

  defp timeline_body_text(text) when is_binary(text) do
    text
    |> humanize_text()
    |> String.trim()
  end

  defp timeline_body_text(text), do: inspect(text)

  defp model_input_summary_markdown(snapshot) do
    request = snapshot.model_request || %{}
    messages = request_messages(request)
    system_prompt = extract_system_prompt(messages)
    current_request = latest_non_system_message(messages)

    bullets = [
      "Source: #{model_request_source_copy(snapshot.model_request_source)}",
      "Provider: #{provider_value(request) || "unknown"}",
      "Model: #{model_value(request) || "unknown"}",
      "Messages: #{length(messages)} total",
      "Current request: #{preview_or_none(current_request)}"
    ]

    [
      "## Model Input Summary",
      bullet_list(bullets),
      "System prompt preview:",
      system_prompt_preview_block(system_prompt),
      "Config snapshot summary:",
      config_snapshot_summary_block(snapshot.instance.config_snapshot)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp delegation_state_markdown(snapshot) do
    case delegation_state(snapshot) do
      %{} = state ->
        bullets = [
          "Latest call id: #{state.call_id}",
          "Child instance: #{state.child_instance}",
          "Status: #{state.status}",
          "Recovery status: #{state.recovery_status}",
          "Result summary: #{state.result_summary}",
          "Error summary: #{state.error_summary}",
          "Manager received callback context: #{state.callback_context_received}",
          "Manager waiting state: #{state.waiting_state}"
        ]

        [
          "## Delegation State",
          bullet_list(bullets)
        ]
        |> Enum.join("\n\n")

      nil ->
        nil
    end
  end

  defp runtime_state_summary_markdown(snapshot) do
    runtime_state = snapshot.runtime_state || %{}

    bullets = [
      "Source: #{runtime_state_source_label(snapshot)}",
      "Status: #{state_status_label(runtime_state, snapshot.instance)}",
      "Queue depth: #{queue_depth_label(runtime_state)}",
      "Retries: #{retry_state_label(runtime_state)}",
      "Current item: #{current_item_label(runtime_state)}",
      "Last error: #{last_error_label(runtime_state)}",
      "Last activity: #{timestamp_label(Map.get(runtime_state, :last_activity_at))}",
      "Context messages: #{message_count_label(runtime_state)}"
    ]

    ["## Runtime State Summary", bullet_list(bullets)]
    |> Enum.join("\n\n")
  end

  defp timestamp_label(nil), do: "none"
  defp timestamp_label(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")
  defp timestamp_label(value), do: inspect(value)

  defp diagnostics_markdown(snapshot) do
    bullets = diagnostic_notes(snapshot)

    ["## Why it likely succeeded / failed", bullet_list(bullets)]
    |> Enum.join("\n\n")
  end

  defp raw_details_markdown(snapshot) do
    raw_sections =
      [
        {"Raw Provider Request", snapshot.model_request, :json},
        {"Raw Context Messages", Map.get(snapshot.runtime_state, :context_messages), :json},
        {"Raw Current Item", Map.get(snapshot.runtime_state, :current_item), :json},
        {"Raw Runtime State", snapshot.runtime_state, :json},
        {"Raw Config Snapshot", snapshot.instance.config_snapshot, :json}
      ]
      |> Enum.flat_map(fn {title, payload, kind} ->
        raw_payload_markdown(title, payload, kind)
      end)

    timeline_raw_sections =
      snapshot.interaction_timeline
      |> Enum.flat_map(fn entry -> raw_timeline_entry_markdown(entry) end)

    all_raw_sections = raw_sections ++ timeline_raw_sections

    case all_raw_sections do
      [] ->
        nil

      sections ->
        [
          "## Raw Details",
          "Source: raw payloads from live executor memory and persisted rows.",
          Enum.join(sections, "\n\n")
        ]
        |> Enum.join("\n\n")
    end
  end

  defp raw_timeline_entry_markdown(%{raw_sections: raw_sections, title: title, summary: summary}) do
    case Enum.reject(raw_sections, &is_nil(&1.payload)) do
      [] ->
        []

      sections ->
        [
          ["### #{title}", summary && "Summary: #{humanize_text(summary)}"]
          |> Enum.reject(&blank?/1)
          |> Enum.join("\n\n"),
          Enum.map_join(sections, "\n\n", fn section ->
            [
              "#### #{section.label}",
              raw_payload_body(section.label, section.payload)
            ]
            |> Enum.join("\n\n")
          end)
        ]
    end
  end

  defp raw_payload_markdown(title, payload, :json) do
    if is_nil(payload) do
      []
    else
      [
        "### #{title}",
        raw_payload_body(title, payload)
      ]
    end
  end

  defp raw_payload_markdown(_title, _payload, _kind), do: []

  defp bullet_list(lines) when is_list(lines) do
    Enum.map_join(lines, "\n", &"- #{&1}")
  end

  defp quoted_block(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"> #{&1}")
  end

  defp preview_text(nil), do: nil

  defp preview_text(text) when is_binary(text) do
    text
    |> humanize_text()
    |> String.trim()
    |> String.split("\n")
    |> Enum.take(6)
    |> Enum.join("\n")
  end

  defp preview_text(text), do: inspect(text)

  defp humanize_text(nil), do: nil

  defp humanize_text(text) when is_binary(text) do
    text
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
  end

  defp humanize_text(text), do: inspect(text)

  defp preview_or_none(nil), do: "none"

  defp preview_or_none(text) do
    preview =
      text
      |> humanize_text()
      |> String.trim()

    if blank?(preview), do: "none", else: preview_text(preview)
  end

  defp system_prompt_preview_block(nil), do: "not available"

  defp system_prompt_preview_block(prompt) do
    prompt
    |> preview_text()
    |> case do
      nil -> "not available"
      preview -> quoted_block(preview)
    end
  end

  defp config_snapshot_summary_block(snapshot) when is_map(snapshot) do
    bullets = [
      "Profile: #{config_profile_label(snapshot)}",
      "Provider/model: #{config_provider_model_label(snapshot)}",
      "Allowed tools: #{config_allowed_tools_label(snapshot)}",
      "Delegation targets: #{config_delegation_targets_label(snapshot)}",
      "Idle TTL: #{config_idle_ttl_label(snapshot)}",
      "Retry limit: #{config_retry_limit_label(snapshot)}"
    ]

    bullet_list(bullets)
  end

  defp config_snapshot_summary_block(_snapshot), do: "Config snapshot unavailable."

  defp request_messages(nil), do: []

  defp request_messages(%{} = request) do
    case Map.get(request, "messages") || Map.get(request, :messages) do
      messages when is_list(messages) ->
        messages

      _other ->
        case Map.get(request, "request") || Map.get(request, :request) do
          %{} = nested -> Map.get(nested, "messages") || Map.get(nested, :messages) || []
          _other -> []
        end
    end
  end

  defp request_messages(_request), do: []

  defp latest_non_system_message(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(fn message ->
      role = Map.get(message, "role") || Map.get(message, :role)
      role != "system"
    end)
    |> case do
      %{"content" => content} -> content
      %{content: content} when is_binary(content) -> content
      _other -> nil
    end
  end

  defp latest_non_system_message(_messages), do: nil

  defp trace_class_label(snapshot) do
    cond do
      snapshot.interaction_timeline_source == :live_executor_trace -> "live"
      snapshot.model_request_source in [:runtime_state, :live_executor_trace] -> "reconstructed"
      snapshot.interaction_timeline_source == :persisted_history_only -> "persisted-only fallback"
      true -> "partial"
    end
  end

  defp outcome_label(snapshot) do
    status = state_status_label(snapshot.runtime_state, snapshot.instance)
    action = final_action_value(snapshot)

    cond do
      status in ["failed", "expired"] -> status
      status == "idle" and action == "reply" -> "completed"
      status == "idle" and action in ["tool_call", "lemming_call"] -> "partial"
      status in ["queued", "processing", "retrying"] -> "in_progress"
      true -> "unknown"
    end
  end

  defp final_action_label(snapshot) do
    final_action_value(snapshot) || "unknown"
  end

  defp final_action_value(snapshot) do
    final_action_from_model_steps(snapshot.model_steps) ||
      final_action_from_timeline(snapshot.interaction_timeline)
  end

  defp final_action_from_model_steps(model_steps)
       when is_list(model_steps) and model_steps != [] do
    case List.last(model_steps) do
      %{parsed_output: %{"action" => action}}
      when action in ["reply", "tool_call", "lemming_call"] ->
        action

      %{parsed_output: %{} = parsed_output} ->
        Map.get(parsed_output, "action")
        |> case do
          action when action in ["reply", "tool_call", "lemming_call"] -> action
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp final_action_from_model_steps(_model_steps), do: nil

  defp final_action_from_timeline(entries) when is_list(entries) and entries != [] do
    entries
    |> List.last()
    |> case do
      %{kind: :final_reply} ->
        "reply"

      %{kind: :tool_call} ->
        "tool_call"

      %{kind: :llm_response, summary: summary} when is_binary(summary) and summary != "" ->
        timeline_action_from_summary(summary)

      _other ->
        nil
    end
  end

  defp final_action_from_timeline(_entries), do: nil

  defp timeline_action_from_summary(summary) do
    cond do
      String.contains?(summary, "tool") -> "tool_call"
      String.contains?(summary, "lemming") -> "lemming_call"
      true -> "reply"
    end
  end

  defp files_created(snapshot) do
    snapshot.instance.id
    |> tool_executions_for_snapshot(snapshot)
    |> Enum.flat_map(&file_created_from_tool_execution/1)
    |> Enum.uniq()
  end

  defp tools_used(snapshot) do
    snapshot.instance.id
    |> tool_executions_for_snapshot(snapshot)
    |> Enum.map(& &1.tool_name)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp delegations_used(snapshot) do
    snapshot.model_steps
    |> Enum.flat_map(&delegation_from_model_step/1)
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp tool_executions_for_snapshot(_instance_id, %__MODULE__{} = snapshot) do
    snapshot.instance
    |> then(&LemmingTools.list_tool_executions(snapshot.world, &1))
  end

  defp file_created_from_tool_execution(
         %ToolExecution{tool_name: "fs.write_text_file"} = execution
       ) do
    path =
      execution.result
      |> map_value(:path)
      |> case do
        nil -> map_value(execution.args, :path)
        value -> value
      end

    case path do
      nil -> [tool_execution_summary_line(execution)]
      value -> [tool_execution_summary_line(execution, value)]
    end
  end

  defp file_created_from_tool_execution(_execution), do: []

  defp tool_execution_summary_line(
         %ToolExecution{tool_name: "fs.write_text_file", result: result},
         path
       ) do
    bytes = map_value(result, :bytes)

    case bytes do
      value when is_integer(value) -> "Wrote file #{path} (#{value} bytes)"
      _other -> "Wrote file #{path}"
    end
  end

  defp tool_execution_summary_line(%ToolExecution{} = execution, path) do
    "#{execution.tool_name} -> #{path}"
  end

  defp tool_execution_summary_line(%ToolExecution{summary: summary}) when is_binary(summary),
    do: summary

  defp tool_execution_summary_line(%ToolExecution{tool_name: tool_name}), do: tool_name

  defp delegation_from_model_step(%{parsed_output: %{"action" => "lemming_call"} = parsed_output}) do
    [
      parsed_output["target"],
      parsed_output["request"]
    ]
  end

  defp delegation_from_model_step(_model_step), do: []

  defp last_model_provider_label(snapshot) do
    "#{last_model_provider_name(snapshot)} / #{last_model_name(snapshot)}"
  end

  defp last_model_provider_name(snapshot) do
    snapshot.model_steps
    |> List.last()
    |> case do
      %{provider: provider} when is_binary(provider) and provider != "" -> provider
      _other -> provider_value(snapshot.model_request || %{}) || "unknown"
    end
  end

  defp last_model_name(snapshot) do
    snapshot.model_steps
    |> List.last()
    |> case do
      %{model: model} when is_binary(model) and model != "" -> model
      _other -> model_value(snapshot.model_request || %{}) || "unknown"
    end
  end

  defp likely_issue_label(snapshot) do
    cond do
      last_error_label(snapshot.runtime_state) =~ "invalid structured output" ->
        "prompt ambiguity / structured-output mismatch"

      tool_failure?(snapshot) ->
        "tool failure"

      delegation_stalled?(snapshot) ->
        "incomplete delegation or manager decision gap"

      final_action_label(snapshot) == "unknown" ->
        "runtime gap"

      trace_class_label(snapshot) == "persisted-only fallback" ->
        "trace reconstruction / partial coverage"

      true ->
        "none"
    end
  end

  defp diagnostic_notes(snapshot) do
    [
      diagnostic_issue_note(snapshot),
      diagnostic_recovery_note(snapshot),
      diagnostic_delegation_note(snapshot),
      diagnostic_trace_note(snapshot)
    ]
    |> Enum.reject(&blank?/1)
  end

  defp diagnostic_issue_note(snapshot) do
    cond do
      last_error_label(snapshot.runtime_state) =~ "invalid structured output" ->
        "Provider returned invalid structured output. Prompt or schema mismatch is likely."

      tool_failure?(snapshot) ->
        "Tool failed and no successful recovery was recorded."

      delegation_stalled?(snapshot) ->
        "Delegated child result was present, but manager did not turn it into a final reply."

      final_action_label(snapshot) == "unknown" ->
        "Final decision is not obvious from the trace."

      true ->
        "No obvious runtime failure detected."
    end
  end

  defp diagnostic_recovery_note(snapshot) do
    cond do
      outcome_label(snapshot) == "completed" ->
        "The requested work appears to have completed successfully."

      outcome_label(snapshot) == "partial" ->
        "Trace shows partial work or a follow-up action still pending."

      true ->
        nil
    end
  end

  defp diagnostic_delegation_note(snapshot) do
    case delegation_state(snapshot) do
      %{status: "running", callback_context_received: "yes"} ->
        "Delegation callback context exists, but latest child call still reports running."

      %{status: "running"} ->
        "Manager delegated work and is still waiting. No delegated-result callback has been appended yet."

      %{status: status, callback_context_received: "yes"}
      when status in ["completed", "failed"] ->
        "Delegated child reached terminal state and callback context was appended to manager history."

      %{status: status} when status in ["completed", "failed"] ->
        "Delegated child reached terminal state, but manager history does not show a callback context yet."

      _other ->
        nil
    end
  end

  defp delegation_state(snapshot) do
    snapshot.delegation_state ||
      build_delegation_state(snapshot.runtime_state, snapshot.instance, snapshot.lemming_calls)
  end

  defp build_delegation_state(runtime_state, instance, lemming_calls) do
    case List.last(lemming_calls || []) do
      %LemmingCall{} = call ->
        %{
          call_id: present_or_default(call.id, "unknown"),
          child_instance: present_or_default(call.callee_instance_id, "unknown"),
          status: present_or_default(call.status, "unknown"),
          recovery_status: present_or_default(call.recovery_status, "none"),
          result_summary: present_or_default(call.result_summary, "none"),
          error_summary: present_or_default(call.error_summary, "none"),
          callback_context_received: callback_context_value(runtime_state, call),
          waiting_state: manager_waiting_state_label(runtime_state, instance, call)
        }

      _other ->
        nil
    end
  end

  defp callback_context_value(runtime_state, call) do
    if callback_context_present?(runtime_state, call), do: "yes", else: "no"
  end

  defp present_or_default(value, _default) when is_binary(value) and value != "", do: value
  defp present_or_default(nil, default), do: default
  defp present_or_default(_value, default), do: default

  defp diagnostic_trace_note(snapshot) do
    case trace_class_label(snapshot) do
      "live" ->
        "Trace is live enough to trust runtime ordering."

      "reconstructed" ->
        "Trace mixes live memory with reconstructed request context."

      "persisted-only fallback" ->
        "Trace is persisted-only fallback. Some intermediate LLM turns may be missing."

      _other ->
        nil
    end
  end

  defp tool_failure?(snapshot) do
    snapshot.instance.id
    |> tool_executions_for_snapshot(snapshot)
    |> Enum.any?(fn execution -> execution.status == "error" end)
  end

  defp delegation_stalled?(snapshot) do
    final_action_label(snapshot) in ["lemming_call", "tool_call"] and
      state_status_label(snapshot.runtime_state, snapshot.instance) in ["failed", "expired"]
  end

  defp state_status_label(runtime_state, instance) do
    runtime_status = map_value(runtime_state, :status)
    instance_status = map_value(instance, :status)

    case runtime_status || instance_status do
      status when is_atom(status) -> Atom.to_string(status)
      status when is_binary(status) -> status
      _other -> "unknown"
    end
  end

  defp queue_depth_label(runtime_state) do
    runtime_state
    |> map_value(:queue)
    |> case do
      queue when is_tuple(queue) -> :queue.len(queue)
      _other -> 0
    end
  end

  defp retry_state_label(runtime_state) do
    current = map_value(runtime_state, :retry_count) || 0
    max = map_value(runtime_state, :max_retries) || 0
    "#{current}/#{max}"
  end

  defp current_item_label(runtime_state) do
    runtime_state
    |> map_value(:current_item)
    |> case do
      nil -> "none"
      %{content: content} when is_binary(content) -> preview_text(content)
      %{"content" => content} when is_binary(content) -> preview_text(content)
      other -> preview_or_none(other)
    end
  end

  defp last_error_label(runtime_state) do
    runtime_state
    |> map_value(:last_error)
    |> case do
      nil -> "none"
      value when is_binary(value) -> value
      other -> inspect(other)
    end
  end

  defp message_count_label(runtime_state) do
    runtime_state
    |> map_value(:context_messages)
    |> case do
      messages when is_list(messages) -> "#{length(messages)}"
      _other -> "0"
    end
  end

  defp runtime_state_source_label(snapshot) do
    case snapshot.interaction_timeline_source do
      :live_executor_trace -> "live executor memory"
      :persisted_history_only -> "persisted transcript/tool history"
      _other -> "reconstructed runtime state"
    end
  end

  defp callback_context_present?(runtime_state, call) do
    runtime_messages =
      runtime_state
      |> map_value(:context_messages)
      |> List.wrap()

    Enum.any?(runtime_messages, fn
      %{} = message ->
        callback_context_message?(message, call)

      _other ->
        false
    end)
  end

  defp callback_context_message?(message, call) do
    content = map_value(message, :content)

    is_binary(content) and
      String.contains?(content, "Lemming call result: status=") and
      callback_matches_call?(content, call)
  end

  defp callback_matches_call?(content, %LemmingCall{} = call) do
    Enum.any?(
      Enum.reject([call.id, call.callee_instance_id], &blank?/1),
      &String.contains?(content, &1)
    )
  end

  defp manager_waiting_state_label(runtime_state, instance, %LemmingCall{status: "running"}) do
    if state_status_label(runtime_state, instance) == "idle" do
      "idle waiting on child"
    else
      "child running"
    end
  end

  defp manager_waiting_state_label(runtime_state, _instance, %LemmingCall{status: status} = call)
       when status in ["completed", "failed"] do
    if callback_context_present?(runtime_state, call) do
      "child terminal and callback delivered"
    else
      "child terminal but callback not visible"
    end
  end

  defp manager_waiting_state_label(_runtime_state, _instance, %LemmingCall{}), do: "unknown"

  defp config_profile_label(snapshot) do
    models_config = map_value(snapshot, :models_config) || %{}
    profiles = map_value(models_config, :profiles) || %{}

    case map_value(profiles, :default) do
      %{} = profile ->
        provider = map_value(profile, :provider) || "unknown"
        model = map_value(profile, :model) || "unknown"
        "default (#{provider}/#{model})"

      _other ->
        "unknown"
    end
  end

  defp config_provider_model_label(snapshot) do
    models_config = map_value(snapshot, :models_config) || %{}
    profiles = map_value(models_config, :profiles) || %{}

    case map_value(profiles, :default) do
      %{} = profile ->
        provider = map_value(profile, :provider) || "unknown"
        model = map_value(profile, :model) || "unknown"
        "#{provider}/#{model}"

      _other ->
        "unknown"
    end
  end

  defp config_allowed_tools_label(snapshot) do
    snapshot
    |> map_value(:tools_config)
    |> case do
      %{} = tools_config ->
        tools_config
        |> map_value(:allowed_tools)
        |> list_label()

      _other ->
        "none"
    end
  end

  defp config_delegation_targets_label(snapshot) do
    snapshot
    |> map_value(:lemming_call_targets)
    |> case do
      targets when is_list(targets) ->
        targets
        |> Enum.map(fn target ->
          [
            map_value(target, :capability) || map_value(target, :slug) || "unknown",
            map_value(target, :role)
          ]
          |> Enum.reject(&blank?/1)
          |> Enum.join(" / ")
        end)
        |> list_label()

      _other ->
        "none"
    end
  end

  defp config_idle_ttl_label(snapshot) do
    snapshot
    |> map_value(:runtime_config)
    |> case do
      %{} = runtime_config ->
        case map_value(runtime_config, :idle_ttl_seconds) do
          seconds when is_integer(seconds) -> "#{seconds}s"
          _other -> "unknown"
        end

      _other ->
        "unknown"
    end
  end

  defp config_retry_limit_label(snapshot) do
    snapshot
    |> map_value(:runtime_config)
    |> case do
      %{} = runtime_config ->
        case map_value(runtime_config, :max_retries) do
          retries when is_integer(retries) -> Integer.to_string(retries)
          _other -> "unknown"
        end

      _other ->
        "unknown"
    end
  end

  defp map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil

  defp list_label(values) when is_list(values) do
    values
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
    |> case do
      [] -> "none"
      items -> Enum.join(items, ", ")
    end
  end

  defp fetch_instance_id(opts) do
    case Keyword.get(opts, :instance_id) do
      instance_id when is_binary(instance_id) and instance_id != "" -> {:ok, instance_id}
      _other -> {:error, :not_found}
    end
  end

  defp fetch_world(opts, _instance_id) do
    case Keyword.get(opts, :world) do
      %World{} = world -> {:ok, world}
      _other -> fetch_world_from_world_id_or_instance(opts)
    end
  end

  defp fetch_world_from_world_id_or_instance(opts) do
    case Keyword.get(opts, :world_id) do
      world_id when is_binary(world_id) and world_id != "" ->
        case Worlds.get_world(world_id) do
          %World{} = world -> {:ok, world}
          nil -> {:error, :not_found}
        end

      _other ->
        infer_world_from_instance(Keyword.get(opts, :instance_id))
    end
  end

  defp infer_world_from_instance(instance_id) when is_binary(instance_id) do
    case Repo.one(
           from instance in LemmingInstance,
             where: instance.id == ^instance_id,
             select: instance.world_id
         ) do
      world_id when is_binary(world_id) ->
        case Worlds.get_world(world_id) do
          %World{} = world -> {:ok, world}
          nil -> {:error, :not_found}
        end

      _other ->
        {:error, :not_found}
    end
  end

  defp infer_world_from_instance(_instance_id), do: {:error, :not_found}

  defp load_runtime_state(instance, world) do
    case LemmingInstances.get_runtime_state(instance.id, world: world) do
      {:ok, state} -> state
      {:error, :not_found} -> %{}
    end
  end

  defp load_messages(instance, world) do
    LemmingInstances.list_messages(instance, world: world)
  end

  defp load_tool_executions(instance, world) do
    LemmingTools.list_tool_executions(world, instance)
  end

  defp load_lemming_calls(%LemmingInstance{lemming: lemming} = instance, messages) do
    if LemmingCalls.manager?(lemming) do
      since = latest_user_message_at(messages)

      instance
      |> LemmingCalls.list_manager_calls()
      |> Repo.preload(@lemming_call_preloads)
      |> Enum.filter(&call_after_or_at?(&1, since))
      |> Enum.sort_by(&lemming_call_sort_key/1)
    else
      []
    end
  end

  defp load_model_steps(instance) do
    case Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id) do
      [{_pid, _value}] ->
        instance.id
        |> Executor.snapshot()
        |> Map.get(:model_steps, [])
        |> Enum.take(-@max_live_steps)

      [] ->
        []
    end
  catch
    :exit, _reason -> []
  end

  defp load_model_request(instance, runtime_state, model_steps, messages)
       when is_list(model_steps) do
    case List.last(model_steps) do
      %{request_payload: payload} when is_map(payload) ->
        {payload, :live_executor_trace}

      _other ->
        fallback_model_request(instance, runtime_state, messages)
    end
  end

  defp fallback_model_request(instance, runtime_state, messages) do
    case build_model_request(instance, runtime_state) do
      {:ok, request} ->
        {request, :runtime_state}

      {:error, _reason} ->
        case build_model_request_from_transcript(instance, messages) do
          {:ok, request} -> {request, :transcript_reconstruction}
          {:error, reason} -> {%{error: inspect(reason)}, :unavailable}
        end
    end
  end

  defp build_model_request(instance, runtime_state) do
    history = Map.get(runtime_state, :context_messages, [])
    current_item = Map.get(runtime_state, :current_item)

    ModelRuntime.debug_request(instance.config_snapshot || %{}, history, current_item)
  end

  defp build_model_request_from_transcript(instance, messages) do
    case split_transcript_for_request(messages) do
      {:ok, history, current_request} ->
        ModelRuntime.debug_request(instance.config_snapshot || %{}, history, current_request)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_transcript_for_request(messages) do
    user_messages =
      Enum.filter(messages, fn
        %Message{role: "user"} -> true
        _message -> false
      end)

    case List.last(user_messages) do
      %Message{} = current_request ->
        history =
          messages
          |> Enum.take_while(&(&1.id != current_request.id))
          |> Enum.map(&message_to_context_message/1)

        {:ok, history, %{content: current_request.content}}

      nil ->
        {:error, :invalid_request}
    end
  end

  defp message_to_context_message(%Message{role: role, content: content}) do
    %{role: role, content: content}
  end

  defp build_interaction_timeline(model_steps, messages, tool_executions, lemming_calls)
       when is_list(model_steps) and model_steps != [] do
    executions_by_id = Map.new(tool_executions, &{&1.id, &1})

    timeline =
      [
        build_user_request_entry(model_steps, messages)
        | build_live_timeline_entries(model_steps, executions_by_id, lemming_calls)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> renumber_timeline()

    {timeline, :live_executor_trace}
  end

  defp build_interaction_timeline(_model_steps, messages, tool_executions, lemming_calls) do
    timeline =
      messages
      |> build_persisted_timeline(tool_executions, lemming_calls)
      |> Enum.reject(&is_nil/1)
      |> renumber_timeline()

    {timeline, :persisted_history_only}
  end

  defp build_user_request_entry(model_steps, messages) do
    content =
      model_steps
      |> List.first()
      |> extract_current_request_content()
      |> case do
        nil -> latest_user_message_content(messages)
        value -> value
      end

    if present?(content) do
      %{
        id: "user-request",
        kind: :user_request,
        title: "1. User -> App",
        summary: "Operator request received",
        body: content,
        timestamp: latest_user_message_at(messages),
        meta: [],
        status: nil,
        raw_sections: []
      }
    end
  end

  defp build_live_timeline_entries(model_steps, executions_by_id, lemming_calls) do
    {entries, _remaining_calls} =
      model_steps
      |> Enum.chunk_by(&Map.get(&1, :request_payload))
      |> Enum.map_reduce(lemming_calls, fn request_group, remaining_calls ->
        build_live_request_group_entries(request_group, executions_by_id, remaining_calls)
      end)

    List.flatten(entries)
  end

  defp build_live_request_group_entries(
         [first_step | _rest] = request_group,
         executions_by_id,
         lemming_calls
       ) do
    {step_entries, remaining_calls} =
      request_group
      |> Enum.with_index(1)
      |> Enum.map_reduce(lemming_calls, fn {model_step, retry_attempt}, remaining_calls ->
        build_live_step_entries(model_step, executions_by_id, retry_attempt, remaining_calls)
      end)

    {[build_llm_request_entry(first_step) | List.flatten(step_entries)], remaining_calls}
  end

  defp build_live_step_entries(model_step, executions_by_id, retry_attempt, lemming_calls) do
    tool_execution =
      model_step
      |> Map.get(:tool_execution_id)
      |> then(&Map.get(executions_by_id, &1))

    {action_entries, remaining_calls} =
      build_action_entries(model_step, tool_execution, lemming_calls)

    {[
       build_llm_response_entry(model_step, retry_attempt)
       | action_entries
     ], remaining_calls}
  end

  defp build_action_entries(
         %{parsed_output: %{"action" => "lemming_call"} = parsed_output} = model_step,
         _tool_execution,
         lemming_calls
       ) do
    {lemming_call, remaining_calls} =
      take_matching_lemming_call(lemming_calls, model_step, parsed_output)

    {build_lemming_call_entries(model_step, parsed_output, lemming_call), remaining_calls}
  end

  defp build_action_entries(model_step, tool_execution, lemming_calls) do
    {build_tool_entries(model_step, tool_execution), lemming_calls}
  end

  defp build_llm_request_entry(model_step) do
    request_payload = Map.get(model_step, :request_payload, %{})
    request = request_payload["request"] || %{}
    messages = request["messages"] || []
    non_system_count = Enum.count(messages, &(&1["role"] != "system"))

    %{
      id: "step-#{model_step.step_index}-llm-request",
      kind: :llm_request,
      title: "App -> LLM",
      summary:
        "Send provider request with system prompt, tools catalog, and #{non_system_count} context message(s)",
      body: request_messages_body(messages),
      timestamp: Map.get(model_step, :started_at),
      meta: request_meta(request_payload, messages),
      status: Map.get(model_step, :status),
      raw_sections: [
        %{label: "Provider request", payload: request_payload},
        %{label: "System prompt", payload: extract_system_prompt(messages)}
      ]
    }
  end

  defp build_llm_response_entry(model_step, retry_attempt) do
    parsed_output = Map.get(model_step, :parsed_output) || %{}
    {summary, body} = llm_response_summary_and_body(model_step, parsed_output)

    %{
      id: "step-#{model_step.step_index}-llm-response",
      kind: :llm_response,
      title: llm_response_title(retry_attempt),
      summary: summary,
      body: body,
      timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
      meta: response_meta(model_step),
      status: Map.get(model_step, :status),
      raw_sections: [
        %{label: "Parsed response", payload: parsed_output},
        %{label: "Provider raw response", payload: model_step.response_payload},
        %{label: "Error", payload: model_step.error}
      ]
    }
  end

  defp llm_response_summary_and_body(_model_step, %{"action" => "tool_call"} = parsed_output) do
    tool_name = parsed_output["tool_name"] || "unknown tool"
    {"LLM requested tool #{tool_name}", format_tool_args_body(parsed_output["args"] || %{})}
  end

  defp llm_response_summary_and_body(_model_step, %{"action" => "reply"} = parsed_output) do
    {"LLM returned final reply", humanize_text(parsed_output["reply"])}
  end

  defp llm_response_summary_and_body(_model_step, %{"action" => "lemming_call"} = parsed_output) do
    target = parsed_output["target"] || "unknown target"
    request = humanize_text(parsed_output["request"] || "")
    {"LLM requested lemming call #{target}", request}
  end

  defp llm_response_summary_and_body(model_step, parsed_output) do
    {"LLM returned an unexpected payload", llm_error_body(model_step, parsed_output)}
  end

  defp llm_error_body(_model_step, parsed_output) when map_size(parsed_output) > 0 do
    Jason.encode!(parsed_output, pretty: true)
  end

  defp llm_error_body(model_step, _parsed_output) do
    error = Map.get(model_step, :error) || %{}
    response_payload = Map.get(model_step, :response_payload) || %{}

    cond do
      is_binary(error["content"]) and error["content"] != "" ->
        humanize_text(error["content"])

      is_binary(response_payload["content"]) ->
        humanize_text(response_payload["content"])

      map_size(error) > 0 ->
        Jason.encode!(error, pretty: true)

      true ->
        "%{}"
    end
  end

  defp build_tool_entries(
         %{parsed_output: %{"action" => "tool_call"} = parsed_output} = model_step,
         tool_execution
       ) do
    tool_name = parsed_output["tool_name"] || "unknown tool"
    tool_args = parsed_output["args"] || %{}

    [
      %{
        id: "step-#{model_step.step_index}-tool-call",
        kind: :tool_call,
        title: "App -> Tool",
        summary: "Execute #{tool_name}",
        body: format_tool_args_body(tool_args),
        timestamp: tool_entry_timestamp(tool_execution),
        meta: tool_call_meta(tool_execution),
        status: tool_execution_status(tool_execution),
        raw_sections: [
          %{label: "Tool arguments", payload: tool_args}
        ]
      },
      build_tool_result_entry(model_step, tool_execution)
    ]
  end

  defp build_tool_entries(_model_step, _tool_execution), do: []

  defp build_lemming_call_entries(model_step, parsed_output, nil) do
    target = parsed_output["target"] || "unknown target"
    request_text = humanize_text(parsed_output["request"] || "")

    [
      %{
        id: "step-#{model_step.step_index}-lemming-call",
        kind: :tool_call,
        title: "App -> Lemming",
        summary: "Delegate to #{target}",
        body: request_text,
        timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
        meta: [],
        status: "running",
        raw_sections: [
          %{label: "Lemming call request", payload: parsed_output}
        ]
      },
      %{
        id: "step-#{model_step.step_index}-lemming-result-missing",
        kind: :tool_result,
        title: "Lemming -> App",
        summary: "Delegated result not available in persistence",
        body: "Live model step exists, but no durable lemming-call row was found.",
        timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
        meta: [],
        status: "error",
        raw_sections: []
      }
    ]
  end

  defp build_lemming_call_entries(model_step, parsed_output, %LemmingCall{} = lemming_call) do
    [
      %{
        id: "step-#{model_step.step_index}-lemming-call",
        kind: :tool_call,
        title: "App -> Lemming",
        summary: lemming_call_request_summary(lemming_call, parsed_output),
        body: humanize_text(lemming_call.request_text || parsed_output["request"] || ""),
        timestamp: lemming_call_request_timestamp(lemming_call),
        meta: lemming_call_request_meta(lemming_call),
        status: lemming_call.status,
        raw_sections: [
          %{label: "Lemming call request", payload: lemming_call_request_payload(lemming_call)}
        ]
      },
      %{
        id: "step-#{model_step.step_index}-lemming-result",
        kind: :tool_result,
        title: "Lemming -> App",
        summary: lemming_call_result_summary(lemming_call),
        body: lemming_call_result_body(lemming_call),
        timestamp: lemming_call_result_timestamp(lemming_call),
        meta: lemming_call_result_meta(lemming_call),
        status: lemming_call.status,
        raw_sections: [
          %{label: "Persisted lemming call", payload: lemming_call_payload(lemming_call)}
        ]
      }
    ]
  end

  defp build_tool_result_entry(model_step, nil) do
    %{
      id: "step-#{model_step.step_index}-tool-result-missing",
      kind: :tool_result,
      title: "Tool -> App",
      summary: "Tool result not available in persistence",
      body: "Live model step exists, but no durable tool row was found.",
      timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
      meta: [],
      status: "error",
      raw_sections: []
    }
  end

  defp build_tool_result_entry(model_step, %ToolExecution{} = tool_execution) do
    %{
      id: "step-#{model_step.step_index}-tool-result",
      kind: :tool_result,
      title: "Tool -> App",
      summary: tool_result_summary(tool_execution),
      body: tool_result_body(tool_execution),
      timestamp: tool_result_timestamp(tool_execution),
      meta: tool_result_meta(tool_execution),
      status: tool_execution.status,
      raw_sections: [
        %{label: "Persisted tool arguments", payload: tool_execution.args},
        %{label: "Persisted tool result", payload: tool_execution.result},
        %{label: "Persisted tool error", payload: tool_execution.error}
      ]
    }
  end

  defp build_persisted_timeline(messages, tool_executions, lemming_calls) do
    [
      build_persisted_user_entry(messages),
      Enum.flat_map(lemming_calls, &build_persisted_lemming_entries/1),
      Enum.map(tool_executions, &build_persisted_tool_entry/1),
      build_persisted_reply_entry(messages)
    ]
    |> List.flatten()
  end

  defp build_persisted_user_entry(messages) do
    case latest_user_message_content(messages) do
      nil ->
        nil

      content ->
        %{
          id: "persisted-user-request",
          kind: :user_request,
          title: "User -> App",
          summary: "Persisted user request",
          body: content,
          timestamp: latest_user_message_at(messages),
          meta: [],
          status: nil,
          raw_sections: []
        }
    end
  end

  defp build_persisted_tool_entry(tool_execution) do
    %{
      id: "persisted-tool-#{tool_execution.id}",
      kind: :tool_result,
      title: "Persisted tool execution",
      summary: tool_result_summary(tool_execution),
      body: tool_result_body(tool_execution),
      timestamp: tool_result_timestamp(tool_execution),
      meta: tool_result_meta(tool_execution),
      status: tool_execution.status,
      raw_sections: [
        %{label: "Persisted tool arguments", payload: tool_execution.args},
        %{label: "Persisted tool result", payload: tool_execution.result},
        %{label: "Persisted tool error", payload: tool_execution.error}
      ]
    }
  end

  defp build_persisted_lemming_entries(%LemmingCall{} = lemming_call) do
    [
      %{
        id: "persisted-lemming-call-#{lemming_call.id}",
        kind: :tool_call,
        title: "App -> Lemming",
        summary: lemming_call_request_summary(lemming_call, %{}),
        body: humanize_text(lemming_call.request_text),
        timestamp: lemming_call_request_timestamp(lemming_call),
        meta: lemming_call_request_meta(lemming_call),
        status: lemming_call.status,
        raw_sections: [
          %{label: "Lemming call request", payload: lemming_call_request_payload(lemming_call)}
        ]
      },
      %{
        id: "persisted-lemming-result-#{lemming_call.id}",
        kind: :tool_result,
        title: "Lemming -> App",
        summary: lemming_call_result_summary(lemming_call),
        body: lemming_call_result_body(lemming_call),
        timestamp: lemming_call_result_timestamp(lemming_call),
        meta: lemming_call_result_meta(lemming_call),
        status: lemming_call.status,
        raw_sections: [
          %{label: "Persisted lemming call", payload: lemming_call_payload(lemming_call)}
        ]
      }
    ]
  end

  defp build_persisted_reply_entry(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(fn
      %Message{role: "assistant"} -> true
      _message -> false
    end)
    |> case do
      %Message{} = message ->
        %{
          id: "persisted-final-reply",
          kind: :final_reply,
          title: "LLM -> App",
          summary: "Final assistant reply stored in transcript",
          body: message.content,
          timestamp: message.inserted_at,
          meta: persisted_message_meta(message),
          status: nil,
          raw_sections: []
        }

      nil ->
        nil
    end
  end

  defp latest_user_message_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: "user", content: content} -> content
      _message -> nil
    end)
  end

  defp latest_user_message_at(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: "user", inserted_at: inserted_at} -> inserted_at
      _message -> nil
    end)
  end

  defp extract_current_request_content(nil), do: nil

  defp extract_current_request_content(%{request_payload: request_payload}) do
    request_payload
    |> Map.get("request", %{})
    |> Map.get("messages", [])
    |> List.last()
    |> case do
      %{"content" => content} when is_binary(content) -> content
      _other -> nil
    end
  end

  defp request_messages_body(messages) when is_list(messages) and messages != [] do
    Enum.map_join(messages, "\n\n", fn message ->
      role =
        message
        |> Map.get("role", "unknown")
        |> to_string()
        |> String.upcase()

      content =
        case Map.get(message, "content") do
          value when is_binary(value) and value != "" -> humanize_text(value)
          _other -> "(empty)"
        end

      "#{role}\n#{content}"
    end)
  end

  defp request_messages_body(_messages), do: "Request messages unavailable."

  defp request_meta(request_payload, messages) do
    [
      provider_value(request_payload),
      model_value(request_payload),
      "#{length(messages)} total message(s)"
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp response_meta(model_step) do
    [
      Map.get(model_step, :provider),
      Map.get(model_step, :model),
      tokens_meta(model_step),
      duration_meta(Map.get(model_step, :duration_ms))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp tool_call_meta(nil), do: []

  defp tool_call_meta(tool_execution) do
    [tool_execution.id, duration_meta(tool_execution.duration_ms)]
    |> Enum.reject(&is_nil/1)
  end

  defp tool_result_meta(tool_execution) do
    [tool_execution.tool_name, duration_meta(tool_execution.duration_ms)]
    |> Enum.reject(&is_nil/1)
  end

  defp persisted_message_meta(%Message{} = message) do
    [message.provider, message.model, tokens_meta(message)]
    |> Enum.reject(&is_nil/1)
  end

  defp tokens_meta(%{input_tokens: input_tokens, output_tokens: output_tokens})
       when is_integer(input_tokens) and is_integer(output_tokens) do
    "#{input_tokens} in / #{output_tokens} out"
  end

  defp tokens_meta(%{total_tokens: total_tokens}) when is_integer(total_tokens) do
    "#{total_tokens} total tokens"
  end

  defp tokens_meta(_payload), do: nil

  defp duration_meta(duration_ms) when is_integer(duration_ms), do: "#{duration_ms} ms"
  defp duration_meta(_duration_ms), do: nil

  defp provider_value(%{"provider" => provider}) when is_binary(provider), do: provider

  defp provider_value(%{"request" => %{"provider" => provider}}) when is_binary(provider),
    do: provider

  defp provider_value(%{request: %{provider: provider}}) when is_binary(provider), do: provider
  defp provider_value(_payload), do: nil

  defp model_value(%{"model" => model}) when is_binary(model), do: model
  defp model_value(%{"request" => %{"model" => model}}) when is_binary(model), do: model
  defp model_value(%{request: %{model: model}}) when is_binary(model), do: model
  defp model_value(_payload), do: nil

  defp format_tool_args_body(args) when is_map(args) and map_size(args) == 0 do
    "Tool called without arguments."
  end

  defp format_tool_args_body(args) when is_map(args) do
    Enum.map_join(args, "\n\n", fn {key, value} ->
      case render_tool_arg_value(value) do
        {:inline, rendered} ->
          "- `#{key}`: #{rendered}"

        {:block, rendered} ->
          "- `#{key}`:\n#{indent_block(rendered, 2)}"
      end
    end)
  end

  defp format_tool_args_body(_args), do: "Tool arguments unavailable."

  defp render_tool_arg_value(value) when is_binary(value) do
    rendered = humanize_text(value)

    if String.contains?(rendered, "\n") do
      {:block, rendered}
    else
      {:inline, rendered}
    end
  end

  defp render_tool_arg_value(value) when is_map(value) or is_list(value) do
    {:block, Jason.encode!(value, pretty: true)}
  end

  defp render_tool_arg_value(value), do: {:inline, inspect(value)}

  defp indent_block(content, spaces)
       when is_binary(content) and is_integer(spaces) and spaces > 0 do
    prefix = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp tool_result_summary(%ToolExecution{status: "ok", tool_name: tool_name}) do
    "#{tool_name} completed"
  end

  defp tool_result_summary(%ToolExecution{status: "error", tool_name: tool_name}) do
    "#{tool_name} failed"
  end

  defp tool_result_summary(%ToolExecution{tool_name: tool_name}), do: tool_name

  defp tool_result_body(%ToolExecution{} = tool_execution) do
    cond do
      present?(tool_execution.preview) and present?(tool_execution.summary) ->
        "#{humanize_text(tool_execution.summary)}\n\n#{humanize_text(tool_execution.preview)}"

      present?(tool_execution.summary) ->
        humanize_text(tool_execution.summary)

      present?(tool_execution.preview) ->
        humanize_text(tool_execution.preview)

      is_map(tool_execution.error) ->
        map_message(tool_execution.error) || inspect(tool_execution.error)

      true ->
        "Tool execution finished without a summary."
    end
  end

  defp map_message(%{"message" => message}) when is_binary(message), do: message
  defp map_message(%{message: message}) when is_binary(message), do: message
  defp map_message(_value), do: nil

  defp tool_execution_status(nil), do: "running"
  defp tool_execution_status(%ToolExecution{status: status}), do: status

  defp tool_entry_timestamp(nil), do: nil
  defp tool_entry_timestamp(%ToolExecution{started_at: %DateTime{} = started_at}), do: started_at

  defp tool_entry_timestamp(%ToolExecution{inserted_at: %DateTime{} = inserted_at}),
    do: inserted_at

  defp tool_entry_timestamp(_tool_execution), do: nil

  defp tool_result_timestamp(%ToolExecution{completed_at: %DateTime{} = completed_at}),
    do: completed_at

  defp tool_result_timestamp(%ToolExecution{updated_at: %DateTime{} = updated_at}), do: updated_at

  defp tool_result_timestamp(%ToolExecution{inserted_at: %DateTime{} = inserted_at}),
    do: inserted_at

  defp tool_result_timestamp(_tool_execution), do: nil

  defp extract_system_prompt(messages) do
    messages
    |> Enum.find(fn message -> message["role"] == "system" end)
    |> case do
      %{"content" => content} -> content
      _other -> nil
    end
  end

  defp llm_response_title(1), do: "LLM -> App"
  defp llm_response_title(retry_attempt), do: "LLM -> App (retry #{retry_attempt})"

  defp take_matching_lemming_call(lemming_calls, model_step, parsed_output) do
    continue_call_id = parsed_output["continue_call_id"]
    request_text = parsed_output["request"]
    step_time = Map.get(model_step, :completed_at) || Map.get(model_step, :started_at)

    pop_first(lemming_calls, fn call ->
      matching_continue_call?(call, continue_call_id) or
        matching_request_text?(call, request_text, step_time)
    end)
  end

  defp matching_continue_call?(_call, value) when value in [nil, ""], do: false

  defp matching_continue_call?(%LemmingCall{} = call, continue_call_id) do
    call.id == continue_call_id or call.previous_call_id == continue_call_id
  end

  defp matching_request_text?(%LemmingCall{} = call, request_text, step_time)
       when is_binary(request_text) and request_text != "" do
    call.request_text == request_text and call_near_step?(call, step_time)
  end

  defp matching_request_text?(_call, _request_text, _step_time), do: false

  defp call_near_step?(_call, nil), do: true

  defp call_near_step?(%LemmingCall{} = call, %DateTime{} = step_time) do
    call
    |> lemming_call_request_timestamp()
    |> case do
      %DateTime{} = call_time ->
        abs(DateTime.diff(call_time, step_time, :second)) <= 300

      nil ->
        true
    end
  end

  defp pop_first([], _matcher), do: {nil, []}

  defp pop_first([item | rest], matcher) do
    if matcher.(item) do
      {item, rest}
    else
      {match, remaining} = pop_first(rest, matcher)
      {match, [item | remaining]}
    end
  end

  defp lemming_call_request_summary(%LemmingCall{} = lemming_call, parsed_output) do
    target = callee_lemming_label(lemming_call) || parsed_output["target"] || "unknown target"
    "Delegate to #{target}"
  end

  defp lemming_call_request_meta(%LemmingCall{} = lemming_call) do
    [
      lemming_call.id,
      lemming_call.callee_instance_id,
      lemming_call_relationship(lemming_call)
    ]
    |> Enum.reject(&blank?/1)
  end

  defp lemming_call_result_meta(%LemmingCall{} = lemming_call) do
    [
      lemming_call.id,
      lemming_call.callee_instance_id,
      lemming_call.recovery_status
    ]
    |> Enum.reject(&blank?/1)
  end

  defp lemming_call_request_payload(%LemmingCall{} = lemming_call) do
    %{
      call_id: lemming_call.id,
      caller: caller_lemming_label(lemming_call),
      callee: callee_lemming_label(lemming_call),
      caller_instance_id: lemming_call.caller_instance_id,
      callee_instance_id: lemming_call.callee_instance_id,
      request_text: lemming_call.request_text,
      status: lemming_call.status,
      previous_call_id: lemming_call.previous_call_id,
      root_call_id: lemming_call.root_call_id
    }
  end

  defp lemming_call_payload(%LemmingCall{} = lemming_call) do
    %{
      call_id: lemming_call.id,
      caller: caller_lemming_label(lemming_call),
      callee: callee_lemming_label(lemming_call),
      caller_instance_id: lemming_call.caller_instance_id,
      callee_instance_id: lemming_call.callee_instance_id,
      request_text: lemming_call.request_text,
      status: lemming_call.status,
      result_summary: lemming_call.result_summary,
      error_summary: lemming_call.error_summary,
      recovery_status: lemming_call.recovery_status,
      previous_call_id: lemming_call.previous_call_id,
      root_call_id: lemming_call.root_call_id
    }
  end

  defp lemming_call_result_summary(%LemmingCall{status: "completed"} = lemming_call) do
    "#{callee_lemming_label(lemming_call) || "Worker"} completed delegated work"
  end

  defp lemming_call_result_summary(%LemmingCall{status: "failed"} = lemming_call) do
    "#{callee_lemming_label(lemming_call) || "Worker"} failed delegated work"
  end

  defp lemming_call_result_summary(%LemmingCall{} = lemming_call) do
    "#{callee_lemming_label(lemming_call) || "Worker"} status #{lemming_call.status}"
  end

  defp lemming_call_result_body(%LemmingCall{} = lemming_call) do
    cond do
      present?(lemming_call.result_summary) ->
        humanize_text(lemming_call.result_summary)

      present?(lemming_call.error_summary) ->
        humanize_text(lemming_call.error_summary)

      true ->
        "Delegated work still in progress."
    end
  end

  defp lemming_call_request_timestamp(%LemmingCall{started_at: %DateTime{} = started_at}),
    do: started_at

  defp lemming_call_request_timestamp(%LemmingCall{inserted_at: %DateTime{} = inserted_at}),
    do: inserted_at

  defp lemming_call_request_timestamp(_call), do: nil

  defp lemming_call_result_timestamp(%LemmingCall{completed_at: %DateTime{} = completed_at}),
    do: completed_at

  defp lemming_call_result_timestamp(%LemmingCall{updated_at: %DateTime{} = updated_at}),
    do: updated_at

  defp lemming_call_result_timestamp(%LemmingCall{} = lemming_call),
    do: lemming_call_request_timestamp(lemming_call)

  defp lemming_call_sort_key(%LemmingCall{} = lemming_call) do
    {
      lemming_call_request_timestamp(lemming_call)
      |> case do
        %DateTime{} = value -> DateTime.to_unix(value, :microsecond)
        nil -> 0
      end,
      lemming_call.id || ""
    }
  end

  defp call_after_or_at?(_call, nil), do: true

  defp call_after_or_at?(%LemmingCall{} = lemming_call, %DateTime{} = since) do
    lemming_call
    |> lemming_call_request_timestamp()
    |> case do
      %DateTime{} = value -> DateTime.compare(value, since) != :lt
      nil -> true
    end
  end

  defp caller_lemming_label(%LemmingCall{caller_lemming: %{name: name}})
       when is_binary(name) and name != "",
       do: name

  defp caller_lemming_label(_lemming_call), do: nil

  defp callee_lemming_label(%LemmingCall{callee_lemming: %{name: name}})
       when is_binary(name) and name != "",
       do: name

  defp callee_lemming_label(_lemming_call), do: nil

  defp lemming_call_relationship(%LemmingCall{} = lemming_call) do
    [caller_lemming_label(lemming_call), callee_lemming_label(lemming_call)]
    |> Enum.reject(&blank?/1)
    |> case do
      [caller, callee] -> "#{caller} -> #{callee}"
      _other -> nil
    end
  end

  defp renumber_timeline(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      Map.put(entry, :title, "#{index}. #{strip_timeline_prefix(entry.title)}")
    end)
  end

  defp strip_timeline_prefix(title) when is_binary(title) do
    Regex.replace(~r/^\d+\.\s+/, title, "")
  end

  defp persisted_history_warning(:persisted_history_only) do
    "Live executor trace is unavailable. This fallback only shows persisted transcript and tool rows, not every intermediate LLM turn."
  end

  defp persisted_history_warning(_source), do: nil

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp nil_or_false?(nil), do: true
  defp nil_or_false?(false), do: true
  defp nil_or_false?(_value), do: false

  defp interaction_timeline_source_copy(:live_executor_trace), do: "live executor trace"

  defp interaction_timeline_source_copy(:persisted_history_only),
    do: "persisted transcript/tool history only"

  defp interaction_timeline_source_copy(_source), do: "unavailable"

  defp model_request_source_copy(:live_executor_trace), do: "exact latest live request"
  defp model_request_source_copy(:runtime_state), do: "live executor snapshot"

  defp model_request_source_copy(:transcript_reconstruction),
    do: "reconstructed from persisted transcript"

  defp model_request_source_copy(_source), do: "unavailable"

  defp timeline_timestamp(nil), do: nil
  defp timeline_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")

  defp json_code_block(payload) do
    "```json\n#{json_payload(payload)}\n```"
  end

  defp raw_payload_body(_title, nil), do: nil

  defp raw_payload_body(_title, payload) when is_binary(payload),
    do: quoted_block(humanize_text(payload))

  defp raw_payload_body(_title, payload) do
    cond do
      request_payload?(payload) ->
        readable_request_payload_markdown(payload)

      context_messages_payload?(payload) ->
        readable_messages_markdown(payload)

      current_item_payload?(payload) ->
        readable_current_item_markdown(payload)

      true ->
        json_code_block(payload)
    end
  end

  defp request_payload?(%{} = payload), do: request_messages(payload) != []
  defp request_payload?(_payload), do: false

  defp context_messages_payload?(payload) when is_list(payload) do
    payload != [] and Enum.all?(payload, &message_payload?/1)
  end

  defp context_messages_payload?(_payload), do: false

  defp current_item_payload?(%{} = payload) do
    case map_value(payload, :content) do
      value when is_binary(value) and value != "" -> true
      _other -> false
    end
  end

  defp current_item_payload?(_payload), do: false

  defp message_payload?(%{} = payload) do
    role = map_value(payload, :role)
    content = map_value(payload, :content)
    is_binary(role) and not is_nil(content)
  end

  defp message_payload?(_payload), do: false

  defp readable_request_payload_markdown(payload) do
    messages = request_messages(payload)

    [
      bullet_list(
        [
          provider_value(payload) && "Provider: #{provider_value(payload)}",
          model_value(payload) && "Model: #{model_value(payload)}",
          "Messages: #{length(messages)}"
        ]
        |> Enum.reject(&nil_or_false?/1)
      ),
      readable_messages_markdown(messages)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n\n")
  end

  defp readable_current_item_markdown(payload) do
    payload
    |> map_value(:content)
    |> humanize_text()
    |> case do
      value when is_binary(value) and value != "" -> quoted_block(value)
      _other -> json_code_block(payload)
    end
  end

  defp readable_messages_markdown(messages) when is_list(messages) do
    messages
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {message, index} ->
      role =
        message
        |> map_value(:role)
        |> to_string()
        |> String.upcase()

      content =
        message
        |> map_value(:content)
        |> readable_message_content()

      [
        "Message #{index} - #{role}",
        quoted_block(content)
      ]
      |> Enum.join("\n\n")
    end)
  end

  defp readable_message_content(content) when is_binary(content), do: humanize_text(content)

  defp readable_message_content(content) when is_list(content) or is_map(content),
    do: json_payload(content)

  defp readable_message_content(content), do: inspect(content)

  defp json_payload(nil), do: "{}"

  defp json_payload(payload) do
    payload
    |> json_sanitize()
    |> Jason.encode!(pretty: true)
  end

  defp json_sanitize(%DateTime{} = value), do: value
  defp json_sanitize(%NaiveDateTime{} = value), do: value
  defp json_sanitize(%Date{} = value), do: value
  defp json_sanitize(%Time{} = value), do: value

  defp json_sanitize(%{} = map) do
    Map.new(map, fn {key, value} ->
      {json_sanitize_key(key), json_sanitize(value)}
    end)
  end

  defp json_sanitize(list) when is_list(list), do: Enum.map(list, &json_sanitize/1)

  defp json_sanitize(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&json_sanitize/1)

  defp json_sanitize(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp json_sanitize(value), do: inspect(value)

  defp json_sanitize_key(key) when is_atom(key), do: key
  defp json_sanitize_key(key) when is_binary(key), do: key
  defp json_sanitize_key(key), do: inspect(key)
end
