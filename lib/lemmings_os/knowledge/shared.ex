defmodule LemmingsOs.Knowledge.Shared do
  @moduledoc false

  import Ecto.Query, warn: false

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Knowledge.KnowledgeItem
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  def scope_data(%World{id: world_id}) when is_binary(world_id),
    do:
      validate_scope_consistency(%{
        world_id: world_id,
        city_id: nil,
        department_id: nil,
        lemming_id: nil
      })

  def scope_data(%City{id: city_id, world_id: world_id})
      when is_binary(world_id) and is_binary(city_id),
      do:
        validate_scope_consistency(%{
          world_id: world_id,
          city_id: city_id,
          department_id: nil,
          lemming_id: nil
        })

  def scope_data(%Department{id: department_id, world_id: world_id, city_id: city_id})
      when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    validate_scope_consistency(%{
      world_id: world_id,
      city_id: city_id,
      department_id: department_id,
      lemming_id: nil
    })
  end

  def scope_data(%Lemming{
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

  def scope_data(_scope), do: {:error, :invalid_scope}

  def validate_requested_scope(attrs, scope_data) do
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

  def validate_exact_scope(%KnowledgeItem{} = knowledge_item, scope_data) do
    if knowledge_item_in_scope?(knowledge_item, scope_data) do
      :ok
    else
      {:error, :scope_mismatch}
    end
  end

  def knowledge_item_in_scope?(%KnowledgeItem{} = knowledge_item, scope_data) do
    knowledge_item.world_id == scope_data.world_id and
      knowledge_item.city_id == scope_data.city_id and
      knowledge_item.department_id == scope_data.department_id and
      knowledge_item.lemming_id == scope_data.lemming_id
  end

  def scope_filters(scope_data) do
    [
      world_id: scope_data.world_id,
      city_id: scope_data.city_id,
      department_id: scope_data.department_id,
      lemming_id: scope_data.lemming_id
    ]
  end

  def filter_scope_relevance(query, %{world_id: world_id, city_id: nil}) do
    from(knowledge_item in query,
      where: knowledge_item.world_id == ^world_id
    )
    |> world_only_filter()
  end

  def filter_scope_relevance(query, %{world_id: world_id, city_id: city_id, department_id: nil})
      when is_binary(city_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and
          (is_nil(knowledge_item.city_id) or knowledge_item.city_id == ^city_id)
    )
    |> city_only_filter()
  end

  def filter_scope_relevance(
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

  def filter_scope_relevance(
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

  def filter_scope_descendants(query, %{world_id: world_id, city_id: nil}) do
    from(knowledge_item in query, where: knowledge_item.world_id == ^world_id)
  end

  def filter_scope_descendants(
        query,
        %{world_id: world_id, city_id: city_id, department_id: nil}
      )
      when is_binary(city_id) do
    from(knowledge_item in query,
      where: knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id
    )
  end

  def filter_scope_descendants(
        query,
        %{world_id: world_id, city_id: city_id, department_id: department_id, lemming_id: nil}
      )
      when is_binary(city_id) and is_binary(department_id) do
    from(knowledge_item in query,
      where:
        knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id and
          knowledge_item.department_id == ^department_id
    )
  end

  def filter_scope_descendants(
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
        knowledge_item.world_id == ^world_id and knowledge_item.city_id == ^city_id and
          knowledge_item.department_id == ^department_id and
          knowledge_item.lemming_id == ^lemming_id
    )
  end

  def owner_scope(%KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil}), do: "world"
  def owner_scope(%KnowledgeItem{department_id: nil, lemming_id: nil}), do: "city"
  def owner_scope(%KnowledgeItem{lemming_id: nil}), do: "department"
  def owner_scope(%KnowledgeItem{}), do: "lemming"

  def inherited_owner?(_knowledge_item, _scope_data, true), do: false

  def inherited_owner?(
        %KnowledgeItem{city_id: nil, department_id: nil, lemming_id: nil},
        _scope_data,
        false
      ),
      do: true

  def inherited_owner?(
        %KnowledgeItem{department_id: nil, lemming_id: nil} = knowledge_item,
        scope_data,
        false
      ) do
    is_binary(scope_data.city_id) and knowledge_item.city_id == scope_data.city_id
  end

  def inherited_owner?(%KnowledgeItem{lemming_id: nil} = knowledge_item, scope_data, false) do
    is_binary(scope_data.department_id) and
      knowledge_item.department_id == scope_data.department_id
  end

  def inherited_owner?(_knowledge_item, _scope_data, false), do: false

  def limit_value(opts, default_limit, max_limit) do
    case Keyword.get(opts, :limit, default_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, max_limit)
      _limit -> default_limit
    end
  end

  def offset_value(opts) do
    case Keyword.get(opts, :offset, 0) do
      offset when is_integer(offset) and offset >= 0 -> offset
      _offset -> 0
    end
  end

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  def safe_reason(%Ecto.Changeset{}), do: "changeset_error"
  def safe_reason(:invalid_scope), do: "invalid_scope"
  def safe_reason(:invalid_event), do: "invalid_event"

  def fetch(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, nil} -> Map.get(map, Atom.to_string(key))
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
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
end
