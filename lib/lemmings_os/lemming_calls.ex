defmodule LemmingsOs.LemmingCalls do
  @moduledoc """
  World-scoped boundary for durable lemming-to-lemming collaboration calls.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

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

      iex> call = %LemmingsOs.LemmingCalls.LemmingCall{status: "accepted"}
      iex> changeset = LemmingsOs.LemmingCalls.LemmingCall.status_changeset(call, %{status: "running"})
      iex> changeset.valid?
      true
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
  """
  @spec manager?(Lemming.t()) :: boolean()
  def manager?(%Lemming{collaboration_role: "manager"}), do: true
  def manager?(%Lemming{}), do: false

  @doc """
  Returns true when lemming has worker collaboration role.
  """
  @spec worker?(Lemming.t()) :: boolean()
  def worker?(%Lemming{collaboration_role: "worker"}), do: true
  def worker?(%Lemming{}), do: false

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
