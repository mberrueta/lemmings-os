defmodule LemmingsOs.Artifacts.Promotion do
  @moduledoc """
  Promotion workflow for copying trusted workspace files into managed Artifact storage.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias LemmingsOs.Artifacts
  alias LemmingsOs.Artifacts.Artifact
  alias LemmingsOs.Artifacts.LocalStorage
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Repo
  alias LemmingsOs.Tools.WorkArea

  @ready_status "ready"
  @promote_modes ~w(update_existing promote_as_new)a
  @extension_types %{
    ".md" => "markdown",
    ".markdown" => "markdown",
    ".pdf" => "pdf",
    ".json" => "json",
    ".csv" => "csv",
    ".eml" => "email",
    ".html" => "html",
    ".htm" => "html",
    ".png" => "image",
    ".jpg" => "image",
    ".jpeg" => "image",
    ".gif" => "image",
    ".webp" => "image",
    ".txt" => "text"
  }

  @doc """
  Promotes one trusted workspace file into managed Artifact storage for a validated scope.

  ## Examples

      iex> scope = %{
      ...>   world_id: Ecto.UUID.generate(),
      ...>   city_id: nil,
      ...>   department_id: nil,
      ...>   lemming_id: nil,
      ...>   lemming_instance_id: nil
      ...> }
      iex> LemmingsOs.Artifacts.Promotion.promote_workspace_file(scope, %{})
      {:error, :invalid_attrs}
  """
  @spec promote_workspace_file(Artifacts.scope_data(), map()) ::
          {:ok, Artifacts.artifact_descriptor()}
          | {:error, atom() | Ecto.Changeset.t() | {atom(), term()}}
  def promote_workspace_file(scope_data, attrs) when is_map(scope_data) and is_map(attrs) do
    result =
      with {:ok, relative_path} <- fetch_non_empty_string(attrs, :relative_path),
           {:ok, mode} <- normalize_mode(map_field(attrs, :mode)),
           {:ok, instance_id} <- resolve_instance_id(scope_data, attrs),
           {:ok, instance} <-
             LemmingInstances.get_instance(instance_id, world_id: scope_data.world_id),
           {:ok, promotion_scope} <- enrich_scope_with_instance(scope_data, instance),
           {:ok, resolved_source} <-
             resolve_workspace_source_path(promotion_scope, instance, relative_path),
           filename <- resolve_filename(attrs, resolved_source.relative_path),
           :ok <- ensure_filename_safe(filename),
           promotion_attrs <- build_promotion_attrs(attrs, promotion_scope, instance, filename) do
        promote_with_mode(
          promotion_scope,
          promotion_attrs,
          resolved_source.absolute_path,
          mode
        )
      else
        {:error, :not_found} -> {:error, :instance_not_found}
        {:error, reason} -> {:error, reason}
      end

    result
  end

  defp promote_with_mode(scope_data, promotion_attrs, source_absolute_path, mode) do
    Multi.new()
    |> Multi.run(:existing_artifact, fn repo, _changes ->
      {:ok, find_existing_artifact(repo, scope_data, promotion_attrs.filename)}
    end)
    |> Multi.run(:artifact, fn repo, %{existing_artifact: existing_artifact} ->
      upsert_promoted_artifact(
        repo,
        existing_artifact,
        scope_data,
        promotion_attrs,
        source_absolute_path,
        mode
      )
    end)
    |> Repo.transaction()
    |> normalize_promotion_result()
  end

  defp find_existing_artifact(repo, scope_data, filename) do
    query =
      Artifact
      |> where([artifact], artifact.world_id == ^scope_data.world_id)
      |> maybe_scope_match(:city_id, scope_data.city_id)
      |> maybe_scope_match(:department_id, scope_data.department_id)
      |> maybe_scope_match(:lemming_id, scope_data.lemming_id)
      |> where([artifact], artifact.filename == ^filename)
      |> order_by([artifact], desc: artifact.inserted_at, desc: artifact.id)
      |> limit(1)

    repo.one(query)
  end

  defp maybe_scope_match(query, _field, nil), do: query

  defp maybe_scope_match(query, field, value) do
    from(artifact in query, where: field(artifact, ^field) == ^value)
  end

  defp upsert_promoted_artifact(
         repo,
         nil,
         scope_data,
         promotion_attrs,
         source_absolute_path,
         _mode
       ) do
    artifact_id = Ecto.UUID.generate()

    with {:ok, stored} <-
           LocalStorage.store_copy(
             scope_data.world_id,
             artifact_id,
             source_absolute_path,
             promotion_attrs.filename
           ) do
      %Artifact{id: artifact_id}
      |> Artifact.changeset(Map.merge(promotion_attrs, stored))
      |> repo.insert()
      |> lifecycle_result(:promoted)
    end
  end

  defp upsert_promoted_artifact(
         repo,
         %Artifact{} = existing_artifact,
         scope_data,
         promotion_attrs,
         source_absolute_path,
         :update_existing
       ) do
    with {:ok, stored} <-
           LocalStorage.store_copy(
             scope_data.world_id,
             existing_artifact.id,
             source_absolute_path,
             existing_artifact.filename
           ) do
      attrs =
        promotion_attrs
        |> Map.put(:filename, existing_artifact.filename)
        |> Map.merge(stored)

      existing_artifact
      |> Artifact.changeset(attrs)
      |> repo.update()
      |> lifecycle_result(:updated)
    end
  end

  defp upsert_promoted_artifact(
         repo,
         %Artifact{},
         scope_data,
         promotion_attrs,
         source_absolute_path,
         :promote_as_new
       ) do
    artifact_id = Ecto.UUID.generate()

    with {:ok, stored} <-
           LocalStorage.store_copy(
             scope_data.world_id,
             artifact_id,
             source_absolute_path,
             promotion_attrs.filename
           ) do
      %Artifact{id: artifact_id}
      |> Artifact.changeset(Map.merge(promotion_attrs, stored))
      |> repo.insert()
      |> lifecycle_result(:promoted)
    end
  end

  defp upsert_promoted_artifact(
         _repo,
         %Artifact{},
         _scope_data,
         _attrs,
         _source_absolute_path,
         nil
       ),
       do: {:error, :mode_required}

  defp upsert_promoted_artifact(
         _repo,
         %Artifact{},
         _scope_data,
         _attrs,
         _source_absolute_path,
         _other_mode
       ),
       do: {:error, :invalid_mode}

  defp normalize_promotion_result(
         {:ok, %{artifact: %{artifact: %Artifact{} = artifact, lifecycle: _lifecycle}}}
       ) do
    {:ok, Artifacts.artifact_descriptor(artifact)}
  end

  defp normalize_promotion_result({:error, :artifact, %Ecto.Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_promotion_result({:error, :artifact, reason, _changes}),
    do: {:error, reason}

  defp normalize_promotion_result({:error, _step, reason, _changes}),
    do: {:error, reason}

  defp build_promotion_attrs(attrs, scope_data, instance, filename) do
    type = map_field(attrs, :type) || infer_type(filename)
    content_type = map_field(attrs, :content_type) || infer_content_type(filename)
    notes = map_field(attrs, :notes)
    created_by_tool_execution_id = map_field(attrs, :created_by_tool_execution_id)
    metadata = map_field(attrs, :metadata) || %{"source" => "manual_promotion"}

    %{
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id,
      lemming_id: scope_data.lemming_id,
      lemming_instance_id: instance.id,
      created_by_tool_execution_id: created_by_tool_execution_id,
      filename: filename,
      type: type,
      content_type: content_type,
      status: @ready_status,
      notes: notes,
      metadata: metadata
    }
  end

  defp resolve_filename(attrs, resolved_relative_path) do
    map_field(attrs, :filename) || Path.basename(resolved_relative_path)
  end

  defp resolve_workspace_source_path(scope_data, %LemmingInstance{} = instance, relative_path) do
    work_area_ref = runtime_work_area_ref(scope_data, instance)

    case WorkArea.resolve(work_area_ref, relative_path) do
      {:ok, %{absolute_path: absolute_path} = resolved} ->
        if File.regular?(absolute_path) do
          {:ok, resolved}
        else
          resolve_workspace_source_path_legacy(instance, relative_path)
        end

      {:error, :work_area_unavailable} ->
        resolve_workspace_source_path_legacy(instance, relative_path)

      {:error, :invalid_path} ->
        {:error, :path_outside_workspace}
    end
  end

  defp resolve_workspace_source_path_legacy(%LemmingInstance{} = instance, relative_path) do
    case LemmingInstances.artifact_absolute_path(instance, relative_path) do
      {:ok, resolved_source} -> {:ok, resolved_source}
      {:error, :invalid_path} -> {:error, :path_outside_workspace}
      {:error, reason} -> {:error, reason}
    end
  end

  defp runtime_work_area_ref(scope_data, %LemmingInstance{} = instance) do
    case LemmingInstances.get_runtime_state(instance.id, world_id: scope_data.world_id) do
      {:ok, %{work_area_ref: work_area_ref}}
      when is_binary(work_area_ref) and work_area_ref != "" ->
        work_area_ref

      _other ->
        instance.id
    end
  end

  defp resolve_instance_id(scope_data, attrs) do
    attrs_instance_id = map_field(attrs, :lemming_instance_id)

    cond do
      is_binary(scope_data.lemming_instance_id) and is_binary(attrs_instance_id) and
          scope_data.lemming_instance_id != attrs_instance_id ->
        {:error, :invalid_scope}

      is_binary(scope_data.lemming_instance_id) ->
        {:ok, scope_data.lemming_instance_id}

      is_binary(attrs_instance_id) ->
        {:ok, attrs_instance_id}

      true ->
        {:error, :missing_instance_id}
    end
  end

  defp enrich_scope_with_instance(scope_data, %LemmingInstance{} = instance) do
    merged_scope = %{
      world_id: scope_data.world_id,
      city_id: scope_data.city_id || instance.city_id,
      department_id: scope_data.department_id || instance.department_id,
      lemming_id: scope_data.lemming_id || instance.lemming_id,
      lemming_instance_id: scope_data.lemming_instance_id || instance.id
    }

    if instance_matches_scope?(merged_scope, instance) do
      {:ok, merged_scope}
    else
      {:error, :invalid_scope}
    end
  end

  defp instance_matches_scope?(scope_data, instance) do
    scope_data.world_id == instance.world_id and
      scope_data.city_id == instance.city_id and
      scope_data.department_id == instance.department_id and
      scope_data.lemming_id == instance.lemming_id and
      scope_data.lemming_instance_id == instance.id
  end

  defp fetch_non_empty_string(attrs, field) do
    case map_field(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _value -> {:error, :invalid_attrs}
    end
  end

  defp normalize_mode(nil), do: {:ok, nil}
  defp normalize_mode(mode) when mode in @promote_modes, do: {:ok, mode}

  defp normalize_mode(mode) when is_binary(mode) do
    case mode do
      "update_existing" -> {:ok, :update_existing}
      "promote_as_new" -> {:ok, :promote_as_new}
      _other -> {:error, :invalid_mode}
    end
  end

  defp normalize_mode(_mode), do: {:error, :invalid_mode}

  defp ensure_filename_safe(filename) when is_binary(filename) do
    case LocalStorage.build_storage_ref(Ecto.UUID.generate(), Ecto.UUID.generate(), filename) do
      {:ok, _storage_ref} -> :ok
      {:error, _reason} -> {:error, :invalid_filename}
    end
  end

  defp infer_content_type(filename) do
    case MIME.from_path(filename) do
      "" -> "application/octet-stream"
      content_type -> content_type
    end
  end

  defp infer_type(filename) do
    filename
    |> Path.extname()
    |> String.downcase()
    |> then(&Map.get(@extension_types, &1, "other"))
  end

  defp lifecycle_result({:ok, %Artifact{} = artifact}, lifecycle),
    do: {:ok, %{artifact: artifact, lifecycle: lifecycle}}

  defp lifecycle_result({:error, reason}, _lifecycle), do: {:error, reason}

  defp map_field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
