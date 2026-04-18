defmodule LemmingsOs.Runtime do
  @moduledoc """
  Application-level runtime entrypoints.

  This module keeps the web layer away from the persistence boundary and
  leaves room for future spawn orchestration without changing callers.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.DepartmentScheduler
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ResourcePool
  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime.ActivityLog
  require Logger

  @recoverable_statuses ~w(created queued processing retrying idle)
  @default_recovery_limit 100

  @doc """
  Spawns a runtime session for a lemming and first request.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming =
      ...>   LemmingsOs.Factory.insert(:lemming,
      ...>     world: world,
      ...>     city: city,
      ...>     department: department,
      ...>     status: "active"
      ...>   )
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{}} =
      ...>   LemmingsOs.Runtime.spawn_session(lemming, "Summarize the roadmap")
  """
  @spec spawn_session(Lemming.t(), String.t(), keyword()) ::
          {:ok, LemmingsOs.LemmingInstances.LemmingInstance.t()}
          | {:error, Ecto.Changeset.t() | atom()}
  def spawn_session(%Lemming{} = lemming, first_request_text, opts \\ []) do
    with {:ok, instance} <-
           LemmingsOs.LemmingInstances.spawn_instance(lemming, first_request_text, opts),
         {:ok, _scheduler_pid} <- start_scheduler(instance, opts),
         {:ok, executor_pid} <-
           start_executor(
             instance,
             Keyword.put(opts, :executor_opts, executor_opts_without_context_load(opts))
           ),
         :ok <- executor_api(opts).enqueue_work(executor_pid, first_request_text) do
      Logger.info("runtime session spawned",
        event: "runtime.spawn_session",
        instance_id: instance.id,
        lemming_id: instance.lemming_id,
        department_id: instance.department_id,
        world_id: instance.world_id
      )

      :telemetry.execute(
        [:lemmings_os, :runtime, :session, :spawn],
        %{count: 1},
        %{
          instance_id: instance.id,
          lemming_id: instance.lemming_id,
          department_id: instance.department_id,
          world_id: instance.world_id
        }
      )

      _ =
        ActivityLog.record(:system, "runtime", "Runtime session spawned", %{
          instance_id: instance.id,
          lemming_id: instance.lemming_id,
          department_id: instance.department_id
        })

      {:ok, instance}
    end
  end

  @doc """
  Retries a failed runtime session.

  If the failed executor is still alive, the retry is pushed into that process.
  Otherwise, the runtime restarts the scheduler/executor pair and resumes the
  latest pending user request from the transcript.
  """
  @spec retry_session(LemmingInstance.t(), keyword()) ::
          {:ok, LemmingInstance.t()} | {:error, atom() | term()}
  def retry_session(instance, opts \\ [])

  def retry_session(%LemmingInstance{status: "failed"} = instance, opts) do
    case Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id) do
      [{executor_pid, _value}] when is_pid(executor_pid) ->
        :ok = Executor.retry(executor_pid)

        Logger.info("runtime session retry requested",
          event: "runtime.retry_session",
          instance_id: instance.id,
          lemming_id: instance.lemming_id,
          department_id: instance.department_id,
          world_id: instance.world_id
        )

        _ =
          ActivityLog.record(:runtime, "instance", "Runtime session retry requested", %{
            instance_id: instance.id,
            mode: "existing_executor"
          })

        {:ok, instance}

      _ ->
        retry_failed_session(instance, opts)
    end
  end

  def retry_session(%LemmingInstance{}, _opts), do: {:error, :instance_not_failed}

  @doc """
  Reconciles created runtime instances after boot.

  This best-effort recovery is intended for sessions that were persisted but
  never entered the executor loop before the app restarted. Recovery runs in a
  bounded sweep so boot does not attempt to reattach the entire table at once.
  """
  @spec recover_created_sessions(keyword()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def recover_created_sessions(opts \\ []) do
    recovery_limit = recovery_limit(opts)

    LemmingInstance
    |> where([instance], instance.status in ^@recoverable_statuses)
    |> order_by([instance], asc: instance.inserted_at, asc: instance.id)
    |> limit(^recovery_limit)
    |> preload([:messages])
    |> Repo.all()
    |> Enum.reduce({0, 0}, fn instance, {recovered_count, skipped_count} ->
      case recover_created_session(instance, opts) do
        {:ok, _instance_id} ->
          {recovered_count + 1, skipped_count}

        {:error, _reason} ->
          {recovered_count, skipped_count + 1}
      end
    end)
    |> then(fn {recovered_count, skipped_count} ->
      Logger.info("runtime recovery completed",
        event: "runtime.recovery.completed",
        recovered_count: recovered_count,
        skipped_count: skipped_count
      )

      _ =
        ActivityLog.record(:system, "runtime", "Runtime recovery completed", %{
          recovery_limit: recovery_limit,
          recovered_count: recovered_count,
          skipped_count: skipped_count
        })

      {:ok, recovered_count}
    end)
  end

  defp start_scheduler(instance, opts) do
    scheduler_opts =
      [department_id: instance.department_id]
      |> Keyword.merge(default_scheduler_opts())
      |> Keyword.merge(Keyword.get(opts, :scheduler_opts, []))

    start_runtime_child(
      LemmingsOs.LemmingInstances.SchedulerSupervisor,
      DepartmentScheduler.child_spec(scheduler_opts)
    )
  end

  defp start_executor(instance, opts) do
    executor_opts =
      [instance: instance]
      |> Keyword.merge(default_executor_opts())
      |> Keyword.merge(Keyword.get(opts, :executor_opts, []))

    start_runtime_child(
      LemmingsOs.LemmingInstances.ExecutorSupervisor,
      Executor.child_spec(executor_opts)
    )
  end

  defp default_scheduler_opts do
    [
      context_mod: LemmingInstances,
      pool_mod: ResourcePool,
      ets_mod: EtsStore,
      pubsub_mod: Phoenix.PubSub,
      pubsub_name: LemmingsOs.PubSub
    ]
  end

  defp default_executor_opts do
    [
      context_mod: LemmingInstances,
      dets_mod: DetsStore,
      ets_mod: EtsStore,
      pool_mod: ResourcePool,
      model_mod: ModelRuntime,
      pubsub_mod: Phoenix.PubSub,
      pubsub_name: LemmingsOs.PubSub
    ]
  end

  defp start_runtime_child(supervisor, child_spec) do
    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _reason} = error -> error
      other -> {:error, other}
    end
  end

  defp recover_created_session(instance, opts) do
    with {:ok, recovered_instance, resume_message} <- recovery_plan(instance),
         {:ok, _scheduler_pid} <- start_scheduler(recovered_instance, opts),
         {:ok, executor_pid} <-
           start_executor(
             recovered_instance,
             Keyword.put(
               opts,
               :executor_opts,
               executor_opts_for_recovery(opts, pending_recovery?(resume_message))
             )
           ),
         :ok <- maybe_resume_pending(executor_pid, resume_message, opts) do
      Logger.info("runtime instance recovered",
        event: "runtime.instance.recovered",
        instance_id: recovered_instance.id,
        lemming_id: recovered_instance.lemming_id,
        department_id: recovered_instance.department_id,
        world_id: recovered_instance.world_id,
        message_id: resume_message_id(resume_message),
        status: recovered_instance.status
      )

      :telemetry.execute(
        [:lemmings_os, :runtime, :session, :recovered],
        %{count: 1},
        %{
          instance_id: recovered_instance.id,
          lemming_id: recovered_instance.lemming_id,
          department_id: recovered_instance.department_id,
          world_id: recovered_instance.world_id,
          message_id: resume_message_id(resume_message)
        }
      )

      _ =
        ActivityLog.record(:system, "runtime", "Runtime instance recovered", %{
          instance_id: recovered_instance.id,
          lemming_id: recovered_instance.lemming_id,
          resume_message_id: resume_message_id(resume_message),
          resumed?: pending_recovery?(resume_message)
        })

      {:ok, recovered_instance.id}
    else
      {:error, reason} = error ->
        Logger.warning("runtime instance recovery failed",
          event: "runtime.instance.recovery_failed",
          instance_id: instance.id,
          lemming_id: instance.lemming_id,
          department_id: instance.department_id,
          world_id: instance.world_id,
          status: instance.status,
          reason: inspect(reason)
        )

        _ =
          ActivityLog.record(:error, "runtime", "Runtime instance recovery failed", %{
            instance_id: instance.id,
            reason: inspect(reason)
          })

        error
    end
  end

  defp retry_failed_session(instance, opts) do
    with {:ok, retried_instance, resume_message} <- retry_plan(instance),
         {:ok, _scheduler_pid} <- start_scheduler(retried_instance, opts),
         {:ok, executor_pid} <-
           start_executor(
             retried_instance,
             Keyword.put(opts, :executor_opts, executor_opts_for_recovery(opts, true))
           ),
         :ok <- maybe_resume_pending(executor_pid, resume_message, opts) do
      Logger.info("runtime session retry requested",
        event: "runtime.retry_session",
        instance_id: retried_instance.id,
        lemming_id: retried_instance.lemming_id,
        department_id: retried_instance.department_id,
        world_id: retried_instance.world_id,
        message_id: resume_message_id(resume_message)
      )

      _ =
        ActivityLog.record(:runtime, "instance", "Runtime session retry requested", %{
          instance_id: retried_instance.id,
          mode: "recovered_executor",
          resume_message_id: resume_message_id(resume_message)
        })

      {:ok, retried_instance}
    end
  end

  defp recovery_plan(instance) do
    case pending_user_message(instance) do
      {:ok, message} ->
        {:ok, %{instance | status: "created"}, {:pending, message}}

      :none ->
        {:ok, normalize_attached_instance(instance), :noop}
    end
  end

  defp retry_plan(instance) do
    case pending_user_message(instance) do
      {:ok, message} ->
        {:ok, %{instance | status: "created"}, {:pending, message}}

      :none ->
        {:error, :no_pending_request}
    end
  end

  defp pending_user_message(instance) do
    messages =
      case Map.get(instance, :messages) do
        messages when is_list(messages) -> messages
        _ -> LemmingInstances.list_messages(instance)
      end

    case List.last(messages) do
      %{role: "user"} = message -> {:ok, message}
      _ -> :none
    end
  end

  defp normalize_attached_instance(%LemmingInstance{status: "idle"} = instance), do: instance

  defp normalize_attached_instance(%LemmingInstance{} = instance) do
    case LemmingInstances.update_status(instance, "idle", %{stopped_at: nil}) do
      {:ok, updated_instance} -> updated_instance
      {:error, _changeset} -> %{instance | status: "idle"}
    end
  end

  defp maybe_resume_pending(_executor_pid, :noop, _opts), do: :ok

  defp maybe_resume_pending(executor_pid, {:pending, message}, opts) do
    executor_api(opts).resume_pending(executor_pid, message.content)
  end

  defp pending_recovery?({:pending, _message}), do: true
  defp pending_recovery?(_resume_message), do: false

  defp resume_message_id({:pending, %{id: id}}), do: id
  defp resume_message_id(_resume_message), do: nil

  defp executor_opts_for_recovery(opts, true) do
    Keyword.get(opts, :executor_opts, [])
    |> Keyword.put(:load_context_messages, true)
  end

  defp executor_opts_for_recovery(opts, false) do
    Keyword.get(opts, :executor_opts, [])
    |> Keyword.put_new(:load_context_messages, true)
  end

  defp executor_opts_without_context_load(opts) do
    Keyword.get(opts, :executor_opts, [])
    |> Keyword.put(:load_context_messages, false)
  end

  defp executor_api(opts) do
    Keyword.get(opts, :executor_api_mod, Executor)
  end

  defp recovery_limit(opts) do
    Keyword.get(opts, :limit) ||
      Keyword.get(
        Application.get_env(:lemmings_os, :runtime_recovery, []),
        :limit,
        @default_recovery_limit
      )
  end
end
