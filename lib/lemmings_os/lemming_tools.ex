defmodule LemmingsOs.LemmingTools do
  @moduledoc """
  World-scoped persistence boundary for lemming tool executions.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @email_draft_tool "email.create_draft"
  @subject_preview_bytes 80

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
      attrs
      |> sanitize_tool_execution_attrs()
      |> Map.merge(%{lemming_instance_id: instance_id, world_id: world_id})
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
    |> ToolExecution.update_changeset(sanitize_tool_execution_attrs(tool_execution, attrs))
    |> Repo.update()
  end

  def update_tool_execution(_, _, _, _), do: {:error, :not_found}

  defp sanitize_tool_execution_attrs(%{"tool_name" => @email_draft_tool} = attrs),
    do: sanitize_email_draft_attrs(attrs)

  defp sanitize_tool_execution_attrs(%{tool_name: @email_draft_tool} = attrs),
    do: sanitize_email_draft_attrs(attrs)

  defp sanitize_tool_execution_attrs(attrs), do: attrs

  defp sanitize_tool_execution_attrs(%ToolExecution{tool_name: @email_draft_tool}, attrs),
    do: sanitize_email_draft_attrs(attrs)

  defp sanitize_tool_execution_attrs(_tool_execution, attrs), do: attrs

  defp sanitize_email_draft_attrs(attrs) do
    attrs
    |> maybe_update_payload(:args, &safe_email_draft_args/1)
    |> maybe_update_payload("args", &safe_email_draft_args/1)
    |> maybe_update_payload(:result, &safe_email_draft_result/1)
    |> maybe_update_payload("result", &safe_email_draft_result/1)
  end

  defp maybe_update_payload(attrs, key, fun) when is_map(attrs) do
    case Map.fetch(attrs, key) do
      {:ok, payload} when is_map(payload) -> Map.put(attrs, key, fun.(payload))
      _missing_or_invalid -> attrs
    end
  end

  defp safe_email_draft_args(args) do
    %{}
    |> maybe_put_safe_string("connection_ref", fetch_payload(args, "connection_ref"))
    |> Map.put("to_count", recipient_count(fetch_payload(args, "to")))
    |> Map.put("cc_count", recipient_count(fetch_payload(args, "cc")))
    |> Map.put("bcc_count", recipient_count(fetch_payload(args, "bcc")))
    |> maybe_put_safe_string("subject_preview", subject_preview(fetch_payload(args, "subject")))
    |> Map.put("body_bytes", body_bytes(fetch_payload(args, "body")))
    |> maybe_put_safe_string("body_format", fetch_payload(args, "body_format"))
    |> Map.put("artifact_count", artifact_ids(args) |> length())
    |> Map.put("artifact_ids", artifact_ids(args))
  end

  defp safe_email_draft_result(result) do
    %{}
    |> maybe_put_safe_string("status", fetch_payload(result, "status"))
    |> maybe_put_safe_string("provider", fetch_payload(result, "provider"))
    |> maybe_put_safe_string("connection_ref", fetch_payload(result, "connection_ref"))
    |> maybe_put_safe_string("draft_id", fetch_payload(result, "draft_id"))
    |> maybe_put_safe_string("message_id", fetch_payload(result, "message_id"))
    |> Map.put("to_count", result_count(result, "to"))
    |> Map.put("cc_count", result_count(result, "cc"))
    |> Map.put("bcc_count", result_count(result, "bcc"))
    |> maybe_put_safe_string("subject_preview", subject_preview(fetch_payload(result, "subject")))
    |> maybe_put_safe_string("subject_preview", fetch_payload(result, "subject_preview"))
    |> Map.put("artifact_count", artifact_count(result))
    |> Map.put("artifact_ids", artifact_ids(result))
  end

  defp result_count(payload, field) do
    case fetch_payload(payload, "#{field}_count") do
      value when is_integer(value) and value >= 0 -> value
      _value -> recipient_count(fetch_payload(payload, field))
    end
  end

  defp artifact_count(payload) do
    case fetch_payload(payload, "artifact_count") do
      value when is_integer(value) and value >= 0 -> value
      _value -> artifact_ids(payload) |> length()
    end
  end

  defp recipient_count(value) when is_list(value), do: length(value)

  defp recipient_count(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> length()
  end

  defp recipient_count(_value), do: 0

  defp body_bytes(value) when is_binary(value), do: byte_size(value)
  defp body_bytes(_value), do: 0

  defp artifact_ids(payload) when is_map(payload) do
    payload
    |> fetch_payload("artifact_ids")
    |> safe_string_list()
  end

  defp subject_preview(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, @subject_preview_bytes)
  end

  defp subject_preview(_value), do: nil

  defp safe_string_list(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp safe_string_list(_values), do: []

  defp maybe_put_safe_string(map, _key, nil), do: map
  defp maybe_put_safe_string(map, _key, ""), do: map
  defp maybe_put_safe_string(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp maybe_put_safe_string(map, _key, _value), do: map

  defp fetch_payload(payload, key) when is_map(payload) and is_binary(key) do
    case payload_atom_key(key) do
      nil -> Map.get(payload, key)
      atom_key -> Map.get(payload, key) || Map.get(payload, atom_key)
    end
  end

  defp payload_atom_key("connection_ref"), do: :connection_ref
  defp payload_atom_key("to"), do: :to
  defp payload_atom_key("cc"), do: :cc
  defp payload_atom_key("bcc"), do: :bcc
  defp payload_atom_key("subject"), do: :subject
  defp payload_atom_key("body"), do: :body
  defp payload_atom_key("body_format"), do: :body_format
  defp payload_atom_key("artifact_ids"), do: :artifact_ids
  defp payload_atom_key("to_count"), do: :to_count
  defp payload_atom_key("cc_count"), do: :cc_count
  defp payload_atom_key("bcc_count"), do: :bcc_count
  defp payload_atom_key("subject_preview"), do: :subject_preview
  defp payload_atom_key("artifact_count"), do: :artifact_count
  defp payload_atom_key("status"), do: :status
  defp payload_atom_key("provider"), do: :provider
  defp payload_atom_key("draft_id"), do: :draft_id
  defp payload_atom_key("message_id"), do: :message_id
  defp payload_atom_key(_key), do: nil

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
