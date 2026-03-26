defmodule LemmingsOs.LemmingInstances do
  @moduledoc """
  Runtime persistence boundary for spawned lemming sessions.

  This context owns durable instance rows, immutable transcript messages, and
  world-scoped runtime queries. It does not start executors or notify
  schedulers.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Helpers
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.Repo
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
        config_snapshot = lemming |> Resolver.resolve() |> snapshot_value()

        transaction =
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

        case Repo.transaction(transaction) do
          {:ok, %{instance: instance}} -> {:ok, instance}
          {:error, _step, reason, _changes} -> {:error, reason}
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
      iex> [%LemmingsOs.LemmingInstances.LemmingInstance{id: ^instance.id}] =
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
      iex> {:ok, %LemmingsOs.LemmingInstances.LemmingInstance{id: ^instance.id}} =
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

  Terminal instances reject new work. The context does not start executors or
  notify schedulers directly.

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
      iex> {:ok, ^instance} = LemmingsOs.LemmingInstances.enqueue_work(instance, "Continue with risks")
      iex> {:error, :terminal_instance} =
      ...>   LemmingsOs.LemmingInstances.enqueue_work(%{instance | status: "failed"}, "Try again")
  """
  @spec enqueue_work(LemmingInstance.t(), String.t(), keyword()) ::
          {:ok, LemmingInstance.t()} | {:error, Ecto.Changeset.t() | atom()}
  def enqueue_work(instance, request_text, opts)

  def enqueue_work(%LemmingInstance{status: status}, _request_text, _opts)
      when status in @terminal_statuses do
    {:error, :terminal_instance}
  end

  def enqueue_work(%LemmingInstance{} = instance, request_text, _opts) do
    if Helpers.blank?(request_text) do
      {:error, :empty_request_text}
    else
      %Message{}
      |> Message.changeset(%{
        lemming_instance_id: instance.id,
        world_id: instance.world_id,
        role: "user",
        content: request_text
      })
      |> Repo.insert()
      |> case do
        {:ok, _message} -> {:ok, instance}
        {:error, changeset} -> {:error, changeset}
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
    do: filter_query(from(item in query, where: item.status == ^status), rest)

  defp filter_query(query, [{:statuses, statuses} | rest]) when is_list(statuses),
    do: filter_query(from(item in query, where: item.status in ^statuses), rest)

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]),
    do: filter_query(from(item in query, where: item.lemming_id == ^lemming_id), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]),
    do: filter_query(from(item in query, where: item.department_id == ^department_id), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(item in query, where: item.id in ^ids), rest)

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

  defp snapshot_value(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {key, snapshot_value(value)} end)
  end

  defp snapshot_value(%{} = map) do
    Map.new(map, fn {key, value} -> {key, snapshot_value(value)} end)
  end

  defp snapshot_value(list) when is_list(list), do: Enum.map(list, &snapshot_value/1)
  defp snapshot_value(value), do: value
end
