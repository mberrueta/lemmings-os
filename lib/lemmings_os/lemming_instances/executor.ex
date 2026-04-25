defmodule LemmingsOs.LemmingInstances.Executor do
  @moduledoc """
  Per-instance runtime executor.

  The executor owns the in-memory work queue and runtime state machine for a
  single `LemmingInstance`. It updates durable status transitions via the
  `LemmingsOs.LemmingInstances` context, publishes status changes via PubSub,
  and delegates model execution through an injectable runtime module.

  Test seams are opt-in keyword options passed to `start_link/1`:

  - `:model_mod` injects a controlled model runtime implementation
  - `:now_fun` injects a deterministic clock
  - `:idle_timeout_ms` overrides the idle expiration timer for deterministic tests
  """

  use GenServer

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.LemmingInstances.Executor.ContextMessages
  alias LemmingsOs.LemmingInstances.Executor.Events
  alias LemmingsOs.LemmingInstances.Executor.FinalizationPayload
  alias LemmingsOs.LemmingInstances.Executor.ModelStepPayload
  alias LemmingsOs.LemmingInstances.Executor.RuntimeStore
  alias LemmingsOs.LemmingInstances.Executor.ToolLifecycle
  alias LemmingsOs.LemmingInstances.Executor.TransitionsData
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.LemmingInstances.RuntimeTableOwner
  alias LemmingsOs.LemmingInstances.Telemetry
  alias LemmingsOs.LemmingCalls
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Tools.Runtime, as: ToolsRuntime
  alias LemmingsOs.Worlds.World

  @runtime_table :lemming_instance_runtime
  @default_max_retries 3
  @default_max_tool_iterations 8
  @default_model_timeout_ms 120_000
  @max_model_steps 40

  @statuses ~w(created queued processing retrying idle failed expired)
  @status_atoms Map.new(@statuses, &{&1, String.to_atom(&1)})

  @type work_item :: %{
          id: Ecto.UUID.t() | binary(),
          content: String.t(),
          origin: :user,
          inserted_at: DateTime.t()
        }

  @type finalization_context :: %{
          tool_name: String.t(),
          tool_status: String.t(),
          tool_result_payload: map(),
          original_goal: String.t(),
          completed_action: String.t() | nil,
          artifacts_created: [String.t()],
          remaining_work: [String.t()]
        }

  @type state :: %{
          instance_id: binary(),
          department_id: binary() | nil,
          instance: LemmingInstance.t() | map(),
          config_snapshot: map(),
          status: String.t(),
          queue: :queue.queue(),
          current_item: work_item() | nil,
          current_resource_key: String.t() | nil,
          retry_count: non_neg_integer(),
          max_retries: pos_integer(),
          context_messages: [map()],
          phase: :action_selection | :finalizing,
          finalization_context: finalization_context() | nil,
          finalization_repair_attempted?: boolean(),
          tool_iteration_count: non_neg_integer(),
          model_step_count: non_neg_integer(),
          model_steps: [map()],
          last_error: String.t() | nil,
          internal_error_details: map() | String.t() | nil,
          active_model_step: map() | nil,
          model_task_pid: pid() | nil,
          model_task_monitor_ref: reference() | nil,
          model_task_ref: reference() | nil,
          model_task_timeout_ref: reference() | nil,
          model_timeout_ms: pos_integer(),
          started_at: DateTime.t(),
          last_activity_at: DateTime.t(),
          idle_timer_ref: reference() | nil,
          idle_timer_token: reference() | nil,
          idle_timeout_ms: pos_integer() | nil,
          context_mod: module() | nil,
          ets_mod: module() | nil,
          dets_mod: module() | nil,
          pool_mod: module() | nil,
          model_mod: module() | nil,
          lemming_calls_mod: module() | nil,
          message_persist_mod: module() | nil,
          tools_context_mod: module() | nil,
          tool_runtime_mod: module() | nil,
          pubsub_mod: module() | nil,
          pubsub_name: atom(),
          load_context_messages?: boolean(),
          now_fun: (-> DateTime.t())
        }

  @doc """
  Returns the Registry name tuple for an executor process.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.via_name("instance-1")
      {:via, Registry, {LemmingsOs.LemmingInstances.ExecutorRegistry, "instance-1"}}
  """
  @spec via_name(binary()) :: {:via, Registry, {module(), binary()}}
  def via_name(instance_id) when is_binary(instance_id) do
    {:via, Registry, {LemmingsOs.LemmingInstances.ExecutorRegistry, instance_id}}
  end

  @doc """
  Starts an executor process for the given instance.

  Pass `name: nil` to skip registry-based naming (useful for tests).
  Pass `idle_timeout_ms: nil` to disable idle expiration in tests, or a small
  integer to force deterministic idle expiry without waiting on config-derived
  seconds.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   id: "instance-1",
      ...>   world_id: "world-1",
      ...>   city_id: "city-1",
      ...>   department_id: "dept-1",
      ...>   lemming_id: "lemming-1",
      ...>   status: "created",
      ...>   config_snapshot: %{}
      ...> }
      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.Executor.start_link(
      ...>     instance: instance,
      ...>     context_mod: nil,
      ...>     model_mod: nil,
      ...>     pubsub_mod: nil,
      ...>     dets_mod: nil,
      ...>     ets_mod: nil,
      ...>     name: nil
      ...>   )
      iex> is_pid(pid)
      true
      iex> GenServer.stop(pid)
      :ok
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    instance_id = resolve_instance_id(opts)

    genserver_opts =
      case Keyword.fetch(opts, :name) do
        {:ok, nil} -> []
        {:ok, name} -> [name: name]
        :error -> if(instance_id, do: [name: via_name(instance_id)], else: [])
      end

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  @doc """
  Builds a DynamicSupervisor-compatible child spec.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   id: "instance-5",
      ...>   world_id: "world-5",
      ...>   city_id: "city-5",
      ...>   department_id: "dept-5",
      ...>   lemming_id: "lemming-5",
      ...>   status: "created",
      ...>   config_snapshot: %{}
      ...> }
      iex> spec =
      ...>   LemmingsOs.LemmingInstances.Executor.child_spec(
      ...>     instance: instance,
      ...>     context_mod: nil,
      ...>     model_mod: nil,
      ...>     pubsub_mod: nil,
      ...>     dets_mod: nil,
      ...>     ets_mod: nil,
      ...>     name: nil
      ...>   )
      iex> {mod, _fun, _args} = spec.start
      iex> mod == LemmingsOs.LemmingInstances.Executor
      true
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    instance_id = resolve_instance_id(opts)

    %{
      id: if(instance_id, do: {__MODULE__, instance_id}, else: __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Enqueues a new work item for the instance.

  Returns `{:error, :empty_request_text}` when content is blank.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.enqueue_work("instance-1", " ")
      {:error, :empty_request_text}
  """
  @spec enqueue_work(GenServer.server() | binary(), String.t()) ::
          :ok | {:error, :empty_request_text | :executor_unavailable | :terminal_instance}
  def enqueue_work(server, content) when is_binary(content) do
    if Helpers.blank?(content) do
      {:error, :empty_request_text}
    else
      safe_call(normalize_server(server), {:enqueue_work, content})
    end
  end

  @doc """
  Requeues a persisted pending user message without duplicating transcript
  context already loaded into memory.
  """
  @spec resume_pending(GenServer.server() | binary(), String.t()) ::
          :ok | {:error, :empty_request_text | :executor_unavailable | :terminal_instance}
  def resume_pending(server, content) when is_binary(content) do
    if Helpers.blank?(content) do
      {:error, :empty_request_text}
    else
      safe_call(normalize_server(server), {:resume_pending, content})
    end
  end

  @doc """
  Resumes a paused manager item after a delegated child call reaches terminal state.
  """
  @spec resume_after_lemming_call(GenServer.server() | binary(), map()) ::
          :ok | {:error, :executor_unavailable | :terminal_instance | :resume_not_possible}
  def resume_after_lemming_call(server, call) when is_map(call) do
    safe_call(normalize_server(server), {:resume_after_lemming_call, call})
  end

  @doc """
  Retries the current failed work item by moving it back into the queue.
  """
  @spec retry(GenServer.server() | binary()) :: :ok
  def retry(server) do
    GenServer.cast(normalize_server(server), :retry_failed)
  end

  @doc """
  Returns the current executor status snapshot.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   id: "instance-2",
      ...>   world_id: "world-2",
      ...>   city_id: "city-2",
      ...>   department_id: "dept-2",
      ...>   lemming_id: "lemming-2",
      ...>   status: "created",
      ...>   config_snapshot: %{}
      ...> }
      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.Executor.start_link(
      ...>     instance: instance,
      ...>     context_mod: nil,
      ...>     model_mod: nil,
      ...>     pubsub_mod: nil,
      ...>     dets_mod: nil,
      ...>     ets_mod: nil,
      ...>     name: nil
      ...>   )
      iex> %{status: "created", queue_depth: 0} =
      ...>   LemmingsOs.LemmingInstances.Executor.status(pid)
      iex> GenServer.stop(pid)
      :ok
  """
  @spec status(GenServer.server() | binary()) :: %{
          status: String.t(),
          retry_count: non_neg_integer(),
          max_retries: pos_integer(),
          queue_depth: non_neg_integer()
        }
  def status(server) do
    GenServer.call(normalize_server(server), :status)
  end

  @doc """
  Returns an operator-facing snapshot for runtime inspection.
  """
  @spec snapshot(GenServer.server() | binary()) :: map()
  def snapshot(server) do
    GenServer.call(normalize_server(server), :snapshot)
  end

  @doc """
  Returns the depth of the in-memory queue.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   id: "instance-3",
      ...>   world_id: "world-3",
      ...>   city_id: "city-3",
      ...>   department_id: "dept-3",
      ...>   lemming_id: "lemming-3",
      ...>   status: "created",
      ...>   config_snapshot: %{}
      ...> }
      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.Executor.start_link(
      ...>     instance: instance,
      ...>     context_mod: nil,
      ...>     model_mod: nil,
      ...>     pubsub_mod: nil,
      ...>     dets_mod: nil,
      ...>     ets_mod: nil,
      ...>     name: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.Executor.queue_depth(pid)
      0
      iex> GenServer.stop(pid)
      :ok
  """
  @spec queue_depth(GenServer.server() | binary()) :: non_neg_integer()
  def queue_depth(server) do
    GenServer.call(normalize_server(server), :queue_depth)
  end

  @doc """
  Handles scheduler admission for the next queued work item.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   id: "instance-4",
      ...>   world_id: "world-4",
      ...>   city_id: "city-4",
      ...>   department_id: "dept-4",
      ...>   lemming_id: "lemming-4",
      ...>   status: "created",
      ...>   config_snapshot: %{}
      ...> }
      iex> {:ok, pid} =
      ...>   LemmingsOs.LemmingInstances.Executor.start_link(
      ...>     instance: instance,
      ...>     context_mod: nil,
      ...>     model_mod: nil,
      ...>     pubsub_mod: nil,
      ...>     dets_mod: nil,
      ...>     ets_mod: nil,
      ...>     name: nil
      ...>   )
      iex> LemmingsOs.LemmingInstances.Executor.admit(pid)
      :ok
      iex> GenServer.stop(pid)
      :ok
  """
  @spec admit(GenServer.server() | binary()) :: :ok
  def admit(server) do
    GenServer.cast(normalize_server(server), :admit)
  end

  @impl true
  def init(opts) do
    instance = Keyword.get(opts, :instance, %{})
    instance_id = resolve_instance_id(opts)

    if is_nil(instance_id) do
      {:stop, :missing_instance_id}
    else
      config_snapshot = Keyword.get(opts, :config_snapshot, instance_config_snapshot(instance))
      status = instance_status(instance)
      now_fun = Keyword.get(opts, :now_fun, &DateTime.utc_now/0)
      now = now_fun.()

      state = %{
        instance_id: instance_id,
        department_id: instance_department_id(instance),
        instance: instance,
        config_snapshot: config_snapshot || %{},
        status: status,
        queue: :queue.new(),
        current_item: nil,
        current_resource_key: nil,
        retry_count: 0,
        max_retries: max_retries(config_snapshot),
        context_messages: [],
        phase: :action_selection,
        finalization_context: nil,
        finalization_repair_attempted?: false,
        tool_iteration_count: 0,
        model_step_count: 0,
        model_steps: [],
        last_error: nil,
        internal_error_details: nil,
        active_model_step: nil,
        model_task_pid: nil,
        model_task_monitor_ref: nil,
        model_task_ref: nil,
        model_task_timeout_ref: nil,
        model_timeout_ms: Keyword.get(opts, :model_timeout_ms, model_timeout_ms(config_snapshot)),
        started_at: now,
        last_activity_at: now,
        idle_timer_ref: nil,
        idle_timer_token: nil,
        idle_timeout_ms: idle_timeout_ms(opts, config_snapshot),
        context_mod: Keyword.get(opts, :context_mod, LemmingsOs.LemmingInstances),
        load_context_messages?: Keyword.get(opts, :load_context_messages, true),
        ets_mod: Keyword.get(opts, :ets_mod),
        dets_mod: Keyword.get(opts, :dets_mod),
        pool_mod: Keyword.get(opts, :pool_mod, ResourcePool),
        model_mod: Keyword.get(opts, :model_mod, LemmingsOs.ModelRuntime),
        lemming_calls_mod: Keyword.get(opts, :lemming_calls_mod, LemmingCalls),
        message_persist_mod: Keyword.get(opts, :message_persist_mod),
        tools_context_mod: Keyword.get(opts, :tools_context_mod, LemmingTools),
        tool_runtime_mod: Keyword.get(opts, :tool_runtime_mod, ToolsRuntime),
        pubsub_mod: Keyword.get(opts, :pubsub_mod, Phoenix.PubSub),
        pubsub_name: Keyword.get(opts, :pubsub_name, LemmingsOs.PubSub),
        now_fun: now_fun
      }

      case ensure_runtime_table() do
        :ok ->
          state =
            state
            |> maybe_load_context_messages()
            |> persist_started_at()
            |> put_runtime_state()
            |> subscribe_scheduler()
            |> maybe_start_idle_timer_on_init()

          Logger.info("executor started",
            event: "instance.executor.started",
            instance_id: state.instance_id,
            lemming_id: instance_lemming_id(state.instance),
            world_id: instance_world_id(state.instance),
            city_id: instance_city_id(state.instance),
            department_id: state.department_id,
            status: state.status,
            queue_depth: :queue.len(state.queue),
            retry_count: state.retry_count,
            max_retries: state.max_retries,
            current_item_id: current_item_id(state.current_item)
          )

          _ =
            Telemetry.execute(
              [:lemmings_os, :instance, :started],
              %{count: 1},
              Telemetry.instance_metadata(state.instance, %{
                instance_id: state.instance_id,
                status: state.status,
                queue_depth: :queue.len(state.queue),
                retry_count: state.retry_count,
                max_retries: state.max_retries
              })
            )

          _ =
            ActivityLog.record(:runtime, "executor", "Executor started", %{
              instance_id: state.instance_id,
              department_id: state.department_id,
              status: state.status
            })

          {:ok, state}

        {:error, reason} ->
          {:stop, {:runtime_table_unavailable, reason}}
      end
    end
  end

  @impl true
  def handle_call({:enqueue_work, content}, _from, state) do
    {reply, next_state} = enqueue_work_item(state, content, append_to_context?: true)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call({:resume_pending, content}, _from, state) do
    {reply, next_state} = enqueue_work_item(state, content, append_to_context?: false)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call({:resume_after_lemming_call, call}, _from, state) do
    {reply, next_state} = resume_after_lemming_call_result(state, call)
    {:reply, reply, next_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    snapshot = %{
      status: state.status,
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      tool_iteration_count: state.tool_iteration_count,
      model_step_count: state.model_step_count,
      queue_depth: :queue.len(state.queue),
      last_error: state.last_error,
      internal_error_details: state.internal_error_details
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      instance_id: state.instance_id,
      department_id: state.department_id,
      world_id: instance_world_id(state.instance),
      city_id: instance_city_id(state.instance),
      lemming_id: instance_lemming_id(state.instance),
      status: state.status,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      tool_iteration_count: state.tool_iteration_count,
      model_step_count: state.model_step_count,
      current_item_id: current_item_id(state.current_item),
      resource_key:
        state.current_resource_key || ConfigSnapshot.resource_key(state.config_snapshot),
      current_resource_key: state.current_resource_key,
      model_steps: state.model_steps,
      last_error: state.last_error,
      internal_error_details: state.internal_error_details,
      started_at: state.started_at,
      last_activity_at: state.last_activity_at
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:queue_depth, _from, state) do
    {:reply, :queue.len(state.queue), state}
  end

  @impl true
  def handle_cast({:enqueue_work, content}, state) do
    {_reply, next_state} = enqueue_work_item(state, content, append_to_context?: true)
    {:noreply, next_state}
  end

  @impl true
  def handle_cast({:resume_pending, content}, state) do
    {_reply, next_state} = enqueue_work_item(state, content, append_to_context?: false)
    {:noreply, next_state}
  end

  @impl true
  def handle_cast(:retry_failed, state) do
    {:noreply, retry_failed(state)}
  end

  @impl true
  def handle_cast(:admit, state) do
    {:noreply, maybe_start_processing(state)}
  end

  @impl true
  def handle_info({:scheduler_admit, payload}, state) do
    instance_id =
      case payload do
        %{instance_id: instance_id} -> instance_id
        instance_id when is_binary(instance_id) -> instance_id
        _ -> nil
      end

    resource_key =
      case payload do
        %{resource_key: resource_key} when is_binary(resource_key) -> resource_key
        _ -> nil
      end

    {:noreply, maybe_start_processing_for(instance_id, resource_key, state)}
  end

  @impl true
  def handle_info({:work_available, _payload}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:capacity_released, _payload}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:retry, state) do
    {:noreply, maybe_restart_retry(state)}
  end

  @impl true
  def handle_info({:model_result, instance_id, model_task_ref, started_at, result}, state) do
    if instance_id == state.instance_id and model_task_ref == state.model_task_ref do
      _ = Events.emit_model_finished(state, result, started_at)

      state =
        state
        |> clear_model_task_tracking()
        |> finalize_model_step(result, started_at)
        |> handle_model_result(result)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:model_timeout, model_task_ref}, state) do
    if model_task_ref == state.model_task_ref do
      _ = Events.emit_model_finished(state, {:error, :model_timeout}, nil)

      state =
        state
        |> terminate_model_task()
        |> clear_model_task_tracking()
        |> finalize_model_step({:error, :model_timeout})
        |> handle_model_retry(:model_timeout)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    if monitor_ref == state.model_task_monitor_ref do
      state = clear_model_task_tracking(state)

      next_state =
        case reason do
          :normal ->
            state

          :killed ->
            state

          :shutdown ->
            _ = Events.emit_model_finished(state, {:error, :model_crash}, nil)
            handle_model_retry(state, :model_crash)

          {:shutdown, _details} ->
            _ = Events.emit_model_finished(state, {:error, :model_crash}, nil)
            handle_model_retry(state, :model_crash)

          _ ->
            _ = Events.emit_model_finished(state, {:error, :model_crash}, nil)
            handle_model_retry(state, :model_crash)
        end

      {:noreply, next_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:idle_timeout, timer_ref}, state) do
    if state.idle_timer_token == timer_ref do
      state
      |> expire_instance()
      |> then(&{:stop, :normal, &1})
    else
      {:noreply, state}
    end
  end

  defp maybe_start_processing_for(instance_id, resource_key, state) do
    if instance_id == state.instance_id do
      state
      |> maybe_store_resource_key(resource_key)
      |> maybe_start_processing()
    else
      state
    end
  end

  defp maybe_start_processing(%{status: "queued"} = state) do
    if state.current_item || :queue.is_empty(state.queue) do
      state
    else
      {{:value, item}, queue} = :queue.out(state.queue)

      state =
        state
        |> cancel_idle_timer()
        |> Map.put(:queue, queue)
        |> Map.put(:current_item, item)
        |> Map.put(:phase, :action_selection)
        |> Map.put(:finalization_context, nil)
        |> Map.put(:finalization_repair_attempted?, false)
        |> Map.put(:retry_count, 0)
        |> transition_to("processing")
        |> put_runtime_state()

      _ = Events.emit_queue_dequeued(state, item, :queue.len(queue))

      start_execution(state)
    end
  end

  defp maybe_start_processing(state), do: state

  defp maybe_restart_retry(%{status: "retrying"} = state) do
    state
    |> transition_to("processing")
    |> put_runtime_state()
    |> start_execution()
  end

  defp maybe_restart_retry(state), do: state

  defp retry_failed(%{status: "failed"} = state) do
    queue =
      case state.current_item do
        nil -> state.queue
        current_item -> :queue.in_r(current_item, state.queue)
      end

    if :queue.is_empty(queue) do
      state
    else
      state
      |> Map.put(:queue, queue)
      |> Map.put(:current_item, nil)
      |> Map.put(:current_resource_key, nil)
      |> Map.put(:phase, :action_selection)
      |> Map.put(:finalization_context, nil)
      |> Map.put(:finalization_repair_attempted?, false)
      |> Map.put(:retry_count, 0)
      |> Map.put(:last_error, nil)
      |> Map.put(:internal_error_details, nil)
      |> transition_to("queued", %{stopped_at: nil})
      |> put_runtime_state()
      |> notify_scheduler()
    end
  end

  defp retry_failed(state), do: state

  defp handle_model_result(
         state,
         {:ok, %LemmingsOs.ModelRuntime.Response{action: :reply} = response}
       ) do
    case maybe_repair_empty_final_response(state, response) do
      {:repair, next_state} ->
        next_state
        |> clear_active_model_step()
        |> start_execution()

      :continue ->
        finalize_model_reply(state, response)
    end
  end

  defp handle_model_result(
         %{phase: :finalizing} = state,
         {:ok, %LemmingsOs.ModelRuntime.Response{action: :tool_call}}
       ) do
    state
    |> clear_active_model_step()
    |> maybe_repair_finalization(:unexpected_tool_call_during_finalization)
  end

  defp handle_model_result(
         state,
         {:ok, %LemmingsOs.ModelRuntime.Response{action: :tool_call} = response}
       ) do
    state =
      state
      |> Map.put(:last_error, nil)
      |> Map.put(:internal_error_details, nil)

    case execute_tool_call(state, response) do
      {:ok, next_state, _tool_execution} ->
        next_state
        |> clear_active_model_step()
        |> continue_after_tool_outcome()

      {:error, reason, next_state} ->
        next_state
        |> clear_active_model_step()
        |> handle_model_retry(reason)
    end
  end

  defp handle_model_result(
         state,
         {:ok, %LemmingsOs.ModelRuntime.Response{action: :lemming_call} = response}
       ) do
    state =
      state
      |> Map.put(:last_error, nil)
      |> Map.put(:internal_error_details, nil)

    case execute_lemming_call(state, response) do
      {:ok, next_state, _call} ->
        next_state
        |> clear_active_model_step()
        |> continue_after_lemming_call()

      {:error, reason, next_state} ->
        next_state
        |> clear_active_model_step()
        |> handle_model_retry(reason)
    end
  end

  defp handle_model_result(state, {:ok, _response}) do
    state
    |> clear_active_model_step()
    |> handle_model_retry(:invalid_provider_response)
  end

  defp handle_model_result(state, {:error, reason}) do
    state
    |> clear_active_model_step()
    |> maybe_repair_finalization(reason)
  end

  defp handle_model_result(state, _unexpected) do
    state
    |> clear_active_model_step()
    |> handle_model_retry(:unexpected_model_result)
  end

  defp handle_model_retry(state, reason) do
    next_retry = state.retry_count + 1
    error_message = TransitionsData.last_error_message(reason)
    internal_error_details = TransitionsData.internal_error_details(reason)

    if next_retry >= state.max_retries do
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> Map.put(:internal_error_details, internal_error_details)
      |> release_resource()
      |> cleanup_snapshot()
      |> transition_to("failed", %{stopped_at: state.now_fun.()})
      |> put_runtime_state()
    else
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> Map.put(:internal_error_details, internal_error_details)
      |> transition_to("retrying")
      |> put_runtime_state()
      |> schedule_retry()
    end
  end

  defp execute_tool_call(
         state,
         %LemmingsOs.ModelRuntime.Response{tool_name: tool_name, tool_args: tool_args}
       )
       when is_binary(tool_name) and is_map(tool_args) do
    started_at = state.now_fun.()
    _ = Events.emit_tool_started(state, tool_name, tool_args)
    state = append_tool_call_context(state, tool_name, tool_args)

    with {:ok, tool_execution, state} <-
           create_tool_execution(state, tool_name, tool_args, started_at),
         {:ok, world} <- runtime_world(state) do
      state
      |> persist_tool_outcome(
        tool_execution,
        execute_tool_runtime(state, world, tool_name, tool_args),
        started_at
      )
      |> normalize_tool_outcome_result()
    else
      {:error, reason, next_state} ->
        {:error, reason, next_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp execute_tool_call(state, _response), do: {:error, :invalid_structured_output, state}

  defp execute_lemming_call(
         %{lemming_calls_mod: nil} = state,
         _response
       ) do
    {:error, :lemming_call_unavailable, state}
  end

  defp execute_lemming_call(
         %{lemming_calls_mod: lemming_calls_mod} = state,
         %LemmingsOs.ModelRuntime.Response{} = response
       ) do
    attrs = %{
      target: response.lemming_target,
      request: response.lemming_request,
      continue_call_id: response.continue_call_id
    }

    state = append_lemming_call_context(state, attrs)

    with true <- module_loaded_and_exports?(lemming_calls_mod, :request_call, 3),
         {:ok, call} <-
           lemming_calls_mod.request_call(instance_with_runtime_snapshot(state), attrs, []) do
      {:ok, state, call}
    else
      false -> {:error, :lemming_call_unavailable, state}
      {:error, reason} -> {:error, {:lemming_call_failed, reason}, state}
    end
  end

  defp continue_after_lemming_call(state) do
    state
    |> release_resource()
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> put_runtime_state()
    |> transition_to("idle", %{stopped_at: nil})
    |> put_runtime_state()
  end

  defp resume_after_lemming_call_result(state, call) do
    cond do
      terminal_status?(state.status) ->
        {{:error, :terminal_instance}, state}

      is_nil(state.current_item) ->
        {{:error, :resume_not_possible}, state}

      not is_nil(state.model_task_pid) ->
        {{:error, :resume_not_possible}, state}

      true ->
        next_state =
          state
          |> append_lemming_call_result_context(call)
          |> Map.put(:retry_count, 0)
          |> Map.put(:last_error, nil)
          |> Map.put(:internal_error_details, nil)
          |> cancel_idle_timer()
          |> transition_to("processing", %{stopped_at: nil})
          |> put_runtime_state()
          |> start_execution()

        {:ok, next_state}
    end
  end

  defp persist_tool_outcome(state, tool_execution, {:ok, execution_result}, started_at) do
    persist_tool_success(state, tool_execution, execution_result, started_at)
  end

  defp persist_tool_outcome(state, tool_execution, {:error, execution_error}, started_at) do
    persist_tool_error(state, tool_execution, execution_error, started_at)
  end

  defp normalize_tool_outcome_result({:ok, updated_tool_execution, next_state}) do
    {:ok, append_tool_result_context(next_state, updated_tool_execution), updated_tool_execution}
  end

  defp normalize_tool_outcome_result({:error, reason, next_state}) do
    {:error, reason, next_state}
  end

  defp continue_after_tool_outcome(state) do
    case state.finalization_context do
      %{tool_status: "ok"} -> start_finalization_phase(state)
      _finalization_context -> continue_tool_loop(state)
    end
  end

  defp continue_tool_loop(state) do
    next_iteration_count = state.tool_iteration_count + 1
    continue_tool_loop(state, next_iteration_count)
  end

  defp finalize_model_reply(state, response) do
    state =
      state
      |> Map.put(:last_error, nil)
      |> Map.put(:internal_error_details, nil)

    case persist_assistant_message(state, response) do
      {:ok, next_state} ->
        next_state
        |> clear_active_model_step()
        |> clear_current_item()
        |> advance_after_success()

      {:error, reason, next_state} ->
        handle_model_retry(next_state, {:assistant_message_persist_failed, reason})
    end
  end

  defp maybe_repair_empty_final_response(state, response) do
    if state.phase == :finalizing and blank_reply?(response.reply) and
         not state.finalization_repair_attempted? do
      {:repair, schedule_finalization_repair(state, :empty_final_response)}
    else
      :continue
    end
  end

  defp maybe_repair_finalization(%{phase: :finalizing} = state, reason) do
    cond do
      repairable_finalization_reason?(reason) and not state.finalization_repair_attempted? ->
        state
        |> schedule_finalization_repair(reason)
        |> start_execution()

      repairable_finalization_reason?(reason) ->
        fail_without_retry(state, reason)

      true ->
        handle_model_retry(state, reason)
    end
  end

  defp maybe_repair_finalization(state, reason), do: handle_model_retry(state, reason)

  defp schedule_finalization_repair(state, reason) do
    state
    |> Map.put(:finalization_repair_attempted?, true)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> put_in([:finalization_context, :repair_reason], inspect(reason))
    |> put_runtime_state()
  end

  defp start_finalization_phase(state) do
    next_iteration_count = state.tool_iteration_count + 1

    state
    |> Map.put(:phase, :finalizing)
    |> Map.put(:tool_iteration_count, next_iteration_count)
    |> Map.put(:retry_count, 0)
    |> Map.put(:last_error, nil)
    |> Map.put(:internal_error_details, nil)
    |> put_runtime_state()
    |> start_execution()
  end

  defp fail_without_retry(state, reason) do
    state
    |> Map.put(:retry_count, state.max_retries)
    |> Map.put(:last_error, TransitionsData.last_error_message(reason))
    |> Map.put(:internal_error_details, TransitionsData.internal_error_details(reason))
    |> release_resource()
    |> cleanup_snapshot()
    |> transition_to("failed", %{stopped_at: state.now_fun.()})
    |> put_runtime_state()
  end

  defp repairable_finalization_reason?({:invalid_structured_output, _metadata}), do: true
  defp repairable_finalization_reason?(:invalid_structured_output), do: true
  defp repairable_finalization_reason?({:unknown_action, _metadata}), do: true
  defp repairable_finalization_reason?(:unknown_action), do: true
  defp repairable_finalization_reason?(:provider_error), do: true
  defp repairable_finalization_reason?(:invalid_provider_response), do: true
  defp repairable_finalization_reason?(:unexpected_tool_call_during_finalization), do: true
  defp repairable_finalization_reason?(_reason), do: false

  defp blank_reply?(reply) when is_binary(reply), do: Helpers.blank?(reply)
  defp blank_reply?(_reply), do: true

  defp continue_tool_loop(state, next_iteration_count) do
    if next_iteration_count >= max_tool_iterations(state.config_snapshot) do
      handle_model_retry(
        %{state | tool_iteration_count: next_iteration_count},
        :tool_iteration_limit_reached
      )
    else
      state
      |> Map.put(:tool_iteration_count, next_iteration_count)
      |> put_runtime_state()
      |> start_execution()
    end
  end

  defp create_tool_execution(
         %{tools_context_mod: nil} = state,
         _tool_name,
         _tool_args,
         _started_at
       ) do
    {:error, :tool_execution_unavailable, state}
  end

  defp create_tool_execution(
         %{tools_context_mod: tools_context} = state,
         tool_name,
         tool_args,
         started_at
       ) do
    tool_attrs = %{
      tool_name: tool_name,
      status: "running",
      args: tool_args,
      started_at: started_at
    }

    with true <- module_loaded_and_exports?(tools_context, :create_tool_execution, 3),
         {:ok, tool_execution} <-
           tools_context.create_tool_execution(
             runtime_world_struct(state),
             state.instance,
             tool_attrs
           ) do
      state = maybe_attach_tool_execution_to_model_step(state, tool_execution)

      log_tool_lifecycle(state, :started, tool_execution)
      emit_tool_telemetry(state, :started, tool_execution)
      record_tool_activity(:runtime, state, :started, tool_execution)

      _ =
        PubSub.broadcast_tool_execution_upserted(
          state.instance_id,
          tool_execution.id,
          tool_execution.status
        )

      {:ok, tool_execution, state}
    else
      false ->
        {:error, :tool_execution_unavailable, state}

      {:error, reason} ->
        {:error, {:tool_execution_create_failed, reason}, state}
    end
  end

  defp execute_tool_runtime(state, world, tool_name, tool_args) do
    tool_runtime_mod = state.tool_runtime_mod

    execute_tool_runtime(tool_runtime_mod, state, world, tool_name, tool_args)
  end

  defp execute_tool_runtime(tool_runtime_mod, state, world, tool_name, tool_args) do
    case module_loaded_and_exports?(tool_runtime_mod, :execute, 4) do
      true ->
        tool_runtime_mod.execute(world, state.instance, tool_name, tool_args)

      false ->
        {:error,
         %{
           tool_name: tool_name,
           code: "tool.runtime.unavailable",
           message: "Tool runtime is unavailable",
           details: %{}
         }}
    end
  end

  defp persist_tool_success(state, tool_execution, execution_result, started_at) do
    completed_at = state.now_fun.()
    duration_ms = DateTime.diff(completed_at, started_at, :millisecond)

    attrs = %{
      status: "ok",
      result: execution_result.result,
      summary: execution_result.summary,
      preview: execution_result.preview,
      completed_at: completed_at,
      duration_ms: max(duration_ms, 0)
    }

    case update_tool_execution(state, tool_execution, attrs) do
      {:ok, updated_tool_execution, next_state} ->
        _ = Events.emit_tool_completed(next_state, updated_tool_execution)
        log_tool_lifecycle(next_state, :completed, updated_tool_execution)
        emit_tool_telemetry(next_state, :completed, updated_tool_execution)
        record_tool_activity(:runtime, next_state, :completed, updated_tool_execution)
        {:ok, updated_tool_execution, next_state}

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  defp persist_tool_error(state, tool_execution, execution_error, started_at) do
    normalized_error = ToolLifecycle.normalize_tool_error(execution_error)
    completed_at = state.now_fun.()
    duration_ms = DateTime.diff(completed_at, started_at, :millisecond)

    attrs = %{
      status: "error",
      error: %{
        code: normalized_error.code,
        message: normalized_error.message,
        details: normalized_error.details
      },
      summary: normalized_error.message,
      completed_at: completed_at,
      duration_ms: max(duration_ms, 0)
    }

    case update_tool_execution(state, tool_execution, attrs) do
      {:ok, updated_tool_execution, next_state} ->
        _ = Events.emit_tool_failed(next_state, updated_tool_execution)
        log_tool_lifecycle(next_state, :failed, updated_tool_execution)
        emit_tool_telemetry(next_state, :failed, updated_tool_execution)
        record_tool_activity(:error, next_state, :failed, updated_tool_execution)
        {:ok, updated_tool_execution, next_state}

      {:error, reason, next_state} ->
        {:error, reason, next_state}
    end
  end

  defp update_tool_execution(%{tools_context_mod: nil} = state, _tool_execution, _attrs) do
    {:error, :tool_execution_unavailable, state}
  end

  defp update_tool_execution(
         %{tools_context_mod: tools_context} = state,
         tool_execution,
         attrs
       ) do
    with true <- module_loaded_and_exports?(tools_context, :update_tool_execution, 4),
         {:ok, updated_tool_execution} <-
           tools_context.update_tool_execution(
             runtime_world_struct(state),
             state.instance,
             tool_execution,
             attrs
           ) do
      _ =
        PubSub.broadcast_tool_execution_upserted(
          state.instance_id,
          updated_tool_execution.id,
          updated_tool_execution.status
        )

      {:ok, updated_tool_execution, state}
    else
      false ->
        {:error, :tool_execution_unavailable, state}

      {:error, reason} ->
        {:error, {:tool_execution_update_failed, reason}, state}
    end
  end

  defp create_model_step(state, attrs) do
    model_step = attrs

    state = %{
      state
      | model_steps: append_capped_model_step(state.model_steps, model_step),
        active_model_step: model_step
    }

    _ =
      PubSub.broadcast_model_step_upserted(
        state.instance_id,
        Integer.to_string(model_step.step_index),
        model_step.status
      )

    {:ok, state}
  end

  defp update_model_step(%{active_model_step: nil} = state, _attrs), do: state

  defp update_model_step(%{active_model_step: active_model_step} = state, attrs) do
    updated_model_step =
      active_model_step
      |> Map.merge(attrs)

    model_steps =
      Enum.map(state.model_steps, fn
        %{step_index: step_index} when step_index == updated_model_step.step_index ->
          updated_model_step

        model_step ->
          model_step
      end)

    _ =
      PubSub.broadcast_model_step_upserted(
        state.instance_id,
        Integer.to_string(updated_model_step.step_index),
        updated_model_step.status
      )

    %{state | model_steps: model_steps, active_model_step: updated_model_step}
  end

  defp maybe_attach_tool_execution_to_model_step(
         %{active_model_step: nil} = state,
         _tool_execution
       ),
       do: state

  defp maybe_attach_tool_execution_to_model_step(
         state,
         tool_execution
       ) do
    update_model_step(state, %{tool_execution_id: tool_execution.id})
  end

  defp clear_active_model_step(state), do: %{state | active_model_step: nil}

  defp append_capped_model_step(model_steps, model_step) do
    model_steps
    |> Kernel.++([model_step])
    |> Enum.take(-@max_model_steps)
  end

  defp append_tool_call_context(state, tool_name, tool_args) do
    tool_call_message = ContextMessages.tool_call_message(tool_name, tool_args)

    %{state | context_messages: state.context_messages ++ [tool_call_message]}
  end

  defp append_lemming_call_context(state, attrs) do
    lemming_call_message = ContextMessages.lemming_call_message(attrs)

    %{state | context_messages: state.context_messages ++ [lemming_call_message]}
  end

  defp append_lemming_call_result_context(state, call) do
    lemming_call_message = ContextMessages.lemming_call_result_message(call)

    %{state | context_messages: state.context_messages ++ [lemming_call_message]}
  end

  defp append_tool_result_context(state, tool_execution) do
    tool_payload = FinalizationPayload.tool_result_payload(tool_execution)
    tool_message = ContextMessages.tool_result_message(tool_execution, tool_payload)

    %{
      state
      | context_messages: state.context_messages ++ [tool_message],
        finalization_context:
          FinalizationPayload.build_finalization_context(
            state.current_item.content,
            tool_execution,
            tool_payload
          ),
        finalization_repair_attempted?: false
    }
  end

  defp log_tool_lifecycle(state, phase, tool_execution),
    do: ToolLifecycle.log_tool_lifecycle(state, phase, tool_execution)

  defp emit_tool_telemetry(state, phase, tool_execution),
    do: ToolLifecycle.emit_tool_telemetry(state, phase, tool_execution)

  defp record_tool_activity(type, state, phase, tool_execution),
    do: ToolLifecycle.record_tool_activity(type, state, phase, tool_execution)

  defp module_loaded_and_exports?(module, function_name, arity)
       when is_atom(module) and is_atom(function_name) and is_integer(arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function_name, arity)
  end

  defp advance_after_success(state) do
    state = release_resource(state)

    if :queue.is_empty(state.queue) do
      state
      |> transition_to("idle")
      |> put_runtime_state()
      |> snapshot_on_idle()
      |> start_idle_timer()
    else
      state
      |> transition_to("queued")
      |> put_runtime_state()
      |> notify_scheduler()
    end
  end

  defp schedule_retry(state) do
    Process.send_after(self(), :retry, 0)
    state
  end

  defp clear_current_item(state) do
    %{
      state
      | current_item: nil,
        retry_count: 0,
        tool_iteration_count: 0,
        phase: :action_selection,
        finalization_context: nil,
        finalization_repair_attempted?: false
    }
  end

  defp enqueue_work_item(state, content, opts) do
    if terminal_status?(state.status) do
      log_terminal_enqueue(state)
      {{:error, :terminal_instance}, state}
    else
      {next_state, did_transition?} = enqueue_item(state, content, opts)
      next_state = if did_transition?, do: notify_scheduler(next_state), else: next_state
      {:ok, next_state}
    end
  end

  defp enqueue_item(state, content, opts) do
    if Helpers.blank?(content) do
      {state, false}
    else
      now = state.now_fun.()
      item = %{id: Ecto.UUID.generate(), content: content, origin: :user, inserted_at: now}
      queue = :queue.in(item, state.queue)
      append_to_context? = Keyword.get(opts, :append_to_context?, true)

      context_messages =
        if append_to_context? do
          state.context_messages ++ [%{role: "user", content: content, request_id: item.id}]
        else
          state.context_messages
        end

      next_status = if state.status in ["created", "idle"], do: "queued", else: state.status

      state =
        state
        |> maybe_cancel_idle(next_status)
        |> Map.put(:queue, queue)
        |> Map.put(:context_messages, context_messages)
        |> transition_to(next_status)
        |> put_runtime_state()

      _ = Events.emit_queue_enqueued(state, item, :queue.len(queue))

      {state, next_status == "queued"}
    end
  end

  defp maybe_cancel_idle(state, "queued"), do: cancel_idle_timer(state)
  defp maybe_cancel_idle(state, _status), do: state

  defp start_model_step(state) do
    started_at = state.now_fun.()
    step_index = state.model_step_count + 1
    _ = Events.emit_model_started(state, step_index)

    attrs = %{
      step_index: step_index,
      status: "running",
      request_payload: current_model_request_payload(state),
      response_payload: nil,
      parsed_output: nil,
      error: nil,
      tool_execution_id: nil,
      provider: nil,
      model: nil,
      input_tokens: nil,
      output_tokens: nil,
      total_tokens: nil,
      usage: nil,
      started_at: started_at
    }

    case create_model_step(state, attrs) do
      {:ok, next_state} ->
        {%{next_state | model_step_count: step_index}, started_at}
    end
  end

  defp start_execution(state) do
    Logger.info("executor starting model task",
      event: "instance.executor.model_start",
      instance_id: state.instance_id,
      lemming_id: instance_lemming_id(state.instance),
      world_id: instance_world_id(state.instance),
      city_id: instance_city_id(state.instance),
      department_id: state.department_id,
      resource_key: state.current_resource_key,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      current_item_id: current_item_id(state.current_item)
    )

    parent = self()
    instance_id = state.instance_id
    model_task_ref = make_ref()
    {state, started_at} = start_model_step(state)

    {:ok, model_task_pid} =
      Task.start(fn ->
        Logger.metadata(instance_id: instance_id, department_id: state.department_id)
        result = safe_execute_model(state)

        send(parent, {:model_result, instance_id, model_task_ref, started_at, result})
      end)

    model_task_monitor_ref = Process.monitor(model_task_pid)

    model_task_timeout_ref =
      Process.send_after(self(), {:model_timeout, model_task_ref}, state.model_timeout_ms)

    %{
      state
      | model_task_pid: model_task_pid,
        model_task_monitor_ref: model_task_monitor_ref,
        model_task_ref: model_task_ref,
        model_task_timeout_ref: model_task_timeout_ref
    }
  end

  defp clear_model_task_tracking(state) do
    if state.model_task_timeout_ref do
      _ = Process.cancel_timer(state.model_task_timeout_ref)
    end

    if state.model_task_monitor_ref do
      _ = Process.demonitor(state.model_task_monitor_ref, [:flush])
    end

    %{
      state
      | model_task_pid: nil,
        model_task_monitor_ref: nil,
        model_task_ref: nil,
        model_task_timeout_ref: nil
    }
  end

  defp terminate_model_task(%{model_task_pid: pid} = state) when is_pid(pid) do
    Process.exit(pid, :kill)
    state
  end

  defp terminate_model_task(state), do: state

  defp finalize_model_step(state, result, completed_at \\ nil)

  defp finalize_model_step(%{active_model_step: nil} = state, _result, _completed_at), do: state

  defp finalize_model_step(
         %{active_model_step: active_model_step} = state,
         result,
         completed_at
       ) do
    completed_at = completed_at || state.now_fun.()
    duration_ms = DateTime.diff(completed_at, active_model_step.started_at, :millisecond)

    attrs =
      result
      |> model_step_result_attrs(completed_at, duration_ms)

    update_model_step(%{state | active_model_step: active_model_step}, attrs)
  end

  defp safe_execute_model(state) do
    execute_model(
      state.model_mod,
      model_config_snapshot(state),
      state.context_messages,
      current_model_request_item(state)
    )
  rescue
    exception ->
      Logger.error("executor model task crashed",
        event: "instance.executor.model_crash",
        instance_id: state.instance_id,
        lemming_id: instance_lemming_id(state.instance),
        world_id: instance_world_id(state.instance),
        city_id: instance_city_id(state.instance),
        department_id: state.department_id,
        resource_key: state.current_resource_key,
        current_item_id: current_item_id(state.current_item),
        retry_count: state.retry_count,
        queue_depth: :queue.len(state.queue),
        reason: Exception.message(exception)
      )

      _ =
        ActivityLog.record(:error, "executor", "Executor model task crashed", %{
          instance_id: state.instance_id,
          reason: Exception.message(exception)
        })

      {:error, :model_crash}
  catch
    kind, reason ->
      Logger.error("executor model task exited",
        event: "instance.executor.model_exit",
        instance_id: state.instance_id,
        lemming_id: instance_lemming_id(state.instance),
        world_id: instance_world_id(state.instance),
        city_id: instance_city_id(state.instance),
        department_id: state.department_id,
        resource_key: state.current_resource_key,
        current_item_id: current_item_id(state.current_item),
        retry_count: state.retry_count,
        queue_depth: :queue.len(state.queue),
        reason: "#{inspect(kind)}: #{inspect(reason)}"
      )

      _ =
        ActivityLog.record(:error, "executor", "Executor model task exited", %{
          instance_id: state.instance_id,
          reason: "#{inspect(kind)}: #{inspect(reason)}"
        })

      {:error, :model_crash}
  end

  defp model_config_snapshot(state) do
    targets = available_lemming_call_targets(state)

    if targets == [] do
      state.config_snapshot
    else
      Map.put(state.config_snapshot, :lemming_call_targets, targets)
    end
  end

  defp available_lemming_call_targets(%{lemming_calls_mod: lemming_calls_mod} = state) do
    if module_loaded_and_exports?(lemming_calls_mod, :available_targets, 1) do
      lemming_calls_mod.available_targets(instance_with_runtime_snapshot(state))
    else
      []
    end
  end

  defp instance_with_runtime_snapshot(state) do
    %{state.instance | config_snapshot: state.config_snapshot}
  end

  defp current_model_request_payload(state) do
    case LemmingsOs.ModelRuntime.debug_request(
           model_config_snapshot(state),
           state.context_messages,
           current_model_request_item(state)
         ) do
      {:ok, payload} -> ModelStepPayload.sanitize_json_map(payload)
      {:error, reason} -> %{"error" => inspect(reason)}
    end
  end

  defp current_model_request_item(%{phase: :finalizing} = state) do
    %{
      content:
        FinalizationPayload.build_post_tool_success_prompt(
          state.finalization_context,
          state.current_item.content
        )
    }
  end

  defp current_model_request_item(state), do: state.current_item

  defp model_step_result_attrs(result, completed_at, duration_ms) do
    ModelStepPayload.model_step_result_attrs(result, completed_at, duration_ms)
  end

  defp execute_model(nil, config_snapshot, context_messages, current_item) do
    LemmingsOs.ModelRuntime.run(config_snapshot, context_messages, current_item)
  end

  defp execute_model(model_mod, config_snapshot, context_messages, current_item) do
    if function_exported?(model_mod, :run, 3) do
      model_mod.run(config_snapshot, context_messages, current_item)
    else
      {:error, :model_runtime_unavailable}
    end
  end

  defp persist_assistant_message(state, response) do
    attrs = %{
      lemming_instance_id: state.instance_id,
      world_id: instance_world_id(state.instance),
      role: "assistant",
      content: response.reply,
      provider: response.provider,
      model: response.model,
      input_tokens: response.input_tokens,
      output_tokens: response.output_tokens,
      total_tokens: response.total_tokens,
      usage: response.usage
    }

    attrs
    |> insert_assistant_message(state)
    |> case do
      {:ok, message} ->
        _ = PubSub.broadcast_message_appended(state.instance_id, message.id, message.role)

        context_messages =
          state.context_messages ++ [%{role: "assistant", content: attrs.content}]

        {:ok, %{state | context_messages: context_messages}}

      {:error, reason} ->
        Logger.error("executor failed to persist assistant message",
          event: "instance.executor.persist_message",
          instance_id: state.instance_id,
          lemming_id: instance_lemming_id(state.instance),
          world_id: instance_world_id(state.instance),
          city_id: instance_city_id(state.instance),
          department_id: state.department_id,
          resource_key: state.current_resource_key,
          current_item_id: current_item_id(state.current_item),
          retry_count: state.retry_count,
          queue_depth: :queue.len(state.queue),
          reason: inspect(reason)
        )

        {:error, reason, state}
    end
  end

  defp insert_assistant_message(attrs, %{message_persist_mod: nil}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_assistant_message(attrs, %{message_persist_mod: mod}) when is_atom(mod) do
    if function_exported?(mod, :insert, 1) do
      mod.insert(attrs)
    else
      {:error, :message_persist_unavailable}
    end
  end

  defp transition_to(state, new_status, attrs \\ %{}) when new_status in @statuses do
    now = state.now_fun.()
    previous_status = state.status

    attrs =
      attrs
      |> Map.put_new(:last_activity_at, now)
      |> Map.put_new(:status, new_status)

    state =
      state
      |> Map.put(:status, new_status)
      |> Map.put(:last_activity_at, attrs.last_activity_at)
      |> persist_status(attrs)
      |> maybe_sync_child_call_terminal(new_status)
      |> broadcast_status()
      |> then(&log_transition(&1, previous_status, new_status))

    if new_status == "idle" do
      state
    else
      cancel_idle_timer(state)
    end
  end

  defp persist_started_at(state) do
    attrs = %{started_at: state.started_at, last_activity_at: state.last_activity_at}
    persist_status(state, attrs)
  end

  defp persist_status(%{context_mod: nil} = state, _attrs), do: state

  defp persist_status(
         %{context_mod: context_mod, instance: %LemmingInstance{} = instance} = state,
         attrs
       ) do
    status = Map.get(attrs, :status, state.status)

    with true <- module_loaded_and_exports?(context_mod, :update_status, 3),
         {:ok, updated_instance} <- context_mod.update_status(instance, status, attrs) do
      %{state | instance: updated_instance}
    else
      _other -> state
    end
  end

  defp persist_status(state, _attrs), do: state

  defp maybe_sync_child_call_terminal(state, "idle") do
    if pending_manager_calls?(state) do
      state
    else
      sync_child_call_terminal(state, "idle")
    end
  end

  defp maybe_sync_child_call_terminal(state, status)
       when status in ["failed", "expired"] do
    sync_child_call_terminal(state, status)
  end

  defp maybe_sync_child_call_terminal(state, _status), do: state

  defp sync_child_call_terminal(state, status) do
    result_summary =
      case {status, state.context_messages} do
        {"idle", messages} -> last_assistant_content(messages)
        _other -> nil
      end

    attrs = %{
      result_summary: result_summary,
      error_summary: state.last_error,
      completed_at: state.now_fun.()
    }

    if module_loaded_and_exports?(state.lemming_calls_mod, :sync_child_instance_terminal, 3) do
      _ = state.lemming_calls_mod.sync_child_instance_terminal(state.instance, status, attrs)
    end

    state
  end

  defp pending_manager_calls?(%{instance: instance, lemming_calls_mod: lemming_calls_mod})
       when not is_nil(lemming_calls_mod) do
    if module_loaded_and_exports?(lemming_calls_mod, :list_manager_calls, 2) do
      case lemming_calls_mod.list_manager_calls(instance, statuses: pending_child_call_statuses()) do
        [] -> false
        [_ | _rest] -> true
      end
    else
      false
    end
  end

  defp pending_manager_calls?(_state), do: false

  defp pending_child_call_statuses,
    do: ["accepted", "running", "needs_more_context", "partial_result"]

  defp last_assistant_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "assistant", content: content} when is_binary(content) -> content
      %{role: :assistant, content: content} when is_binary(content) -> content
      _message -> nil
    end)
  end

  defp broadcast_status(state) do
    metadata = %{
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      queue_depth: :queue.len(state.queue),
      current_item_id: current_item_id(state.current_item)
    }

    _ = PubSub.broadcast_status_change(state.instance_id, state.status, metadata)
    state
  end

  defp log_transition(state, previous_status, new_status) do
    level = transition_log_level(new_status)
    reason = transition_reason(state, new_status)

    metadata = %{
      event: "instance.executor.transition",
      instance_id: state.instance_id,
      lemming_id: instance_lemming_id(state.instance),
      world_id: instance_world_id(state.instance),
      city_id: instance_city_id(state.instance),
      department_id: state.department_id,
      resource_key: state.current_resource_key,
      from_status: previous_status,
      to_status: new_status,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      current_item_id: current_item_id(state.current_item),
      reason: reason
    }

    Logger.log(level, "executor status transitioned", metadata)

    _ =
      Telemetry.execute(
        [:lemmings_os, :instance, status_atom(new_status)],
        transition_measurements(state, new_status),
        Telemetry.instance_metadata(state.instance, %{
          instance_id: state.instance_id,
          resource_key: state.current_resource_key,
          from_status: previous_status,
          to_status: new_status,
          retry_count: state.retry_count,
          max_retries: state.max_retries,
          attempt: state.retry_count,
          max_attempts: state.max_retries,
          queue_depth: :queue.len(state.queue),
          current_item_id: current_item_id(state.current_item),
          reason: reason
        })
      )

    _ =
      ActivityLog.record(:runtime, "executor", "Status #{previous_status} -> #{new_status}", %{
        instance_id: state.instance_id,
        from_status: previous_status,
        to_status: new_status
      })

    state
  end

  defp notify_scheduler(state) do
    if is_binary(state.department_id) do
      Logger.info("scheduler work announced",
        event: "instance.scheduler.work_announced",
        instance_id: state.instance_id,
        lemming_id: instance_lemming_id(state.instance),
        world_id: instance_world_id(state.instance),
        city_id: instance_city_id(state.instance),
        department_id: state.department_id,
        queue_depth: :queue.len(state.queue),
        current_item_id: current_item_id(state.current_item)
      )

      _ =
        Telemetry.execute(
          [:lemmings_os, :scheduler, :work_announced],
          %{count: 1},
          Telemetry.instance_metadata(state.instance, %{
            instance_id: state.instance_id,
            queue_depth: :queue.len(state.queue),
            current_item_id: current_item_id(state.current_item)
          })
        )

      _ = PubSub.broadcast_work_available(state.department_id)
    end

    state
  end

  defp subscribe_scheduler(state) do
    if is_binary(state.department_id) do
      _ = PubSub.subscribe_scheduler(state.department_id)
    end

    state
  end

  defp maybe_start_idle_timer_on_init(%{status: "idle"} = state), do: start_idle_timer(state)
  defp maybe_start_idle_timer_on_init(state), do: state

  defp start_idle_timer(state) do
    case state.idle_timeout_ms do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        token = make_ref()
        timer_ref = Process.send_after(self(), {:idle_timeout, token}, timeout_ms)
        %{state | idle_timer_ref: timer_ref, idle_timer_token: token}

      _ ->
        state
    end
  end

  defp cancel_idle_timer(%{idle_timer_ref: nil} = state), do: state

  defp cancel_idle_timer(%{idle_timer_ref: timer_ref} = state) do
    _ = Process.cancel_timer(timer_ref)
    %{state | idle_timer_ref: nil, idle_timer_token: nil}
  end

  defp snapshot_on_idle(state) do
    runtime_state = runtime_state_map(state)
    RuntimeStore.snapshot_on_idle(state, runtime_state)
  end

  defp cleanup_snapshot(state) do
    RuntimeStore.cleanup_snapshot(state)
  end

  defp expire_instance(state) do
    state
    |> release_resource()
    |> transition_to("expired", %{stopped_at: state.now_fun.()})
    |> put_runtime_state()
    |> cleanup_runtime()
  end

  defp cleanup_runtime(state) do
    RuntimeStore.cleanup_runtime(state, @runtime_table)
  end

  defp ensure_runtime_table, do: RuntimeTableOwner.ensure_table()

  defp put_runtime_state(state) do
    runtime_state = runtime_state_map(state)
    RuntimeStore.put_runtime_state(state, runtime_state, @runtime_table)
  end

  defp runtime_state_map(state) do
    %{
      department_id: instance_department_id(state.instance),
      world_id: instance_world_id(state.instance),
      city_id: instance_city_id(state.instance),
      lemming_id: instance_lemming_id(state.instance),
      queue: state.queue,
      current_item: state.current_item,
      config_snapshot: state.config_snapshot,
      resource_key:
        state.current_resource_key || ConfigSnapshot.resource_key(state.config_snapshot),
      retry_count: state.retry_count,
      tool_iteration_count: state.tool_iteration_count,
      max_retries: state.max_retries,
      context_messages: state.context_messages,
      phase: state.phase,
      finalization_context: state.finalization_context,
      finalization_repair_attempted?: state.finalization_repair_attempted?,
      last_error: state.last_error,
      internal_error_details: state.internal_error_details,
      status: status_atom(state.status),
      started_at: state.started_at,
      last_activity_at: state.last_activity_at
    }
  end

  defp maybe_load_context_messages(%{context_mod: nil} = state), do: state
  defp maybe_load_context_messages(%{load_context_messages?: false} = state), do: state

  defp maybe_load_context_messages(
         %{context_mod: context_mod, instance: %LemmingInstance{} = instance} = state
       ) do
    case module_loaded_and_exports?(context_mod, :list_messages, 2) do
      true ->
        messages =
          context_mod.list_messages(instance, [])
          |> Enum.map(fn message ->
            %{role: message.role, content: message.content}
          end)

        %{state | context_messages: messages}

      false ->
        state
    end
  end

  defp maybe_load_context_messages(state), do: state

  defp resolve_instance_id(opts) do
    cond do
      Keyword.get(opts, :instance_id) ->
        Keyword.get(opts, :instance_id)

      match?(%{id: id} when is_binary(id), Keyword.get(opts, :instance)) ->
        Keyword.get(opts, :instance).id

      true ->
        nil
    end
  end

  defp instance_status(%{status: status}) when is_binary(status), do: status
  defp instance_status(_instance), do: "created"

  defp instance_config_snapshot(%{config_snapshot: snapshot}) when is_map(snapshot), do: snapshot
  defp instance_config_snapshot(_instance), do: %{}

  defp instance_world_id(%{world_id: world_id}), do: world_id
  defp instance_world_id(_instance), do: nil

  defp instance_city_id(%{city_id: city_id}), do: city_id
  defp instance_city_id(_instance), do: nil

  defp instance_department_id(%{department_id: department_id}), do: department_id
  defp instance_department_id(_instance), do: nil

  defp instance_lemming_id(%{lemming_id: lemming_id}), do: lemming_id
  defp instance_lemming_id(_instance), do: nil

  defp runtime_world_struct(state) do
    %World{id: instance_world_id(state.instance)}
  end

  defp runtime_world(state) do
    case instance_world_id(state.instance) do
      world_id when is_binary(world_id) -> {:ok, %World{id: world_id}}
      _world_id -> {:error, :invalid_world_scope}
    end
  end

  defp current_item_id(%{id: id}) when is_binary(id), do: id
  defp current_item_id(_current_item), do: nil

  defp status_atom(status) when is_binary(status) do
    TransitionsData.status_atom(status, @status_atoms)
  end

  defp terminal_status?(status), do: status in ["failed", "expired"]

  defp transition_log_level(status), do: TransitionsData.transition_log_level(status)

  defp transition_reason(state, status), do: TransitionsData.transition_reason(state, status)

  defp transition_measurements(state, status),
    do: TransitionsData.transition_measurements(state, status)

  defp maybe_store_resource_key(state, resource_key) when is_binary(resource_key) do
    %{state | current_resource_key: resource_key}
  end

  defp maybe_store_resource_key(state, _resource_key), do: state

  defp release_resource(%{current_resource_key: nil} = state), do: state

  defp release_resource(%{pool_mod: nil} = state) do
    %{state | current_resource_key: nil}
  end

  defp release_resource(state) do
    if function_exported?(state.pool_mod, :checkin, 2) do
      _ = state.pool_mod.checkin(state.current_resource_key, self())
    else
      _ = state.pool_mod.checkin(state.current_resource_key)
    end

    %{state | current_resource_key: nil}
  end

  defp normalize_server(server) when is_binary(server), do: via_name(server)
  defp normalize_server(server), do: server

  defp safe_call(server, message) do
    GenServer.call(server, message)
  catch
    :exit, _reason -> {:error, :executor_unavailable}
  end

  defp log_terminal_enqueue(state) do
    Logger.info("executor ignored work for terminal instance",
      event: "instance.executor.enqueue",
      instance_id: state.instance_id,
      lemming_id: instance_lemming_id(state.instance),
      world_id: instance_world_id(state.instance),
      city_id: instance_city_id(state.instance),
      department_id: state.department_id,
      resource_key: state.current_resource_key,
      status: state.status
    )
  end

  defp max_retries(config_snapshot) do
    runtime_config_value(config_snapshot, :max_retries) ||
      runtime_config_value(config_snapshot, :max_attempts) ||
      @default_max_retries
  end

  defp max_tool_iterations(config_snapshot) do
    runtime_config_value(config_snapshot, :max_tool_iterations) || @default_max_tool_iterations
  end

  defp model_timeout_ms(config_snapshot) do
    runtime_config_value(config_snapshot, :model_timeout_ms) ||
      runtime_config_value(config_snapshot, :model_timeout) ||
      Keyword.get(
        Application.get_env(:lemmings_os, :model_runtime, []),
        :timeout,
        @default_model_timeout_ms
      )
  end

  defp idle_timeout_ms(opts, config_snapshot) do
    case Keyword.get(opts, :idle_timeout_ms, :use_config) do
      timeout_ms when is_integer(timeout_ms) and timeout_ms > 0 ->
        timeout_ms

      nil ->
        nil

      :use_config ->
        case runtime_config_value(config_snapshot, :idle_ttl_seconds) do
          ttl when is_integer(ttl) and ttl > 0 -> ttl * 1000
          _ -> nil
        end

      _other ->
        nil
    end
  end

  defp runtime_config_value(config_snapshot, key) when is_map(config_snapshot) do
    runtime =
      Map.get(config_snapshot, :runtime_config) ||
        Map.get(config_snapshot, "runtime_config") ||
        %{}

    Map.get(runtime, key) || Map.get(runtime, Atom.to_string(key))
  end

  defp runtime_config_value(_config_snapshot, _key), do: nil
end
