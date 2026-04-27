defmodule LemmingsOs.LemmingInstances.Executor.Communication do
  @moduledoc """
  Multi-lemming communication helpers used by the executor runtime.

  This module centralizes lemming-call request shaping, optional module
  capability checks, and child-terminal synchronization decisions.
  """

  alias LemmingsOs.LemmingInstances.Executor.ContextMessages
  alias LemmingsOs.ModelRuntime.Response

  @type request_result ::
          {:ok, map(), map()}
          | {:error, :lemming_call_unavailable | {:lemming_call_failed, term()}}
  @type resume_rejection_reason :: :terminal_instance | :resume_not_possible
  @type resume_call_rejection_reason :: :child_call_not_terminal

  @doc """
  Builds request attributes expected by `LemmingCalls.request_call/3`.

  ## Examples

      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :lemming_call,
      ...>     lemming_target: "ops-worker",
      ...>     lemming_request: "Draft child notes",
      ...>     continue_call_id: nil,
      ...>     provider: "fake",
      ...>     model: "fake-model",
      ...>     raw: %{}
      ...>   )
      iex> LemmingsOs.LemmingInstances.Executor.Communication.lemming_call_attrs(response)
      %{target: "ops-worker", request: "Draft child notes", continue_call_id: nil}
  """
  @spec lemming_call_attrs(Response.t()) :: %{
          target: String.t() | nil,
          request: String.t() | nil,
          continue_call_id: Ecto.UUID.t() | String.t() | nil
        }
  def lemming_call_attrs(%Response{} = response) do
    %{
      target: response.lemming_target,
      request: response.lemming_request,
      continue_call_id: response.continue_call_id
    }
  end

  @doc """
  Requests a delegated child call when the calls module supports it.

  ## Examples

      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :lemming_call,
      ...>     lemming_target: "ops-worker",
      ...>     lemming_request: "Draft child notes",
      ...>     continue_call_id: nil,
      ...>     provider: "fake",
      ...>     model: "fake-model",
      ...>     raw: %{}
      ...>   )
      iex> LemmingsOs.LemmingInstances.Executor.Communication.request_call(nil, %{id: "instance-1"}, response)
      {:error, :lemming_call_unavailable}
  """
  @spec request_call(module() | nil, map(), Response.t(), keyword()) :: request_result()
  def request_call(lemming_calls_mod, instance, response, opts \\ [])

  def request_call(nil, _instance, _response, _opts), do: {:error, :lemming_call_unavailable}

  def request_call(lemming_calls_mod, instance, %Response{} = response, opts)
      when is_list(opts) do
    attrs = lemming_call_attrs(response)

    with true <- module_loaded_and_exports?(lemming_calls_mod, :request_call, 3),
         {:ok, call} <- lemming_calls_mod.request_call(instance, attrs, opts) do
      {:ok, attrs, call}
    else
      false -> {:error, :lemming_call_unavailable}
      {:error, reason} -> {:error, {:lemming_call_failed, reason}}
    end
  end

  @doc """
  Returns the rejection reason for resume-after-call requests, or `nil` when
  resuming is allowed.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_rejection_reason("failed", %{id: "item-1"}, nil)
      :terminal_instance
      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_rejection_reason("idle", nil, nil)
      :resume_not_possible
      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_rejection_reason("idle", %{id: "item-1"}, self())
      :resume_not_possible
      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_rejection_reason("idle", %{id: "item-1"}, nil)
      nil
  """
  @spec resume_rejection_reason(String.t(), map() | nil, pid() | nil) ::
          resume_rejection_reason() | nil
  def resume_rejection_reason(status, _current_item, _model_task_pid)
      when status in ["failed", "expired"],
      do: :terminal_instance

  def resume_rejection_reason(_status, nil, _model_task_pid), do: :resume_not_possible

  def resume_rejection_reason(_status, _current_item, model_task_pid) when is_pid(model_task_pid),
    do: :resume_not_possible

  def resume_rejection_reason(_status, _current_item, _model_task_pid), do: nil

  @doc """
  Returns `true` when a delegated call is terminal and safe to resume from.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.call_terminal?(%{status: "completed"})
      true
      iex> LemmingsOs.LemmingInstances.Executor.Communication.call_terminal?(%{status: "running"})
      false
  """
  @spec call_terminal?(map()) :: boolean()
  def call_terminal?(%{status: status}) when status in ["completed", "failed"], do: true
  def call_terminal?(_call), do: false

  @doc """
  Returns the rejection reason for a delegated call that is not yet terminal.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_call_rejection_reason(%{status: "running"})
      :child_call_not_terminal
      iex> LemmingsOs.LemmingInstances.Executor.Communication.resume_call_rejection_reason(%{status: "completed"})
      nil
  """
  @spec resume_call_rejection_reason(map()) :: resume_call_rejection_reason() | nil
  def resume_call_rejection_reason(call) when is_map(call) do
    if call_terminal?(call), do: nil, else: :child_call_not_terminal
  end

  @doc """
  Appends a delegated call-result context message to runtime history.

  ## Examples

      iex> messages = [%{role: "user", content: "Delegate this"}]
      iex> call = %{status: "completed", result_summary: "Done"}
      iex> updated = LemmingsOs.LemmingInstances.Executor.Communication.append_call_result_context(messages, call)
      iex> length(updated)
      2
      iex> String.contains?(List.last(updated).content, "Lemming call result:")
      true
  """
  @spec append_call_result_context([map()], map()) :: [map()]
  def append_call_result_context(context_messages, call)
      when is_list(context_messages) and is_map(call) do
    context_messages ++ [ContextMessages.lemming_call_result_message(call)]
  end

  @doc """
  Applies the standard state resets for resuming a paused manager execution.

  ## Examples

      iex> state = %{context_messages: [%{role: "user", content: "Delegate this"}], retry_count: 2, last_error: "boom", internal_error_details: %{kind: :model_timeout}}
      iex> call = %{status: "completed", result_summary: "Done"}
      iex> updated = LemmingsOs.LemmingInstances.Executor.Communication.prepare_state_for_resume(state, call)
      iex> {updated.retry_count, updated.last_error, updated.internal_error_details}
      {0, nil, nil}
      iex> length(updated.context_messages)
      2
  """
  @spec prepare_state_for_resume(map(), map()) :: map()
  def prepare_state_for_resume(state, call) when is_map(state) and is_map(call) do
    state
    |> Map.put(:context_messages, append_call_result_context(state.context_messages, call))
    |> Map.put(:retry_count, 0)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
  end

  @doc """
  Returns available delegated call targets for the current instance.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.available_targets(nil, %{id: "instance-1"})
      []
  """
  @spec available_targets(module() | nil, map()) :: list()
  def available_targets(lemming_calls_mod, instance) do
    if module_loaded_and_exports?(lemming_calls_mod, :available_targets, 1) do
      lemming_calls_mod.available_targets(instance)
    else
      []
    end
  end

  @doc """
  Merges delegated targets into a runtime config snapshot when present.

  ## Examples

      iex> config = %{model: "fake-model"}
      iex> LemmingsOs.LemmingInstances.Executor.Communication.put_targets_in_config(config, [])
      %{model: "fake-model"}
      iex> LemmingsOs.LemmingInstances.Executor.Communication.put_targets_in_config(config, [%{slug: "ops-worker"}])
      %{model: "fake-model", lemming_call_targets: [%{slug: "ops-worker"}]}
  """
  @spec put_targets_in_config(map(), list()) :: map()
  def put_targets_in_config(config_snapshot, []), do: config_snapshot

  def put_targets_in_config(config_snapshot, targets),
    do: Map.put(config_snapshot, :lemming_call_targets, targets)

  @doc """
  Returns true when a manager instance still has pending child calls.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.pending_manager_calls?(nil, %{id: "instance-1"})
      false
  """
  @spec pending_manager_calls?(module() | nil, map()) :: boolean()
  def pending_manager_calls?(lemming_calls_mod, instance) do
    if module_loaded_and_exports?(lemming_calls_mod, :list_manager_calls, 2) do
      case lemming_calls_mod.list_manager_calls(instance, statuses: pending_child_call_statuses()) do
        [] -> false
        [_ | _rest] -> true
      end
    else
      false
    end
  end

  @doc """
  Returns child statuses considered pending from the manager perspective.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.pending_child_call_statuses()
      ["accepted", "running", "needs_more_context", "partial_result"]
  """
  @spec pending_child_call_statuses() :: [String.t()]
  def pending_child_call_statuses,
    do: ["accepted", "running", "needs_more_context", "partial_result"]

  @doc """
  Computes terminal sync decision for child instances.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.child_terminal_sync_decision("idle", true)
      :skip
      iex> LemmingsOs.LemmingInstances.Executor.Communication.child_terminal_sync_decision("failed", true)
      :sync
  """
  @spec child_terminal_sync_decision(String.t(), boolean()) :: :sync | :skip
  def child_terminal_sync_decision("idle", true), do: :skip

  def child_terminal_sync_decision(status, _pending?)
      when status in ["idle", "failed", "expired"],
      do: :sync

  def child_terminal_sync_decision(_status, _pending?), do: :skip

  @doc """
  Builds sync attrs sent to `sync_child_instance_terminal/3`.

  ## Examples

      iex> messages = [%{role: "assistant", content: "Final child answer"}]
      iex> attrs =
      ...>   LemmingsOs.LemmingInstances.Executor.Communication.child_terminal_sync_attrs(
      ...>     "idle",
      ...>     messages,
      ...>     nil,
      ...>     ~U[2026-04-26 15:00:00Z]
      ...>   )
      iex> attrs.result_summary
      "Final child answer"
      iex> attrs.error_summary
      nil
      iex> attrs.completed_at
      ~U[2026-04-26 15:00:00Z]
  """
  @spec child_terminal_sync_attrs(String.t(), list(), String.t() | nil, DateTime.t()) :: map()
  def child_terminal_sync_attrs(status, context_messages, last_error, completed_at) do
    result_summary =
      case status do
        "idle" -> last_assistant_content(context_messages)
        _other -> nil
      end

    %{
      result_summary: result_summary,
      error_summary: last_error,
      completed_at: completed_at
    }
  end

  @doc """
  Synchronizes child instance terminal status when supported.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.Communication.sync_child_instance_terminal(nil, %{id: "instance-1"}, "idle", %{})
      :ok
  """
  @spec sync_child_instance_terminal(module() | nil, map(), String.t(), map()) :: :ok
  def sync_child_instance_terminal(lemming_calls_mod, instance, status, attrs) do
    if module_loaded_and_exports?(lemming_calls_mod, :sync_child_instance_terminal, 3) do
      _ = lemming_calls_mod.sync_child_instance_terminal(instance, status, attrs)
    end

    :ok
  end

  @doc """
  Finds the latest assistant message content from context history.

  ## Examples

      iex> messages = [%{role: "user", content: "hi"}, %{role: "assistant", content: "done"}]
      iex> LemmingsOs.LemmingInstances.Executor.Communication.last_assistant_content(messages)
      "done"
  """
  @spec last_assistant_content(list()) :: String.t() | nil
  def last_assistant_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "assistant", content: content} when is_binary(content) -> content
      %{role: :assistant, content: content} when is_binary(content) -> content
      _message -> nil
    end)
  end

  defp module_loaded_and_exports?(module, function_name, arity)
       when is_atom(module) and is_atom(function_name) and is_integer(arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function_name, arity)
  end

  defp module_loaded_and_exports?(_module, _function_name, _arity), do: false
end
