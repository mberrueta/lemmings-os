defmodule LemmingsOs.Events do
  @moduledoc """
  Generic append-only durable events API.

  The API is intentionally small so other features can record stable events
  without introducing event-specific tables or schemas.
  """

  import Ecto.Query, warn: false

  require Logger

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events.Event
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @event_families ~w(audit telemetry)
  @default_limit 25
  @max_limit 100

  @type scope_data :: %{
          required(:world_id) => Ecto.UUID.t() | nil,
          required(:city_id) => Ecto.UUID.t() | nil,
          required(:department_id) => Ecto.UUID.t() | nil,
          required(:lemming_id) => Ecto.UUID.t() | nil
        }

  @doc """
  Records one durable event using a minimal generic envelope.

  `opts` supports:
  - `:occurred_at` (`DateTime`)
  - `:payload` (map, default `%{}`)
  - `:event_family` (`"audit"` or `"telemetry"`, default `"audit"`)
  - optional ADR-0018 fields (`:actor_type`, `:actor_id`, `:actor_role`,
    `:resource_type`, `:resource_id`, `:correlation_id`, `:causation_id`,
    `:request_id`, `:tool_invocation_id`, `:approval_request_id`, `:action`,
    `:status`)

  ## Examples

      iex> {:error, :invalid_scope} = LemmingsOs.Events.record_event("api.requested", %{}, "API request started")
  """
  @spec record_event(
          String.t(),
          World.t() | City.t() | Department.t() | Lemming.t() | map(),
          String.t(),
          keyword()
        ) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t() | :invalid_scope | :invalid_event}
  def record_event(event_type, scope, message, opts \\ [])

  def record_event(event_type, scope, message, opts)
      when is_binary(event_type) and is_binary(message) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         {:ok, attrs} <- event_attrs(event_type, scope_data, message, opts) do
      %Event{}
      |> Event.create_changeset(attrs)
      |> Repo.insert()
      |> tap(&emit_observability(&1, attrs))
    end
  end

  def record_event(_event_type, _scope, _message, _opts), do: {:error, :invalid_event}

  @doc """
  Lists recent durable events relevant to a hierarchy scope.

  Filtering:
  - world scope: all events in world
  - city scope: world + the city subtree + world-level events
  - department scope: world + city + department subtree
  - lemming scope: world + city + department + the target lemming
  """
  @spec list_recent_events(World.t() | City.t() | Department.t() | Lemming.t() | map(), keyword()) ::
          [Event.t()]
  def list_recent_events(scope, opts \\ []) when is_list(opts) do
    case scope_data(scope) do
      {:ok, scope_data} ->
        Event
        |> where([event], event.world_id == ^scope_data.world_id)
        |> filter_scope_relevance(scope_data)
        |> filter_query(opts)
        |> order_by([event], desc: event.occurred_at, desc: event.id)
        |> limit(^limit_value(opts))
        |> Repo.all()

      {:error, _reason} ->
        []
    end
  end

  defp event_attrs(event_type, scope_data, message, opts) do
    with {:ok, event_type} <- normalize_non_empty(event_type),
         {:ok, message} <- normalize_non_empty(message),
         {:ok, payload} <- payload_value(Keyword.get(opts, :payload, %{})),
         {:ok, occurred_at} <-
           occurred_at_value(Keyword.get(opts, :occurred_at, DateTime.utc_now())),
         {:ok, event_family} <- event_family_value(Keyword.get(opts, :event_family, "audit")) do
      {:ok,
       %{
         event_family: event_family,
         event_type: event_type,
         occurred_at: occurred_at,
         world_id: scope_data.world_id,
         city_id: scope_data.city_id,
         department_id: scope_data.department_id,
         lemming_id: scope_data.lemming_id,
         correlation_id: correlation_id(opts),
         message: message,
         payload: payload
       }
       |> put_optional_attrs(opts)}
    end
  end

  defp put_optional_attrs(attrs, opts) do
    opts
    |> Keyword.take([
      :actor_type,
      :actor_id,
      :actor_role,
      :resource_type,
      :resource_id,
      :causation_id,
      :request_id,
      :tool_invocation_id,
      :approval_request_id,
      :action,
      :status
    ])
    |> Enum.reduce(attrs, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end

  defp scope_data(%World{id: world_id}) when is_binary(world_id),
    do: {:ok, %{world_id: world_id, city_id: nil, department_id: nil, lemming_id: nil}}

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(world_id) and is_binary(city_id),
       do: {:ok, %{world_id: world_id, city_id: city_id, department_id: nil, lemming_id: nil}}

  defp scope_data(%Department{id: department_id, world_id: world_id, city_id: city_id})
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: nil
     }}
  end

  defp scope_data(%Lemming{
         id: lemming_id,
         world_id: world_id,
         city_id: city_id,
         department_id: department_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id) do
    {:ok,
     %{
       world_id: world_id,
       city_id: city_id,
       department_id: department_id,
       lemming_id: lemming_id
     }}
  end

  defp scope_data(%{} = scope) do
    world_id = fetch(scope, :world_id)
    city_id = fetch(scope, :city_id)
    department_id = fetch(scope, :department_id)
    lemming_id = fetch(scope, :lemming_id)

    if valid_scope_shape?(world_id, city_id, department_id, lemming_id) do
      {:ok,
       %{
         world_id: world_id,
         city_id: city_id,
         department_id: department_id,
         lemming_id: lemming_id
       }}
    else
      {:error, :invalid_scope}
    end
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp valid_scope_shape?(world_id, city_id, department_id, lemming_id)
       when is_binary(world_id) and is_nil(city_id) and is_nil(department_id) and
              is_nil(lemming_id),
       do: true

  defp valid_scope_shape?(world_id, city_id, department_id, lemming_id)
       when is_binary(world_id) and is_binary(city_id) and is_nil(department_id) and
              is_nil(lemming_id),
       do: true

  defp valid_scope_shape?(world_id, city_id, department_id, lemming_id)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_nil(lemming_id),
       do: true

  defp valid_scope_shape?(world_id, city_id, department_id, lemming_id)
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) and
              is_binary(lemming_id),
       do: true

  defp valid_scope_shape?(_world_id, _city_id, _department_id, _lemming_id), do: false

  defp filter_scope_relevance(query, %{city_id: nil}), do: query

  defp filter_scope_relevance(query, %{city_id: city_id, department_id: nil})
       when is_binary(city_id) do
    from(event in query,
      where: is_nil(event.city_id) or event.city_id == ^city_id
    )
  end

  defp filter_scope_relevance(query, %{
         city_id: city_id,
         department_id: department_id,
         lemming_id: nil
       })
       when is_binary(city_id) and is_binary(department_id) do
    from(event in query,
      where:
        (is_nil(event.city_id) or event.city_id == ^city_id) and
          (is_nil(event.department_id) or event.department_id == ^department_id)
    )
  end

  defp filter_scope_relevance(query, %{
         city_id: city_id,
         department_id: department_id,
         lemming_id: lemming_id
       })
       when is_binary(city_id) and is_binary(department_id) and is_binary(lemming_id) do
    from(event in query,
      where:
        (is_nil(event.city_id) or event.city_id == ^city_id) and
          (is_nil(event.department_id) or event.department_id == ^department_id) and
          (is_nil(event.lemming_id) or event.lemming_id == ^lemming_id)
    )
  end

  defp filter_query(query, [{:event_type, event_type} | rest]) when is_binary(event_type) do
    filter_query(from(event in query, where: event.event_type == ^event_type), rest)
  end

  defp filter_query(query, [{:event_types, event_types} | rest]) when is_list(event_types) do
    filter_query(from(event in query, where: event.event_type in ^event_types), rest)
  end

  defp filter_query(query, [{:event_family, event_family} | rest]) when is_binary(event_family) do
    filter_query(from(event in query, where: event.event_family == ^event_family), rest)
  end

  defp filter_query(query, [_unknown | rest]), do: filter_query(query, rest)
  defp filter_query(query, []), do: query

  defp normalize_non_empty(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> {:error, :invalid_event}
      normalized -> {:ok, normalized}
    end
  end

  defp payload_value(payload) when is_map(payload), do: {:ok, payload}
  defp payload_value(_payload), do: {:error, :invalid_event}

  defp occurred_at_value(%DateTime{} = occurred_at),
    do: {:ok, DateTime.truncate(occurred_at, :second)}

  defp occurred_at_value(_occurred_at), do: {:error, :invalid_event}

  defp event_family_value(event_family) when event_family in @event_families,
    do: {:ok, event_family}

  defp event_family_value(_event_family), do: {:error, :invalid_event}

  defp correlation_id(opts) do
    case Keyword.get(opts, :correlation_id) do
      value when is_binary(value) and value != "" -> value
      _value -> Ecto.UUID.generate()
    end
  end

  defp limit_value(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @max_limit)
      _limit -> @default_limit
    end
  end

  defp emit_observability({:ok, _event}, attrs) do
    metadata = observability_metadata(attrs, "ok")

    Logger.info("durable event recorded", metadata)

    :telemetry.execute(
      [:lemmings_os, :events, :recorded],
      %{count: 1},
      metadata
    )
  end

  defp emit_observability({:error, _changeset}, attrs) do
    metadata = observability_metadata(attrs, "error")

    Logger.warning("durable event failed to record", metadata)

    :telemetry.execute(
      [:lemmings_os, :events, :record_failed],
      %{count: 1},
      metadata
    )
  end

  defp observability_metadata(attrs, status) do
    %{
      event: "durable_event.record",
      operation: Map.get(attrs, :event_type),
      status: status,
      world_id: Map.get(attrs, :world_id),
      city_id: Map.get(attrs, :city_id),
      department_id: Map.get(attrs, :department_id),
      lemming_id: Map.get(attrs, :lemming_id)
    }
  end

  defp fetch(scope, key) when is_map(scope) do
    Map.get(scope, key) || Map.get(scope, Atom.to_string(key))
  end
end
