defmodule LemmingsOs.LemmingCalls do
  @moduledoc """
  World-scoped boundary for durable lemming-to-lemming collaboration calls.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime
  alias LemmingsOs.Worlds.World

  @terminal_statuses ~w(completed failed)

  @create_fields ~w(
    world_id
    city_id
    caller_department_id
    callee_department_id
    caller_lemming_id
    callee_lemming_id
    caller_instance_id
    callee_instance_id
    root_call_id
    previous_call_id
    request_text
    status
    result_summary
    error_summary
    recovery_status
    started_at
    completed_at
  )a

  @doc """
  Returns persisted collaboration calls for a World.

  Accepts a `%World{}` or explicit World id. Optional filters can narrow by
  status, department, caller instance, callee instance, or successor chain.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> LemmingsOs.LemmingCalls.list_calls(world)
      []
  """
  @spec list_calls(World.t() | Ecto.UUID.t(), keyword()) :: [LemmingCall.t()]
  def list_calls(world_or_id, opts \\ [])

  def list_calls(%World{id: world_id}, opts) when is_binary(world_id) and is_list(opts) do
    list_calls(world_id, opts)
  end

  def list_calls(world_id, opts) when is_binary(world_id) and is_list(opts) do
    LemmingCall
    |> filter_query([{:world_id, world_id} | opts])
    |> order_by([call], desc: call.inserted_at, desc: call.id)
    |> Repo.all()
  end

  def list_calls(_world_or_id, _opts), do: []

  @doc """
  Returns one collaboration call constrained to an explicit World.

  Missing or mismatched World scope returns `{:error, :not_found}`.

  ## Examples

      iex> {:error, :not_found} = LemmingsOs.LemmingCalls.get_call(Ecto.UUID.generate(), world_id: Ecto.UUID.generate())
  """
  @spec get_call(Ecto.UUID.t(), keyword()) :: {:ok, LemmingCall.t()} | {:error, :not_found}
  def get_call(id, opts) when is_binary(id) and is_list(opts) do
    case world_scope_id(opts) do
      world_id when is_binary(world_id) ->
        LemmingCall
        |> where([call], call.id == ^id and call.world_id == ^world_id)
        |> filter_query(opts)
        |> Repo.one()
        |> normalize_get_result()

      _ ->
        {:error, :not_found}
    end
  end

  def get_call(_id, _opts), do: {:error, :not_found}

  @doc """
  Creates durable collaboration call under an explicit World scope.

  Caller and callee instance ids are used to derive World, City, Department, and
  Lemming identity, preventing callers from forging cross-World links.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> {:error, :missing_instance_ids} = LemmingsOs.LemmingCalls.create_call(%{}, world: world)
  """
  @spec create_call(map(), keyword()) ::
          {:ok, LemmingCall.t()} | {:error, Ecto.Changeset.t() | atom()}
  def create_call(attrs, opts \\ [])

  def create_call(attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, world_id} <- explicit_world_scope(opts),
         {:ok, caller_instance_id, callee_instance_id} <- instance_ids(attrs),
         {:ok, caller_instance} <- get_instance_for_call(caller_instance_id, world_id),
         {:ok, callee_instance} <- get_instance_for_call(callee_instance_id, world_id),
         :ok <- validate_same_city(caller_instance, callee_instance),
         :ok <- validate_successor_world(attrs, world_id) do
      attrs
      |> normalize_create_attrs(world_id, caller_instance, callee_instance)
      |> insert_call()
    end
  end

  def create_call(_attrs, _opts), do: {:error, :invalid_attrs}

  @doc """
  Updates persisted call status and optional result/error summary fields.

  ## Examples

      iex> call = LemmingsOs.Factory.insert(:lemming_call, status: "accepted")
      iex> {:ok, updated} = LemmingsOs.LemmingCalls.update_call_status(call, "running")
      iex> updated.status
      "running"

      iex> call = LemmingsOs.Factory.insert(:lemming_call, status: "accepted")
      iex> {:error, changeset} = LemmingsOs.LemmingCalls.update_call_status(call, "unknown")
      iex> changeset.valid?
      false
  """
  @spec update_call_status(LemmingCall.t(), String.t(), map()) ::
          {:ok, LemmingCall.t()} | {:error, Ecto.Changeset.t()}
  def update_call_status(%LemmingCall{} = call, status, attrs \\ %{})
      when is_binary(status) and is_map(attrs) do
    call
    |> LemmingCall.status_changeset(Map.put(attrs, :status, status))
    |> Repo.update()
  end

  @doc """
  Lists calls spawned by a manager instance.

  ## Examples

      iex> call = LemmingsOs.Factory.insert(:lemming_call)
      iex> [found] = LemmingsOs.LemmingCalls.list_manager_calls(call.caller_instance)
      iex> found.id == call.id
      true

      iex> LemmingsOs.LemmingCalls.list_manager_calls(%{})
      []
  """
  @spec list_manager_calls(LemmingInstance.t(), keyword()) :: [LemmingCall.t()]
  def list_manager_calls(manager_instance, opts \\ [])

  def list_manager_calls(%LemmingInstance{id: instance_id, world_id: world_id}, opts)
      when is_binary(instance_id) and is_binary(world_id) and is_list(opts) do
    LemmingCall
    |> filter_query([{:world_id, world_id}, {:caller_instance_id, instance_id} | opts])
    |> order_by([call], desc: call.inserted_at, desc: call.id)
    |> Repo.all()
  end

  def list_manager_calls(_manager_instance, _opts), do: []

  @doc """
  Lists calls received by a child instance.

  ## Examples

      iex> call = LemmingsOs.Factory.insert(:lemming_call)
      iex> [found] = LemmingsOs.LemmingCalls.list_child_calls(call.callee_instance)
      iex> found.id == call.id
      true

      iex> LemmingsOs.LemmingCalls.list_child_calls(%{})
      []
  """
  @spec list_child_calls(LemmingInstance.t(), keyword()) :: [LemmingCall.t()]
  def list_child_calls(child_instance, opts \\ [])

  def list_child_calls(%LemmingInstance{id: instance_id, world_id: world_id}, opts)
      when is_binary(instance_id) and is_binary(world_id) and is_list(opts) do
    LemmingCall
    |> filter_query([{:world_id, world_id}, {:callee_instance_id, instance_id} | opts])
    |> order_by([call], desc: call.inserted_at, desc: call.id)
    |> Repo.all()
  end

  def list_child_calls(_child_instance, _opts), do: []

  @doc """
  Returns true when lemming has manager collaboration role.

  ## Examples

      iex> LemmingsOs.LemmingCalls.manager?(%LemmingsOs.Lemmings.Lemming{collaboration_role: "manager"})
      true

      iex> LemmingsOs.LemmingCalls.manager?(%LemmingsOs.Lemmings.Lemming{collaboration_role: "worker"})
      false
  """
  @spec manager?(Lemming.t()) :: boolean()
  def manager?(%Lemming{collaboration_role: "manager"}), do: true
  def manager?(%Lemming{}), do: false

  @doc """
  Returns true when lemming has worker collaboration role.

  ## Examples

      iex> LemmingsOs.LemmingCalls.worker?(%LemmingsOs.Lemmings.Lemming{collaboration_role: "worker"})
      true

      iex> LemmingsOs.LemmingCalls.worker?(%LemmingsOs.Lemmings.Lemming{collaboration_role: "manager"})
      false
  """
  @spec worker?(Lemming.t()) :: boolean()
  def worker?(%Lemming{collaboration_role: "worker"}), do: true
  def worker?(%Lemming{}), do: false

  @doc """
  Returns manager-visible lemming call targets for an instance.

  Only manager lemmings receive targets. Results are limited to active workers
  in the same department plus active managers in other departments in the same
  World and City.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city, slug: "ops")
      iex> manager = LemmingsOs.Factory.insert(:manager_lemming, world: world, city: city, department: department, status: "active")
      iex> _worker = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, status: "active", slug: "researcher")
      iex> {:ok, instance} = LemmingsOs.LemmingInstances.spawn_instance(manager, "Coordinate work")
      iex> Enum.map(LemmingsOs.LemmingCalls.available_targets(instance), & &1.slug)
      ["researcher"]

      iex> worker = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department, status: "active")
      iex> {:ok, worker_instance} = LemmingsOs.LemmingInstances.spawn_instance(worker, "Do work")
      iex> LemmingsOs.LemmingCalls.available_targets(worker_instance)
      []
  """
  @spec available_targets(LemmingInstance.t()) :: [map()]
  def available_targets(%LemmingInstance{} = instance) do
    with {:ok, caller} <- caller_lemming(instance),
         true <- manager?(caller) do
      instance
      |> target_query()
      |> Repo.all()
      |> Enum.map(&target_capability(instance, &1))
    else
      _other -> []
    end
  end

  def available_targets(_instance), do: []

  @doc """
  Starts or continues a collaboration call requested by a manager instance.

  ## Examples

      iex> worker_instance = LemmingsOs.Factory.insert(:lemming_instance)
      iex> LemmingsOs.LemmingCalls.request_call(worker_instance, %{target: "anyone", request: "Help"})
      {:error, :lemming_call_not_allowed}

      iex> LemmingsOs.LemmingCalls.request_call(worker_instance, %{target: "", request: "Help"})
      {:error, :empty_target}
  """
  @spec request_call(LemmingInstance.t(), map(), keyword()) ::
          {:ok, LemmingCall.t()} | {:error, atom() | Ecto.Changeset.t()}
  def request_call(caller_instance, attrs, opts \\ [])

  def request_call(%LemmingInstance{} = caller_instance, attrs, opts)
      when is_map(attrs) and is_list(opts) do
    with {:ok, request_text} <- request_text(attrs),
         {:ok, target} <- target_text(attrs) do
      case continue_call_id(attrs) do
        nil -> start_new_call(caller_instance, target, request_text, opts)
        call_id -> continue_call(caller_instance, call_id, target, request_text, opts)
      end
    end
  end

  def request_call(_caller_instance, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc """
  Synchronizes terminal child executor outcomes back to durable call records.

  ## Examples

      iex> call = LemmingsOs.Factory.insert(:lemming_call, status: "running")
      iex> :ok = LemmingsOs.LemmingCalls.sync_child_instance_terminal(call.callee_instance, "idle", %{result_summary: "Done"})
      iex> {:ok, updated} = LemmingsOs.LemmingCalls.get_call(call.id, world_id: call.world_id)
      iex> {updated.status, updated.result_summary}
      {"completed", "Done"}

      iex> LemmingsOs.LemmingCalls.sync_child_instance_terminal(%{}, "idle", %{})
      :ok
  """
  @spec sync_child_instance_terminal(LemmingInstance.t(), String.t(), map()) :: :ok
  def sync_child_instance_terminal(%LemmingInstance{} = instance, "idle", attrs)
      when is_map(attrs) do
    update_child_calls(instance, "completed", %{
      result_summary: Map.get(attrs, :result_summary),
      completed_at: Map.get(attrs, :completed_at) || now()
    })
  end

  def sync_child_instance_terminal(%LemmingInstance{} = instance, "failed", attrs)
      when is_map(attrs) do
    update_child_calls(instance, "failed", %{
      error_summary: Map.get(attrs, :error_summary),
      completed_at: Map.get(attrs, :completed_at) || now()
    })
  end

  def sync_child_instance_terminal(%LemmingInstance{} = instance, "expired", attrs)
      when is_map(attrs) do
    update_child_calls(instance, "failed", %{
      error_summary:
        Map.get(attrs, :error_summary) || "Child instance expired before completion.",
      recovery_status: "expired",
      completed_at: Map.get(attrs, :completed_at) || now()
    })
  end

  def sync_child_instance_terminal(_instance, _status, _attrs), do: :ok

  @doc """
  Records direct child input against the parent call record.

  ## Examples

      iex> call = LemmingsOs.Factory.insert(:lemming_call, status: "running")
      iex> :ok = LemmingsOs.LemmingCalls.note_child_user_input(call.callee_instance, "More context")
      iex> {:ok, updated} = LemmingsOs.LemmingCalls.get_call(call.id, world_id: call.world_id)
      iex> updated.recovery_status
      "direct_child_input"

      iex> LemmingsOs.LemmingCalls.note_child_user_input(%{}, "More context")
      :ok
  """
  @spec note_child_user_input(LemmingInstance.t(), String.t()) :: :ok
  def note_child_user_input(%LemmingInstance{} = instance, request_text)
      when is_binary(request_text) do
    update_child_calls(instance, "running", %{
      result_summary: "Direct child input received.",
      recovery_status: "direct_child_input"
    })
  end

  def note_child_user_input(_instance, _request_text), do: :ok

  defp caller_lemming(%LemmingInstance{lemming: %Lemming{} = lemming}), do: {:ok, lemming}

  defp caller_lemming(%LemmingInstance{lemming_id: lemming_id, world_id: world_id})
       when is_binary(lemming_id) and is_binary(world_id) do
    case Repo.get_by(Lemming, id: lemming_id, world_id: world_id) do
      %Lemming{} = lemming -> {:ok, lemming}
      nil -> {:error, :caller_lemming_not_found}
    end
  end

  defp caller_lemming(_instance), do: {:error, :caller_lemming_not_found}

  defp target_query(%LemmingInstance{
         world_id: world_id,
         city_id: city_id,
         department_id: department_id,
         lemming_id: lemming_id
       }) do
    from lemming in Lemming,
      join: department in assoc(lemming, :department),
      where:
        lemming.world_id == ^world_id and
          lemming.city_id == ^city_id and
          lemming.id != ^lemming_id and
          lemming.status == "active" and
          ((lemming.department_id == ^department_id and lemming.collaboration_role == "worker") or
             (lemming.department_id != ^department_id and lemming.collaboration_role == "manager")),
      preload: [department: department],
      order_by: [asc: department.slug, asc: lemming.slug]
  end

  defp target_capability(caller_instance, %Lemming{} = target) do
    department = target.department

    %{
      slug: target.slug,
      capability: "#{department.slug}/#{target.slug}",
      role: target.collaboration_role,
      department_id: target.department_id,
      department_slug: department.slug,
      lemming_id: target.id,
      description: target.description || target.name,
      relation: target_relation(caller_instance, target)
    }
  end

  defp target_relation(%LemmingInstance{department_id: department_id}, %Lemming{
         department_id: department_id
       }),
       do: "same_department_worker"

  defp target_relation(%LemmingInstance{}, %Lemming{collaboration_role: "manager"}),
    do: "peer_department_manager"

  defp target_relation(%LemmingInstance{}, %Lemming{}), do: "unavailable"

  defp request_text(attrs) do
    attrs
    |> attr_value(:request)
    |> normalize_required_text(:empty_request_text)
  end

  defp target_text(attrs) do
    attrs
    |> attr_value(:target)
    |> normalize_required_text(:empty_target)
  end

  defp normalize_required_text(value, error) when is_binary(value) do
    if Helpers.blank?(value), do: {:error, error}, else: {:ok, String.trim(value)}
  end

  defp normalize_required_text(_value, error), do: {:error, error}

  defp continue_call_id(attrs) do
    case attr_value(attrs, :continue_call_id) do
      value when is_binary(value) -> if(Helpers.blank?(value), do: nil, else: value)
      _value -> nil
    end
  end

  defp attr_value(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp start_new_call(caller_instance, target, request_text, opts) do
    with :ok <- authorize_manager(caller_instance),
         {:ok, callee} <- resolve_target(caller_instance, target),
         {:ok, callee_instance} <- spawn_child(callee, request_text, opts),
         {:ok, call} <-
           create_call(
             %{
               caller_instance_id: caller_instance.id,
               callee_instance_id: callee_instance.id,
               request_text: request_text,
               status: "accepted"
             },
             world_id: caller_instance.world_id
           ) do
      update_call_status(call, "running", %{started_at: now()})
    end
  end

  defp continue_call(caller_instance, call_id, target, request_text, opts) do
    with :ok <- authorize_manager(caller_instance),
         {:ok, call_id} <- cast_uuid(call_id),
         {:ok, call} <- get_call(call_id, world_id: caller_instance.world_id),
         :ok <- validate_caller_owns_call(caller_instance, call),
         {:ok, callee_instance} <- get_call_callee_instance(call) do
      continue_existing_or_successor(
        caller_instance,
        call,
        callee_instance,
        target,
        request_text,
        opts
      )
    end
  end

  defp cast_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :call_not_found}
    end
  end

  defp authorize_manager(caller_instance) do
    with {:ok, caller} <- caller_lemming(caller_instance),
         true <- manager?(caller) do
      :ok
    else
      false -> {:error, :lemming_call_not_allowed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_target(caller_instance, target) do
    caller_instance
    |> available_targets()
    |> Enum.find(&target_matches?(&1, target))
    |> case do
      nil -> {:error, :target_not_available}
      %{lemming_id: lemming_id} -> {:ok, Repo.get!(Lemming, lemming_id)}
    end
  end

  defp target_matches?(target, value), do: value in [target.slug, target.capability]

  defp spawn_child(callee, request_text, opts) do
    runtime_mod = Keyword.get(opts, :runtime_mod, Runtime)

    if function_exported?(runtime_mod, :spawn_session, 3) do
      runtime_mod.spawn_session(callee, request_text, Keyword.get(opts, :runtime_opts, []))
    else
      {:error, :runtime_unavailable}
    end
  end

  defp validate_caller_owns_call(
         %LemmingInstance{id: caller_instance_id},
         %LemmingCall{caller_instance_id: caller_instance_id}
       ),
       do: :ok

  defp validate_caller_owns_call(%LemmingInstance{}, %LemmingCall{}),
    do: {:error, :call_not_found}

  defp get_call_callee_instance(%LemmingCall{
         callee_instance_id: callee_instance_id,
         world_id: world_id
       }) do
    LemmingInstances.get_instance(callee_instance_id, world_id: world_id, preload: [:lemming])
  end

  defp continue_existing_or_successor(
         caller_instance,
         call,
         %LemmingInstance{status: "expired"} = callee_instance,
         target,
         request_text,
         opts
       ) do
    root_call_id = call.root_call_id || call.id

    with {:ok, callee} <- successor_callee(caller_instance, callee_instance, target),
         {:ok, successor_instance} <- spawn_child(callee, request_text, opts),
         {:ok, successor_call} <-
           create_call(
             %{
               caller_instance_id: caller_instance.id,
               callee_instance_id: successor_instance.id,
               root_call_id: root_call_id,
               previous_call_id: call.id,
               request_text: request_text,
               status: "accepted"
             },
             world_id: caller_instance.world_id
           ) do
      update_call_status(successor_call, "running", %{started_at: now()})
    end
  end

  defp continue_existing_or_successor(
         _caller_instance,
         %LemmingCall{} = call,
         %LemmingInstance{} = callee_instance,
         _target,
         request_text,
         opts
       ) do
    with :ok <- ensure_call_continuable(call),
         {:ok, _instance} <- LemmingInstances.enqueue_work(callee_instance, request_text, opts) do
      update_call_status(call, "running", %{
        result_summary: nil,
        error_summary: nil,
        recovery_status: nil
      })
    end
  end

  defp successor_callee(caller_instance, %LemmingInstance{lemming: %Lemming{} = callee}, target) do
    callee = Repo.preload(callee, :department)

    if target_matches?(target_capability(caller_instance, callee), target) do
      {:ok, callee}
    else
      resolve_target(caller_instance, target)
    end
  end

  defp successor_callee(caller_instance, %LemmingInstance{lemming_id: lemming_id}, target)
       when is_binary(lemming_id) do
    callee = Lemming |> Repo.get!(lemming_id) |> Repo.preload(:department)

    if target_matches?(target_capability(caller_instance, callee), target) do
      {:ok, callee}
    else
      resolve_target(caller_instance, target)
    end
  end

  defp ensure_call_continuable(%LemmingCall{status: status}) when status in @terminal_statuses,
    do: {:error, :call_terminal}

  defp ensure_call_continuable(%LemmingCall{}), do: :ok

  defp update_child_calls(instance, status, attrs) do
    instance
    |> list_child_calls(statuses: ["accepted", "running", "needs_more_context", "partial_result"])
    |> Enum.each(fn call ->
      _ = update_call_status(call, status, attrs)
    end)

    :ok
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(call in query, where: call.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]),
    do: filter_query(from(call in query, where: call.city_id == ^city_id), rest)

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(call in query, where: call.status == ^status), rest)

  defp filter_query(query, [{:statuses, statuses} | rest]) when is_list(statuses),
    do: filter_query(from(call in query, where: call.status in ^statuses), rest)

  defp filter_query(query, [{:caller_instance_id, instance_id} | rest]),
    do: filter_query(from(call in query, where: call.caller_instance_id == ^instance_id), rest)

  defp filter_query(query, [{:callee_instance_id, instance_id} | rest]),
    do: filter_query(from(call in query, where: call.callee_instance_id == ^instance_id), rest)

  defp filter_query(query, [{:root_call_id, call_id} | rest]),
    do: filter_query(from(call in query, where: call.root_call_id == ^call_id), rest)

  defp filter_query(query, [{:previous_call_id, call_id} | rest]),
    do: filter_query(from(call in query, where: call.previous_call_id == ^call_id), rest)

  defp filter_query(query, [{:caller_department_id, department_id} | rest]),
    do:
      filter_query(from(call in query, where: call.caller_department_id == ^department_id), rest)

  defp filter_query(query, [{:callee_department_id, department_id} | rest]),
    do:
      filter_query(from(call in query, where: call.callee_department_id == ^department_id), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]) do
    query =
      from call in query,
        where:
          call.caller_department_id == ^department_id or
            call.callee_department_id == ^department_id

    filter_query(query, rest)
  end

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(call in query, where: call.id in ^ids), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp normalize_get_result(nil), do: {:error, :not_found}
  defp normalize_get_result(%LemmingCall{} = call), do: {:ok, call}

  defp explicit_world_scope(opts) do
    case world_scope_id(opts) do
      nil -> {:error, :missing_world_scope}
      world_id -> {:ok, world_id}
    end
  end

  defp world_scope_id(opts) do
    case Keyword.get(opts, :world) || Keyword.get(opts, :world_id) do
      %World{id: world_id} when is_binary(world_id) -> world_id
      world_id when is_binary(world_id) -> world_id
      _ -> nil
    end
  end

  defp instance_ids(attrs) do
    case Helpers.take_existing(attrs, [:caller_instance_id, :callee_instance_id]) do
      %{caller_instance_id: caller_instance_id, callee_instance_id: callee_instance_id}
      when is_binary(caller_instance_id) and is_binary(callee_instance_id) ->
        {:ok, caller_instance_id, callee_instance_id}

      _ ->
        {:error, :missing_instance_ids}
    end
  end

  defp get_instance_for_call(instance_id, world_id) do
    LemmingInstance
    |> where([instance], instance.id == ^instance_id and instance.world_id == ^world_id)
    |> Repo.one()
    |> case do
      %LemmingInstance{} = instance -> {:ok, instance}
      nil -> {:error, :instance_not_found}
    end
  end

  defp validate_same_city(
         %LemmingInstance{city_id: city_id},
         %LemmingInstance{city_id: city_id}
       ),
       do: :ok

  defp validate_same_city(%LemmingInstance{}, %LemmingInstance{}), do: {:error, :cross_city_call}

  defp validate_successor_world(attrs, world_id) do
    call_attrs = Helpers.take_existing(attrs, [:root_call_id, :previous_call_id])

    case validate_optional_call_world(Map.get(call_attrs, :root_call_id), world_id) do
      :ok -> validate_optional_call_world(Map.get(call_attrs, :previous_call_id), world_id)
      {:error, _reason} = error -> error
    end
  end

  defp validate_optional_call_world(nil, _world_id), do: :ok

  defp validate_optional_call_world(call_id, world_id) when is_binary(call_id) do
    case Repo.exists?(
           from call in LemmingCall, where: call.id == ^call_id and call.world_id == ^world_id
         ) do
      true -> :ok
      false -> {:error, :call_not_found}
    end
  end

  defp validate_optional_call_world(_call_id, _world_id), do: {:error, :call_not_found}

  defp normalize_create_attrs(attrs, world_id, caller_instance, callee_instance) do
    attrs
    |> Helpers.take_existing(@create_fields)
    |> Map.merge(%{
      world_id: world_id,
      city_id: caller_instance.city_id,
      caller_department_id: caller_instance.department_id,
      callee_department_id: callee_instance.department_id,
      caller_lemming_id: caller_instance.lemming_id,
      callee_lemming_id: callee_instance.lemming_id,
      caller_instance_id: caller_instance.id,
      callee_instance_id: callee_instance.id
    })
    |> Map.put_new(:status, "accepted")
  end

  defp insert_call(attrs) do
    %LemmingCall{}
    |> LemmingCall.create_changeset(attrs)
    |> Repo.insert()
  end
end
