defmodule LemmingsOs.LemmingTools do
  @moduledoc """
  World-scoped persistence boundary for lemming tool executions.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Creates a durable tool-execution record for a runtime instance in a World scope.

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
      iex> {:ok, %LemmingsOs.LemmingInstances.ToolExecution{status: "running"}} =
      ...>   LemmingsOs.LemmingTools.create_tool_execution(
      ...>     world,
      ...>     instance,
      ...>     %{
      ...>       tool_name: "fs.read_text_file",
      ...>       status: "running",
      ...>       args: %{"path" => "notes.txt"}
      ...>     }
      ...>   )
  """
  @spec create_tool_execution(World.t(), LemmingInstance.t(), map()) ::
          {:ok, ToolExecution.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def create_tool_execution(world, instance, attrs \\ %{})

  def create_tool_execution(
        %World{id: world_id},
        %LemmingInstance{id: instance_id, world_id: world_id},
        attrs
      )
      when is_binary(instance_id) and is_map(attrs) do
    %ToolExecution{}
    |> ToolExecution.create_changeset(
      Map.merge(attrs, %{lemming_instance_id: instance_id, world_id: world_id})
    )
    |> Repo.insert()
  end

  def create_tool_execution(_, _, _), do: {:error, :not_found}

  @doc """
  Returns persisted tool executions for an instance in chronological order.

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
      iex> {:ok, tool_execution} =
      ...>   LemmingsOs.LemmingTools.create_tool_execution(
      ...>     world,
      ...>     instance,
      ...>     %{
      ...>       tool_name: "fs.read_text_file",
      ...>       status: "running",
      ...>       args: %{"path" => "notes.txt"}
      ...>     }
      ...>   )
      iex> [listed_execution] = LemmingsOs.LemmingTools.list_tool_executions(world, instance)
      iex> listed_execution.id == tool_execution.id
      true
  """
  @spec list_tool_executions(World.t(), LemmingInstance.t(), keyword()) :: [ToolExecution.t()]
  def list_tool_executions(world, instance, opts \\ [])

  def list_tool_executions(
        %World{id: world_id},
        %LemmingInstance{id: instance_id, world_id: world_id},
        opts
      )
      when is_binary(instance_id) and is_list(opts) do
    ToolExecution
    |> where(
      [tool_execution],
      tool_execution.lemming_instance_id == ^instance_id and tool_execution.world_id == ^world_id
    )
    |> filter_query(opts)
    |> order_by([tool_execution], asc: tool_execution.inserted_at, asc: tool_execution.id)
    |> Repo.all()
  end

  def list_tool_executions(_, _, _), do: []

  @doc """
  Returns a persisted tool-execution record constrained to the given World and instance.

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
      iex> {:ok, tool_execution} =
      ...>   LemmingsOs.LemmingTools.create_tool_execution(
      ...>     world,
      ...>     instance,
      ...>     %{
      ...>       tool_name: "fs.read_text_file",
      ...>       status: "running",
      ...>       args: %{"path" => "notes.txt"}
      ...>     }
      ...>   )
      iex> {:ok, %LemmingsOs.LemmingInstances.ToolExecution{id: id}} =
      ...>   LemmingsOs.LemmingTools.get_tool_execution(world, instance, tool_execution.id)
      iex> id == tool_execution.id
      true
  """
  @spec get_tool_execution(World.t(), LemmingInstance.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, ToolExecution.t()} | {:error, :not_found}
  def get_tool_execution(world, instance, tool_execution_id, opts \\ [])

  def get_tool_execution(
        %World{id: world_id},
        %LemmingInstance{id: instance_id, world_id: world_id},
        tool_execution_id,
        opts
      )
      when is_binary(instance_id) and is_binary(tool_execution_id) and is_list(opts) do
    ToolExecution
    |> where(
      [tool_execution],
      tool_execution.id == ^tool_execution_id and
        tool_execution.lemming_instance_id == ^instance_id and
        tool_execution.world_id == ^world_id
    )
    |> filter_query(opts)
    |> Repo.one()
    |> normalize_tool_execution_result()
  end

  def get_tool_execution(_, _, _, _), do: {:error, :not_found}

  @doc """
  Updates a persisted tool-execution record in a World and instance scope.

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
      iex> {:ok, tool_execution} =
      ...>   LemmingsOs.LemmingTools.create_tool_execution(
      ...>     world,
      ...>     instance,
      ...>     %{
      ...>       tool_name: "fs.read_text_file",
      ...>       status: "running",
      ...>       args: %{"path" => "notes.txt"}
      ...>     }
      ...>   )
      iex> {:ok, %LemmingsOs.LemmingInstances.ToolExecution{status: "ok"}} =
      ...>   LemmingsOs.LemmingTools.update_tool_execution(
      ...>     world,
      ...>     instance,
      ...>     tool_execution,
      ...>     %{status: "ok", result: %{"content" => "notes"}}
      ...>   )
  """
  @spec update_tool_execution(World.t(), LemmingInstance.t(), ToolExecution.t(), map()) ::
          {:ok, ToolExecution.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def update_tool_execution(world, instance, tool_execution, attrs \\ %{})

  def update_tool_execution(
        %World{id: world_id},
        %LemmingInstance{id: instance_id, world_id: world_id},
        %ToolExecution{
          id: tool_execution_id,
          lemming_instance_id: instance_id,
          world_id: world_id
        } =
          tool_execution,
        attrs
      )
      when is_binary(tool_execution_id) and is_map(attrs) do
    tool_execution
    |> ToolExecution.update_changeset(attrs)
    |> Repo.update()
  end

  def update_tool_execution(_, _, _, _), do: {:error, :not_found}

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(item in query, where: field(item, ^:status) == ^status), rest)

  defp filter_query(query, [{:statuses, statuses} | rest]) when is_list(statuses),
    do: filter_query(from(item in query, where: field(item, ^:status) in ^statuses), rest)

  defp filter_query(query, [{:lemming_instance_id, lemming_instance_id} | rest]),
    do:
      filter_query(
        from(item in query, where: field(item, ^:lemming_instance_id) == ^lemming_instance_id),
        rest
      )

  defp filter_query(query, [{:tool_name, tool_name} | rest]),
    do: filter_query(from(item in query, where: field(item, ^:tool_name) == ^tool_name), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(item in query, where: field(item, ^:id) in ^ids), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [_ | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp normalize_tool_execution_result(nil), do: {:error, :not_found}

  defp normalize_tool_execution_result(%ToolExecution{} = tool_execution),
    do: {:ok, tool_execution}
end
