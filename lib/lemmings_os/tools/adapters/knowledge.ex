defmodule LemmingsOs.Tools.Adapters.Knowledge do
  @moduledoc """
  Tool Runtime adapter for memory storage (`knowledge.store`).

  This module is the boundary between model-generated tool arguments and the
  `LemmingsOs.Knowledge` context.

  It is intentionally narrow and safety-focused:
  - accepts only memory inputs (`title`, `content`, optional `tags`, optional `scope`)
  - rejects unsupported/file-oriented fields
  - resolves scope from runtime instance ancestry (defaulting to current lemming)
  - persists with runtime-owned metadata (`source = "llm"` + creator metadata)
  - returns a minimal, non-leaky tool payload (`knowledge_item_id`, `status`, `scope`)
  """

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Ecto.Changeset
  alias LemmingsOs.Events
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge, as: KnowledgeContext
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @allowed_fields MapSet.new(["title", "content", "tags", "scope"])

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
    args
    |> Map.keys()
    |> Enum.map(&normalize_key/1)
    |> Enum.reject(&MapSet.member?(@allowed_fields, &1))
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

  defp safe_reason(%Changeset{}), do: "changeset_error"
  defp safe_reason({:error, reason}), do: safe_reason(reason)
  defp safe_reason({tag, _reason}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_reason), do: "unknown_error"

  defp fetch(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
