defmodule LemmingsOs.LemmingInstances.Executor do
  @moduledoc """
  Per-instance runtime executor.

  The executor owns the in-memory work queue and runtime state machine for a
  single `LemmingInstance`. It updates durable status transitions via the
  `LemmingsOs.LemmingInstances` context, publishes status changes via PubSub,
  and delegates model execution through an injectable runtime module.
  """

  use GenServer

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime.ActivityLog

  @runtime_table :lemming_instance_runtime
  @default_max_retries 3
  @default_model_timeout_ms 120_000

  @statuses ~w(created queued processing retrying idle failed expired)
  @status_atoms Map.new(@statuses, &{&1, String.to_atom(&1)})

  @type work_item :: %{
          id: Ecto.UUID.t() | binary(),
          content: String.t(),
          origin: :user,
          inserted_at: DateTime.t()
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
          last_error: String.t() | nil,
          model_task_pid: pid() | nil,
          model_task_monitor_ref: reference() | nil,
          model_task_ref: reference() | nil,
          model_task_timeout_ref: reference() | nil,
          model_timeout_ms: pos_integer(),
          started_at: DateTime.t(),
          last_activity_at: DateTime.t(),
          idle_timer_ref: reference() | nil,
          idle_timer_token: reference() | nil,
          idle_ttl_seconds: pos_integer() | nil,
          context_mod: module() | nil,
          ets_mod: module() | nil,
          dets_mod: module() | nil,
          pool_mod: module() | nil,
          model_mod: module() | nil,
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
          :ok | {:error, :empty_request_text}
  def enqueue_work(server, content) when is_binary(content) do
    if Helpers.blank?(content) do
      {:error, :empty_request_text}
    else
      GenServer.cast(normalize_server(server), {:enqueue_work, content})
      :ok
    end
  end

  @doc """
  Requeues a persisted pending user message without duplicating transcript
  context already loaded into memory.
  """
  @spec resume_pending(GenServer.server() | binary(), String.t()) ::
          :ok | {:error, :empty_request_text}
  def resume_pending(server, content) when is_binary(content) do
    if Helpers.blank?(content) do
      {:error, :empty_request_text}
    else
      GenServer.cast(normalize_server(server), {:resume_pending, content})
      :ok
    end
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
        last_error: nil,
        model_task_pid: nil,
        model_task_monitor_ref: nil,
        model_task_ref: nil,
        model_task_timeout_ref: nil,
        model_timeout_ms: Keyword.get(opts, :model_timeout_ms, model_timeout_ms(config_snapshot)),
        started_at: now,
        last_activity_at: now,
        idle_timer_ref: nil,
        idle_timer_token: nil,
        idle_ttl_seconds: idle_ttl_seconds(config_snapshot),
        context_mod: Keyword.get(opts, :context_mod, LemmingsOs.LemmingInstances),
        load_context_messages?: Keyword.get(opts, :load_context_messages, true),
        ets_mod: Keyword.get(opts, :ets_mod),
        dets_mod: Keyword.get(opts, :dets_mod),
        pool_mod: Keyword.get(opts, :pool_mod, ResourcePool),
        model_mod: Keyword.get(opts, :model_mod, LemmingsOs.ModelRuntime),
        pubsub_mod: Keyword.get(opts, :pubsub_mod, Phoenix.PubSub),
        pubsub_name: Keyword.get(opts, :pubsub_name, LemmingsOs.PubSub),
        now_fun: now_fun
      }

      state =
        state
        |> ensure_runtime_table()
        |> maybe_load_context_messages()
        |> persist_started_at()
        |> put_runtime_state()
        |> subscribe_scheduler()

      Logger.info("executor started",
        event: "instance.executor.started",
        instance_id: state.instance_id,
        department_id: state.department_id,
        status: state.status,
        queue_depth: :queue.len(state.queue),
        retry_count: state.retry_count,
        max_retries: state.max_retries,
        current_item_id: current_item_id(state.current_item)
      )

      _ =
        ActivityLog.record(:runtime, "executor", "Executor started", %{
          instance_id: state.instance_id,
          department_id: state.department_id,
          status: state.status
        })

      {:ok, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    snapshot = %{
      status: state.status,
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      queue_depth: :queue.len(state.queue),
      last_error: state.last_error
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      instance_id: state.instance_id,
      department_id: state.department_id,
      status: state.status,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      current_item_id: current_item_id(state.current_item),
      current_resource_key: state.current_resource_key,
      last_error: state.last_error,
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
    if terminal_status?(state.status) do
      Logger.info("executor ignored work for terminal instance",
        event: "instance.executor.enqueue",
        instance_id: state.instance_id,
        department_id: state.department_id,
        resource_key: state.current_resource_key,
        status: state.status
      )

      {:noreply, state}
    else
      {state, did_transition?} = enqueue_item(state, content, append_to_context?: true)
      state = if did_transition?, do: notify_scheduler(state), else: state
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:resume_pending, content}, state) do
    if terminal_status?(state.status) do
      {:noreply, state}
    else
      {state, did_transition?} = enqueue_item(state, content, append_to_context?: false)
      state = if did_transition?, do: notify_scheduler(state), else: state
      {:noreply, state}
    end
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
  def handle_info({:model_result, instance_id, model_task_ref, result}, state) do
    if instance_id == state.instance_id and model_task_ref == state.model_task_ref do
      {:noreply, state |> clear_model_task_tracking() |> handle_model_result(result)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:model_timeout, model_task_ref}, state) do
    if model_task_ref == state.model_task_ref do
      state =
        state
        |> terminate_model_task()
        |> clear_model_task_tracking()
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
          :normal -> state
          :killed -> state
          :shutdown -> handle_model_retry(state, :model_crash)
          {:shutdown, _details} -> handle_model_retry(state, :model_crash)
          _ -> handle_model_retry(state, :model_crash)
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
        |> Map.put(:retry_count, 0)
        |> transition_to("processing")
        |> put_runtime_state()

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

  defp handle_model_result(state, {:ok, %LemmingsOs.ModelRuntime.Response{} = response}) do
    state
    |> Map.put(:last_error, nil)
    |> persist_assistant_message(response)
    |> clear_current_item()
    |> advance_after_success()
  end

  defp handle_model_result(state, {:ok, _response}) do
    handle_model_retry(state, :invalid_provider_response)
  end

  defp handle_model_result(state, {:error, reason}) do
    handle_model_retry(state, reason)
  end

  defp handle_model_result(state, _unexpected) do
    handle_model_retry(state, :unexpected_model_result)
  end

  defp handle_model_retry(state, reason) do
    next_retry = state.retry_count + 1
    error_message = last_error_message(reason)

    if next_retry >= state.max_retries do
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> release_resource()
      |> cleanup_snapshot()
      |> transition_to("failed", %{stopped_at: state.now_fun.()})
      |> put_runtime_state()
    else
      state
      |> Map.put(:retry_count, next_retry)
      |> Map.put(:last_error, error_message)
      |> transition_to("retrying")
      |> put_runtime_state()
      |> schedule_retry()
    end
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
    %{state | current_item: nil, retry_count: 0}
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
          state.context_messages ++ [%{role: "user", content: content}]
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

      {state, next_status == "queued"}
    end
  end

  defp maybe_cancel_idle(state, "queued"), do: cancel_idle_timer(state)
  defp maybe_cancel_idle(state, _status), do: state

  defp start_execution(state) do
    Logger.info("executor starting model task",
      event: "instance.executor.model_start",
      instance_id: state.instance_id,
      department_id: state.department_id,
      resource_key: state.current_resource_key,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      current_item_id: current_item_id(state.current_item)
    )

    parent = self()
    instance_id = state.instance_id
    model_task_ref = make_ref()

    {:ok, model_task_pid} =
      Task.start(fn ->
        Logger.metadata(instance_id: instance_id, department_id: state.department_id)
        result = safe_execute_model(state)

        send(parent, {:model_result, instance_id, model_task_ref, result})
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

  defp safe_execute_model(state) do
    execute_model(
      state.model_mod,
      state.config_snapshot,
      state.context_messages,
      state.current_item
    )
  rescue
    exception ->
      Logger.error("executor model task crashed",
        event: "instance.executor.model_crash",
        instance_id: state.instance_id,
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

    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        _ = PubSub.broadcast_message_appended(state.instance_id, message.id, message.role)

        context_messages =
          state.context_messages ++ [%{role: "assistant", content: attrs.content}]

        %{state | context_messages: context_messages}

      {:error, _changeset} ->
        Logger.error("executor failed to persist assistant message",
          event: "instance.executor.persist_message",
          instance_id: state.instance_id,
          department_id: state.department_id,
          resource_key: state.current_resource_key,
          current_item_id: current_item_id(state.current_item),
          retry_count: state.retry_count,
          queue_depth: :queue.len(state.queue)
        )

        state
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

  defp persist_status(%{context_mod: context_mod} = state, attrs) do
    instance = state.instance
    status = Map.get(attrs, :status, state.status)

    if function_exported?(context_mod, :update_status, 3) and match?(%LemmingInstance{}, instance) do
      case context_mod.update_status(instance, status, attrs) do
        {:ok, updated_instance} -> %{state | instance: updated_instance}
        {:error, _changeset} -> state
      end
    else
      state
    end
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
    Logger.info("executor status transitioned",
      event: "instance.executor.transition",
      instance_id: state.instance_id,
      department_id: state.department_id,
      resource_key: state.current_resource_key,
      from_status: previous_status,
      to_status: new_status,
      queue_depth: :queue.len(state.queue),
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      current_item_id: current_item_id(state.current_item)
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

  defp start_idle_timer(state) do
    case state.idle_ttl_seconds do
      ttl when is_integer(ttl) and ttl > 0 ->
        token = make_ref()
        timer_ref = Process.send_after(self(), {:idle_timeout, token}, ttl * 1000)
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

    case state.dets_mod do
      nil ->
        state

      dets_mod ->
        if function_exported?(dets_mod, :snapshot, 2) do
          _ = dets_mod.snapshot(state.instance_id, runtime_state)
        end

        state
    end
  end

  defp cleanup_snapshot(%{dets_mod: nil} = state), do: state

  defp cleanup_snapshot(state) do
    if function_exported?(state.dets_mod, :delete, 1) do
      _ = state.dets_mod.delete(state.instance_id)
    end

    state
  end

  defp expire_instance(state) do
    state
    |> release_resource()
    |> transition_to("expired", %{stopped_at: state.now_fun.()})
    |> put_runtime_state()
    |> cleanup_runtime()
  end

  defp cleanup_runtime(state) do
    case state.ets_mod do
      nil ->
        _ = :ets.delete(@runtime_table, state.instance_id)

      ets_mod ->
        if function_exported?(ets_mod, :delete, 1) do
          _ = ets_mod.delete(state.instance_id)
        end
    end

    case state.dets_mod do
      nil ->
        :ok

      dets_mod ->
        if function_exported?(dets_mod, :delete, 1) do
          _ = dets_mod.delete(state.instance_id)
        end
    end

    state
  end

  defp ensure_runtime_table(state) do
    case :ets.whereis(@runtime_table) do
      :undefined ->
        _ =
          :ets.new(@runtime_table, [
            :set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: true
          ])

        state

      _ ->
        state
    end
  end

  defp put_runtime_state(state) do
    runtime_state = runtime_state_map(state)

    case state.ets_mod do
      nil ->
        _ = :ets.insert(@runtime_table, {state.instance_id, runtime_state})

      ets_mod ->
        if function_exported?(ets_mod, :put, 2) do
          _ = ets_mod.put(state.instance_id, runtime_state)
        end
    end

    state
  end

  defp runtime_state_map(state) do
    %{
      department_id: instance_department_id(state.instance),
      world_id: instance_world_id(state.instance),
      queue: state.queue,
      current_item: state.current_item,
      config_snapshot: state.config_snapshot,
      resource_key:
        state.current_resource_key || ConfigSnapshot.resource_key(state.config_snapshot),
      retry_count: state.retry_count,
      max_retries: state.max_retries,
      context_messages: state.context_messages,
      last_error: state.last_error,
      status: status_atom(state.status),
      started_at: state.started_at,
      last_activity_at: state.last_activity_at
    }
  end

  defp maybe_load_context_messages(%{context_mod: nil} = state), do: state
  defp maybe_load_context_messages(%{load_context_messages?: false} = state), do: state

  defp maybe_load_context_messages(%{context_mod: context_mod, instance: instance} = state) do
    if function_exported?(context_mod, :list_messages, 2) and match?(%LemmingInstance{}, instance) do
      messages =
        context_mod.list_messages(instance, [])
        |> Enum.map(fn message ->
          %{role: message.role, content: message.content}
        end)

      %{state | context_messages: messages}
    else
      state
    end
  end

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

  defp instance_department_id(%{department_id: department_id}), do: department_id
  defp instance_department_id(_instance), do: nil

  defp current_item_id(%{id: id}) when is_binary(id), do: id
  defp current_item_id(_current_item), do: nil

  defp last_error_message(:provider_error),
    do: "Model provider returned a non-success response."

  defp last_error_message({:provider_http_error, %{provider: provider} = metadata}) do
    provider_label = provider_label(provider)
    status_copy = provider_status_copy(metadata)
    detail_copy = provider_detail_copy(metadata)

    "#{provider_label} provider returned a non-success response#{status_copy}#{detail_copy}"
  end

  defp last_error_message({:provider_timeout, %{provider: provider}}),
    do: "#{provider_label(provider)} provider request timed out."

  defp last_error_message({:provider_network_error, %{provider: provider} = metadata}) do
    case Map.get(metadata, :reason) do
      reason when is_binary(reason) and reason != "" ->
        "#{provider_label(provider)} provider request failed: #{reason}."

      _ ->
        "#{provider_label(provider)} provider request failed due to a network error."
    end
  end

  defp last_error_message({:provider_invalid_response, %{provider: provider}}),
    do: "#{provider_label(provider)} provider returned an invalid response."

  defp last_error_message(:network_error),
    do: "Model provider request failed due to a network error."

  defp last_error_message(:timeout),
    do: "Model provider request timed out."

  defp last_error_message(:invalid_structured_output),
    do: "Model returned invalid structured output."

  defp last_error_message(:unknown_action),
    do: "Model returned an unsupported action."

  defp last_error_message(:missing_model),
    do: "Runtime config is missing a model."

  defp last_error_message(:unsupported_provider),
    do: "Runtime config uses an unsupported provider."

  defp last_error_message(:model_runtime_unavailable),
    do: "Model runtime is unavailable."

  defp last_error_message(:model_crash),
    do: "Executor model task crashed."

  defp last_error_message(:model_timeout),
    do: "Executor model task timed out."

  defp last_error_message(:invalid_provider_response),
    do: "Model provider returned an invalid response payload."

  defp last_error_message(:unexpected_model_result),
    do: "Executor received an unexpected model result."

  defp last_error_message(reason) when is_atom(reason),
    do: "Runtime error: #{Atom.to_string(reason)}."

  defp last_error_message(reason), do: "Runtime error: #{inspect(reason)}."

  defp provider_label(provider) when is_binary(provider) and provider != "", do: provider
  defp provider_label(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_label(_provider), do: "model"

  defp provider_status_copy(%{status: status}) when is_integer(status), do: " (HTTP #{status})"
  defp provider_status_copy(_metadata), do: ""

  defp provider_detail_copy(%{detail: detail}) when is_binary(detail) and detail != "",
    do: ": #{detail}."

  defp provider_detail_copy(_metadata), do: "."

  defp status_atom(status) when is_binary(status) do
    Map.fetch!(@status_atoms, status)
  end

  defp terminal_status?(status), do: status in ["failed", "expired"]

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

  defp max_retries(config_snapshot) do
    runtime_config_value(config_snapshot, :max_retries) ||
      runtime_config_value(config_snapshot, :max_attempts) ||
      @default_max_retries
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

  defp idle_ttl_seconds(config_snapshot) do
    runtime_config_value(config_snapshot, :idle_ttl_seconds)
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
