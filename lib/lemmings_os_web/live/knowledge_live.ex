defmodule LemmingsOsWeb.KnowledgeLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.Worlds

  @page_limit 25

  def mount(params, session, socket) do
    socket =
      socket
      |> assign_shell(:knowledge, "Knowledge")
      |> assign(:embedded?, false)
      |> assign(:scope_form, to_form(%{"scope_type" => "world", "scope_id" => ""}, as: :scope))
      |> assign(
        :filter_form,
        to_form(%{"query" => "", "source" => "", "status" => "active"}, as: :filter)
      )
      |> assign(:memory_form, to_form(Knowledge.change_memory(%KnowledgeItem{}), as: :memory))
      |> assign(:memory_tags_value, "")
      |> assign(:scope_options, %{worlds: [], cities: [], departments: [], lemmings: []})
      |> assign(:city_lookup, %{})
      |> assign(:department_lookup, %{})
      |> assign(:lemming_lookup, %{})
      |> assign(:scope, nil)
      |> assign(:scope_type, "world")
      |> assign(:scope_id, nil)
      |> assign(:scoped_mode?, false)
      |> assign(:memory_id, nil)
      |> assign(:entries, [])
      |> assign(:total_count, 0)
      |> assign(:offset, 0)
      |> assign(:limit, @page_limit)
      |> assign(:query, "")
      |> assign(:source, "")
      |> assign(:status, "active")
      |> assign(:form_mode, :new)
      |> assign(:editing_memory, nil)
      |> assign(:form_open?, false)

    {:ok, hydrate_from_params(socket, mount_params(params, session))}
  end

  def handle_event("change_scope", %{"scope" => params}, socket) do
    scope_type = normalize_scope_type(params["scope_type"] || socket.assigns.scope_type)

    scope_id =
      case params["scope_id"] do
        nil -> socket.assigns.scope_id
        "" -> nil
        value -> value
      end

    {:noreply,
     socket
     |> assign(:scope_type, scope_type)
     |> assign(:scope_id, scope_id)
     |> assign(
       :scope_form,
       to_form(%{"scope_type" => scope_type, "scope_id" => scope_id || ""}, as: :scope)
     )}
  end

  def handle_event("change_filters", %{"filter" => params}, socket) do
    query = String.trim(params["query"] || "")
    source = normalize_source(params["source"])
    status = normalize_status(params["status"])

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:source, source)
     |> assign(:status, status)
     |> assign(:offset, 0)
     |> assign(
       :filter_form,
       to_form(%{"query" => query, "source" => source, "status" => status}, as: :filter)
     )
     |> load_memories()}
  end

  def handle_event("new_memory", _params, socket) do
    {:noreply,
     socket
     |> assign(:form_open?, true)
     |> assign(:form_mode, :new)
     |> assign(:editing_memory, nil)
     |> assign(:memory_tags_value, "")
     |> assign(:memory_form, to_form(Knowledge.change_memory(%KnowledgeItem{}), as: :memory))}
  end

  def handle_event("close_memory_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:form_open?, false)
     |> assign(:form_mode, :new)
     |> assign(:editing_memory, nil)
     |> assign(:memory_tags_value, "")
     |> assign(:memory_form, to_form(Knowledge.change_memory(%KnowledgeItem{}), as: :memory))}
  end

  def handle_event("edit_memory", %{"id" => memory_id}, socket) do
    case find_memory_row(socket.assigns.entries, memory_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Memory not found in current page.")}

      row ->
        {:noreply, socket |> assign(:form_open?, true) |> open_memory_for_edit(row.memory)}
    end
  end

  def handle_event("validate_memory", %{"memory" => params}, socket) do
    attrs = normalize_memory_params(params)

    changeset =
      case socket.assigns.editing_memory do
        %KnowledgeItem{} = memory -> Knowledge.change_memory(memory, attrs)
        _other -> Knowledge.change_memory(%KnowledgeItem{}, attrs)
      end
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:memory_tags_value, Map.get(params, "tags", ""))
     |> assign(:memory_form, to_form(changeset, as: :memory))}
  end

  def handle_event("save_memory", %{"memory" => params}, socket) do
    attrs = normalize_memory_params(params)

    case socket.assigns.editing_memory do
      %KnowledgeItem{} = memory ->
        case memory_scope(memory) do
          nil -> {:noreply, put_flash(socket, :error, "Unable to resolve memory scope.")}
          scope -> {:noreply, save_edited_memory(socket, scope, memory, attrs, params)}
        end

      _other ->
        case selected_create_scope(socket) do
          nil ->
            {:noreply, put_flash(socket, :error, "Select a valid scope before saving memory.")}

          scope ->
            {:noreply, save_new_memory(socket, scope, attrs, params)}
        end
    end
  end

  def handle_event("delete_memory", %{"id" => memory_id}, socket) do
    memory = Enum.find(socket.assigns.entries, fn row -> row.memory.id == memory_id end)

    case memory do
      %{memory: %KnowledgeItem{} = memory_item} ->
        {:noreply, delete_memory_row(socket, memory_item)}

      _other ->
        {:noreply, put_flash(socket, :error, "Memory not found in current page.")}
    end
  end

  def handle_event("page_prev", _params, socket) do
    next_offset = max(socket.assigns.offset - socket.assigns.limit, 0)

    {:noreply, socket |> assign(:offset, next_offset) |> load_memories()}
  end

  def handle_event("page_next", _params, socket) do
    next_offset = socket.assigns.offset + socket.assigns.limit

    {:noreply, socket |> assign(:offset, next_offset) |> load_memories()}
  end

  defp load_scope_options(socket) do
    worlds = Worlds.list_worlds() |> Enum.sort_by(&{&1.inserted_at, &1.id})
    cities = worlds |> Enum.flat_map(&Cities.list_cities/1) |> Enum.uniq_by(& &1.id)

    departments =
      cities
      |> Enum.flat_map(&Departments.list_departments(&1))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{&1.inserted_at, &1.id})

    lemmings =
      departments
      |> Enum.flat_map(&Lemmings.list_lemmings(&1))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{&1.name, &1.id})

    socket
    |> assign(:scope_options, %{
      worlds: worlds,
      cities: cities,
      departments: departments,
      lemmings: lemmings
    })
    |> assign(:city_lookup, Map.new(cities, &{&1.id, &1}))
    |> assign(:department_lookup, Map.new(departments, &{&1.id, &1}))
    |> assign(:lemming_lookup, Map.new(lemmings, &{&1.id, &1}))
  end

  defp load_memories(%{assigns: %{scope: nil}} = socket) do
    if socket.assigns.scoped_mode? do
      socket
      |> assign(:entries, [])
      |> assign(:total_count, 0)
    else
      load_all_memories(socket)
    end
  end

  defp load_memories(socket) do
    if socket.assigns.scoped_mode? do
      load_scoped_memories(socket)
    else
      load_all_memories(socket)
    end
  end

  defp load_scoped_memories(socket) do
    opts =
      [limit: socket.assigns.limit, offset: socket.assigns.offset, status: socket.assigns.status]
      |> maybe_put_query(socket.assigns.query)
      |> maybe_put_source(socket.assigns.source)

    case Knowledge.list_scope_memories(socket.assigns.scope, opts) do
      {:ok, result} ->
        socket
        |> assign(:entries, result.entries)
        |> assign(:total_count, result.total_count)
        |> assign(:offset, result.offset)
        |> assign(:limit, result.limit)

      {:error, _reason} ->
        socket
        |> assign(:entries, [])
        |> assign(:total_count, 0)
    end
  end

  defp load_all_memories(socket) do
    opts =
      [limit: socket.assigns.limit, offset: socket.assigns.offset, status: socket.assigns.status]
      |> maybe_put_query(socket.assigns.query)
      |> maybe_put_source(socket.assigns.source)

    {:ok, result} = Knowledge.list_all_memories(opts)

    socket
    |> assign(:entries, result.entries)
    |> assign(:total_count, result.total_count)
    |> assign(:offset, result.offset)
    |> assign(:limit, result.limit)
  end

  defp resolve_scope(scope_options, "world", scope_id) do
    scope = Enum.find(scope_options.worlds, &(&1.id == scope_id))
    {scope, maybe_id(scope)}
  end

  defp resolve_scope(scope_options, "city", scope_id) do
    scope = Enum.find(scope_options.cities, &(&1.id == scope_id))
    {scope, maybe_id(scope)}
  end

  defp resolve_scope(scope_options, "department", scope_id) do
    scope = Enum.find(scope_options.departments, &(&1.id == scope_id))
    {scope, maybe_id(scope)}
  end

  defp resolve_scope(scope_options, "lemming", scope_id) do
    scope = Enum.find(scope_options.lemmings, &(&1.id == scope_id))
    {scope, maybe_id(scope)}
  end

  defp normalize_scope_type(scope_type)
       when scope_type in ["world", "city", "department", "lemming"],
       do: scope_type

  defp normalize_scope_type(_scope_type), do: "world"

  defp normalize_source("user"), do: "user"
  defp normalize_source("llm"), do: "llm"
  defp normalize_source(_source), do: ""

  defp normalize_status("active"), do: "active"
  defp normalize_status(_status), do: "active"

  defp normalize_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {value, ""} when value >= 0 -> value
      _other -> 0
    end
  end

  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(_offset), do: 0

  defp maybe_id(nil), do: nil
  defp maybe_id(%{id: id}), do: id

  defp maybe_put_query(opts, ""), do: opts
  defp maybe_put_query(opts, query), do: Keyword.put(opts, :q, query)

  defp maybe_put_source(opts, ""), do: opts
  defp maybe_put_source(opts, source), do: Keyword.put(opts, :source, source)

  defp resolve_params(_socket, params) do
    memory_id = normalize_memory_id(params["memory_id"])
    linked_memory = linked_memory(memory_id)
    raw_query = String.trim(params["q"] || "")
    raw_source = normalize_source(params["source"])
    raw_offset = normalize_offset(params["offset"])

    %{
      memory_id: memory_id,
      linked_memory: linked_memory,
      query: if(linked_memory, do: "", else: raw_query),
      source: if(linked_memory, do: "", else: raw_source),
      status: normalize_status(params["status"]),
      offset: if(linked_memory, do: 0, else: raw_offset)
    }
  end

  defp save_edited_memory(socket, scope, memory, attrs, raw_params) do
    case Knowledge.update_memory(scope, memory, attrs) do
      {:ok, _memory} ->
        socket
        |> put_flash(:info, "Memory updated.")
        |> assign(:form_open?, false)
        |> assign(:form_mode, :new)
        |> assign(:editing_memory, nil)
        |> assign(:memory_tags_value, "")
        |> assign(:memory_form, to_form(Knowledge.change_memory(%KnowledgeItem{}), as: :memory))
        |> load_memories()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:memory_tags_value, Map.get(raw_params, "tags", ""))
        |> assign(:memory_form, to_form(changeset, as: :memory))

      {:error, _reason} ->
        put_flash(socket, :error, "Unable to update memory.")
    end
  end

  defp save_new_memory(socket, scope, attrs, raw_params) do
    case Knowledge.create_memory(scope, attrs) do
      {:ok, _memory} ->
        socket
        |> put_flash(:info, "Memory created.")
        |> assign(:form_open?, false)
        |> assign(:memory_tags_value, "")
        |> assign(:memory_form, to_form(Knowledge.change_memory(%KnowledgeItem{}), as: :memory))
        |> load_memories()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:memory_tags_value, Map.get(raw_params, "tags", ""))
        |> assign(:memory_form, to_form(changeset, as: :memory))

      {:error, _reason} ->
        put_flash(socket, :error, "Unable to create memory.")
    end
  end

  defp selected_create_scope(socket) do
    if socket.assigns.scoped_mode? and socket.assigns.scope do
      socket.assigns.scope
    else
      {scope, _scope_id} =
        resolve_scope(
          socket.assigns.scope_options,
          socket.assigns.scope_type,
          socket.assigns.scope_id
        )

      scope
    end
  end

  defp normalize_memory_id(nil), do: nil

  defp normalize_memory_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_memory_id(_value), do: nil

  defp linked_memory(nil), do: nil

  defp linked_memory(memory_id) do
    case Knowledge.get_memory_by_id(memory_id) do
      %KnowledgeItem{kind: "memory"} = memory -> memory
      _other -> nil
    end
  end

  defp maybe_open_linked_memory(socket, nil), do: socket

  defp maybe_open_linked_memory(socket, %KnowledgeItem{} = memory) do
    socket
    |> assign(:memory_id, memory.id)
    |> assign(:form_open?, true)
    |> open_memory_for_edit(memory)
  end

  defp find_memory_row(entries, memory_id) do
    Enum.find(entries, fn row -> row.memory.id == memory_id end)
  end

  defp open_memory_for_edit(socket, %KnowledgeItem{} = memory) do
    tags_value = memory.tags |> List.wrap() |> Enum.join(", ")

    socket
    |> assign(:form_mode, :edit)
    |> assign(:editing_memory, memory)
    |> assign(:memory_tags_value, tags_value)
    |> assign(:memory_form, to_form(Knowledge.change_memory(memory), as: :memory))
  end

  defp delete_memory_row(socket, %KnowledgeItem{} = memory_item) do
    case memory_scope(memory_item) do
      nil ->
        put_flash(socket, :error, "Unable to resolve memory scope.")

      scope ->
        case Knowledge.delete_memory(scope, memory_item) do
          {:ok, _memory} ->
            socket
            |> put_flash(:info, "Memory deleted.")
            |> load_memories()

          {:error, _reason} ->
            put_flash(socket, :error, "Unable to delete memory.")
        end
    end
  end

  defp memory_scope(%KnowledgeItem{} = memory) do
    cond do
      is_binary(memory.lemming_id) ->
        %Lemming{
          id: memory.lemming_id,
          world_id: memory.world_id,
          city_id: memory.city_id,
          department_id: memory.department_id
        }

      is_binary(memory.department_id) ->
        %Department{id: memory.department_id, world_id: memory.world_id, city_id: memory.city_id}

      is_binary(memory.city_id) ->
        %City{id: memory.city_id, world_id: memory.world_id}

      is_binary(memory.world_id) ->
        %World{id: memory.world_id}

      true ->
        nil
    end
  end

  defp normalize_memory_params(params) when is_map(params) do
    %{
      title: Map.get(params, "title", ""),
      content: Map.get(params, "content", ""),
      tags:
        params
        |> Map.get("tags", "")
        |> normalize_tags()
    }
  end

  defp normalize_tags(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tags(value) when is_list(value), do: value
  defp normalize_tags(_value), do: []

  defp resolve_scoped_mode(socket, params) do
    scope_type = normalize_scope_type(params["scope_type"])
    scope_id = params["scope_id"]

    if is_binary(scope_id) and scope_id != "" and Map.has_key?(params, "scope_type") do
      {scope, resolved_scope_id} =
        resolve_scope(socket.assigns.scope_options, scope_type, scope_id)

      {scope, resolved_scope_id, not is_nil(scope)}
    else
      {nil, nil, false}
    end
  end

  defp maybe_assign_scope_form_for_scoped_mode(socket, false, _scope_id), do: socket

  defp maybe_assign_scope_form_for_scoped_mode(socket, true, scope_id) do
    assign(
      socket,
      :scope_form,
      to_form(%{"scope_type" => socket.assigns.scope_type, "scope_id" => scope_id || ""},
        as: :scope
      )
    )
  end

  defp mount_params(:not_mounted_at_router, session), do: session_params(session)
  defp mount_params(params, _session) when is_map(params), do: params
  defp mount_params(_params, _session), do: %{}

  defp session_params(session) when is_map(session) do
    Map.take(session, [
      "scope_type",
      "scope_id",
      "q",
      "source",
      "status",
      "offset",
      "memory_id",
      "embedded"
    ])
  end

  defp session_params(_session), do: %{}

  defp hydrate_from_params(socket, params) do
    embedded? = params["embedded"] in ["1", "true"]
    socket = load_scope_options(socket)
    resolved = resolve_params(socket, params)
    {scope, scope_id, scoped_mode?} = resolve_scoped_mode(socket, params)

    socket
    |> assign(:scope, scope)
    |> assign(:embedded?, embedded?)
    |> assign(:scope_id, scope_id)
    |> assign(
      :scope_type,
      if(scoped_mode?,
        do: normalize_scope_type(params["scope_type"]),
        else: socket.assigns.scope_type
      )
    )
    |> assign(:scoped_mode?, scoped_mode?)
    |> assign(:memory_id, resolved.memory_id)
    |> assign(:query, resolved.query)
    |> assign(:source, resolved.source)
    |> assign(:status, resolved.status)
    |> assign(:offset, resolved.offset)
    |> assign(
      :filter_form,
      to_form(
        %{"query" => resolved.query, "source" => resolved.source, "status" => resolved.status},
        as: :filter
      )
    )
    |> maybe_assign_scope_form_for_scoped_mode(scoped_mode?, scope_id)
    |> maybe_open_linked_memory(resolved.linked_memory)
    |> load_memories()
  end
end
