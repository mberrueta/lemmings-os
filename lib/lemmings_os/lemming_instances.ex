defmodule LemmingsOs.LemmingInstances do
  @moduledoc """
  Runtime persistence boundary for spawned lemming sessions.

  This context owns durable instance rows, immutable transcript messages, and
  world-scoped runtime queries. It persists transcript messages and hands
  follow-up work to the running executor through the runtime boundary.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Ecto.Multi
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.ConfigSnapshot
  alias LemmingsOs.LemmingInstances.DetsStore
  alias LemmingsOs.LemmingInstances.EtsStore
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.Telemetry
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Worlds.World

  @statuses ~w(created queued processing retrying idle failed expired)
  @terminal_statuses ~w(failed expired)

  @doc false
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc false
  @spec roles() :: [String.t()]
  def roles, do: Message.roles()

  @doc """
  Creates a runtime instance and its first user message atomically.

  The instance record stores only durable runtime identity and frozen config
  state. The initial user request is persisted as the first transcript message.

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
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{status: "created"}} =
      ...>   LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
  """
  @spec spawn_instance(Lemming.t(), String.t(), keyword()) ::
          {:ok, LemmingInstance.t()} | {:error, Ecto.Changeset.t() | atom()}
  def spawn_instance(%Lemming{} = lemming, first_request_text, opts \\ [])
      when is_list(opts) do
    cond do
      Helpers.blank?(first_request_text) ->
        {:error, :empty_request_text}

      lemming.status != "active" ->
        {:error, :lemming_not_active}

      true ->
        lemming = preload_lemming_for_snapshot(lemming, opts)

        config_snapshot =
          lemming
          |> Resolver.resolve()
          |> snapshot_value()
          |> ConfigSnapshot.enrich()

        work_area_path = build_work_area_path(lemming)

        with :ok <- create_work_area(work_area_path),
             {:ok, %{instance: instance, message: message}} <-
               persist_spawn(
                 lemming,
                 config_snapshot,
                 first_request_text
               ) do
          Logger.info("runtime instance spawned",
            event: "instance.spawn",
            instance_id: instance.id,
            lemming_id: instance.lemming_id,
            world_id: instance.world_id,
            city_id: instance.city_id,
            department_id: instance.department_id,
            message_id: message.id,
            status: instance.status,
            path: work_area_path
          )

          _ =
            Telemetry.execute(
              [:lemmings_os, :instance, :created],
              %{count: 1},
              Telemetry.instance_metadata(instance, %{
                status: instance.status,
                message_id: message.id,
                work_area_path: work_area_path
              })
            )

          _ =
            ActivityLog.record(:runtime, "instance", "Runtime instance spawned", %{
              instance_id: instance.id,
              lemming_id: instance.lemming_id,
              message_id: message.id,
              work_area_path: work_area_path
            })

          {:ok, instance}
        else
          {:error, _reason} = error ->
            cleanup_work_area(work_area_path)
            error
        end
    end
  end

  @doc """
  Returns persisted runtime instances for the given World scope.

  Optional keyword filters can narrow the result set or preload associations.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "List the project risks")
      iex> instance_id = instance.id
      iex> [%LemmingsOs.LemmingInstances.LemmingInstance{id: ^instance_id}] =
      ...>   LemmingsOs.LemmingInstances.list_instances(world)
  """
  @spec list_instances(World.t(), keyword()) :: [LemmingInstance.t()]
  def list_instances(%World{id: world_id}, opts \\ [])
      when is_binary(world_id) and is_list(opts) do
    LemmingInstance
    |> where([instance], instance.world_id == ^world_id)
    |> filter_query(opts)
    |> order_by([instance], desc: instance.inserted_at, desc: instance.id)
    |> Repo.all()
  end

  @doc """
  Returns a runtime instance for the given ID, constrained to a World scope.

  The scope is passed via `world_id:` or `world:` in `opts`. If no World scope
  is supplied, the instance is treated as not found.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> instance_id = instance.id
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{id: ^instance_id}} =
      ...>   LemmingsOs.LemmingInstances.get_instance(instance.id, world: world)
  """
  @spec get_instance(Ecto.UUID.t(), keyword()) ::
          {:ok, LemmingInstance.t()} | {:error, :not_found}
  def get_instance(id, opts \\ [])

  def get_instance(id, opts) when is_binary(id) and is_list(opts) do
    case world_scope_id(opts) do
      nil ->
        {:error, :not_found}

      world_id ->
        LemmingInstance
        |> where([instance], instance.id == ^id and instance.world_id == ^world_id)
        |> filter_query(opts)
        |> Repo.one()
        |> normalize_get_result()
    end
  end

  def get_instance(_, _), do: {:error, :not_found}

  @doc """
  Returns a normalized runtime-state snapshot for an instance.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> now = DateTime.utc_now() |> DateTime.truncate(:second)
      iex> :ok =
      ...>   LemmingsOs.LemmingInstances.DetsStore.snapshot(instance.id, %{
      ...>     department_id: instance.department_id,
      ...>     queue: :queue.new(),
      ...>     current_item: nil,
      ...>     retry_count: 0,
      ...>     max_retries: 3,
      ...>     context_messages: [],
      ...>     status: :idle,
      ...>     started_at: now,
      ...>     last_activity_at: now
      ...>   })
      iex> {:ok, runtime_state} =
      ...>   LemmingsOs.LemmingInstances.get_runtime_state(instance.id, world: world)
      iex> runtime_state.status
      "idle"
  """
  @spec get_runtime_state(LemmingInstance.t() | Ecto.UUID.t(), keyword()) ::
          {:ok, map()} | {:error, :not_found}
  def get_runtime_state(instance, opts \\ [])

  def get_runtime_state(%LemmingInstance{id: instance_id}, opts) when is_list(opts) do
    get_runtime_state(instance_id, opts)
  end

  def get_runtime_state(instance_id, opts) when is_binary(instance_id) and is_list(opts) do
    with world_id when is_binary(world_id) <- world_scope_id(opts),
         {:ok, _instance} <- get_instance(instance_id, world_id: world_id),
         {:ok, state} <- read_runtime_state(instance_id) do
      {:ok, normalize_runtime_state(state)}
    else
      _other -> {:error, :not_found}
    end
  end

  def get_runtime_state(_instance_id, _opts), do: {:error, :not_found}

  @doc """
  Updates a runtime instance status and any supplied temporal markers.

  Transition policy is intentionally left open in v1. Callers decide which
  markers to set; the changeset simply casts the permitted fields.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{status: "idle"}} =
      ...>   LemmingsOs.LemmingInstances.update_status(instance, "idle", %{last_activity_at: DateTime.utc_now()})
  """
  @spec update_status(LemmingInstance.t(), String.t(), map()) ::
          {:ok, LemmingInstance.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%LemmingInstance{} = instance, status, attrs \\ %{})
      when is_binary(status) and is_map(attrs) do
    instance
    |> LemmingInstance.status_changeset(Map.put(attrs, :status, status))
    |> Repo.update()
  end

  @doc """
  Appends a follow-up user message to an existing instance transcript.

  Terminal instances reject new work. The context persists the user message and
  forwards the request to the running executor, which owns queueing and
  runtime notifications.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> {:ok, ^instance} =
      ...>   LemmingsOs.LemmingInstances.enqueue_work(instance, "Continue with risks",
      ...>     executor_pid: self(),
      ...>     executor_mod: LemmingsOs.LemmingInstancesTest.FakeExecutor
      ...>   )
      iex> {:error, :terminal_instance} =
      ...>   LemmingsOs.LemmingInstances.enqueue_work(%{instance | status: "failed"}, "Try again")
  """
  @spec enqueue_work(LemmingInstance.t(), String.t(), keyword()) ::
          {:ok, LemmingInstance.t()} | {:error, Ecto.Changeset.t() | atom()}
  def enqueue_work(instance, request_text, opts \\ [])

  def enqueue_work(%LemmingInstance{status: status}, _request_text, _opts)
      when status in @terminal_statuses do
    {:error, :terminal_instance}
  end

  def enqueue_work(%LemmingInstance{} = instance, request_text, opts) do
    if Helpers.blank?(request_text) do
      {:error, :empty_request_text}
    else
      result =
        with {:ok, executor_pid} <- resolve_executor_pid(instance, opts),
             {:ok, message} <- persist_user_message(instance, request_text),
             :ok <- dispatch_work_to_executor(executor_pid, request_text, opts) do
          _ = PubSub.broadcast_message_appended(instance.id, message.id, message.role)

          Logger.info("follow-up request enqueued",
            event: "instance.follow_up.enqueue",
            instance_id: instance.id,
            world_id: instance.world_id,
            department_id: instance.department_id,
            message_id: message.id,
            status: instance.status
          )

          _ =
            ActivityLog.record(:runtime, "instance", "Follow-up request enqueued", %{
              instance_id: instance.id,
              message_id: message.id
            })

          {:ok, instance}
        end

      case result do
        {:ok, instance} ->
          {:ok, instance}

        {:error, reason} = error ->
          Logger.warning("follow-up request could not be queued",
            event: "instance.follow_up.enqueue_failed",
            instance_id: instance.id,
            world_id: instance.world_id,
            department_id: instance.department_id,
            status: instance.status,
            reason: inspect(reason)
          )

          _ =
            ActivityLog.record(:error, "instance", "Follow-up request could not be queued", %{
              instance_id: instance.id,
              reason: inspect(reason)
            })

          error
      end
    end
  end

  @doc """
  Returns transcript messages for the given runtime instance in chronological order.

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
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> [message] = LemmingsOs.LemmingInstances.list_messages(instance)
      iex> {message.role, message.content}
      {"user", "Summarize the roadmap"}
  """
  @spec list_messages(LemmingInstance.t(), keyword()) :: [Message.t()]
  def list_messages(instance, opts \\ [])

  def list_messages(%LemmingInstance{id: instance_id, world_id: world_id}, opts)
      when is_binary(instance_id) and is_binary(world_id) and is_list(opts) do
    Message
    |> where(
      [message],
      message.lemming_instance_id == ^instance_id and message.world_id == ^world_id
    )
    |> filter_query(opts)
    |> order_by([message], asc: message.inserted_at, asc: message.id)
    |> Repo.all()
  end

  def list_messages(_, _), do: []

  @doc """
  Returns aggregate runtime counts for a World.

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
      iex> _ = LemmingsOs.LemmingInstances.spawn_instance(lemming, "Summarize the roadmap")
      iex> summary = LemmingsOs.LemmingInstances.topology_summary(world)
      iex> {summary.instance_count, summary.active_instance_count}
      {1, 1}
  """
  @spec topology_summary(World.t() | Ecto.UUID.t()) :: %{
          instance_count: non_neg_integer(),
          active_instance_count: non_neg_integer()
        }
  def topology_summary(%World{id: world_id}) when is_binary(world_id) do
    topology_summary(world_id)
  end

  def topology_summary(world_id) when is_binary(world_id) do
    case Ecto.UUID.cast(world_id) do
      {:ok, world_id} ->
        LemmingInstance
        |> where([instance], instance.world_id == ^world_id)
        |> select([instance], %{
          instance_count: count(instance.id),
          active_instance_count:
            sum(
              fragment(
                "CASE WHEN ? NOT IN ('failed', 'expired') THEN 1 ELSE 0 END",
                instance.status
              )
            )
        })
        |> Repo.one()
        |> normalize_topology_summary()

      :error ->
        normalize_topology_summary(nil)
    end
  end

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(item in query, where: field(item, ^:status) == ^status), rest)

  defp filter_query(query, [{:statuses, statuses} | rest]) when is_list(statuses),
    do: filter_query(from(item in query, where: field(item, ^:status) in ^statuses), rest)

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]),
    do: filter_query(from(item in query, where: field(item, ^:lemming_id) == ^lemming_id), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]),
    do:
      filter_query(
        from(item in query, where: field(item, ^:department_id) == ^department_id),
        rest
      )

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(item in query, where: field(item, ^:id) in ^ids), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp normalize_get_result(nil), do: {:error, :not_found}
  defp normalize_get_result(%LemmingInstance{} = instance), do: {:ok, instance}

  defp normalize_topology_summary(nil), do: %{instance_count: 0, active_instance_count: 0}

  defp normalize_topology_summary(summary) do
    %{
      instance_count: summary.instance_count || 0,
      active_instance_count: summary.active_instance_count || 0
    }
  end

  defp world_scope_id(opts) do
    case Keyword.get(opts, :world) || Keyword.get(opts, :world_id) do
      %World{id: world_id} when is_binary(world_id) -> world_id
      world_id when is_binary(world_id) -> world_id
      _ -> nil
    end
  end

  defp preload_lemming_for_snapshot(%Lemming{} = lemming, opts) do
    if Keyword.get(opts, :preload, true) do
      Repo.preload(lemming, [:world, city: :world, department: [city: :world]])
    else
      lemming
    end
  end

  defp snapshot_value(%Ecto.Association.NotLoaded{}), do: nil

  defp snapshot_value(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> Map.new(fn {key, value} -> {key, snapshot_value(value)} end)
  end

  defp snapshot_value(%{} = map) do
    map = Map.delete(map, :__meta__)
    Map.new(map, fn {key, value} -> {key, snapshot_value(value)} end)
  end

  defp snapshot_value(list) when is_list(list), do: Enum.map(list, &snapshot_value/1)
  defp snapshot_value(value), do: value

  defp persist_spawn(lemming, config_snapshot, first_request_text) do
    Multi.new()
    |> Multi.insert(
      :instance,
      LemmingInstance.create_changeset(%LemmingInstance{}, %{
        lemming_id: lemming.id,
        world_id: lemming.world_id,
        city_id: lemming.city_id,
        department_id: lemming.department_id,
        status: "created",
        config_snapshot: config_snapshot
      })
    )
    |> Multi.insert(:message, fn %{instance: instance} ->
      Message.changeset(%Message{}, %{
        lemming_instance_id: instance.id,
        world_id: instance.world_id,
        role: "user",
        content: first_request_text
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{instance: instance, message: message}} ->
        {:ok, %{instance: instance, message: message}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp build_work_area_path(%Lemming{department_id: department_id, id: lemming_id})
       when is_binary(department_id) and is_binary(lemming_id) do
    Path.join([department_id, lemming_id])
  end

  @doc """
  Resolves a workspace-relative artifact path for an instance into an absolute path.
  """
  @spec artifact_absolute_path(LemmingInstance.t(), String.t()) ::
          {:ok, %{absolute_path: String.t(), relative_path: String.t()}} | {:error, term()}
  def artifact_absolute_path(
        %LemmingInstance{department_id: department_id, lemming_id: lemming_id},
        relative_path
      )
      when is_binary(department_id) and is_binary(lemming_id) and is_binary(relative_path) do
    cond do
      relative_path == "" ->
        {:error, :invalid_path}

      Path.type(relative_path) == :absolute ->
        {:error, :path_outside_workspace}

      true ->
        workspace_root = workspace_root()
        work_area_root = Path.join([workspace_root, department_id, lemming_id])
        absolute_path = Path.expand(relative_path, work_area_root)

        if path_within_root?(absolute_path, work_area_root) do
          {:ok,
           %{
             absolute_path: absolute_path,
             relative_path: Path.relative_to(absolute_path, work_area_root)
           }}
        else
          {:error, :path_outside_workspace}
        end
    end
  end

  def artifact_absolute_path(_instance, _relative_path), do: {:error, :invalid_path}

  defp create_work_area(work_area_path) when is_binary(work_area_path) do
    workspace_root()
    |> Path.join(work_area_path)
    |> File.mkdir_p()
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("runtime instance work area could not be created",
          event: "instance.work_area.create_failed",
          path: work_area_path,
          reason: inspect(reason)
        )

        {:error, :work_area_unavailable}
    end
  end

  defp cleanup_work_area(work_area_path) when is_binary(work_area_path) do
    work_area_path
    |> work_area_absolute_path()
    |> File.rm_rf()

    :ok
  end

  defp workspace_root do
    Application.get_env(
      :lemmings_os,
      :runtime_workspace_root,
      Path.expand("../../../priv/runtime/workspace", __DIR__)
    )
  end

  defp work_area_absolute_path(work_area_path) do
    Path.join(workspace_root(), work_area_path)
  end

  defp path_within_root?(absolute_path, root_path)
       when is_binary(absolute_path) and is_binary(root_path) do
    normalized_absolute = Path.expand(absolute_path)
    normalized_root = Path.expand(root_path)

    normalized_absolute == normalized_root or
      String.starts_with?(normalized_absolute, normalized_root <> "/")
  end

  defp persist_user_message(%LemmingInstance{} = instance, request_text) do
    %Message{}
    |> Message.changeset(%{
      lemming_instance_id: instance.id,
      world_id: instance.world_id,
      role: "user",
      content: request_text
    })
    |> Repo.insert()
  end

  defp resolve_executor_pid(%LemmingInstance{id: instance_id}, opts) do
    case Keyword.get(opts, :executor_pid) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        case Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance_id) do
          [{pid, _value}] when is_pid(pid) -> {:ok, pid}
          _ -> {:error, :executor_unavailable}
        end
    end
  end

  defp dispatch_work_to_executor(executor_pid, request_text, opts) when is_pid(executor_pid) do
    executor_mod = Keyword.get(opts, :executor_mod, Executor)

    if function_exported?(executor_mod, :enqueue_work, 2) do
      executor_mod.enqueue_work(executor_pid, request_text)
    else
      {:error, :executor_unavailable}
    end
  end

  defp read_runtime_state(instance_id) do
    case EtsStore.get(instance_id) do
      {:ok, state} ->
        {:ok, state}

      {:error, :not_started} ->
        case DetsStore.read(instance_id) do
          {:ok, state} -> {:ok, state}
          _ -> {:error, :not_found}
        end

      {:error, :not_found} ->
        case DetsStore.read(instance_id) do
          {:ok, state} -> {:ok, state}
          _ -> {:error, :not_found}
        end
    end
  end

  defp normalize_runtime_state(state) do
    %{
      retry_count: Map.get(state, :retry_count, 0),
      max_retries: Map.get(state, :max_retries, 3),
      queue_depth: runtime_queue_depth(Map.get(state, :queue)),
      tool_iteration_count: Map.get(state, :tool_iteration_count, 0),
      current_item: Map.get(state, :current_item),
      context_messages: normalize_context_messages(Map.get(state, :context_messages)),
      last_error: Map.get(state, :last_error),
      internal_error_details: Map.get(state, :internal_error_details),
      status: runtime_status(Map.get(state, :status)),
      started_at: Map.get(state, :started_at),
      last_activity_at: Map.get(state, :last_activity_at)
    }
  end

  defp runtime_queue_depth(queue) when is_tuple(queue) do
    if :queue.is_queue(queue), do: :queue.len(queue), else: 0
  end

  defp runtime_queue_depth(queue) when is_list(queue), do: length(queue)
  defp runtime_queue_depth(_queue), do: 0

  defp normalize_context_messages(messages) when is_list(messages), do: messages
  defp normalize_context_messages(_messages), do: []

  defp runtime_status(status) when is_atom(status), do: Atom.to_string(status)
  defp runtime_status(status) when is_binary(status), do: status
  defp runtime_status(_status), do: nil
end
