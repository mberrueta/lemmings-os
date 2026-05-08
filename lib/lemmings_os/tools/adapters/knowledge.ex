defmodule LemmingsOs.Tools.Adapters.Knowledge do
  @moduledoc """
  Tool Runtime adapter for knowledge tools (`knowledge.store`, `knowledge.search`,
  and `knowledge.read`).

  This module is the boundary between model-generated tool arguments and the
  `LemmingsOs.Knowledge` context.

  It is intentionally narrow and safety-focused:
  - keeps `knowledge.store` memory-only
  - rejects unsupported or mismatched fields instead of ignoring them
  - resolves scope from runtime instance ancestry (defaulting to current lemming)
  - returns bounded content or descriptor-only payloads without storage internals
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Ecto.Changeset
  alias LemmingsOs.Events
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge, as: KnowledgeContext
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Knowledge.SourceFiles.EmbeddingService
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @allowed_fields MapSet.new(["title", "content", "tags", "scope"])
  @search_allowed_fields MapSet.new([
                           "query",
                           "q",
                           "kind",
                           "source_file_type",
                           "reference_file_type",
                           "type",
                           "category",
                           "tags",
                           "status",
                           "scope",
                           "owner_scope",
                           "limit",
                           "offset",
                           "top_k"
                         ])
  @source_file_search_fields MapSet.new([
                               "query",
                               "kind",
                               "source_file_type",
                               "tags",
                               "scope",
                               "top_k"
                             ])
  @reference_file_search_fields MapSet.new([
                                  "query",
                                  "q",
                                  "kind",
                                  "reference_file_type",
                                  "type",
                                  "category",
                                  "tags",
                                  "status",
                                  "scope",
                                  "owner_scope",
                                  "limit",
                                  "offset",
                                  "top_k"
                                ])
  @read_allowed_fields MapSet.new([
                         "chunk_ref",
                         "knowledge_item_id",
                         "reference_ref",
                         "kind",
                         "scope",
                         "max_chars"
                       ])
  @search_top_k_default 5
  @search_top_k_max 20
  @reference_file_search_limit_default 10
  @reference_file_search_limit_max 20
  @read_max_chars_default 4_000
  @read_max_chars_max 8_000

  @type runtime_meta :: %{
          optional(:actor_instance_id) => String.t(),
          optional(:work_area_ref) => String.t(),
          optional(:world_id) => String.t(),
          optional(:city_id) => String.t(),
          optional(:department_id) => String.t()
        }

  @type success_result :: %{
          summary: String.t(),
          preview: String.t() | nil,
          result: map()
        }

  @type error_result :: %{
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @doc """
  Executes the `knowledge.store` adapter for memory-only persistence.

  Use this from Tool Runtime when an LLM wants to store a reusable memory note.

  The adapter validates and normalizes input before persistence:
  - `title` and `content` are required non-empty strings
  - `tags` may be a list of strings or a comma-separated string
  - `scope` is optional; defaults to `"lemming"` for the active instance
  - explicit scope hints are allowed only when they match the current instance ancestry

  On success, the returned payload is intentionally minimal and safe for model
  consumption. On failure, errors are normalized into the standard tool error
  envelope with non-sensitive details.

  ## Examples

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department)
      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   world_id: world.id,
      ...>   city_id: city.id,
      ...>   department_id: department.id,
      ...>   lemming_id: lemming.id
      ...> }
      iex> {:ok, result} =
      ...>   LemmingsOs.Tools.Adapters.Knowledge.store_memory(
      ...>     instance,
      ...>     %{"title" => "ACME - email summary language", "content" => "Use Portuguese."}
      ...>   )
      iex> result.result.scope
      "lemming"
      iex> is_binary(result.result.knowledge_item_id)
      true

      iex> world = LemmingsOs.Factory.insert(:world)
      iex> city = LemmingsOs.Factory.insert(:city, world: world)
      iex> department = LemmingsOs.Factory.insert(:department, world: world, city: city)
      iex> lemming = LemmingsOs.Factory.insert(:lemming, world: world, city: city, department: department)
      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   world_id: world.id,
      ...>   city_id: city.id,
      ...>   department_id: department.id,
      ...>   lemming_id: lemming.id
      ...> }
      iex> {:error, error} =
      ...>   LemmingsOs.Tools.Adapters.Knowledge.store_memory(
      ...>     instance,
      ...>     %{"title" => "Invalid", "content" => "Nope", "artifact_id" => Ecto.UUID.generate()}
      ...>   )
      iex> error.code
      "tool.knowledge.unsupported_fields"
  """
  @spec store_memory(LemmingInstance.t(), map(), runtime_meta()) ::
          {:ok, success_result()} | {:error, error_result()}
  def store_memory(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with :ok <- validate_allowed_fields(args),
         {:ok, title} <- validate_required_text(args, :title),
         {:ok, content} <- validate_required_text(args, :content),
         {:ok, tags} <- validate_optional_tags(args),
         {:ok, scope_name, scope} <- resolve_scope_hint(instance, args),
         {:ok, %KnowledgeItem{} = memory} <-
           KnowledgeContext.create_memory(
             scope,
             %{title: title, content: content, tags: tags},
             source: "llm",
             creator: creator_metadata(instance, runtime_meta)
           ) do
      _ = record_llm_memory_event(memory, instance)
      _ = notify_runtime_chat(memory, runtime_meta)

      {:ok,
       %{
         summary: "Stored memory #{memory.title}",
         preview: String.slice(memory.content, 0, 280),
         result: %{
           knowledge_item_id: memory.id,
           status: "stored",
           scope: scope_name
         }
       }}
    else
      {:error, %Changeset{} = changeset} -> {:error, validation_error(changeset)}
      {:error, :invalid_scope} -> {:error, invalid_scope_error()}
      {:error, :scope_mismatch} -> {:error, invalid_scope_error()}
      {:error, :invalid_attrs} -> {:error, invalid_args_error()}
      {:error, %{} = error} -> {:error, error}
    end
  end

  defp validate_allowed_fields(args) do
    args
    |> unsupported_fields()
    |> validate_unsupported_fields()
  end

  @doc """
  Executes `knowledge.search` for source-file chunk retrieval or reference-file lookup.
  """
  @spec search(LemmingInstance.t(), map(), runtime_meta()) ::
          {:ok, success_result()} | {:error, error_result()}
  def search(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with :ok <- validate_allowed_fields(args, @search_allowed_fields, "knowledge.search"),
         {:ok, kind} <- normalize_search_kind(fetch(args, :kind)) do
      search_by_kind(kind, instance, args)
    else
      {:error, %{} = error} -> {:error, error}
    end
  end

  @doc """
  Executes `knowledge.read` for bounded source-file chunk or reference-file content retrieval.
  """
  @spec read(LemmingInstance.t(), map(), runtime_meta()) ::
          {:ok, success_result()} | {:error, error_result()}
  def read(%LemmingInstance{} = instance, args, _runtime_meta \\ %{}) when is_map(args) do
    with :ok <- validate_allowed_fields(args, @read_allowed_fields, "knowledge.read"),
         {:ok, kind} <- normalize_read_kind(fetch(args, :kind), args) do
      read_by_kind(kind, instance, args)
    else
      {:error, %{} = error} ->
        {:error, error}
    end
  end

  defp search_by_kind("source_file", %LemmingInstance{} = instance, args) do
    with :ok <- validate_kind_allowed_fields(args, @source_file_search_fields, "source_file"),
         {:ok, query} <- validate_required_text(args, :query),
         {:ok, tags} <- validate_optional_tags(args),
         {:ok, scope_name, scope} <- resolve_scope_hint(instance, args),
         {:ok, top_k} <- normalize_top_k(fetch(args, :top_k)),
         {:ok, query_embedding} <- query_embedding(query),
         results <-
           KnowledgeContext.search_source_file_chunks(
             scope,
             query_embedding,
             query_text: query,
             source_file_type: fetch(args, :source_file_type),
             tags: tags,
             top_k: top_k
           ) do
      {:ok,
       %{
         summary: "Found #{length(results)} source-file chunks",
         preview: search_preview(results),
         result: %{
           kind: "source_file",
           scope: scope_name,
           count: length(results),
           results: results
         }
       }}
    end
  end

  defp search_by_kind("reference_file", %LemmingInstance{} = instance, args) do
    with :ok <-
           validate_kind_allowed_fields(args, @reference_file_search_fields, "reference_file"),
         {:ok, tags} <- validate_optional_tags(args),
         {:ok, scope_name, scope} <- resolve_scope_hint(instance, args),
         {:ok, limit} <-
           normalize_reference_file_limit(fetch(args, :limit) || fetch(args, :top_k)),
         {:ok, offset} <- normalize_offset(fetch(args, :offset)),
         {:ok, page} <-
           KnowledgeContext.search_reference_files(
             scope,
             reference_file_search_opts(args, tags, limit, offset)
           ) do
      results = Enum.map(page.entries, &reference_file_search_result/1)

      {:ok,
       %{
         summary: "Found #{length(results)} reference files",
         preview: reference_file_search_preview(results),
         result: %{
           kind: "reference_file",
           scope: scope_name,
           count: length(results),
           total_count: page.total_count,
           limit: page.limit,
           offset: page.offset,
           results: results
         }
       }}
      |> maybe_record_reference_file_search_event(instance, scope, args)
    else
      {:error, :invalid_scope} -> {:error, invalid_scope_error()}
      {:error, :scope_mismatch} -> {:error, invalid_scope_error()}
      {:error, %{} = error} -> {:error, error}
    end
  end

  defp read_by_kind("source_file", %LemmingInstance{} = instance, args) do
    with {:ok, chunk_ref} <- validate_required_text(args, :chunk_ref),
         {:ok, scope_name, scope} <- resolve_scope_hint(instance, args),
         {:ok, max_chars} <- normalize_max_chars(fetch(args, :max_chars)),
         {:ok, chunk} <-
           KnowledgeContext.read_source_file_chunk(scope, chunk_ref, max_chars: max_chars) do
      {:ok,
       %{
         summary: "Read chunk #{chunk.chunk_ref}",
         preview: String.slice(chunk.content, 0, 280),
         result: %{
           kind: "source_file",
           scope: scope_name,
           chunk_ref: chunk.chunk_ref,
           knowledge_item_id: chunk.knowledge_item_id,
           source_file_type: chunk.source_file_type,
           title: chunk.title,
           chunk_index: chunk.chunk_index,
           content: chunk.content,
           content_length: String.length(chunk.content),
           truncated: chunk.truncated,
           metadata: chunk.metadata
         }
       }}
    else
      {:error, :not_found} -> {:error, not_found_error("Chunk not found")}
      {:error, :invalid_scope} -> {:error, invalid_scope_error()}
      {:error, :scope_mismatch} -> {:error, invalid_scope_error()}
      {:error, %{} = error} -> {:error, error}
    end
  end

  defp read_by_kind("reference_file", %LemmingInstance{} = instance, args) do
    with {:ok, identifier} <- reference_file_read_identifier(args),
         {:ok, scope_name, scope} <- resolve_scope_hint(instance, args),
         {:ok, max_chars} <- normalize_max_chars(fetch(args, :max_chars)),
         {:ok, read_result} <-
           KnowledgeContext.read_reference_file(scope, identifier, max_chars: max_chars) do
      result = reference_file_read_result(read_result, scope_name)

      {:ok,
       %{
         summary: reference_file_read_summary(result),
         preview: reference_file_read_preview(result),
         result: result
       }}
      |> maybe_record_reference_file_read_event(instance, scope)
    else
      {:error, :not_found} -> {:error, not_found_error("Reference file not found")}
      {:error, :invalid_scope} -> {:error, invalid_scope_error()}
      {:error, :scope_mismatch} -> {:error, invalid_scope_error()}
      {:error, %{} = error} -> {:error, error}
    end
  end

  defp validate_required_text(args, field) do
    args
    |> fetch(field)
    |> normalize_required_text(field)
  end

  defp validate_optional_tags(args) do
    args
    |> fetch(:tags)
    |> normalize_tags()
  end

  defp normalize_tags(nil), do: {:ok, []}

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> normalize_tags()
  end

  defp normalize_tags(tags) when is_list(tags), do: normalize_tag_list(tags, [])
  defp normalize_tags(_tags), do: {:error, invalid_tags_error()}

  defp normalize_tag_list([], acc), do: {:ok, Enum.reverse(acc)}

  defp normalize_tag_list([tag | rest], acc) when is_binary(tag) do
    normalize_tag_list(rest, maybe_prepend_tag(String.trim(tag), acc))
  end

  defp normalize_tag_list([_invalid | _rest], _acc), do: {:error, invalid_tags_error()}

  defp maybe_prepend_tag("", acc), do: acc
  defp maybe_prepend_tag(tag, acc), do: [tag | acc]

  defp invalid_tags_error do
    %{
      code: "tool.validation.invalid_args",
      message: "Invalid tool arguments",
      details: %{field: "tags"}
    }
  end

  defp resolve_scope_hint(%LemmingInstance{} = instance, args) do
    args
    |> fetch(:scope)
    |> resolve_scope_hint(instance)
  end

  defp resolve_scope_hint(nil, instance), do: scope_from_name(instance, "lemming")

  defp resolve_scope_hint(scope_name, instance) when is_binary(scope_name) do
    scope_name
    |> String.trim()
    |> String.downcase()
    |> normalize_scope_name()
    |> scope_from_name_or_error(instance)
  end

  defp resolve_scope_hint(%{} = scope_hint, instance),
    do: normalize_and_build_map_scope(instance, scope_hint)

  defp resolve_scope_hint(_scope_hint, _instance), do: {:error, invalid_scope_error()}

  defp normalize_and_build_map_scope(instance, scope_hint) do
    world_id = fetch(scope_hint, :world_id)
    city_id = fetch(scope_hint, :city_id)
    department_id = fetch(scope_hint, :department_id)
    lemming_id = fetch(scope_hint, :lemming_id)

    with {:ok, scope_name} <- scope_name_from_hint(world_id, city_id, department_id, lemming_id),
         :ok <-
           validate_scope_hint_matches_instance(
             instance,
             world_id,
             city_id,
             department_id,
             lemming_id
           ),
         {:ok, _scope_name, scope} <- scope_from_name(instance, scope_name) do
      {:ok, scope_name, scope}
    end
  end

  defp scope_name_from_hint(world_id, nil, nil, nil) when is_binary(world_id), do: {:ok, "world"}

  defp scope_name_from_hint(world_id, city_id, nil, nil)
       when is_binary(world_id) and is_binary(city_id),
       do: {:ok, "city"}

  defp scope_name_from_hint(world_id, city_id, department_id, nil)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id),
       do: {:ok, "department"}

  defp scope_name_from_hint(world_id, city_id, department_id, lemming_id)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id),
       do: {:ok, "lemming"}

  defp scope_name_from_hint(_world_id, _city_id, _department_id, _lemming_id),
    do: {:error, invalid_scope_error()}

  defp validate_scope_hint_matches_instance(
         %LemmingInstance{} = instance,
         world_id,
         city_id,
         department_id,
         lemming_id
       ),
       do:
         scope_hint_match_result(
           matches_scope?(instance, world_id, city_id, department_id, lemming_id)
         )

  defp matches_scope?(instance, world_id, city_id, department_id, lemming_id) do
    world_id == instance.world_id and
      maybe_match_id(city_id, instance.city_id) and
      maybe_match_id(department_id, instance.department_id) and
      maybe_match_id(lemming_id, instance.lemming_id)
  end

  defp maybe_match_id(nil, _instance_id), do: true
  defp maybe_match_id(id, instance_id), do: id == instance_id

  defp scope_from_name(%LemmingInstance{} = instance, "world")
       when is_binary(instance.world_id) do
    {:ok, "world", %World{id: instance.world_id}}
  end

  defp scope_from_name(%LemmingInstance{} = instance, "city")
       when is_binary(instance.world_id) and is_binary(instance.city_id) do
    {:ok, "city", %City{id: instance.city_id, world_id: instance.world_id}}
  end

  defp scope_from_name(%LemmingInstance{} = instance, "department")
       when is_binary(instance.world_id) and is_binary(instance.city_id) and
              is_binary(instance.department_id) do
    {:ok, "department",
     %Department{
       id: instance.department_id,
       world_id: instance.world_id,
       city_id: instance.city_id
     }}
  end

  defp scope_from_name(%LemmingInstance{} = instance, "lemming")
       when is_binary(instance.world_id) and is_binary(instance.city_id) and
              is_binary(instance.department_id) and is_binary(instance.lemming_id) do
    {:ok, "lemming",
     %Lemming{
       id: instance.lemming_id,
       world_id: instance.world_id,
       city_id: instance.city_id,
       department_id: instance.department_id
     }}
  end

  defp scope_from_name(_instance, _scope_name), do: {:error, invalid_scope_error()}

  defp creator_metadata(instance, runtime_meta) do
    %{}
    |> maybe_put(:creator_type, "tool_runtime")
    |> maybe_put(:creator_id, "knowledge.store")
    |> maybe_put(:creator_lemming_id, instance.lemming_id)
    |> maybe_put(:creator_lemming_instance_id, creator_instance_id(instance, runtime_meta))
  end

  defp creator_instance_id(instance, runtime_meta) do
    runtime_meta
    |> fetch(:actor_instance_id)
    |> resolve_creator_instance_id(instance.world_id)
  end

  defp runtime_instance_exists?(instance_id, world_id)
       when is_binary(instance_id) and is_binary(world_id) do
    Repo.exists?(
      from(lemming_instance in LemmingInstance,
        where: lemming_instance.id == ^instance_id and lemming_instance.world_id == ^world_id
      )
    )
  end

  defp runtime_instance_exists?(_instance_id, _world_id), do: false

  defp unsupported_fields(args) do
    unsupported_fields(args, @allowed_fields)
  end

  defp unsupported_fields(args, allowed_fields) do
    args
    |> Map.keys()
    |> Enum.map(&normalize_key/1)
    |> Enum.reject(&MapSet.member?(allowed_fields, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_unsupported_fields([]), do: :ok

  defp validate_unsupported_fields(fields) do
    {:error,
     %{
       code: "tool.knowledge.unsupported_fields",
       message: "Unsupported knowledge.store fields",
       details: %{fields: fields}
     }}
  end

  defp validate_allowed_fields(args, allowed_fields, tool_name)
       when is_map(args) and is_map(allowed_fields) and is_binary(tool_name) do
    case unsupported_fields(args, allowed_fields) do
      [] ->
        :ok

      fields ->
        {:error,
         %{
           code: "tool.knowledge.unsupported_fields",
           message: "Unsupported #{tool_name} fields",
           details: %{fields: fields}
         }}
    end
  end

  defp validate_kind_allowed_fields(args, allowed_fields, kind)
       when is_map(args) and is_map(allowed_fields) and is_binary(kind) do
    case unsupported_fields(args, allowed_fields) do
      [] ->
        :ok

      fields ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{kind: kind, unsupported_fields: fields}
         }}
    end
  end

  defp normalize_search_kind(nil), do: {:ok, "source_file"}
  defp normalize_search_kind("source_file"), do: {:ok, "source_file"}
  defp normalize_search_kind("reference_file"), do: {:ok, "reference_file"}

  defp normalize_search_kind(_other) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{field: "kind", allowed: ["source_file", "reference_file"]}
     }}
  end

  defp normalize_read_kind(nil, args) do
    chunk_ref? = present?(fetch(args, :chunk_ref))

    reference_file? =
      present?(fetch(args, :knowledge_item_id)) or present?(fetch(args, :reference_ref))

    cond do
      chunk_ref? and reference_file? ->
        {:error, invalid_args_error(["chunk_ref", "knowledge_item_id", "reference_ref"])}

      chunk_ref? ->
        {:ok, "source_file"}

      reference_file? ->
        {:ok, "reference_file"}

      true ->
        {:error, invalid_args_error(["chunk_ref", "knowledge_item_id", "reference_ref"])}
    end
  end

  defp normalize_read_kind("source_file", args) do
    if present?(fetch(args, :chunk_ref)) and not present?(fetch(args, :knowledge_item_id)) and
         not present?(fetch(args, :reference_ref)) do
      {:ok, "source_file"}
    else
      {:error, invalid_args_error(["chunk_ref"])}
    end
  end

  defp normalize_read_kind("reference_file", args) do
    reference_file? =
      present?(fetch(args, :knowledge_item_id)) or present?(fetch(args, :reference_ref))

    if reference_file? and not present?(fetch(args, :chunk_ref)) do
      {:ok, "reference_file"}
    else
      {:error, invalid_args_error(["knowledge_item_id", "reference_ref"])}
    end
  end

  defp normalize_read_kind(_other, _args) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{field: "kind", allowed: ["source_file", "reference_file"]}
     }}
  end

  defp normalize_top_k(nil), do: {:ok, @search_top_k_default}

  defp normalize_top_k(value) do
    case parse_positive_integer(value) do
      {:ok, top_k} -> {:ok, min(top_k, @search_top_k_max)}
      :error -> {:error, invalid_args_error(["top_k"])}
    end
  end

  defp normalize_reference_file_limit(nil), do: {:ok, @reference_file_search_limit_default}

  defp normalize_reference_file_limit(value) do
    case parse_positive_integer(value) do
      {:ok, limit} -> {:ok, min(limit, @reference_file_search_limit_max)}
      :error -> {:error, invalid_args_error(["limit"])}
    end
  end

  defp normalize_offset(nil), do: {:ok, 0}

  defp normalize_offset(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp normalize_offset(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _other -> {:error, invalid_args_error(["offset"])}
    end
  end

  defp normalize_offset(_value), do: {:error, invalid_args_error(["offset"])}

  defp normalize_max_chars(nil), do: {:ok, @read_max_chars_default}

  defp normalize_max_chars(value) do
    case parse_positive_integer(value) do
      {:ok, max_chars} -> {:ok, min(max_chars, @read_max_chars_max)}
      :error -> {:error, invalid_args_error(["max_chars"])}
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _other -> :error
    end
  end

  defp parse_positive_integer(_value), do: :error

  defp query_embedding(query) do
    case EmbeddingService.embed_texts([query]) do
      {:ok, [embedding]} when is_list(embedding) -> {:ok, embedding}
      {:ok, _other} -> {:error, search_unavailable_error()}
      {:error, _reason} -> {:error, search_unavailable_error()}
    end
  end

  defp search_unavailable_error do
    %{
      code: "tool.knowledge.search_unavailable",
      message: "Knowledge search is unavailable",
      details: %{}
    }
  end

  defp not_found_error(message) when is_binary(message) do
    %{
      code: "tool.knowledge.not_found",
      message: message,
      details: %{}
    }
  end

  defp search_preview([]), do: nil
  defp search_preview([first | _rest]), do: Map.get(first, :snippet) || Map.get(first, "snippet")

  defp reference_file_search_opts(args, tags, limit, offset) do
    [
      kind: "reference_file",
      query: fetch(args, :query) || fetch(args, :q),
      reference_file_type: fetch(args, :reference_file_type) || fetch(args, :type),
      category: fetch(args, :category),
      tags: tags,
      status: fetch(args, :status) || "active",
      owner_scope: fetch(args, :owner_scope),
      limit: limit,
      offset: offset
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp reference_file_search_result(%{
         descriptor: descriptor,
         owner_scope: owner_scope,
         local?: local?,
         inherited?: inherited?
       }) do
    %{
      reference_ref: descriptor.reference_ref,
      knowledge_item_id: descriptor.knowledge_item_id,
      kind: "reference_file",
      reference_file_type: descriptor.reference_file_type,
      title: descriptor.title,
      tags: descriptor.tags || [],
      status: descriptor.status,
      content_type: descriptor.content_type,
      scope: %{type: owner_scope, local: local?, inherited: inherited?}
    }
  end

  defp reference_file_search_result(_row), do: %{}

  defp reference_file_search_preview([]), do: nil

  defp reference_file_search_preview([%{title: title} | _rest]) when is_binary(title), do: title

  defp reference_file_search_preview([%{reference_ref: reference_ref} | _rest])
       when is_binary(reference_ref),
       do: reference_ref

  defp reference_file_search_preview(_results), do: nil

  defp reference_file_read_identifier(args) do
    knowledge_item_id = fetch(args, :knowledge_item_id)
    reference_ref = fetch(args, :reference_ref)

    cond do
      present?(knowledge_item_id) -> {:ok, %{knowledge_item_id: String.trim(knowledge_item_id)}}
      present?(reference_ref) -> {:ok, %{reference_ref: String.trim(reference_ref)}}
      true -> {:error, invalid_args_error(["knowledge_item_id", "reference_ref"])}
    end
  end

  defp reference_file_read_result(%{descriptor: descriptor} = read_result, scope_name) do
    %{
      kind: "reference_file",
      scope: scope_name,
      reference_ref: descriptor.reference_ref,
      knowledge_item_id: descriptor.knowledge_item_id,
      reference_file_type: descriptor.reference_file_type,
      title: descriptor.title,
      tags: descriptor.tags || [],
      content_type: descriptor.content_type,
      descriptor: descriptor,
      content_status: read_result.content_status,
      content: read_result.content,
      content_length: read_result.content_length,
      truncated: read_result.truncated
    }
    |> maybe_put(:extraction_method, Map.get(read_result, :extraction_method))
  end

  defp reference_file_read_summary(%{title: title, content_status: content_status})
       when is_binary(title) do
    "Read reference file #{title} (#{content_status})"
  end

  defp reference_file_read_summary(%{
         reference_ref: reference_ref,
         content_status: content_status
       }) do
    "Read reference file #{reference_ref} (#{content_status})"
  end

  defp reference_file_read_preview(%{content: content}) when is_binary(content),
    do: String.slice(content, 0, 280)

  defp reference_file_read_preview(%{title: title}) when is_binary(title), do: title
  defp reference_file_read_preview(_result), do: nil

  defp normalize_required_text(value, field) when is_binary(value),
    do: normalize_required_text_trimmed(String.trim(value), field)

  defp normalize_required_text(_value, field),
    do: {:error, invalid_args_error([field_name(field)])}

  defp normalize_required_text_trimmed("", field),
    do: {:error, invalid_args_error([field_name(field)])}

  defp normalize_required_text_trimmed(value, _field), do: {:ok, value}

  defp normalize_scope_name("world"), do: "world"
  defp normalize_scope_name("city"), do: "city"
  defp normalize_scope_name("department"), do: "department"
  defp normalize_scope_name("lemming"), do: "lemming"
  defp normalize_scope_name("lemming_type"), do: "lemming"
  defp normalize_scope_name(_scope_name), do: :invalid

  defp scope_from_name_or_error(:invalid, _instance), do: {:error, invalid_scope_error()}
  defp scope_from_name_or_error(scope_name, instance), do: scope_from_name(instance, scope_name)

  defp scope_hint_match_result(true), do: :ok
  defp scope_hint_match_result(false), do: {:error, invalid_scope_error()}

  defp resolve_creator_instance_id(actor_instance_id, world_id)
       when is_binary(actor_instance_id) and is_binary(world_id) do
    actor_instance_id
    |> runtime_instance_exists?(world_id)
    |> creator_instance_id_result(actor_instance_id)
  end

  defp resolve_creator_instance_id(_actor_instance_id, _world_id), do: nil

  defp creator_instance_id_result(true, actor_instance_id), do: actor_instance_id
  defp creator_instance_id_result(false, _actor_instance_id), do: nil

  defp notify_runtime_chat(%KnowledgeItem{} = memory, runtime_meta) do
    with instance_id when is_binary(instance_id) <- fetch(runtime_meta, :actor_instance_id),
         true <- runtime_instance_exists?(instance_id, memory.world_id),
         {:ok, %Message{} = message} <- persist_memory_notification_message(memory, instance_id),
         :ok <- PubSub.broadcast_message_appended(instance_id, message.id, message.role) do
      :ok
    else
      nil ->
        :ok

      false ->
        Logger.warning("memory chat notification skipped for invalid actor instance",
          event: "knowledge.memory.notification_skipped",
          instance_id: fetch(runtime_meta, :actor_instance_id),
          world_id: memory.world_id,
          department_id: memory.department_id,
          lemming_id: memory.lemming_id,
          reason: "invalid_actor_instance_id"
        )

        :ok

      {:error, reason} ->
        Logger.warning("memory chat notification failed",
          event: "knowledge.memory.notification_failed",
          instance_id: fetch(runtime_meta, :actor_instance_id),
          world_id: memory.world_id,
          department_id: memory.department_id,
          lemming_id: memory.lemming_id,
          reason: safe_reason(reason)
        )

        :ok
    end
  end

  defp persist_memory_notification_message(%KnowledgeItem{} = memory, instance_id) do
    content =
      [
        "Memory added:",
        memory.title,
        memory_notification_preview(memory.content),
        "View or edit: /knowledge?memory_id=#{memory.id}"
      ]
      |> Enum.join("\n")

    %Message{}
    |> Message.changeset(%{
      lemming_instance_id: instance_id,
      world_id: memory.world_id,
      role: "assistant",
      content: content
    })
    |> Repo.insert()
  end

  defp memory_notification_preview(content) when is_binary(content) do
    content
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp memory_notification_preview(_content), do: ""

  defp record_llm_memory_event(%KnowledgeItem{} = memory, %LemmingInstance{} = instance) do
    payload =
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
        creator_tool_execution_id: memory.creator_tool_execution_id,
        actor_instance_id: instance.id
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case Events.record_event(
           "knowledge.memory.created_by_llm",
           memory_scope(memory),
           "Memory created by llm",
           payload: payload,
           event_family: "audit",
           action: "create",
           status: "succeeded",
           resource_type: "knowledge_item",
           resource_id: memory.id
         ) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to record llm memory event",
          event: "knowledge.memory.event_failed",
          instance_id: instance.id,
          world_id: memory.world_id,
          department_id: memory.department_id,
          lemming_id: memory.lemming_id,
          reason: safe_reason(reason)
        )

        :ok
    end
  end

  defp maybe_record_reference_file_search_event(
         {:ok, %{result: %{kind: "reference_file"} = result}} = adapter_result,
         %LemmingInstance{} = instance,
         scope,
         args
       )
       when is_map(args) do
    payload =
      %{
        lemming_instance_id: instance.id,
        actor_lemming_id: instance.lemming_id,
        actor_world_id: instance.world_id,
        actor_city_id: instance.city_id,
        actor_department_id: instance.department_id,
        kind: "reference_file",
        status: fetch(args, :status) || "active",
        owner_scope: fetch(args, :owner_scope) || fetch(args, :scope),
        reference_file_type: fetch(args, :reference_file_type) || fetch(args, :type),
        has_query: present?(fetch(args, :query) || fetch(args, :q)),
        tags_count: tag_count(fetch(args, :tags)),
        limit: fetch(result, :limit),
        offset: fetch(result, :offset),
        result_count: fetch(result, :count),
        total_count: fetch(result, :total_count),
        source: "llm"
      }
      |> Map.merge(scope_payload(scope))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    record_reference_file_access_event(
      "knowledge.reference_file.search_performed",
      scope,
      "Reference file search performed",
      payload
    )

    adapter_result
  end

  defp maybe_record_reference_file_search_event(result, _instance, _scope, _args), do: result

  defp maybe_record_reference_file_read_event(
         {:ok,
          %{result: %{kind: "reference_file", knowledge_item_id: knowledge_item_id} = result}} =
           adapter_result,
         %LemmingInstance{} = instance,
         scope
       ) do
    payload =
      %{
        lemming_instance_id: instance.id,
        actor_lemming_id: instance.lemming_id,
        actor_world_id: instance.world_id,
        actor_city_id: instance.city_id,
        actor_department_id: instance.department_id,
        knowledge_item_id: knowledge_item_id,
        reference_ref: fetch(result, :reference_ref),
        reference_file_type: fetch(result, :reference_file_type),
        content_status: fetch(result, :content_status),
        has_content: is_binary(fetch(result, :content)),
        truncated: fetch(result, :truncated),
        source: "llm"
      }
      |> Map.merge(scope_payload(scope))
      |> maybe_put(:content_length, fetch(result, :content_length))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    record_reference_file_access_event(
      "knowledge.reference_file.read",
      scope,
      "Reference file read",
      payload,
      knowledge_item_id
    )

    adapter_result
  end

  defp maybe_record_reference_file_read_event(result, _instance, _scope), do: result

  defp record_reference_file_access_event(event_type, scope, message, payload, resource_id \\ nil)
       when is_binary(event_type) and is_binary(message) and is_map(payload) do
    case Events.record_event(
           event_type,
           scope,
           message,
           payload: payload,
           event_family: "audit",
           action: reference_file_access_action(event_type),
           status: "succeeded",
           resource_type: "knowledge_reference_file_access",
           resource_id: resource_id
         ) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to record reference file access event",
          event: "knowledge.reference_file.access_event_failed",
          instance_id: fetch(payload, :lemming_instance_id),
          world_id: fetch(payload, :world_id),
          department_id: fetch(payload, :department_id),
          lemming_id: fetch(payload, :lemming_id),
          reason: safe_reason(reason)
        )

        :ok
    end
  end

  defp reference_file_access_action("knowledge.reference_file.search_performed"), do: "search"
  defp reference_file_access_action("knowledge.reference_file.read"), do: "read"
  defp reference_file_access_action(_event_type), do: "read"

  defp tag_count(nil), do: 0
  defp tag_count(tags) when is_list(tags), do: length(tags)

  defp tag_count(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> Enum.count()
  end

  defp tag_count(_tags), do: 0

  defp scope_payload(%World{id: world_id}) do
    %{
      world_id: world_id,
      city_id: nil,
      department_id: nil,
      lemming_id: nil
    }
  end

  defp scope_payload(%City{id: city_id, world_id: world_id}) do
    %{
      world_id: world_id,
      city_id: city_id,
      department_id: nil,
      lemming_id: nil
    }
  end

  defp scope_payload(%Department{id: department_id, city_id: city_id, world_id: world_id}) do
    %{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: nil
    }
  end

  defp scope_payload(%Lemming{
         id: lemming_id,
         department_id: department_id,
         city_id: city_id,
         world_id: world_id
       }) do
    %{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: lemming_id
    }
  end

  defp scope_payload(_scope), do: %{}

  defp memory_scope(%KnowledgeItem{} = memory) do
    %{
      world_id: memory.world_id,
      city_id: memory.city_id,
      department_id: memory.department_id,
      lemming_id: memory.lemming_id
    }
  end

  defp field_name(field) when is_atom(field), do: Atom.to_string(field)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validation_error(%Changeset{} = changeset) do
    fields =
      changeset
      |> Changeset.traverse_errors(fn {message, _opts} -> message end)
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    %{
      code: "tool.validation.invalid_args",
      message: "Invalid tool arguments",
      details: %{fields: fields}
    }
  end

  defp invalid_args_error(required \\ ["title", "content"]) do
    %{
      code: "tool.validation.invalid_args",
      message: "Invalid tool arguments",
      details: %{required: required}
    }
  end

  defp invalid_scope_error do
    %{
      code: "tool.knowledge.invalid_scope",
      message: "Invalid knowledge scope",
      details: %{}
    }
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(_key), do: ""

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp safe_reason(%Changeset{}), do: "changeset_error"
  defp safe_reason({:error, reason}), do: safe_reason(reason)
  defp safe_reason({tag, _reason}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_reason), do: "unknown_error"

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
