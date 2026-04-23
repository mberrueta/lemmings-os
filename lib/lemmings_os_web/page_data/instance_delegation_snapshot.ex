defmodule LemmingsOsWeb.PageData.InstanceDelegationSnapshot do
  @moduledoc """
  Delegated-work read model for runtime instance pages.
  """

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming

  @manager_preloads [
    :caller_department,
    :caller_instance,
    :caller_lemming,
    :callee_department,
    :callee_instance,
    :callee_lemming
  ]

  @type call_view :: %{
          id: String.t(),
          request_text: String.t(),
          requested_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          result_summary: String.t() | nil,
          error_summary: String.t() | nil,
          raw_status: String.t(),
          recovery_status: String.t() | nil,
          ui_state: String.t(),
          ui_state_label: String.t(),
          ui_state_tone: String.t(),
          state_copy: String.t() | nil,
          relationship_copy: String.t(),
          caller_label: String.t(),
          callee_label: String.t(),
          caller_role: String.t(),
          callee_role: String.t(),
          caller_department: String.t() | nil,
          callee_department: String.t() | nil,
          caller_instance_path: String.t() | nil,
          callee_instance_path: String.t() | nil,
          previous_call_id: String.t() | nil,
          successor_call_id: String.t() | nil
        }

  @type t :: %__MODULE__{
          mode: :manager | :child | :none,
          calls: [call_view()],
          available_targets: [map()],
          active_count: non_neg_integer(),
          historical_count: non_neg_integer()
        }

  defstruct mode: :none,
            calls: [],
            available_targets: [],
            active_count: 0,
            historical_count: 0

  @doc """
  Builds delegated-work data for an instance session page.
  """
  @spec build(LemmingInstance.t()) :: t()
  def build(%LemmingInstance{} = instance) do
    if manager_instance?(instance), do: manager_snapshot(instance), else: child_snapshot(instance)
  end

  def build(_instance), do: %__MODULE__{}

  defp manager_snapshot(%LemmingInstance{} = instance) do
    calls =
      instance
      |> LemmingCalls.list_manager_calls(preload: @manager_preloads)
      |> call_views(instance.world_id)

    %__MODULE__{
      mode: :manager,
      calls: calls,
      available_targets: LemmingCalls.available_targets(instance),
      active_count: Enum.count(calls, &active_call?/1),
      historical_count: Enum.count(calls, &(not active_call?(&1)))
    }
  end

  defp child_snapshot(%LemmingInstance{} = instance) do
    calls =
      instance
      |> LemmingCalls.list_child_calls(preload: @manager_preloads)
      |> call_views(instance.world_id)

    mode = if calls == [], do: :none, else: :child

    %__MODULE__{
      mode: mode,
      calls: calls,
      available_targets: [],
      active_count: Enum.count(calls, &active_call?/1),
      historical_count: Enum.count(calls, &(not active_call?(&1)))
    }
  end

  defp call_views(calls, world_id) do
    successor_ids =
      Map.new(calls, fn %LemmingCall{previous_call_id: previous_call_id, id: id} ->
        {previous_call_id, id}
      end)

    Enum.map(calls, &call_view(&1, world_id, successor_ids))
  end

  defp call_view(%LemmingCall{} = call, world_id, successor_ids) do
    ui_state = ui_state(call, Map.get(successor_ids, call.id))

    %{
      id: call.id,
      request_text: call.request_text,
      requested_at: call.inserted_at,
      started_at: call.started_at,
      completed_at: call.completed_at,
      result_summary: blank_to_nil(call.result_summary),
      error_summary: blank_to_nil(call.error_summary),
      raw_status: call.status,
      recovery_status: blank_to_nil(call.recovery_status),
      ui_state: ui_state,
      ui_state_label: ui_state_label(ui_state),
      ui_state_tone: ui_state_tone(ui_state),
      state_copy: state_copy(call, ui_state),
      relationship_copy: relationship_copy(call),
      caller_label: lemming_label(call.caller_lemming),
      callee_label: lemming_label(call.callee_lemming),
      caller_role: lemming_role(call.caller_lemming),
      callee_role: lemming_role(call.callee_lemming),
      caller_department: department_name(call.caller_department),
      callee_department: department_name(call.callee_department),
      caller_instance_path: instance_path(call.caller_instance_id, world_id),
      callee_instance_path: instance_path(call.callee_instance_id, world_id),
      previous_call_id: call.previous_call_id,
      successor_call_id: Map.get(successor_ids, call.id)
    }
  end

  defp manager_instance?(%LemmingInstance{lemming: %Lemming{} = lemming}),
    do: LemmingCalls.manager?(lemming)

  defp manager_instance?(_instance), do: false

  defp active_call?(call),
    do: call.ui_state in ["queued", "running", "retrying", "recovery_pending"]

  defp ui_state(%LemmingCall{status: "accepted"}, _successor_call_id), do: "queued"

  defp ui_state(
         %LemmingCall{status: "running", recovery_status: recovery_status},
         _successor_call_id
       )
       when is_binary(recovery_status),
       do: "recovery_pending"

  defp ui_state(%LemmingCall{status: "running"}, _successor_call_id), do: "running"

  defp ui_state(%LemmingCall{status: "needs_more_context"}, _successor_call_id),
    do: "recovery_pending"

  defp ui_state(%LemmingCall{status: "partial_result"}, _successor_call_id),
    do: "recovery_pending"

  defp ui_state(%LemmingCall{status: "completed"}, _successor_call_id), do: "completed"

  defp ui_state(%LemmingCall{status: "failed", recovery_status: "expired"}, _successor_call_id),
    do: "dead"

  defp ui_state(%LemmingCall{status: "failed"}, successor_call_id)
       when is_binary(successor_call_id),
       do: "retrying"

  defp ui_state(%LemmingCall{status: "failed"}, _successor_call_id), do: "failed"
  defp ui_state(%LemmingCall{}, _successor_call_id), do: "queued"

  defp ui_state_label("queued"), do: "Queued"
  defp ui_state_label("running"), do: "Running"
  defp ui_state_label("retrying"), do: "Retrying"
  defp ui_state_label("completed"), do: "Completed"
  defp ui_state_label("failed"), do: "Failed"
  defp ui_state_label("dead"), do: "Dead"
  defp ui_state_label("recovery_pending"), do: "Recovery pending"
  defp ui_state_label(state) when is_binary(state), do: String.capitalize(state)

  defp ui_state_tone("queued"), do: "warning"
  defp ui_state_tone("running"), do: "info"
  defp ui_state_tone("retrying"), do: "warning"
  defp ui_state_tone("completed"), do: "success"
  defp ui_state_tone("failed"), do: "danger"
  defp ui_state_tone("dead"), do: "danger"
  defp ui_state_tone("recovery_pending"), do: "warning"
  defp ui_state_tone(_state), do: "muted"

  defp state_copy(%LemmingCall{recovery_status: "direct_child_input"}, _ui_state),
    do: "Direct child input changed this delegated work."

  defp state_copy(%LemmingCall{status: "needs_more_context"}, _ui_state),
    do: "Child session requested more context."

  defp state_copy(%LemmingCall{status: "partial_result"}, _ui_state),
    do: "Child session reported a partial result."

  defp state_copy(%LemmingCall{status: "failed", recovery_status: "expired"}, _ui_state),
    do: "Child session expired before completion."

  defp state_copy(%LemmingCall{status: "failed"}, "retrying"),
    do: "A successor child session is retrying this task."

  defp state_copy(%LemmingCall{result_summary: summary}, _ui_state) when is_binary(summary),
    do: summary

  defp state_copy(%LemmingCall{error_summary: summary}, _ui_state) when is_binary(summary),
    do: summary

  defp state_copy(_call, _ui_state), do: nil

  defp relationship_copy(%LemmingCall{} = call) do
    "#{lemming_label(call.caller_lemming)} -> #{lemming_label(call.callee_lemming)}"
  end

  defp lemming_label(%Lemming{name: name}) when is_binary(name) and name != "", do: name
  defp lemming_label(%Lemming{slug: slug}) when is_binary(slug) and slug != "", do: slug
  defp lemming_label(_lemming), do: "Unknown lemming"

  defp lemming_role(%Lemming{collaboration_role: role}) when is_binary(role), do: role
  defp lemming_role(_lemming), do: "worker"

  defp department_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp department_name(_department), do: nil

  defp instance_path(instance_id, world_id)
       when is_binary(instance_id) and is_binary(world_id) do
    "/lemmings/instances/#{instance_id}?world=#{world_id}"
  end

  defp instance_path(_instance_id, _world_id), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    if Helpers.blank?(value), do: nil, else: value
  end

  defp blank_to_nil(value), do: value
end
