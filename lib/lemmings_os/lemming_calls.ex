defmodule LemmingsOs.LemmingCalls do
  @moduledoc """
  World-scoped boundary for durable lemming-to-lemming collaboration calls.
  """

  import Ecto.Query, warn: false

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingCalls.PubSub
  alias LemmingsOs.LemmingCalls.Telemetry
  alias LemmingsOs.LemmingCalls.LemmingCall
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Runtime
  alias LemmingsOs.Runtime.ActivityLog
  alias LemmingsOs.Worlds.World

  @terminal_statuses ~w(completed failed)
  @lemming_call_tool "lemming.call"
  @delegation_max_artifacts 2
  @delegation_artifact_char_limit 12_000

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
    previous_status = call.status

    case call
         |> LemmingCall.status_changeset(Map.put(attrs, :status, status))
         |> Repo.update() do
      {:ok, updated_call} = ok ->
        emit_status_observability(updated_call, previous_status)
        ok

      {:error, _changeset} = error ->
        emit_status_update_failure(call, status)
        error
    end
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
      iex> manager = LemmingsOs.Factory.insert(:manager_lemming, world: world, city: city, department: department, status: "active", tools_config: %{allowed_tools: ["lemming.call"]})
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
      |> Enum.filter(&can_call_lemming?(instance, &1, instance.config_snapshot))
      |> Enum.map(&target_capability(instance, &1))
    else
      _other -> []
    end
  end

  def available_targets(_instance), do: []

  @doc """
  Returns true when a caller instance is authorized to address a target lemming.

  Manager role is necessary but not sufficient: effective `lemming.call` tool
  availability and the collaboration routing policy must also allow the target.
  """
  @spec can_call_lemming?(LemmingInstance.t(), Lemming.t(), map()) :: boolean()
  def can_call_lemming?(
        %LemmingInstance{} = caller_instance,
        %Lemming{} = target_lemming,
        config_snapshot
      )
      when is_map(config_snapshot) do
    with {:ok, caller} <- caller_lemming(caller_instance),
         true <- manager?(caller),
         true <- lemming_call_enabled?(config_snapshot),
         true <- target_lemming.status == "active",
         true <- caller_instance.world_id == target_lemming.world_id,
         true <- caller_instance.city_id == target_lemming.city_id,
         true <- call_relation_allowed?(caller_instance, target_lemming) do
      true
    else
      _other -> false
    end
  end

  def can_call_lemming?(_caller_instance, _target_lemming, _config_snapshot), do: false

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

  defp lemming_call_enabled?(config_snapshot) do
    allowed_tools = config_tools(config_snapshot, :allowed_tools)
    denied_tools = MapSet.new(config_tools(config_snapshot, :denied_tools))

    @lemming_call_tool in allowed_tools and not MapSet.member?(denied_tools, @lemming_call_tool)
  end

  defp config_tools(config_snapshot, field) when is_map(config_snapshot) do
    config_snapshot
    |> config_value(:tools_config)
    |> case do
      tools_config when is_map(tools_config) ->
        tools_config
        |> config_value(field)
        |> normalize_tool_list()

      _tools_config ->
        []
    end
  end

  defp config_value(map, field) when is_map(map),
    do: Map.get(map, field) || Map.get(map, "#{field}")

  defp normalize_tool_list(tools) when is_list(tools), do: Enum.filter(tools, &is_binary/1)
  defp normalize_tool_list(_tools), do: []

  defp call_relation_allowed?(
         %LemmingInstance{department_id: department_id},
         %Lemming{department_id: department_id, collaboration_role: "worker"}
       ),
       do: true

  defp call_relation_allowed?(
         %LemmingInstance{department_id: caller_department_id},
         %Lemming{department_id: target_department_id, collaboration_role: "manager"}
       )
       when caller_department_id != target_department_id,
       do: true

  defp call_relation_allowed?(_caller_instance, _target_lemming), do: false

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
         child_request_text = child_request_text(caller_instance, request_text),
         {:ok, callee_instance} <- spawn_child(callee, child_request_text, opts) do
      case persist_spawned_call(caller_instance, callee_instance, request_text, opts) do
        {:ok, call} ->
          {:ok, call}

        {:error, reason} = error ->
          compensate_spawned_child(callee_instance, reason)

          emit_request_failure(caller_instance, reason, %{
            target: target,
            callee_instance_id: callee_instance.id
          })

          error
      end
    else
      {:error, reason} = error ->
        emit_request_failure(caller_instance, reason, %{target: target})
        error
    end
  end

  defp continue_call(caller_instance, call_id, target, request_text, opts) do
    with :ok <- authorize_manager(caller_instance),
         {:ok, call_id} <- cast_uuid(call_id),
         {:ok, call} <- get_call(call_id, world_id: caller_instance.world_id),
         :ok <- validate_caller_owns_call(caller_instance, call),
         :ok <- ensure_call_continuable(call),
         {:ok, callee_instance} <- get_call_callee_instance(call) do
      continue_existing_or_successor(
        caller_instance,
        call,
        callee_instance,
        target,
        request_text,
        opts
      )
    else
      {:error, reason} = error ->
        emit_request_failure(caller_instance, reason, %{
          target: target,
          lemming_call_id: call_id
        })

        error
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
         child_request_text = child_request_text(caller_instance, request_text),
         {:ok, successor_instance} <- spawn_child(callee, child_request_text, opts) do
      attrs = %{root_call_id: root_call_id, previous_call_id: call.id}

      case persist_spawned_call(caller_instance, successor_instance, request_text, opts, attrs) do
        {:ok, updated_call} ->
          emit_recovered(call, updated_call)
          {:ok, updated_call}

        {:error, reason} = error ->
          compensate_spawned_child(successor_instance, reason)
          error
      end
    end
  end

  defp continue_existing_or_successor(
         caller_instance,
         %LemmingCall{} = call,
         %LemmingInstance{} = callee_instance,
         _target,
         request_text,
         opts
       ) do
    child_request_text = child_request_text(caller_instance, request_text)

    with :ok <- authorize_target(caller_instance, callee_instance),
         {:ok, _instance} <-
           LemmingInstances.enqueue_work(callee_instance, child_request_text, opts) do
      update_call_status(call, "running", %{
        result_summary: nil,
        error_summary: nil,
        recovery_status: nil
      })
    end
  end

  defp authorize_target(caller_instance, %LemmingInstance{lemming: %Lemming{} = target}) do
    if can_call_lemming?(caller_instance, target, caller_instance.config_snapshot) do
      :ok
    else
      {:error, :lemming_call_not_allowed}
    end
  end

  defp authorize_target(caller_instance, %LemmingInstance{
         lemming_id: lemming_id,
         world_id: world_id
       })
       when is_binary(lemming_id) and is_binary(world_id) do
    case Repo.get_by(Lemming, id: lemming_id, world_id: world_id) do
      %Lemming{} = target ->
        if can_call_lemming?(caller_instance, target, caller_instance.config_snapshot) do
          :ok
        else
          {:error, :lemming_call_not_allowed}
        end

      nil ->
        {:error, :target_not_available}
    end
  end

  defp persist_spawned_call(
         caller_instance,
         callee_instance,
         request_text,
         opts,
         extra_attrs \\ %{}
       ) do
    create_call_fun = Keyword.get(opts, :create_call_fun, &create_call/2)
    update_call_status_fun = Keyword.get(opts, :update_call_status_fun, &update_call_status/3)

    attrs =
      Map.merge(
        %{
          caller_instance_id: caller_instance.id,
          callee_instance_id: callee_instance.id,
          request_text: request_text,
          status: "accepted"
        },
        extra_attrs
      )

    with {:ok, call} <-
           safe_call_persistence(fn ->
             create_call_fun.(attrs, world_id: caller_instance.world_id)
           end) do
      safe_call_persistence(fn ->
        update_call_status_fun.(call, "running", %{started_at: now()})
      end)
    end
  end

  defp safe_call_persistence(fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp compensate_spawned_child(%LemmingInstance{} = instance, reason) do
    now = now()

    _ =
      LemmingInstances.update_status(instance, "expired", %{
        stopped_at: now,
        last_activity_at: now
      })

    Logger.warning("expired spawned child after lemming call persistence failure",
      event: "lemming_call.child_compensated",
      instance_id: instance.id,
      reason: inspect(reason)
    )

    :ok
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

  defp child_request_text(%LemmingInstance{} = caller_instance, request_text)
       when is_binary(request_text) do
    request_text <> delegation_artifact_context(caller_instance, request_text)
  end

  defp delegation_artifact_context(%LemmingInstance{} = caller_instance, request_text)
       when is_binary(request_text) do
    caller_instance
    |> referenced_artifact_contexts(request_text)
    |> case do
      [] ->
        ""

      contexts ->
        [
          "",
          "Delegation Artifact Context:",
          "The following artifact content was copied from the caller workspace.",
          "These files do not exist in your workspace unless you write them yourself.",
          "Use this content as source material. Do not call fs.read_text_file for these paths unless runtime later provides them inside your own workspace.",
          Enum.map_join(contexts, "\n\n", &artifact_context_block/1)
        ]
        |> Enum.join("\n")
    end
  end

  defp referenced_artifact_contexts(%LemmingInstance{} = caller_instance, request_text) do
    request_text
    |> referenced_artifact_paths()
    |> Enum.take(@delegation_max_artifacts)
    |> Enum.flat_map(fn path ->
      case artifact_context(caller_instance, path) do
        {:ok, context} -> [context]
        :error -> []
      end
    end)
  end

  defp referenced_artifact_paths(request_text) when is_binary(request_text) do
    ~r/(?<![A-Za-z0-9_\/.-])([A-Za-z0-9_][A-Za-z0-9_\/.-]*\.[A-Za-z0-9]+)/
    |> Regex.scan(request_text, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.reject(&Helpers.blank?/1)
    |> Enum.uniq()
  end

  defp artifact_context(caller_instance, path) when is_binary(path) do
    with {:ok, %{absolute_path: absolute_path, relative_path: relative_path}} <-
           LemmingInstances.artifact_absolute_path(caller_instance, path),
         {:ok, content} <- File.read(absolute_path),
         true <- String.valid?(content) do
      {:ok,
       %{
         path: relative_path,
         content: String.slice(content, 0, @delegation_artifact_char_limit)
       }}
    else
      _other -> :error
    end
  end

  defp artifact_context_block(%{path: path, content: content}) do
    [
      "Artifact: #{path}",
      "BEGIN ARTIFACT #{path}",
      content,
      "END ARTIFACT #{path}"
    ]
    |> Enum.join("\n")
  end

  defp update_child_calls(instance, status, attrs) do
    instance
    |> list_child_calls(statuses: ["accepted", "running", "needs_more_context", "partial_result"])
    |> Enum.each(fn call ->
      case update_call_status(call, status, attrs) do
        {:ok, updated_call} when status in ["completed", "failed"] ->
          resume_caller_instance(updated_call)

        {:ok, _updated_call} ->
          :ok

        {:error, _changeset} ->
          :ok
      end
    end)

    :ok
  end

  defp resume_caller_instance(%LemmingCall{caller_instance_id: caller_instance_id} = call)
       when is_binary(caller_instance_id) do
    with true <- registry_alive?(LemmingsOs.LemmingInstances.ExecutorRegistry),
         result <- Executor.resume_after_lemming_call(caller_instance_id, call) do
      handle_caller_resume_result(result, call, caller_instance_id)
    else
      false -> :ok
    end
  end

  defp handle_caller_resume_result(:ok, _call, _caller_instance_id), do: :ok

  defp handle_caller_resume_result({:error, :terminal_instance}, _call, _caller_instance_id),
    do: :ok

  defp handle_caller_resume_result({:error, :executor_unavailable}, call, caller_instance_id) do
    Logger.warning("caller executor unavailable for lemming call resume",
      event: "lemming_call.caller_resume_unavailable",
      lemming_call_id: call.id,
      caller_instance_id: caller_instance_id
    )

    :ok
  end

  defp handle_caller_resume_result({:error, :resume_not_possible}, call, caller_instance_id) do
    Logger.warning("caller executor could not resume lemming call",
      event: "lemming_call.caller_resume_not_possible",
      lemming_call_id: call.id,
      caller_instance_id: caller_instance_id
    )

    :ok
  end

  defp registry_alive?(name) when is_atom(name), do: is_pid(Process.whereis(name))

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
    case %LemmingCall{}
         |> LemmingCall.create_changeset(attrs)
         |> Repo.insert() do
      {:ok, call} = ok ->
        emit_call_created(call)
        ok

      {:error, _changeset} = error ->
        emit_create_failure(attrs)
        error
    end
  end

  defp emit_call_created(%LemmingCall{} = call) do
    metadata =
      call_log_metadata(call, %{
        event: "lemming_call.created",
        status: call.status
      })

    Logger.info("lemming call created", metadata)

    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :lemming_call, :created],
        %{count: 1},
        Telemetry.call_metadata(call)
      )

    _ =
      ActivityLog.record(:runtime, "lemming_call", "Lemming call created", %{
        lemming_call_id: call.id,
        world_id: call.world_id,
        city_id: call.city_id,
        caller_department_id: call.caller_department_id,
        callee_department_id: call.callee_department_id,
        caller_instance_id: call.caller_instance_id,
        callee_instance_id: call.callee_instance_id,
        status: call.status
      })

    _ = PubSub.broadcast_call_upserted(call)
    :ok
  end

  defp emit_create_failure(attrs) do
    metadata =
      attrs
      |> create_failure_metadata()
      |> Map.put(:event, "lemming_call.create_failed")

    Logger.warning("lemming call could not be created", metadata)
    :ok
  end

  defp emit_status_update_failure(%LemmingCall{} = call, status) do
    Logger.warning(
      "lemming call status update failed",
      call_log_metadata(call, %{
        event: "lemming_call.status_update_failed",
        status: status
      })
    )

    :ok
  end

  defp emit_status_observability(%LemmingCall{} = call, previous_status) do
    event = call_status_event(call, previous_status)
    log_event = "lemming_call." <> Atom.to_string(event)

    Logger.info(
      "lemming call status transitioned",
      call_log_metadata(call, %{
        event: log_event,
        status: call.status,
        from_status: previous_status,
        to_status: call.status,
        result_summary: loggable_summary(call.result_summary),
        error_summary: loggable_summary(call.error_summary),
        duration_ms: duration_for_log(call)
      })
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :lemming_call, event],
        status_measurements(call, previous_status),
        Telemetry.call_metadata(call, %{
          from_status: previous_status,
          to_status: call.status,
          result_summary: loggable_summary(call.result_summary),
          error_summary: loggable_summary(call.error_summary),
          duration_ms: Telemetry.duration_ms(call)
        })
      )

    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :lemming_call, :status_changed],
        status_measurements(call, previous_status),
        Telemetry.call_metadata(call, %{
          from_status: previous_status,
          to_status: call.status,
          result_summary: loggable_summary(call.result_summary),
          error_summary: loggable_summary(call.error_summary),
          duration_ms: Telemetry.duration_ms(call)
        })
      )

    _ =
      ActivityLog.record(
        activity_type(call),
        "lemming_call",
        activity_action(call, previous_status),
        %{
          lemming_call_id: call.id,
          world_id: call.world_id,
          city_id: call.city_id,
          caller_department_id: call.caller_department_id,
          callee_department_id: call.callee_department_id,
          caller_instance_id: call.caller_instance_id,
          callee_instance_id: call.callee_instance_id,
          from_status: previous_status,
          to_status: call.status,
          recovery_status: call.recovery_status,
          result_summary: loggable_summary(call.result_summary),
          error_summary: loggable_summary(call.error_summary)
        }
      )

    _ = PubSub.broadcast_call_upserted(call)
    _ = PubSub.broadcast_status_changed(call, previous_status)
    :ok
  end

  defp emit_request_failure(%LemmingInstance{} = caller_instance, reason, extra) do
    Logger.warning(
      "lemming call request failed",
      %{
        event: "lemming_call.request_failed",
        reason: normalize_reason(reason),
        world_id: caller_instance.world_id,
        city_id: caller_instance.city_id,
        department_id: caller_instance.department_id,
        caller_department_id: caller_instance.department_id,
        callee_department_id: Map.get(extra, :callee_department_id),
        caller_instance_id: caller_instance.id,
        callee_instance_id: Map.get(extra, :callee_instance_id),
        lemming_call_id: Map.get(extra, :lemming_call_id)
      }
    )

    :ok
  end

  defp emit_recovered(%LemmingCall{} = previous_call, %LemmingCall{} = successor_call) do
    Logger.info(
      "lemming call recovered",
      call_log_metadata(successor_call, %{
        event: "lemming_call.recovered",
        reason: "expired",
        previous_call_id: previous_call.id
      })
    )

    _ =
      Telemetry.execute(
        [:lemmings_os, :runtime, :lemming_call, :recovered],
        %{count: 1},
        Telemetry.call_metadata(successor_call, %{
          previous_call_id: previous_call.id,
          root_call_id:
            successor_call.root_call_id || previous_call.root_call_id || previous_call.id
        })
      )

    _ =
      ActivityLog.record(:runtime, "lemming_call", "Lemming call recovered", %{
        lemming_call_id: successor_call.id,
        previous_call_id: previous_call.id,
        world_id: successor_call.world_id,
        city_id: successor_call.city_id,
        caller_department_id: successor_call.caller_department_id,
        callee_department_id: successor_call.callee_department_id,
        caller_instance_id: successor_call.caller_instance_id,
        callee_instance_id: successor_call.callee_instance_id
      })

    :ok
  end

  defp call_status_event(
         %LemmingCall{status: "running", started_at: %DateTime{}},
         previous_status
       )
       when previous_status != "running",
       do: :started

  defp call_status_event(%LemmingCall{status: "completed"}, _previous_status), do: :completed

  defp call_status_event(
         %LemmingCall{status: "failed", recovery_status: "expired"},
         _previous_status
       ),
       do: :dead

  defp call_status_event(%LemmingCall{status: "failed"}, _previous_status), do: :failed

  defp call_status_event(%LemmingCall{recovery_status: recovery_status}, _previous_status)
       when is_binary(recovery_status),
       do: :recovery_pending

  defp call_status_event(%LemmingCall{}, _previous_status), do: :status_changed

  defp status_measurements(call, previous_status) do
    base = %{count: 1}

    if call.status != previous_status and call.status in @terminal_statuses do
      Map.put(base, :duration_ms, Telemetry.duration_ms(call))
    else
      base
    end
  end

  defp activity_type(%LemmingCall{status: "failed"}), do: :error
  defp activity_type(%LemmingCall{}), do: :runtime

  defp activity_action(call, previous_status) do
    case call_status_event(call, previous_status) do
      :started -> "Lemming call started"
      :completed -> "Lemming call completed"
      :failed -> "Lemming call failed"
      :dead -> "Lemming call dead"
      :recovery_pending -> "Lemming call recovery pending"
      _ -> "Lemming call status updated"
    end
  end

  defp call_log_metadata(call, extra) do
    %{
      world_id: call.world_id,
      city_id: call.city_id,
      department_id: call.caller_department_id,
      caller_department_id: call.caller_department_id,
      callee_department_id: call.callee_department_id,
      caller_instance_id: call.caller_instance_id,
      callee_instance_id: call.callee_instance_id,
      instance_id: call.caller_instance_id,
      lemming_call_id: call.id,
      reason: Map.get(extra, :reason),
      previous_call_id: Map.get(extra, :previous_call_id),
      from_status: Map.get(extra, :from_status),
      to_status: Map.get(extra, :to_status),
      status: Map.get(extra, :status, call.status),
      result_summary: Map.get(extra, :result_summary),
      error_summary: Map.get(extra, :error_summary),
      duration_ms: Map.get(extra, :duration_ms),
      event: Map.get(extra, :event)
    }
  end

  defp create_failure_metadata(attrs) do
    %{
      world_id: Map.get(attrs, :world_id) || Map.get(attrs, "world_id"),
      city_id: Map.get(attrs, :city_id) || Map.get(attrs, "city_id"),
      department_id:
        Map.get(attrs, :caller_department_id) || Map.get(attrs, "caller_department_id"),
      caller_department_id:
        Map.get(attrs, :caller_department_id) || Map.get(attrs, "caller_department_id"),
      callee_department_id:
        Map.get(attrs, :callee_department_id) || Map.get(attrs, "callee_department_id"),
      caller_instance_id:
        Map.get(attrs, :caller_instance_id) || Map.get(attrs, "caller_instance_id"),
      callee_instance_id:
        Map.get(attrs, :callee_instance_id) || Map.get(attrs, "callee_instance_id"),
      lemming_call_id: Map.get(attrs, :id) || Map.get(attrs, "id")
    }
  end

  defp loggable_summary(summary) when is_binary(summary) do
    summary = String.trim(summary)

    cond do
      summary == "" -> nil
      String.length(summary) <= 160 -> summary
      true -> String.slice(summary, 0, 157) <> "..."
    end
  end

  defp loggable_summary(_summary), do: nil

  defp duration_for_log(call) do
    duration_ms = Telemetry.duration_ms(call)
    if duration_ms > 0, do: duration_ms, else: nil
  end

  defp normalize_reason(%Ecto.Changeset{}), do: "changeset_invalid"
  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(_reason), do: "runtime_error"
end
