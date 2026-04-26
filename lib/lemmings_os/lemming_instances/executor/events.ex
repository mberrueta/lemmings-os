defmodule LemmingsOs.LemmingInstances.Executor.Events do
  @moduledoc """
  Lightweight runtime-event emitter for executor internals.

  These events are best-effort PubSub broadcasts intended for non-critical
  observers such as runtime traces and diagnostics.
  """

  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.Telemetry
  alias LemmingsOs.ModelRuntime.Response

  @doc """
  Emits a queue-enqueued runtime event for trace/diagnostic consumers.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> item = %{id: "item-1"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_queue_enqueued(state, item, 1)
      :ok
  """
  @spec emit_queue_enqueued(map(), map(), non_neg_integer()) :: :ok
  def emit_queue_enqueued(state, item, queue_depth) do
    emit(state, "runtime.queue.enqueued", %{
      item_id: Map.get(item, :id),
      queue_depth: queue_depth
    })
  end

  @doc """
  Emits a queue-dequeued runtime event for trace/diagnostic consumers.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> item = %{id: "item-1"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_queue_dequeued(state, item, 0)
      :ok
  """
  @spec emit_queue_dequeued(map(), map(), non_neg_integer()) :: :ok
  def emit_queue_dequeued(state, item, queue_depth) do
    emit(state, "runtime.queue.dequeued", %{
      item_id: Map.get(item, :id),
      queue_depth: queue_depth
    })
  end

  @doc """
  Emits a model-call-started runtime event.

  ## Examples

      iex> state = %{instance_id: "instance-1", phase: :action_selection, retry_count: 0}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_model_started(state, 1)
      :ok
  """
  @spec emit_model_started(map(), non_neg_integer()) :: :ok
  def emit_model_started(state, step_index) do
    emit(state, "runtime.model_call.started", %{
      step_index: step_index,
      phase: Map.get(state, :phase),
      retry_count: Map.get(state, :retry_count)
    })
  end

  @doc """
  Emits a model-call terminal runtime event (`completed` or `failed`).

  ## Examples

      iex> state = %{instance_id: "instance-1", model_step_count: 1, phase: :action_selection, now_fun: &DateTime.utc_now/0}
      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :reply,
      ...>     reply: "ok",
      ...>     provider: "fake",
      ...>     model: "test",
      ...>     raw: %{}
      ...>   )
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_model_finished(state, {:ok, response}, nil)
      :ok
  """
  @spec emit_model_finished(map(), term(), DateTime.t() | nil) :: :ok
  def emit_model_finished(state, result, started_at) do
    payload =
      %{
        step_index: Map.get(state, :model_step_count),
        phase: Map.get(state, :phase),
        duration_ms: duration_ms(state, started_at)
      }
      |> Map.merge(model_result_payload(result))

    emit(state, model_event(result), payload)
  end

  @doc """
  Emits a tool-call-started runtime event.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_tool_started(state, "web.fetch", %{"url" => "https://example.com"})
      :ok
  """
  @spec emit_tool_started(map(), String.t(), map()) :: :ok
  def emit_tool_started(state, tool_name, tool_args) do
    emit(state, "runtime.tool_call.started", %{
      tool_name: tool_name,
      args_keys: map_keys(tool_args)
    })
  end

  @doc """
  Emits a tool-call-completed runtime event.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> tool_execution = %{id: "tool-1", tool_name: "web.fetch", status: "ok", duration_ms: 12}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_tool_completed(state, tool_execution)
      :ok
  """
  @spec emit_tool_completed(map(), map()) :: :ok
  def emit_tool_completed(state, tool_execution) do
    emit(state, "runtime.tool_call.completed", %{
      tool_name: Map.get(tool_execution, :tool_name),
      tool_execution_id: Map.get(tool_execution, :id),
      status: Map.get(tool_execution, :status),
      duration_ms: Map.get(tool_execution, :duration_ms)
    })
  end

  @doc """
  Emits a tool-call-failed runtime event.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> tool_execution = %{id: "tool-1", tool_name: "web.fetch", status: "error", duration_ms: 12, error: %{code: "tool.web.request_failed"}}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_tool_failed(state, tool_execution)
      :ok
  """
  @spec emit_tool_failed(map(), map()) :: :ok
  def emit_tool_failed(state, tool_execution) do
    emit(state, "runtime.tool_call.failed", %{
      tool_name: Map.get(tool_execution, :tool_name),
      tool_execution_id: Map.get(tool_execution, :id),
      status: Map.get(tool_execution, :status),
      duration_ms: Map.get(tool_execution, :duration_ms),
      reason: tool_error_reason(Map.get(tool_execution, :error))
    })
  end

  @doc """
  Emits a resume-started runtime event for delegated child-call continuation.

  ## Examples

      iex> state = %{instance_id: "instance-1", status: "idle"}
      iex> call = %{id: "call-1", status: "completed"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_lemming_resume_started(state, call)
      :ok
  """
  @spec emit_lemming_resume_started(map(), map()) :: :ok
  def emit_lemming_resume_started(state, call) do
    emit(state, "runtime.lemming_call.resume.started", %{
      call_id: Map.get(call, :id),
      call_status: Map.get(call, :status),
      executor_status: Map.get(state, :status)
    })
  end

  @doc """
  Emits a resume-rejected runtime event with the normalized rejection reason.

  ## Examples

      iex> state = %{instance_id: "instance-1", status: "failed"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_lemming_resume_rejected(state, :terminal_instance)
      :ok
  """
  @spec emit_lemming_resume_rejected(map(), atom()) :: :ok
  def emit_lemming_resume_rejected(state, reason) when is_atom(reason) do
    emit(state, "runtime.lemming_call.resume.rejected", %{
      reason: Atom.to_string(reason),
      executor_status: Map.get(state, :status)
    })
  end

  @doc """
  Emits a resume-completed runtime event after processing restarts.

  ## Examples

      iex> state = %{instance_id: "instance-1", status: "processing", current_item: %{id: "item-1"}}
      iex> call = %{id: "call-1", status: "completed"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit_lemming_resume_completed(state, call)
      :ok
  """
  @spec emit_lemming_resume_completed(map(), map()) :: :ok
  def emit_lemming_resume_completed(state, call) do
    emit(state, "runtime.lemming_call.resume.completed", %{
      call_id: Map.get(call, :id),
      call_status: Map.get(call, :status),
      current_item_id: current_item_id(Map.get(state, :current_item)),
      executor_status: Map.get(state, :status)
    })
  end

  @doc """
  Emits a best-effort runtime event on the instance transcript PubSub topic.

  ## Examples

      iex> state = %{instance_id: "instance-1"}
      iex> LemmingsOs.LemmingInstances.Executor.Events.emit(state, "runtime.custom", %{key: "value"})
      :ok
  """
  @spec emit(map(), String.t(), map()) :: :ok
  def emit(state, event, payload \\ %{}) when is_binary(event) and is_map(payload) do
    _ = PubSub.broadcast_runtime_event(Map.get(state, :instance_id), event, payload)
    :ok
  end

  defp model_event({:ok, %Response{}}), do: "runtime.model_call.completed"
  defp model_event(_result), do: "runtime.model_call.failed"

  defp model_result_payload({:ok, %Response{} = response}) do
    %{
      status: "ok",
      action: response.action,
      provider: response.provider,
      model: response.model,
      total_tokens: response.total_tokens
    }
  end

  defp model_result_payload({:error, reason}) do
    %{status: "error", reason: Telemetry.reason_token(reason)}
  end

  defp model_result_payload(_result) do
    %{status: "error", reason: "unexpected_model_result"}
  end

  defp duration_ms(_state, nil), do: nil

  defp duration_ms(state, %DateTime{} = started_at) do
    state
    |> Map.fetch!(:now_fun)
    |> then(& &1.())
    |> DateTime.diff(started_at, :millisecond)
    |> max(0)
  end

  defp map_keys(args) when is_map(args),
    do: Map.keys(args) |> Enum.map(&to_string/1) |> Enum.sort()

  defp map_keys(_args), do: []

  defp tool_error_reason(%{"code" => code}) when is_binary(code), do: code
  defp tool_error_reason(%{code: code}) when is_binary(code), do: code
  defp tool_error_reason(_error), do: nil

  defp current_item_id(%{id: id}), do: id
  defp current_item_id(_item), do: nil
end
