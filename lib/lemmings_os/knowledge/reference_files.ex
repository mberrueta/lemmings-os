defmodule LemmingsOs.Knowledge.ReferenceFiles do
  @moduledoc false

  import Ecto.Query, warn: false

  require Logger

  alias LemmingsOs.Artifacts
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.ReferenceFile
  alias LemmingsOs.Knowledge.ReferenceFileStorageService
  alias LemmingsOs.Knowledge.Shared
  alias LemmingsOs.Knowledge.SourceFiles.ExtractionService
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @default_limit 25
  @max_limit 100
  @default_read_max_chars 4_000
  @max_read_max_chars 8_000

  @spec create_reference_file(World.t() | City.t() | Department.t() | Lemming.t(), map()) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_reference_file(scope, attrs) when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         {:ok, knowledge_item_attrs, reference_file_attrs} <-
           reference_file_create_attrs(attrs, scope_data) do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :knowledge_item,
          KnowledgeItem.changeset(%KnowledgeItem{}, knowledge_item_attrs)
        )
        |> Ecto.Multi.insert(:reference_file, fn %{knowledge_item: knowledge_item} ->
          reference_ref =
            fetch(reference_file_attrs, :reference_ref) ||
              build_reference_ref!(knowledge_item.id)

          attrs =
            reference_file_attrs
            |> Map.put(:reference_ref, reference_ref)
            |> Map.put(:knowledge_item_id, knowledge_item.id)

          ReferenceFile.changeset(%ReferenceFile{}, attrs)
        end)

      case Repo.transaction(multi) do
        {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}} ->
          {:ok, %{knowledge_item: knowledge_item, reference_file: reference_file}}
          |> maybe_record_reference_file_event("knowledge.reference_file.created", scope_data)

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  def create_reference_file(_scope, _attrs), do: {:error, :invalid_attrs}

  @spec create_reference_file_upload(
          World.t() | City.t() | Department.t() | Lemming.t(),
          map(),
          String.t()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def create_reference_file_upload(scope, attrs, source_path)
      when is_map(attrs) and is_binary(source_path) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         filename when is_binary(filename) <- fetch(attrs, :original_filename),
         {:ok, knowledge_item_id} <- Ecto.UUID.cast(Ecto.UUID.generate()),
         {:ok, stored} <-
           ReferenceFileStorageService.put(
             scope_data.world_id,
             knowledge_item_id,
             source_path,
             filename
           ) do
      attrs =
        attrs
        |> Map.put(:storage_ref, stored.storage_ref)
        |> Map.put(:size_bytes, stored.size_bytes)
        |> Map.put(:checksum, stored.checksum)

      create_reference_file(scope, attrs)
    else
      {:error, reason}
      when reason in [:invalid_source_path, :source_not_found, :file_too_large] ->
        {:error, :invalid_attrs}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :invalid_attrs}
    end
  end

  def create_reference_file_upload(_scope, _attrs, _source_path), do: {:error, :invalid_attrs}

  @spec promote_artifact_to_reference_file(
          World.t() | City.t() | Department.t() | Lemming.t(),
          Ecto.UUID.t(),
          map()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error,
             Ecto.Changeset.t()
             | :invalid_scope
             | :scope_mismatch
             | :invalid_attrs
             | :operator_approval_required
             | :artifact_unavailable}
  def promote_artifact_to_reference_file(scope, artifact_id, attrs)
      when is_binary(artifact_id) and is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         :ok <- validate_requested_scope(attrs, scope_data),
         :ok <- require_operator_approval(attrs),
         {:ok, artifact} <- Artifacts.get_artifact(scope, artifact_id),
         :ok <- validate_promoted_artifact_scope(artifact, scope_data),
         {:ok, opened} <- Artifacts.open_artifact_download(scope, artifact_id) do
      upload_attrs =
        attrs
        |> Map.put_new(:original_filename, artifact.filename)
        |> Map.put_new(:content_type, artifact.content_type)
        |> Map.put(:artifact_id, artifact_id)

      create_reference_file_upload(scope, upload_attrs, opened.path)
      |> maybe_record_reference_file_event(
        "knowledge.reference_file.artifact_promoted",
        scope_data
      )
    else
      {:error, :not_found} ->
        {:error, :artifact_unavailable}

      {:error, :scope_mismatch} ->
        {:error, :artifact_unavailable}

      {:error, _reason} = error ->
        error
    end
  end

  def promote_artifact_to_reference_file(_scope, _artifact_id, _attrs),
    do: {:error, :invalid_attrs}

  @spec list_reference_files(World.t() | City.t() | Department.t() | Lemming.t(), keyword()) ::
          [ReferenceFile.t()]
  def list_reference_files(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        status = Keyword.get(opts, :status)

        ReferenceFile
        |> join(:inner, [reference_file], knowledge_item in KnowledgeItem,
          on: knowledge_item.id == reference_file.knowledge_item_id
        )
        |> where(
          [_reference_file, knowledge_item],
          knowledge_item.world_id == ^scope_data.world_id
        )
        |> maybe_scope_eq(:city_id, scope_data.city_id)
        |> maybe_scope_eq(:department_id, scope_data.department_id)
        |> maybe_scope_eq(:lemming_id, scope_data.lemming_id)
        |> maybe_filter_reference_file_status(status)
        |> order_by([reference_file, _knowledge_item],
          desc: reference_file.inserted_at,
          desc: reference_file.id
        )
        |> Repo.all()
        |> Repo.preload(:knowledge_item)

      {:error, _reason} ->
        []
    end
  end

  @spec list_effective_reference_files(
          World.t() | City.t() | Department.t() | Lemming.t(),
          keyword()
        ) ::
          {:ok, [map()]} | {:error, :invalid_scope | :scope_mismatch}
  def list_effective_reference_files(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      status = Keyword.get(opts, :status, "active")

      rows =
        KnowledgeItem
        |> where([knowledge_item], knowledge_item.kind == "reference_file")
        |> filter_scope_relevance(scope_data)
        |> maybe_filter_effective_status(status)
        |> join(:inner, [knowledge_item], reference_file in ReferenceFile,
          on: reference_file.knowledge_item_id == knowledge_item.id
        )
        |> order_by([_knowledge_item, reference_file],
          desc: reference_file.inserted_at,
          desc: reference_file.id
        )
        |> select([_knowledge_item, reference_file], reference_file)
        |> Repo.all()
        |> Repo.preload(:knowledge_item)

      {:ok,
       Enum.map(rows, fn %ReferenceFile{knowledge_item: knowledge_item} = reference_file ->
         owner_scope = owner_scope(knowledge_item)
         local? = knowledge_item_in_scope?(knowledge_item, scope_data)
         inherited? = inherited_owner?(knowledge_item, scope_data, local?)

         %{
           reference_file: reference_file,
           descriptor: build_reference_file_descriptor(reference_file),
           owner_scope: owner_scope,
           owner_scope_label: String.capitalize(owner_scope),
           local?: local?,
           inherited?: inherited?,
           descendant?: not local? and not inherited?
         }
       end)}
    end
  end

  @spec update_reference_file_metadata(
          World.t() | City.t() | Department.t() | Lemming.t(),
          ReferenceFile.t(),
          map()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch | :invalid_attrs}
  def update_reference_file_metadata(scope, %ReferenceFile{} = reference_file, attrs)
      when is_map(attrs) do
    with {:ok, scope_data} <- scope_data(scope),
         %ReferenceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} = reference_file <-
           Repo.preload(reference_file, :knowledge_item),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      knowledge_attrs =
        attrs
        |> Map.take([:title, :content, :tags])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      reference_file_attrs =
        attrs
        |> Map.take([:reference_file_type])
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      multi =
        Ecto.Multi.new()
        |> maybe_update_knowledge_item(knowledge_item, knowledge_attrs)
        |> maybe_update_reference_file(reference_file, reference_file_attrs)

      case Repo.transaction(multi) do
        {:ok, %{reference_file: updated_reference_file, knowledge_item: updated_knowledge_item}} ->
          {:ok, %{knowledge_item: updated_knowledge_item, reference_file: updated_reference_file}}
          |> maybe_record_reference_file_event("knowledge.reference_file.updated", scope_data)

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :scope_mismatch}
    end
  end

  def update_reference_file_metadata(_scope, _reference_file, _attrs),
    do: {:error, :invalid_attrs}

  @spec archive_reference_file(
          World.t() | City.t() | Department.t() | Lemming.t(),
          ReferenceFile.t()
        ) ::
          {:ok, %{knowledge_item: KnowledgeItem.t(), reference_file: ReferenceFile.t()}}
          | {:error, Ecto.Changeset.t() | :invalid_scope | :scope_mismatch}
  def archive_reference_file(scope, %ReferenceFile{} = reference_file) do
    with {:ok, scope_data} <- scope_data(scope),
         %ReferenceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} = reference_file <-
           Repo.preload(reference_file, :knowledge_item),
         :ok <- validate_exact_scope(knowledge_item, scope_data) do
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :knowledge_item,
          KnowledgeItem.changeset(knowledge_item, %{status: "archived"})
        )
        |> Ecto.Multi.put(:reference_file, reference_file)

      case Repo.transaction(multi) do
        {:ok, %{knowledge_item: updated_knowledge_item, reference_file: updated_reference_file}} ->
          {:ok, %{knowledge_item: updated_knowledge_item, reference_file: updated_reference_file}}
          |> maybe_record_reference_file_event("knowledge.reference_file.archived", scope_data)

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :scope_mismatch}
    end
  end

  @spec build_reference_file_descriptor(ReferenceFile.t()) :: map()
  def build_reference_file_descriptor(%ReferenceFile{} = reference_file) do
    reference_file = Repo.preload(reference_file, :knowledge_item)
    knowledge_item = fetch(reference_file, :knowledge_item)
    public = ReferenceFileStorageService.public_descriptor(reference_file)

    %{
      reference_ref: fetch(public, :reference_ref),
      knowledge_item_id: fetch(reference_file, :knowledge_item_id),
      kind: fetch(knowledge_item, :kind),
      reference_file_type: fetch(public, :reference_file_type),
      title: fetch(knowledge_item, :title),
      tags: fetch(knowledge_item, :tags) || [],
      status: fetch(knowledge_item, :status),
      content_type: fetch(public, :content_type)
    }
  end

  @spec list_available_reference_files(
          World.t() | City.t() | Department.t() | Lemming.t(),
          keyword()
        ) ::
          {:ok, [map()]} | {:error, :invalid_scope | :scope_mismatch}
  def list_available_reference_files(scope, opts \\ []) when is_list(opts) do
    opts =
      opts
      |> Keyword.delete(:status)
      |> Keyword.put(:status, "active")
      |> Keyword.put_new(:limit, @max_limit)

    with {:ok, page} <- search_reference_files(scope, opts) do
      {:ok, page.entries}
    end
  end

  @spec search_reference_files(World.t() | City.t() | Department.t() | Lemming.t(), keyword()) ::
          {:ok, map()} | {:error, :invalid_scope | :scope_mismatch}
  def search_reference_files(scope, opts \\ []) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope) do
      limit = limit_value(opts)
      offset = offset_value(opts)

      entries =
        scope_data
        |> reference_file_search_rows(reference_search_status(opts))
        |> Enum.filter(&reference_file_search_match?(&1, opts))
        |> sort_reference_file_rows(scope_data, opts)

      {:ok,
       %{
         entries: entries |> Enum.drop(offset) |> Enum.take(limit),
         total_count: length(entries),
         limit: limit,
         offset: offset
       }}
    end
  end

  @spec read_reference_file(
          World.t() | City.t() | Department.t() | Lemming.t(),
          String.t() | map() | keyword(),
          keyword()
        ) :: {:ok, map()} | {:error, :invalid_scope | :scope_mismatch | :not_found}
  def read_reference_file(scope, identifier, opts \\ [])

  def read_reference_file(scope, identifier, opts) when is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         {:ok, normalized_identifier} <- normalize_reference_file_identifier(identifier),
         %ReferenceFile{} = reference_file <-
           get_visible_active_reference_file(scope_data, normalized_identifier) do
      {:ok, reference_file_read_result(reference_file, read_max_chars_value(opts))}
    else
      {:error, :invalid_scope} = error -> error
      {:error, :scope_mismatch} = error -> error
      _other -> {:error, :not_found}
    end
  end

  def read_reference_file(_scope, _identifier, _opts), do: {:error, :not_found}

  defp reference_file_search_rows(scope_data, status) do
    KnowledgeItem
    |> where([knowledge_item], knowledge_item.kind == "reference_file")
    |> filter_scope_relevance(scope_data)
    |> maybe_filter_reference_file_search_status(status)
    |> join(:inner, [knowledge_item], reference_file in ReferenceFile,
      on: reference_file.knowledge_item_id == knowledge_item.id
    )
    |> select([_knowledge_item, reference_file], reference_file)
    |> Repo.all()
    |> Repo.preload(:knowledge_item)
    |> Enum.map(&reference_file_row(&1, scope_data))
  end

  defp reference_file_row(
         %ReferenceFile{knowledge_item: %KnowledgeItem{} = knowledge_item} = file,
         scope_data
       ) do
    owner_scope = owner_scope(knowledge_item)
    local? = knowledge_item_in_scope?(knowledge_item, scope_data)
    inherited? = inherited_owner?(knowledge_item, scope_data, local?)

    %{
      reference_file: file,
      descriptor: build_reference_file_descriptor(file),
      owner_scope: owner_scope,
      owner_scope_label: String.capitalize(owner_scope),
      local?: local?,
      inherited?: inherited?,
      descendant?: not local? and not inherited?
    }
  end

  defp reference_file_search_match?(%{descriptor: descriptor, reference_file: file}, opts) do
    reference_file_kind_match?(descriptor, Keyword.get(opts, :kind)) and
      reference_file_type_match?(
        descriptor,
        Keyword.get(opts, :reference_file_type) || Keyword.get(opts, :type)
      ) and
      reference_file_tags_match?(descriptor, Keyword.get(opts, :tags)) and
      reference_file_owner_scope_match?(
        file,
        Keyword.get(opts, :owner_scope) || Keyword.get(opts, :scope)
      ) and
      reference_file_query_match?(
        descriptor,
        file,
        Keyword.get(opts, :q) || Keyword.get(opts, :query)
      )
  end

  defp reference_file_kind_match?(_descriptor, nil), do: true
  defp reference_file_kind_match?(%{kind: kind}, kind), do: true
  defp reference_file_kind_match?(_descriptor, _kind), do: false

  defp reference_file_type_match?(_descriptor, nil), do: true

  defp reference_file_type_match?(%{reference_file_type: reference_file_type}, type)
       when is_binary(type) do
    normalized_filter = normalize_search_text(type)
    normalized_type = normalize_search_text(reference_file_type || "")

    normalized_filter == "" or String.contains?(normalized_type, normalized_filter)
  end

  defp reference_file_type_match?(_descriptor, _type), do: true

  defp reference_file_tags_match?(_descriptor, nil), do: true

  defp reference_file_tags_match?(%{tags: tags}, requested_tags) when is_list(requested_tags) do
    normalized_tags =
      requested_tags
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    normalized_tags == [] or Enum.all?(normalized_tags, &(&1 in tags))
  end

  defp reference_file_tags_match?(_descriptor, _requested_tags), do: true

  defp reference_file_owner_scope_match?(_file, nil), do: true

  defp reference_file_owner_scope_match?(
         %ReferenceFile{knowledge_item: %KnowledgeItem{} = item},
         scope
       )
       when scope in ["world", "city", "department", "lemming"],
       do: owner_scope(item) == scope

  defp reference_file_owner_scope_match?(_file, _scope), do: true

  defp reference_file_query_match?(_descriptor, _file, nil), do: true

  defp reference_file_query_match?(descriptor, %ReferenceFile{} = file, query)
       when is_binary(query) do
    normalized_query = normalize_search_text(query)

    normalized_query == "" or
      descriptor
      |> reference_file_search_text(file)
      |> String.contains?(normalized_query)
  end

  defp reference_file_query_match?(_descriptor, _file, _query), do: true

  defp sort_reference_file_rows(rows, scope_data, opts) do
    query = normalize_search_text(Keyword.get(opts, :q) || Keyword.get(opts, :query) || "")

    Enum.sort_by(rows, fn %{reference_file: file, descriptor: descriptor} ->
      knowledge_item = fetch(file, :knowledge_item)
      inserted_at = fetch(file, :inserted_at) || fetch(knowledge_item, :inserted_at)

      {
        reference_file_scope_distance(knowledge_item, scope_data),
        -scope_depth(knowledge_item),
        -reference_file_match_score(descriptor, file, query),
        -datetime_sort_value(inserted_at),
        fetch(file, :id) || ""
      }
    end)
  end

  defp reference_file_match_score(_descriptor, _file, ""), do: 0

  defp reference_file_match_score(descriptor, %ReferenceFile{} = file, query) do
    title = normalize_search_text(fetch(descriptor, :title) || "")
    type = normalize_search_text(fetch(descriptor, :reference_file_type) || "")
    reference_ref = normalize_search_text(fetch(descriptor, :reference_ref) || "")
    tags = fetch(descriptor, :tags) || []

    0
    |> add_score(title == query, 50)
    |> add_score(String.contains?(title, query), 35)
    |> add_score(Enum.any?(tags, &(normalize_search_text(&1) == query)), 30)
    |> add_score(Enum.any?(tags, &String.contains?(normalize_search_text(&1), query)), 20)
    |> add_score(type == query, 25)
    |> add_score(String.contains?(type, query), 15)
    |> add_score(reference_ref == query, 20)
    |> add_score(String.contains?(reference_file_search_text(descriptor, file), query), 5)
  end

  defp add_score(score, true, amount), do: score + amount
  defp add_score(score, false, _amount), do: score

  defp reference_file_scope_distance(%KnowledgeItem{} = knowledge_item, scope_data) do
    abs(scope_depth(knowledge_item) - scope_data_depth(scope_data))
  end

  defp reference_file_scope_distance(_knowledge_item, _scope_data), do: 99

  defp scope_depth(%KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil}), do: 0
  defp scope_depth(%KnowledgeItem{department_id: nil, lemming_id: nil}), do: 1
  defp scope_depth(%KnowledgeItem{lemming_id: nil}), do: 2
  defp scope_depth(%KnowledgeItem{}), do: 3

  defp scope_data_depth(%{city_id: nil, department_id: nil, lemming_id: nil}), do: 0
  defp scope_data_depth(%{department_id: nil, lemming_id: nil}), do: 1
  defp scope_data_depth(%{lemming_id: nil}), do: 2
  defp scope_data_depth(%{}), do: 3

  defp datetime_sort_value(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp datetime_sort_value(%NaiveDateTime{} = datetime),
    do: NaiveDateTime.to_gregorian_seconds(datetime)

  defp datetime_sort_value(_datetime), do: 0

  defp reference_file_search_text(descriptor, %ReferenceFile{} = file) do
    [
      fetch(descriptor, :title),
      fetch(descriptor, :reference_ref),
      fetch(descriptor, :reference_file_type),
      fetch(descriptor, :content_type),
      fetch(file, :original_filename),
      fetch(fetch(file, :knowledge_item) || %{}, :content),
      Enum.join(fetch(descriptor, :tags) || [], " ")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &to_string/1)
    |> normalize_search_text()
  end

  defp normalize_search_text(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.trim()
  end

  defp normalize_search_text(_value), do: ""

  defp reference_search_status(opts) do
    case Keyword.get(opts, :status, "active") do
      "active" -> "active"
      "archived" -> "archived"
      "all" -> "all"
      _other -> "active"
    end
  end

  defp maybe_filter_reference_file_search_status(query, "all"), do: query

  defp maybe_filter_reference_file_search_status(query, status)
       when status in ["active", "archived"] do
    from([knowledge_item] in query, where: knowledge_item.status == ^status)
  end

  defp normalize_reference_file_identifier(identifier) when is_list(identifier) do
    identifier
    |> Enum.into(%{})
    |> normalize_reference_file_identifier()
  end

  defp normalize_reference_file_identifier(%{} = identifier) do
    knowledge_item_id = fetch(identifier, :knowledge_item_id)
    reference_ref = fetch(identifier, :reference_ref)

    cond do
      is_binary(knowledge_item_id) and
          Ecto.UUID.cast(knowledge_item_id) == {:ok, knowledge_item_id} ->
        {:ok, {:knowledge_item_id, knowledge_item_id}}

      is_binary(reference_ref) and safe_reference_ref?(reference_ref) ->
        {:ok, {:reference_ref, reference_ref}}

      true ->
        {:error, :not_found}
    end
  end

  defp normalize_reference_file_identifier(identifier) when is_binary(identifier) do
    cond do
      Ecto.UUID.cast(identifier) == {:ok, identifier} -> {:ok, {:knowledge_item_id, identifier}}
      safe_reference_ref?(identifier) -> {:ok, {:reference_ref, identifier}}
      true -> {:error, :not_found}
    end
  end

  defp normalize_reference_file_identifier(_identifier), do: {:error, :not_found}

  defp safe_reference_ref?(reference_ref) when is_binary(reference_ref) do
    String.match?(reference_ref, ~r/\A[A-Za-z0-9][A-Za-z0-9:_-]*\z/)
  end

  defp get_visible_active_reference_file(scope_data, {:knowledge_item_id, knowledge_item_id}) do
    visible_active_reference_file_query(scope_data)
    |> where([knowledge_item, _reference_file], knowledge_item.id == ^knowledge_item_id)
    |> select([_knowledge_item, reference_file], reference_file)
    |> Repo.one()
    |> Repo.preload(:knowledge_item)
  end

  defp get_visible_active_reference_file(scope_data, {:reference_ref, reference_ref}) do
    visible_active_reference_file_query(scope_data)
    |> where([_knowledge_item, reference_file], reference_file.reference_ref == ^reference_ref)
    |> select([_knowledge_item, reference_file], reference_file)
    |> Repo.one()
    |> Repo.preload(:knowledge_item)
  end

  defp visible_active_reference_file_query(scope_data) do
    KnowledgeItem
    |> where([knowledge_item], knowledge_item.kind == "reference_file")
    |> filter_scope_relevance(scope_data)
    |> where([knowledge_item], knowledge_item.status == "active")
    |> join(:inner, [knowledge_item], reference_file in ReferenceFile,
      on: reference_file.knowledge_item_id == knowledge_item.id
    )
  end

  defp reference_file_read_result(%ReferenceFile{} = reference_file, max_chars) do
    descriptor = build_reference_file_descriptor(reference_file)

    cond do
      direct_text_reference_file?(reference_file) ->
        read_direct_reference_file_text(reference_file, descriptor, max_chars)

      convertible_reference_file?(reference_file) ->
        read_converted_reference_file_text(reference_file, descriptor, max_chars)

      true ->
        reference_file_descriptor_result(descriptor, "unreadable")
    end
  end

  defp reference_file_descriptor_result(descriptor, content_status) do
    %{
      descriptor: descriptor,
      content_status: content_status,
      content: nil,
      content_length: 0,
      truncated: false
    }
  end

  defp read_direct_reference_file_text(%ReferenceFile{} = reference_file, descriptor, max_chars) do
    case ReferenceFileStorageService.read_private(reference_file.storage_ref) do
      {:ok, binary} when is_binary(binary) ->
        if String.valid?(binary) do
          reference_file_content_result(descriptor, "readable", binary, max_chars, "direct")
        else
          reference_file_descriptor_result(descriptor, "unreadable")
        end

      {:error, _reason} ->
        reference_file_descriptor_result(descriptor, "unavailable")
    end
  end

  defp read_converted_reference_file_text(
         %ReferenceFile{} = reference_file,
         descriptor,
         max_chars
       ) do
    reference_file.storage_ref
    |> ReferenceFileStorageService.with_temp_file(fn path ->
      ExtractionService.extract_path(reference_file.content_type, path)
    end)
    |> case do
      {:ok, {:ok, %{text: text, method: method}}} when is_binary(text) ->
        reference_file_content_result(descriptor, "converted", text, max_chars, method)

      {:ok, {:error, :unsupported}} ->
        reference_file_descriptor_result(descriptor, "unreadable")

      {:ok, {:error, _reason}} ->
        reference_file_descriptor_result(descriptor, "conversion_failed")

      {:error, _reason} ->
        reference_file_descriptor_result(descriptor, "unavailable")
    end
  end

  defp reference_file_content_result(descriptor, content_status, text, max_chars, method) do
    content_length = String.length(text)

    %{
      descriptor: descriptor,
      content_status: content_status,
      content: String.slice(text, 0, max_chars),
      content_length: min(content_length, max_chars),
      truncated: content_length > max_chars,
      extraction_method: method
    }
  end

  defp direct_text_reference_file?(%ReferenceFile{} = reference_file) do
    content_type = reference_file.content_type || ""

    String.starts_with?(content_type, "text/") or
      content_type in [
        "application/json",
        "application/ld+json",
        "application/xml",
        "application/xhtml+xml",
        "application/yaml",
        "application/x-yaml",
        "application/toml",
        "application/csv"
      ]
  end

  defp convertible_reference_file?(%ReferenceFile{} = reference_file) do
    content_type = reference_file.content_type || ""

    extension =
      reference_file.original_filename |> to_string() |> Path.extname() |> String.downcase()

    content_type in convertible_reference_file_content_types() or
      extension in convertible_reference_file_extensions()
  end

  defp convertible_reference_file_content_types do
    [
      "application/pdf",
      "application/msword",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "application/vnd.ms-excel",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "application/vnd.ms-powerpoint",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation",
      "application/rtf",
      "application/vnd.oasis.opendocument.text",
      "application/vnd.oasis.opendocument.spreadsheet",
      "application/vnd.oasis.opendocument.presentation"
    ]
  end

  defp convertible_reference_file_extensions do
    ~w(.pdf .doc .docx .xls .xlsx .ppt .pptx .rtf .odt .ods .odp)
  end

  defp read_max_chars_value(opts) do
    case Keyword.get(opts, :max_chars, @default_read_max_chars) do
      value when is_integer(value) and value > 0 -> min(value, @max_read_max_chars)
      _value -> @default_read_max_chars
    end
  end

  defp maybe_filter_reference_file_status(query, status) when is_binary(status) do
    if status in ["active", "archived"] do
      from([_reference_file, knowledge_item] in query, where: knowledge_item.status == ^status)
    else
      query
    end
  end

  defp maybe_filter_reference_file_status(query, _status), do: query

  defp maybe_filter_effective_status(query, status) when status in ["active"] do
    from([knowledge_item] in query, where: knowledge_item.status == ^status)
  end

  defp maybe_filter_effective_status(query, _status), do: query

  defp maybe_scope_eq(query, field, nil) when field in [:city_id, :department_id, :lemming_id] do
    from([_source_file, knowledge_item] in query, where: is_nil(field(knowledge_item, ^field)))
  end

  defp maybe_scope_eq(query, field, value)
       when field in [:city_id, :department_id, :lemming_id] and is_binary(value) do
    from([_source_file, knowledge_item] in query, where: field(knowledge_item, ^field) == ^value)
  end

  defp maybe_update_knowledge_item(multi, knowledge_item, attrs) when map_size(attrs) == 0 do
    Ecto.Multi.put(multi, :knowledge_item, knowledge_item)
  end

  defp maybe_update_knowledge_item(multi, knowledge_item, attrs) do
    Ecto.Multi.update(
      multi,
      :knowledge_item,
      KnowledgeItem.user_update_changeset(knowledge_item, attrs)
    )
  end

  defp maybe_update_reference_file(multi, reference_file, attrs) when map_size(attrs) == 0 do
    Ecto.Multi.put(multi, :reference_file, reference_file)
  end

  defp maybe_update_reference_file(multi, reference_file, attrs) do
    Ecto.Multi.update(multi, :reference_file, ReferenceFile.changeset(reference_file, attrs))
  end

  defp reference_file_create_attrs(attrs, scope_data) do
    filename = fetch(attrs, :original_filename)
    content_type = fetch(attrs, :content_type)
    storage_ref = fetch(attrs, :storage_ref)
    reference_file_type = fetch(attrs, :reference_file_type)
    size_bytes = fetch(attrs, :size_bytes)
    checksum = fetch(attrs, :checksum)
    reference_ref = fetch(attrs, :reference_ref)
    title = fetch(attrs, :title) || filename || "Reference file"
    content = fetch(attrs, :content) || "Reference file metadata summary."
    tags = fetch(attrs, :tags) || []

    with :ok <-
           validate_reference_file_create_inputs(
             filename,
             content_type,
             storage_ref,
             reference_file_type,
             size_bytes
           ),
         :ok <- validate_reference_file_storage_ref(storage_ref, scope_data.world_id),
         :ok <- validate_optional_reference_ref(reference_ref),
         {:ok, artifact_id} <- normalize_optional_artifact_id(fetch(attrs, :artifact_id)) do
      knowledge_item_attrs =
        %{
          world_id: scope_data.world_id,
          city_id: scope_data.city_id,
          department_id: scope_data.department_id,
          lemming_id: scope_data.lemming_id,
          kind: "reference_file",
          source: "user",
          status: "active",
          title: title,
          content: content,
          tags: tags
        }
        |> maybe_put(:artifact_id, artifact_id)

      reference_file_attrs =
        %{
          reference_file_type: reference_file_type,
          original_filename: filename,
          content_type: content_type,
          size_bytes: size_bytes,
          checksum: checksum,
          storage_ref: storage_ref
        }
        |> maybe_put(:reference_ref, reference_ref)

      {:ok, knowledge_item_attrs, reference_file_attrs}
    end
  end

  defp validate_reference_file_create_inputs(
         filename,
         content_type,
         storage_ref,
         reference_file_type,
         size_bytes
       )
       when is_binary(filename) and is_binary(content_type) and is_binary(storage_ref) and
              is_binary(reference_file_type) and is_integer(size_bytes) and size_bytes > 0,
       do: :ok

  defp validate_reference_file_create_inputs(
         _filename,
         _content_type,
         _storage_ref,
         _reference_file_type,
         _size_bytes
       ),
       do: {:error, :invalid_attrs}

  defp validate_reference_file_storage_ref(storage_ref, world_id) do
    case ReferenceFileStorageService.storage_ref_world_id(storage_ref) do
      {:ok, ^world_id} -> :ok
      {:ok, _other_world_id} -> {:error, :scope_mismatch}
      {:error, _reason} -> {:error, :invalid_attrs}
    end
  end

  defp validate_optional_reference_ref(nil), do: :ok

  defp validate_optional_reference_ref(reference_ref) when is_binary(reference_ref) do
    if String.match?(reference_ref, ~r/\A[A-Za-z0-9][A-Za-z0-9:_-]*\z/) do
      :ok
    else
      {:error, :invalid_attrs}
    end
  end

  defp validate_optional_reference_ref(_reference_ref), do: {:error, :invalid_attrs}

  defp build_reference_ref!(knowledge_item_id) do
    case ReferenceFileStorageService.build_reference_ref(knowledge_item_id) do
      {:ok, reference_ref} -> reference_ref
      {:error, _reason} -> raise ArgumentError, "invalid knowledge_item_id for reference_ref"
    end
  end

  defp normalize_optional_artifact_id(nil), do: {:ok, nil}

  defp normalize_optional_artifact_id(artifact_id) when is_binary(artifact_id) do
    case Ecto.UUID.cast(artifact_id) do
      {:ok, _uuid} -> {:ok, artifact_id}
      :error -> {:error, :invalid_attrs}
    end
  end

  defp normalize_optional_artifact_id(_artifact_id), do: {:error, :invalid_attrs}

  defp require_operator_approval(attrs) do
    case fetch(attrs, :operator_approved) do
      true -> :ok
      _other -> {:error, :operator_approval_required}
    end
  end

  defp validate_promoted_artifact_scope(artifact, scope_data) do
    if map_scope_value(artifact, :world_id) == scope_data.world_id and
         map_scope_value(artifact, :city_id) == scope_data.city_id and
         map_scope_value(artifact, :department_id) == scope_data.department_id and
         map_scope_value(artifact, :lemming_id) == scope_data.lemming_id do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  defp map_scope_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp maybe_record_reference_file_event(
         {:ok,
          %{
            knowledge_item: %KnowledgeItem{} = knowledge_item,
            reference_file: %ReferenceFile{} = reference_file
          }} = result,
         event_type,
         scope_data
       )
       when is_binary(event_type) and is_map(scope_data) do
    payload = reference_file_event_payload(knowledge_item, reference_file, scope_data)

    case Events.record_event(
           event_type,
           scope_data,
           reference_file_event_message(event_type, reference_file.reference_ref),
           payload: payload,
           event_family: "audit",
           action: reference_file_event_action(event_type),
           status: "succeeded",
           resource_type: "knowledge_reference_file",
           resource_id: reference_file.id
         ) do
      {:ok, _event} ->
        result

      {:error, reason} ->
        Logger.warning("failed to record reference file lifecycle event",
          event: "knowledge.reference_file.event_failed",
          world_id: knowledge_item.world_id,
          city_id: knowledge_item.city_id,
          department_id: knowledge_item.department_id,
          lemming_id: knowledge_item.lemming_id,
          reason: safe_reason(reason)
        )

        result
    end
  end

  defp maybe_record_reference_file_event(result, _event_type, _scope_data), do: result

  defp reference_file_event_action("knowledge.reference_file.created"), do: "create"
  defp reference_file_event_action("knowledge.reference_file.updated"), do: "update"
  defp reference_file_event_action("knowledge.reference_file.archived"), do: "archive"
  defp reference_file_event_action("knowledge.reference_file.artifact_promoted"), do: "promote"
  defp reference_file_event_action(_event_type), do: "update"

  defp reference_file_event_message(event_type, reference_ref) do
    case event_type do
      "knowledge.reference_file.created" -> "Reference file #{reference_ref} created"
      "knowledge.reference_file.updated" -> "Reference file #{reference_ref} updated"
      "knowledge.reference_file.archived" -> "Reference file #{reference_ref} archived"
      "knowledge.reference_file.artifact_promoted" -> "Reference file #{reference_ref} promoted"
      _other -> "Reference file #{reference_ref} updated"
    end
  end

  defp reference_file_event_payload(
         %KnowledgeItem{} = knowledge_item,
         %ReferenceFile{} = reference_file,
         scope_data
       ) do
    %{
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id,
      lemming_id: scope_data.lemming_id,
      knowledge_item_id: knowledge_item.id,
      reference_file_id: reference_file.id,
      reference_ref: reference_file.reference_ref,
      kind: knowledge_item.kind,
      source: knowledge_item.source,
      status: knowledge_item.status,
      reference_file_type: reference_file.reference_file_type,
      artifact_id: knowledge_item.artifact_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp inherited_owner?(knowledge_item, scope_data, local?),
    do: Shared.inherited_owner?(knowledge_item, scope_data, local?)

  defp owner_scope(%KnowledgeItem{} = knowledge_item), do: Shared.owner_scope(knowledge_item)

  defp limit_value(opts), do: Shared.limit_value(opts, @default_limit, @max_limit)

  defp offset_value(opts), do: Shared.offset_value(opts)

  defp validate_exact_scope(%KnowledgeItem{} = knowledge_item, scope_data),
    do: Shared.validate_exact_scope(knowledge_item, scope_data)

  defp knowledge_item_in_scope?(%KnowledgeItem{} = knowledge_item, scope_data),
    do: Shared.knowledge_item_in_scope?(knowledge_item, scope_data)

  defp validate_requested_scope(attrs, scope_data),
    do: Shared.validate_requested_scope(attrs, scope_data)

  defp maybe_put(map, key, value), do: Shared.maybe_put(map, key, value)

  defp scope_data(scope), do: Shared.scope_data(scope)

  defp filter_scope_relevance(query, scope_data),
    do: Shared.filter_scope_relevance(query, scope_data)

  defp safe_reason(reason), do: Shared.safe_reason(reason)

  defp fetch(map, key), do: Shared.fetch(map, key)
end
