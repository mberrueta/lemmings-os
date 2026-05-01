defmodule LemmingsOs.Artifacts do
  @moduledoc """
  World-scoped persistence boundary for Artifact metadata and lifecycle state.

  This context exposes explicit-scope APIs for creating, retrieving, listing,
  and status updates while keeping storage internals private. Public read models
  use `artifact_descriptor/1`, which omits `storage_ref` and any filesystem path.
  """

  import Ecto.Query, warn: false

  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Artifacts.Promotion
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @ready_status "ready"
  @artifact_statuses Artifact.statuses()
  @status_fields ~w(status statuses include_non_ready)a
  @scope_fields ~w(world_id city_id department_id lemming_id lemming_instance_id)a
  @descriptor_fields ~w(
    id
    world_id
    city_id
    department_id
    lemming_id
    lemming_instance_id
    created_by_tool_execution_id
    type
    filename
    content_type
    size_bytes
    checksum
    status
    notes
    metadata
    inserted_at
    updated_at
  )a

  @type scope_data :: %{
          required(:world_id) => Ecto.UUID.t(),
          required(:city_id) => Ecto.UUID.t() | nil,
          required(:department_id) => Ecto.UUID.t() | nil,
          required(:lemming_id) => Ecto.UUID.t() | nil,
          required(:lemming_instance_id) => Ecto.UUID.t() | nil
        }

  @type scope ::
          World.t() | City.t() | Department.t() | Lemming.t() | LemmingInstance.t() | map()

  @type artifact_descriptor :: %{
          id: Ecto.UUID.t(),
          world_id: Ecto.UUID.t(),
          city_id: Ecto.UUID.t() | nil,
          department_id: Ecto.UUID.t() | nil,
          lemming_id: Ecto.UUID.t() | nil,
          lemming_instance_id: Ecto.UUID.t() | nil,
          created_by_tool_execution_id: Ecto.UUID.t() | nil,
          type: String.t(),
          filename: String.t(),
          content_type: String.t(),
          size_bytes: non_neg_integer(),
          checksum: String.t(),
          status: String.t(),
          notes: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type download_artifact :: %{
          id: Ecto.UUID.t(),
          filename: String.t(),
          content_type: String.t(),
          storage_ref: String.t()
        }

  @doc """
  Creates an Artifact row from trusted metadata inside an explicit scope.

  Scope ids are context-controlled. Conflicting scope fields in `attrs` are
  rejected with `{:error, :scope_mismatch}`.

  ## Examples

      iex> LemmingsOs.Artifacts.create_artifact(%{city_id: Ecto.UUID.generate()}, %{})
      {:error, :invalid_scope}
  """
  @spec create_artifact(scope(), map()) ::
          {:ok, artifact_descriptor()}
          | {:error, :invalid_scope | :scope_mismatch | Ecto.Changeset.t()}
  def create_artifact(scope, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- ensure_scope_attr_consistency(scope_data, attrs) do
      attrs =
        attrs
        |> Map.new()
        |> Map.merge(scope_attrs(scope_data))

      %Artifact{}
      |> Artifact.changeset(attrs)
      |> Repo.insert()
      |> normalize_write_result()
    end
  end

  def create_artifact(_scope, _attrs), do: {:error, :invalid_scope}

  @doc """
  Promotes one trusted workspace file into managed Artifact storage.

  Promotion always computes and persists `storage_ref`, `size_bytes`, and
  `checksum`, and sets Artifact status to `ready`.

  Collision behavior for existing `(world_id, city_id, department_id, lemming_id, filename)`:
  - `mode: :update_existing` overwrites the existing managed file and keeps the same row.
  - `mode: :promote_as_new` creates a new Artifact row with a new id.
  - missing/invalid mode when a collision exists returns a safe error.

  ## Examples

      iex> LemmingsOs.Artifacts.promote_workspace_file(%{city_id: Ecto.UUID.generate()}, %{})
      {:error, :invalid_scope}
  """
  @spec promote_workspace_file(scope(), map()) ::
          {:ok, artifact_descriptor()}
          | {:error, atom() | Ecto.Changeset.t() | {atom(), term()}}
  def promote_workspace_file(scope, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope) do
      Promotion.promote_workspace_file(scope_data, attrs)
    end
  end

  def promote_workspace_file(_scope, _attrs), do: {:error, :invalid_scope}

  @doc """
  Retrieves one `ready` Artifact by id within an explicit scope.

  ## Examples

      iex> LemmingsOs.Artifacts.get_artifact(%{city_id: Ecto.UUID.generate()}, Ecto.UUID.generate())
      {:error, :invalid_scope}
  """
  @spec get_artifact(scope(), Ecto.UUID.t()) ::
          {:ok, artifact_descriptor()} | {:error, :invalid_scope | :not_found}
  def get_artifact(scope, artifact_id), do: get_artifact(scope, artifact_id, [])

  @doc """
  Retrieves one Artifact by id within an explicit scope.

  By default, only `ready` artifacts are returned. Pass `include_non_ready: true`
  or explicit `:status`/`:statuses` filters to include other lifecycle states.

  ## Examples

      iex> scope = %{world_id: Ecto.UUID.generate()}
      iex> LemmingsOs.Artifacts.get_artifact(scope, Ecto.UUID.generate(), include_non_ready: true)
      {:error, :not_found}
  """
  @spec get_artifact(scope(), Ecto.UUID.t(), keyword()) ::
          {:ok, artifact_descriptor()} | {:error, :invalid_scope | :not_found}
  def get_artifact(scope, artifact_id, opts)
      when is_binary(artifact_id) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      Artifact
      |> filter_query(scope_filters(scope_data))
      |> filter_query([{:id, artifact_id} | normalize_status_filters(opts)])
      |> Repo.one()
      |> normalize_read_result()
    end
  end

  def get_artifact(_scope, _artifact_id, _opts), do: {:error, :invalid_scope}

  @doc """
  Retrieves one download-ready Artifact with internal storage metadata.

  This API is for trusted runtime/controller boundaries that must resolve and
  stream Artifact files. It only returns `ready` artifacts and is scoped
  explicitly to the given world hierarchy.

  ## Examples

      iex> LemmingsOs.Artifacts.get_artifact_download(%{city_id: Ecto.UUID.generate()}, Ecto.UUID.generate())
      {:error, :invalid_scope}
  """
  @spec get_artifact_download(scope(), Ecto.UUID.t()) ::
          {:ok, download_artifact()} | {:error, :invalid_scope | :not_found}
  def get_artifact_download(scope, artifact_id) when is_binary(artifact_id) do
    with {:ok, scope_data} <- scope_data(scope) do
      Artifact
      |> filter_query(scope_filters(scope_data))
      |> filter_query(id: artifact_id, status: @ready_status)
      |> Repo.one()
      |> normalize_download_result()
    end
  end

  def get_artifact_download(_scope, _artifact_id), do: {:error, :invalid_scope}

  @doc """
  Lists `ready` artifacts in an explicit scope.

  ## Examples

      iex> LemmingsOs.Artifacts.list_artifacts_for_scope(%{city_id: Ecto.UUID.generate()})
      {:error, :invalid_scope}
  """
  @spec list_artifacts_for_scope(scope(), keyword()) ::
          {:ok, [artifact_descriptor()]} | {:error, :invalid_scope}
  def list_artifacts_for_scope(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      artifacts =
        Artifact
        |> filter_query(scope_filters(scope_data))
        |> filter_query(normalize_status_filters(opts))
        |> order_by([artifact], desc: artifact.inserted_at, desc: artifact.id)
        |> Repo.all()
        |> Enum.map(&artifact_descriptor/1)

      {:ok, artifacts}
    end
  end

  @doc """
  Lists `ready` artifacts for a runtime instance id within an explicit scope.

  ## Examples

      iex> scope = %{world_id: Ecto.UUID.generate()}
      iex> LemmingsOs.Artifacts.list_artifacts_for_instance(scope, Ecto.UUID.generate())
      {:ok, []}
  """
  @spec list_artifacts_for_instance(scope(), Ecto.UUID.t()) ::
          {:ok, [artifact_descriptor()]} | {:error, :invalid_scope}
  def list_artifacts_for_instance(scope, lemming_instance_id),
    do: list_artifacts_for_instance(scope, lemming_instance_id, [])

  @doc """
  Lists artifacts for a runtime instance id within an explicit scope.

  By default, only `ready` artifacts are returned. Pass `include_non_ready: true`
  or explicit `:status`/`:statuses` filters to include other lifecycle states.

  ## Examples

      iex> LemmingsOs.Artifacts.list_artifacts_for_instance(%{city_id: Ecto.UUID.generate()}, Ecto.UUID.generate())
      {:error, :invalid_scope}
  """
  @spec list_artifacts_for_instance(scope(), Ecto.UUID.t(), keyword()) ::
          {:ok, [artifact_descriptor()]} | {:error, :invalid_scope}
  def list_artifacts_for_instance(scope, lemming_instance_id, opts)
      when is_binary(lemming_instance_id) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- ensure_scope_instance_consistency(scope_data, lemming_instance_id) do
      artifacts =
        Artifact
        |> filter_query(scope_filters(scope_data))
        |> filter_query([
          {:lemming_instance_id, lemming_instance_id} | normalize_status_filters(opts)
        ])
        |> order_by([artifact], desc: artifact.inserted_at, desc: artifact.id)
        |> Repo.all()
        |> Enum.map(&artifact_descriptor/1)

      {:ok, artifacts}
    end
  end

  def list_artifacts_for_instance(_scope, _lemming_instance_id, _opts),
    do: {:error, :invalid_scope}

  @doc """
  Updates Artifact lifecycle status in explicit scope.

  ## Examples

      iex> scope = %{world_id: Ecto.UUID.generate()}
      iex> LemmingsOs.Artifacts.update_artifact_status(scope, Ecto.UUID.generate(), "pending")
      {:error, :invalid_status}
  """
  @spec update_artifact_status(scope(), Ecto.UUID.t(), String.t()) ::
          {:ok, artifact_descriptor()}
          | {:error, :invalid_scope | :not_found | :invalid_status | Ecto.Changeset.t()}
  def update_artifact_status(scope, artifact_id, status)
      when is_binary(artifact_id) and is_binary(status) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_status(status),
         {:ok, artifact} <- get_artifact_record(scope_data, artifact_id) do
      artifact
      |> Artifact.changeset(%{status: status})
      |> Repo.update()
      |> normalize_write_result()
    end
  end

  def update_artifact_status(_scope, _artifact_id, _status), do: {:error, :invalid_scope}

  @doc """
  Returns a safe public descriptor for an Artifact.

  The descriptor intentionally excludes `storage_ref` and any filesystem paths.

  ## Examples

      iex> artifact = %LemmingsOs.Artifacts.Artifact{
      ...>   id: Ecto.UUID.generate(),
      ...>   world_id: Ecto.UUID.generate(),
      ...>   filename: "summary.md",
      ...>   type: "markdown",
      ...>   content_type: "text/markdown",
      ...>   storage_ref: "local://artifacts/world/artifact/summary.md",
      ...>   size_bytes: 7,
      ...>   checksum: String.duplicate("a", 64),
      ...>   status: "ready",
      ...>   metadata: %{}
      ...> }
      iex> descriptor = LemmingsOs.Artifacts.artifact_descriptor(artifact)
      iex> Map.has_key?(descriptor, :storage_ref)
      false
  """
  @spec artifact_descriptor(Artifact.t()) :: artifact_descriptor()
  def artifact_descriptor(%Artifact{} = artifact) do
    Map.take(artifact, @descriptor_fields)
  end

  @doc """
  Decorates artifact descriptors with scope slugs for UI display.

  Adds `:city_slug`, `:department_slug`, and `:lemming_slug` keys when the
  corresponding scope ids are present and resolvable.

  ## Examples

      iex> LemmingsOs.Artifacts.decorate_scope_slugs([])
      []
  """
  @spec decorate_scope_slugs([artifact_descriptor()]) :: [map()]
  def decorate_scope_slugs(rows) when is_list(rows) do
    city_slug_by_id = slug_map_for(City, rows, :city_id)
    department_slug_by_id = slug_map_for(Department, rows, :department_id)
    lemming_slug_by_id = slug_map_for(Lemming, rows, :lemming_id)

    Enum.map(rows, fn row ->
      city_id = map_field(row, :city_id)
      department_id = map_field(row, :department_id)
      lemming_id = map_field(row, :lemming_id)

      row
      |> Map.put(:city_slug, Map.get(city_slug_by_id, city_id))
      |> Map.put(:department_slug, Map.get(department_slug_by_id, department_id))
      |> Map.put(:lemming_slug, Map.get(lemming_slug_by_id, lemming_id))
    end)
  end

  def decorate_scope_slugs(_rows), do: []

  defp get_artifact_record(scope_data, artifact_id) do
    Artifact
    |> filter_query(scope_filters(scope_data))
    |> filter_query(id: artifact_id)
    |> Repo.one()
    |> normalize_artifact_result()
  end

  defp normalize_read_result(nil), do: {:error, :not_found}
  defp normalize_read_result(%Artifact{} = artifact), do: {:ok, artifact_descriptor(artifact)}

  defp normalize_download_result(nil), do: {:error, :not_found}

  defp normalize_download_result(%Artifact{} = artifact) do
    {:ok,
     %{
       id: artifact.id,
       filename: artifact.filename,
       content_type: artifact.content_type,
       storage_ref: artifact.storage_ref
     }}
  end

  defp normalize_write_result({:ok, %Artifact{} = artifact}),
    do: {:ok, artifact_descriptor(artifact)}

  defp normalize_write_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_artifact_result(nil), do: {:error, :not_found}
  defp normalize_artifact_result(%Artifact{} = artifact), do: {:ok, artifact}

  defp validate_status(status) when status in @artifact_statuses, do: :ok
  defp validate_status(_status), do: {:error, :invalid_status}

  defp normalize_status_filters(opts) do
    cond do
      Keyword.has_key?(opts, :status) ->
        Keyword.drop(opts, [:include_non_ready])

      Keyword.has_key?(opts, :statuses) ->
        Keyword.drop(opts, [:include_non_ready])

      Keyword.get(opts, :include_non_ready, false) ->
        Keyword.drop(opts, [:include_non_ready])

      true ->
        [{:status, @ready_status} | Keyword.drop(opts, [:include_non_ready])]
    end
  end

  defp ensure_scope_instance_consistency(%{lemming_instance_id: nil}, _instance_id), do: :ok

  defp ensure_scope_instance_consistency(%{lemming_instance_id: lemming_instance_id}, instance_id)
       when lemming_instance_id == instance_id,
       do: :ok

  defp ensure_scope_instance_consistency(_scope_data, _instance_id), do: {:error, :invalid_scope}

  defp ensure_scope_attr_consistency(scope_data, attrs) do
    Enum.reduce_while(@scope_fields, :ok, fn field, :ok ->
      expected = Map.get(scope_data, field)
      actual = map_field(attrs, field)

      if is_nil(actual) or actual == expected do
        {:cont, :ok}
      else
        {:halt, {:error, :scope_mismatch}}
      end
    end)
  end

  defp scope_attrs(%{} = scope_data) do
    Map.take(scope_data, @scope_fields)
  end

  defp scope_filters(scope_data) do
    Enum.reduce(@scope_fields, [], fn field, acc ->
      case Map.get(scope_data, field) do
        nil -> acc
        value -> [{field, value} | acc]
      end
    end)
  end

  defp slug_map_for(schema, rows, field) do
    ids = collect_scope_ids(rows, field)

    case ids do
      [] ->
        %{}

      _ids ->
        schema
        |> where([entity], entity.id in ^ids)
        |> select([entity], {entity.id, entity.slug})
        |> Repo.all()
        |> Map.new()
    end
  end

  defp collect_scope_ids(rows, field) do
    rows
    |> Enum.map(&map_field(&1, field))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp scope_data(%World{id: world_id}) when is_binary(world_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: nil,
       department_id: nil,
       lemming_id: nil,
       lemming_instance_id: nil
     }}
  end

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: nil,
       lemming_id: nil,
       lemming_instance_id: nil
     }}
  end

  defp scope_data(%Department{id: department_id, city_id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: nil,
       lemming_instance_id: nil
     }}
  end

  defp scope_data(%Lemming{
         id: lemming_id,
         department_id: department_id,
         city_id: city_id,
         world_id: world_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: lemming_id,
       lemming_instance_id: nil
     }}
  end

  defp scope_data(%LemmingInstance{
         id: lemming_instance_id,
         lemming_id: lemming_id,
         department_id: department_id,
         city_id: city_id,
         world_id: world_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) and is_binary(lemming_instance_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: lemming_id,
       lemming_instance_id: lemming_instance_id
     }}
  end

  defp scope_data(%{} = scope) do
    world_id = map_field(scope, :world_id)
    city_id = map_field(scope, :city_id)
    department_id = map_field(scope, :department_id)
    lemming_id = map_field(scope, :lemming_id)
    lemming_instance_id = map_field(scope, :lemming_instance_id)

    with :ok <-
           validate_scope_shape(world_id, city_id, department_id, lemming_id, lemming_instance_id),
         :ok <-
           validate_scope_uuids(world_id, city_id, department_id, lemming_id, lemming_instance_id) do
      {:ok,
       %{
         world_id: world_id,
         city_id: city_id,
         department_id: department_id,
         lemming_id: lemming_id,
         lemming_instance_id: lemming_instance_id
       }}
    end
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp validate_scope_shape(world_id, nil, nil, nil, nil) when is_binary(world_id), do: :ok

  defp validate_scope_shape(world_id, city_id, nil, nil, nil)
       when is_binary(world_id) and is_binary(city_id),
       do: :ok

  defp validate_scope_shape(world_id, city_id, department_id, nil, nil)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id),
       do: :ok

  defp validate_scope_shape(world_id, city_id, department_id, lemming_id, nil)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id),
       do: :ok

  defp validate_scope_shape(world_id, city_id, department_id, lemming_id, lemming_instance_id)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) and is_binary(lemming_instance_id),
       do: :ok

  defp validate_scope_shape(_world_id, _city_id, _department_id, _lemming_id, _instance_id),
    do: {:error, :invalid_scope}

  defp validate_scope_uuids(world_id, city_id, department_id, lemming_id, lemming_instance_id) do
    [world_id, city_id, department_id, lemming_id, lemming_instance_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce_while(:ok, fn value, :ok ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> {:cont, :ok}
        :error -> {:halt, {:error, :invalid_scope}}
      end
    end)
  end

  defp map_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp filter_query(query, [{:id, id} | rest]),
    do: filter_query(from(artifact in query, where: artifact.id == ^id), rest)

  defp filter_query(query, [{:ids, ids} | rest]) when is_list(ids),
    do: filter_query(from(artifact in query, where: artifact.id in ^ids), rest)

  defp filter_query(query, [{:world_id, world_id} | rest]),
    do: filter_query(from(artifact in query, where: artifact.world_id == ^world_id), rest)

  defp filter_query(query, [{:city_id, city_id} | rest]),
    do: filter_query(from(artifact in query, where: artifact.city_id == ^city_id), rest)

  defp filter_query(query, [{:department_id, department_id} | rest]),
    do:
      filter_query(from(artifact in query, where: artifact.department_id == ^department_id), rest)

  defp filter_query(query, [{:lemming_id, lemming_id} | rest]),
    do: filter_query(from(artifact in query, where: artifact.lemming_id == ^lemming_id), rest)

  defp filter_query(query, [{:lemming_instance_id, lemming_instance_id} | rest]),
    do:
      filter_query(
        from(artifact in query, where: artifact.lemming_instance_id == ^lemming_instance_id),
        rest
      )

  defp filter_query(query, [{:created_by_tool_execution_id, created_by_tool_execution_id} | rest]),
    do:
      filter_query(
        from(
          artifact in query,
          where: artifact.created_by_tool_execution_id == ^created_by_tool_execution_id
        ),
        rest
      )

  defp filter_query(query, [{:filename, filename} | rest]),
    do: filter_query(from(artifact in query, where: artifact.filename == ^filename), rest)

  defp filter_query(query, [{:type, type} | rest]),
    do: filter_query(from(artifact in query, where: artifact.type == ^type), rest)

  defp filter_query(query, [{:status, status} | rest]),
    do: filter_query(from(artifact in query, where: artifact.status == ^status), rest)

  defp filter_query(query, [{:statuses, statuses} | rest]) when is_list(statuses),
    do: filter_query(from(artifact in query, where: artifact.status in ^statuses), rest)

  defp filter_query(query, [{:preload, preloads} | rest]),
    do: filter_query(preload(query, ^preloads), rest)

  defp filter_query(query, [{key, _value} | rest]) when key in @status_fields,
    do: filter_query(query, rest)

  defp filter_query(query, [_unknown | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query
end
