defmodule LemmingsOs.Knowledge do
  @moduledoc """
  Knowledge domain boundary for memory CRUD and scope-safe retrieval.

  This phase is memory-only and keeps product-state rules (`kind`, `source`,
  `status`) in context/schema validations.
  """

  import Ecto.Query, warn: false

  require Logger

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Events
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @default_limit 25
  @max_limit 100

  @type scope :: World.t() | City.t() | Department.t() | Lemming.t()

  @type scope_data :: %{
          required(:world_id) => Ecto.UUID.t(),
          required(:city_id) => Ecto.UUID.t() | nil,
          required(:department_id) => Ecto.UUID.t() | nil,
          required(:lemming_id) => Ecto.UUID.t() | nil
        }

  @type creator_metadata :: %{
          optional(:creator_type) => String.t(),
          optional(:creator_id) => String.t(),
          optional(:creator_lemming_id) => Ecto.UUID.t(),
          optional(:creator_lemming_instance_id) => Ecto.UUID.t(),
          optional(:creator_tool_execution_id) => Ecto.UUID.t()
        }

  @type effective_memory_row :: %{
          required(:memory) => KnowledgeItem.t(),
          required(:owner_scope) => String.t(),
          required(:owner_scope_label) => String.t(),
          required(:local?) => boolean(),
          required(:inherited?) => boolean(),
          required(:descendant?) => boolean()
        }

  @type paginated_memories :: %{
          required(:entries) => [effective_memory_row()],
          required(:total_count) => non_neg_integer(),
          required(:limit) => pos_integer(),
          required(:offset) => non_neg_integer()
        }

  @doc """
  Lists memories at the exact requested scope (local-only).

  ## Examples

      iex> LemmingsOs.Knowledge.list_memories(%{})
      []
  """
  @spec list_memories(scope(), keyword()) :: [KnowledgeItem.t()]
  def list_memories(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        KnowledgeItem
        |> filter_query(scope_filters(scope_data) ++ [{:kind, "memory"}])
        |> apply_memory_filters(opts)
        |> order_by([knowledge_item], asc: knowledge_item.inserted_at, asc: knowledge_item.id)
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Lists effective visible memories with filters and local Ecto pagination.

  `opts` supports:
  - `:q` (single text query over title and tags)
  - `:source` (`"user"` or `"llm"`)
  - `:status` (`"active"` for current MVP)
  - `:limit` (default `25`, max `100`)
  - `:offset` (default `0`)

  Returns read-model rows with ownership metadata:
  - `:owner_scope` (`"world" | "city" | "department" | "lemming"`)
  - `:local?`, `:inherited?`, `:descendant?`

  ## Examples

      iex> LemmingsOs.Knowledge.list_effective_memories(%{})
      {:error, :invalid_scope}
  """
  @spec list_effective_memories(scope(), keyword()) ::
          {:ok, paginated_memories()} | {:error, :invalid_scope | :scope_mismatch}
  def list_effective_memories(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      limit = limit_value(opts)
      offset = offset_value(opts)
      page_number = page_number_from_offset(offset, limit)

      query =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.kind == "memory")
        |> filter_scope_relevance(scope_data)
        |> apply_memory_filters(opts)

      page =
        query
        |> order_by([knowledge_item], desc: knowledge_item.inserted_at, desc: knowledge_item.id)
        |> Repo.paginate(page: page_number, page_size: limit)

      entries = Enum.map(page.entries, &to_effective_row(&1, scope_data))

      {:ok,
       %{
         entries: entries,
         total_count: page.total_entries,
         limit: page.page_size,
         offset: (page.page_number - 1) * page.page_size
       }}
    end
  end

  @doc """
  Returns one memory visible from the requested scope.

  Visibility follows hierarchy inheritance:
  - city sees world + city memories
  - department sees world + city + department + department lemming memories
  - lemming sees world + city + department + own lemming memories

  ## Examples

      iex> LemmingsOs.Knowledge.get_memory(%{}, Ecto.UUID.generate())
      nil
  """
  @spec get_memory(scope(), Ecto.UUID.t(), keyword()) :: KnowledgeItem.t() | nil
  def get_memory(scope, id, opts \\ [])

  def get_memory(scope, id, opts) when is_binary(id) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :visible)

    with {:ok, scope_data} <- scope_data(scope),
         {:ok, mode} <- normalize_read_mode(mode) do
      base_query =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.id == ^id)
        |> where([knowledge_item], knowledge_item.kind == "memory")

      query =
        case mode do
          :local -> filter_query(base_query, scope_filters(scope_data))
          :visible -> filter_scope_relevance(base_query, scope_data)
        end

      Repo.one(query)
    else
      {:error, _reason} -> nil
    end
  end

  def get_memory(_scope, _id, _opts), do: nil

  @doc """
  Creates one user memory at the exact requested scope.

  Runtime-owned fields are assigned by this context:
  - `kind = "memory"`
  - `source = "user"`
  - `status = "active"`

  Optional creator metadata can be passed via `opts[:creator]`.

  ## Examples

      iex> LemmingsOs.Knowledge.create_memory(%{}, %{})
      {:error, :invalid_scope}
  """
  @spec create_memory(scope(), map(), keyword()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_memory(scope, attrs, opts \\ [])

  def create_memory(scope, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         {:ok, creator_metadata} <- creator_metadata(opts),
         {:ok, source} <- normalize_source(Keyword.get(opts, :source, "user")),
         {:ok, status} <- normalize_status(Keyword.get(opts, :status, "active")),
         {:ok, kind} <- normalize_kind(Keyword.get(opts, :kind, "memory")) do
      attrs =
        attrs
        |> Map.take([:title, :content, :tags])
        |> Map.merge(scope_data)
        |> Map.merge(%{kind: kind, source: source, status: status})
        |> Map.merge(creator_metadata)

      %KnowledgeItem{}
      |> KnowledgeItem.changeset(attrs)
      |> Repo.insert()
      |> maybe_record_memory_event("knowledge.memory.created", scope_data, "Memory created")
    end
  end

  def create_memory(_scope, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc """
  Updates mutable user fields on a memory at exact scope.

  Only `title`, `content`, and `tags` are mutable through this API.

  ## Examples

      iex> LemmingsOs.Knowledge.update_memory(%{}, %LemmingsOs.Knowledge.KnowledgeItem{}, %{})
      {:error, :invalid_scope}
  """
  @spec update_memory(scope(), KnowledgeItem.t(), map()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def update_memory(scope, %KnowledgeItem{} = knowledge_item, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      knowledge_item
      |> KnowledgeItem.user_update_changeset(Map.take(attrs, [:title, :content, :tags]))
      |> Repo.update()
      |> maybe_record_memory_event("knowledge.memory.updated", scope_data, "Memory updated")
    end
  end

  def update_memory(_scope, _knowledge_item, _attrs), do: {:error, :invalid_attrs}

  @doc """
  Hard deletes a memory at exact scope.

  ## Examples

      iex> LemmingsOs.Knowledge.delete_memory(%{}, %LemmingsOs.Knowledge.KnowledgeItem{})
      {:error, :invalid_scope}
  """
  @spec delete_memory(scope(), KnowledgeItem.t()) ::
          {:ok, KnowledgeItem.t()}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def delete_memory(scope, %KnowledgeItem{} = knowledge_item) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      Repo.delete(knowledge_item)
      |> maybe_record_memory_event("knowledge.memory.deleted", scope_data, "Memory deleted")
    end
  end

  @doc """
  Returns a changeset for memory form handling.
  """
  @spec change_memory(KnowledgeItem.t(), map()) :: Ecto.Changeset.t()
  def change_memory(%KnowledgeItem{} = knowledge_item, attrs \\ %{}) when is_map(attrs) do
    KnowledgeItem.user_update_changeset(knowledge_item, attrs)
  end

  defp apply_memory_filters(query, opts) do
    query
    |> maybe_filter_source(Keyword.get(opts, :source))
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_query(Keyword.get(opts, :q) || Keyword.get(opts, :query))
  end

  defp maybe_filter_source(query, source) when source in ["user", "llm"] do
    from(knowledge_item in query, where: knowledge_item.source == ^source)
  end

  defp maybe_filter_source(query, _source), do: query

  defp maybe_filter_status(query, status) when status in ["active"] do
    from(knowledge_item in query, where: knowledge_item.status == ^status)
  end

  defp maybe_filter_status(query, _status), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      query
    else
      pattern = "%" <> trimmed <> "%"

      from(knowledge_item in query,
        where:
          ilike(knowledge_item.title, ^pattern) or
            ilike(fragment("array_to_string(?, ' ')", knowledge_item.tags), ^pattern)
      )
    end
  end

  defp maybe_filter_query(query, _value), do: query

  defp to_effective_row(%KnowledgeItem{} = knowledge_item, scope_data) do
    owner_scope = owner_scope(knowledge_item)
    local? = knowledge_item_in_scope?(knowledge_item, scope_data)
    inherited? = inherited_owner?(knowledge_item, scope_data, local?)

    %{
      memory: knowledge_item,
      owner_scope: owner_scope,
      owner_scope_label: String.capitalize(owner_scope),
      local?: local?,
      inherited?: inherited?,
      descendant?: not local? and not inherited?
    }
  end

  defp inherited_owner?(_knowledge_item, _scope_data, true), do: false

  defp inherited_owner?(
         %KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil},
         _scope_data,
         false
       ),
       do: true

  defp inherited_owner?(
         %KnowledgeItem{department_id: nil, lemming_id: nil} = knowledge_item,
         scope_data,
         false
       ) do
    is_binary(scope_data.city_id) and knowledge_item.city_id == scope_data.city_id
  end

  defp inherited_owner?(%KnowledgeItem{lemming_id: nil} = knowledge_item, scope_data, false) do
    is_binary(scope_data.department_id) and
      knowledge_item.department_id == scope_data.department_id
  end

  defp inherited_owner?(_knowledge_item, _scope_data, false), do: false

  defp owner_scope(%KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil}), do: "world"
  defp owner_scope(%KnowledgeItem{department_id: nil, lemming_id: nil}), do: "city"
  defp owner_scope(%KnowledgeItem{lemming_id: nil}), do: "department"
  defp owner_scope(%KnowledgeItem{}), do: "lemming"

  defp limit_value(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @max_limit)
      _limit -> @default_limit
    end
  end

  defp offset_value(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) and offset >= 0 -> offset
      _offset -> 0
    end
  end

  defp page_number_from_offset(offset, limit) do
    offset
    |> Kernel.div(limit)
    |> Kernel.+(1)
  end

  defp validate_exact_scope(%KnowledgeItem{} = knowledge_item, scope_data) do
    if knowledge_item_in_scope?(knowledge_item, scope_data) do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp knowledge_item_in_scope?(%KnowledgeItem{} = knowledge_item, scope_data) do
    knowledge_item.world_id == scope_data.world_id and
      knowledge_item.city_id == scope_data.city_id and
      knowledge_item.department_id == scope_data.department_id and
      knowledge_item.lemming_id == scope_data.lemming_id
  end

  defp validate_requested_scope(attrs, scope_data) do
    attrs_scope_data =
      attrs
      |> Map.take([
        :world_id,
        :city_id,
        :department_id,
        :lemming_id,
        "world_id",
        "city_id",
        "department_id",
        "lemming_id"
      ])
      |> scope_data_from_attrs()

    case attrs_scope_data do
      :none -> :ok
      %{} = attrs_scope when attrs_scope == scope_data -> :ok
      %{} -> {:error, :scope_mismatch}
    end
  end

  defp scope_data_from_attrs(attrs) do
    world_id = fetch(attrs, :world_id)
    city_id = fetch(attrs, :city_id)
    department_id = fetch(attrs, :department_id)
    lemming_id = fetch(attrs, :lemming_id)

    if is_nil(world_id) and is_nil(city_id) and is_nil(department_id) and is_nil(lemming_id) do
      :none
    else
      %{
        world_id: world_id,
        city_id: city_id,
        department_id: department_id,
        lemming_id: lemming_id
      }
    end
  end

  defp creator_metadata(opts) do
    opts
    |> Keyword.get(:creator, %{})
    |> normalize_creator_metadata()
  end

  defp normalize_creator_metadata(%{} = creator) do
    creator_type = fetch(creator, :creator_type)
    creator_id = fetch(creator, :creator_id)
    creator_lemming_id = fetch(creator, :creator_lemming_id)
    creator_lemming_instance_id = fetch(creator, :creator_lemming_instance_id)
    creator_tool_execution_id = fetch(creator, :creator_tool_execution_id)

    with :ok <- maybe_validate_uuid(creator_lemming_id),
         :ok <- maybe_validate_uuid(creator_lemming_instance_id),
         :ok <- maybe_validate_uuid(creator_tool_execution_id),
         :ok <- validate_creator_refs(creator_lemming_instance_id, creator_tool_execution_id) do
      {:ok,
       %{}
       |> maybe_put(:creator_type, creator_type)
       |> maybe_put(:creator_id, creator_id)
       |> maybe_put(:creator_lemming_id, creator_lemming_id)
       |> maybe_put(:creator_lemming_instance_id, creator_lemming_instance_id)
       |> maybe_put(:creator_tool_execution_id, creator_tool_execution_id)}
    end
  end

  defp normalize_creator_metadata(_creator), do: {:error, :invalid_attrs}

  defp validate_creator_refs(nil, nil), do: :ok
  defp validate_creator_refs(instance_id, nil) when is_binary(instance_id), do: :ok

  defp validate_creator_refs(instance_id, tool_execution_id)
       when is_binary(instance_id) and is_binary(tool_execution_id) do
    exists? =
      ToolExecution
      |> where(
        [tool_execution],
        tool_execution.id == ^tool_execution_id and
          tool_execution.lemming_instance_id == ^instance_id
      )
      |> Repo.exists?()

    if exists?, do: :ok, else: {:error, :scope_mismatch}
  end

  defp validate_creator_refs(_instance_id, _tool_execution_id), do: {:error, :invalid_attrs}

  defp maybe_validate_uuid(nil), do: :ok

  defp maybe_validate_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_attrs}
    end
  end

  defp maybe_validate_uuid(_value), do: {:error, :invalid_attrs}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_record_memory_event(
         {:ok, %KnowledgeItem{} = memory} = result,
         event_type,
         scope_data,
         message
       )
       when is_binary(event_type) and is_map(scope_data) and is_binary(message) do
    payload = memory_event_payload(memory)

    case Events.record_event(
           event_type,
           scope_data,
           message,
           payload: payload,
           event_family: "audit",
           action: memory_event_action(event_type),
           status: "succeeded",
           resource_type: "knowledge_item",
           resource_id: memory.id
         ) do
      {:ok, _event} ->
        result

      {:error, reason} ->
        Logger.warning("failed to record memory lifecycle event",
          event: "knowledge.memory.event_failed",
          world_id: memory.world_id,
          department_id: memory.department_id,
          lemming_id: memory.lemming_id,
          reason: inspect(reason)
        )

        result
    end
  end

  defp maybe_record_memory_event(result, _event_type, _scope_data, _message), do: result

  defp memory_event_action("knowledge.memory.created"), do: "create"
  defp memory_event_action("knowledge.memory.updated"), do: "update"
  defp memory_event_action("knowledge.memory.deleted"), do: "delete"
  defp memory_event_action(_event_type), do: "update"

  defp memory_event_payload(%KnowledgeItem{} = memory) do
    %{
      knowledge_item_id: memory.id,
      kind: memory.kind,
      source: memory.source,
      status: memory.status,
      world_id: memory.world_id,
      city_id: memory.city_id,
      department_id: memory.department_id,
      lemming_id: memory.lemming_id,
      creator_type: memory.creator_type,
      creator_id: memory.creator_id,
      creator_lemming_id: memory.creator_lemming_id,
      creator_lemming_instance_id: memory.creator_lemming_instance_id,
      creator_tool_execution_id: memory.creator_tool_execution_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_read_mode(:local), do: {:ok, :local}
  defp normalize_read_mode(:visible), do: {:ok, :visible}
  defp normalize_read_mode(_mode), do: {:error, :invalid_attrs}

  defp normalize_source(source) when is_binary(source) do
    if source in KnowledgeItem.sources(), do: {:ok, source}, else: {:error, :invalid_attrs}
  end

  defp normalize_source(_source), do: {:error, :invalid_attrs}

  defp normalize_status(status) when is_binary(status) do
    if status in KnowledgeItem.statuses(), do: {:ok, status}, else: {:error, :invalid_attrs}
  end

  defp normalize_status(_status), do: {:error, :invalid_attrs}

  defp normalize_kind(kind) when is_binary(kind) do
    if kind in KnowledgeItem.kinds(), do: {:ok, kind}, else: {:error, :invalid_attrs}
  end

  defp normalize_kind(_kind), do: {:error, :invalid_attrs}

  defp scope_data(%World{id: world_id}) when is_binary(world_id),
    do:
      validate_scope_consistency(%{
        world_id: world_id,
        city_id: nil,
        department_id: nil,
        lemming_id: nil
      })

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id),
       do:
         validate_scope_consistency(%{
           world_id: world_id,
           city_id: city_id,
           department_id: nil,
           lemming_id: nil
         })

  defp scope_data(%Department{id: department_id, world_id: world_id, city_id: city_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    validate_scope_consistency(%{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: nil
    })
  end

  defp scope_data(%Lemming{
         id: lemming_id,
         world_id: world_id,
         city_id: city_id,
         department_id: department_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    validate_scope_consistency(%{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: lemming_id
    })
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: nil,
           department_id: nil,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) do
    exists? = world_scope_exists?(world_id)
    scope_consistency_result(exists?, scope_data)
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: nil,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) do
    scope_consistency_result(city_scope_exists?(world_id, city_id), scope_data)
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: nil
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    scope_consistency_result(
      department_scope_exists?(world_id, city_id, department_id),
      scope_data
    )
  end

  defp validate_scope_consistency(
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         } = scope_data
       )
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    scope_consistency_result(
      lemming_scope_exists?(world_id, city_id, department_id, lemming_id),
      scope_data
    )
  end

  defp validate_scope_consistency(_scope_data), do: {:error, :invalid_scope}

  defp scope_consistency_result(true, scope_data), do: {:ok, scope_data}
  defp scope_consistency_result(false, _scope_data), do: {:error, :scope_mismatch}

  defp scope_filters(scope_data) do
    [
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id,
      lemming_id: scope_data.lemming_id
    ]
  end

  defp filter_scope_relevance(query, %{world_id: world_id, city_id: nil}) do
    from(knowledge_item in query,
      where: knowledge_item.world_id == ^world_id
    )
    |> world_only_filter()
  end

  defp filter_scope_relevance(query, %{world_id: world_id, city_id: city_id, department_id: nil})
       when is_binary(city_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id)
    )
    |> city_only_filter()
  end

  defp filter_scope_relevance(
         query,
         %{world_id: world_id, city_id: city_id, department_id: department_id, lemming_id: nil}
       )
       when is_binary(city_id) and is_binary(department_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id)
    )
  end

  defp filter_scope_relevance(
         query,
         %{
           world_id: world_id,
           city_id: city_id,
           department_id: department_id,
           lemming_id: lemming_id
         }
       )
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id) and
          (is_nil(knowledge_item.department_id) or knowledge_item.department_id == ^department_id) and
          (is_nil(knowledge_item.lemming_id) or knowledge_item.lemming_id == ^lemming_id)
    )
  end

  defp world_scope_exists?(world_id) do
    World
    |> where([world], world.id == ^world_id)
    |> Repo.exists?()
  end

  defp city_scope_exists?(world_id, city_id) do
    City
    |> where([city], city.id == ^city_id and city.world_id == ^world_id)
    |> Repo.exists?()
  end

  defp department_scope_exists?(world_id, city_id, department_id) do
    Department
    |> join(:inner, [department], city in City, on: city.id == department.city_id)
    |> where(
      [department, city],
      department.id == ^department_id and department.world_id == ^world_id and
        department.city_id == ^city_id and city.world_id == ^world_id
    )
    |> Repo.exists?()
  end

  defp lemming_scope_exists?(world_id, city_id, department_id, lemming_id) do
    Lemming
    |> join(:inner, [lemming], department in Department,
      on: department.id == lemming.department_id
    )
    |> join(:inner, [lemming, department], city in City, on: city.id == lemming.city_id)
    |> where(
      [lemming, department, city],
      lemming.id == ^lemming_id and lemming.world_id == ^world_id and
        lemming.city_id == ^city_id and lemming.department_id == ^department_id and
        department.world_id == ^world_id and department.city_id == ^city_id and
        city.world_id == ^world_id
    )
    |> Repo.exists?()
  end

  defp world_only_filter(query) do
    from(knowledge_item in query,
      where:
        is_nil(knowledge_item.city_id) and is_nil(knowledge_item.department_id) and
          is_nil(knowledge_item.lemming_id)
    )
  end

  defp city_only_filter(query) do
    from(knowledge_item in query,
      where: is_nil(knowledge_item.department_id) and is_nil(knowledge_item.lemming_id)
    )
  end

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do:
      filter_query(
        from(knowledge_item in query, where: knowledge_item.world_id == ^world_id),
        rest
      )

  defp filter_query(query, [{:city_id, city_id} | rest]) when is_binary(city_id),
    do:
      filter_query(from(knowledge_item in query, where: knowledge_item.city_id == ^city_id), rest)

  defp filter_query(query, [{:city_id, nil} | rest]),
    do: filter_query(from(knowledge_item in query, where: is_nil(knowledge_item.city_id)), rest)

  defp filter_query(query, [{:department_id, department_id} | rest])
       when is_binary(department_id),
       do:
         filter_query(
           from(knowledge_item in query, where: knowledge_item.department_id == ^department_id),
           rest
         )

  defp filter_query(query, [{:department_id, nil} | rest]),
    do:
      filter_query(
        from(knowledge_item in query, where: is_nil(knowledge_item.department_id)),
        rest
      )

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]) when is_binary(lemming_id),
    do:
      filter_query(
        from(knowledge_item in query, where: knowledge_item.lemming_id == ^lemming_id),
        rest
      )

  defp filter_query(query, [{:lemming_id, nil} | rest]),
    do:
      filter_query(from(knowledge_item in query, where: is_nil(knowledge_item.lemming_id)), rest)

  defp filter_query(query, [{:kind, kind} | rest]),
    do: filter_query(from(knowledge_item in query, where: knowledge_item.kind == ^kind), rest)

  defp filter_query(query, [_unknown | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
