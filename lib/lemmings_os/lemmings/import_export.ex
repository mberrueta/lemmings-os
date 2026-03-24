defmodule LemmingsOs.Lemmings.ImportExport do
  @moduledoc """
  Portable import and export helpers for persisted Lemming definitions.
  """

  alias Ecto.Multi
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Lemmings
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World

  @doc """
  Exports a Lemming into a portable JSON-serializable map.
  """
  @spec export_lemming(Lemming.t()) :: map()
  def export_lemming(%Lemming{} = lemming) do
    %{
      "schema_version" => 1,
      "name" => lemming.name,
      "slug" => lemming.slug,
      "description" => lemming.description,
      "instructions" => lemming.instructions,
      "status" => lemming.status,
      "limits_config" => export_bucket(lemming.limits_config),
      "runtime_config" => export_bucket(lemming.runtime_config),
      "costs_config" => export_bucket(lemming.costs_config),
      "models_config" => export_bucket(lemming.models_config),
      "tools_config" => export_bucket(lemming.tools_config)
    }
  end

  @doc """
  Imports one or more Lemming definitions into the target World, City, and Department.
  """
  @spec import_lemmings(World.t(), City.t(), Department.t(), map() | [map()]) ::
          {:ok, [Lemming.t()]}
          | {:error, :unsupported_schema_version | [map()]}
  def import_lemmings(%World{} = world, %City{} = city, %Department{} = department, json_data) do
    with :ok <- validate_city_in_world(world.id, city),
         :ok <- validate_department_in_city_world(world.id, city.id, department),
         {:ok, records} <- normalize_import_records(json_data),
         :ok <- validate_schema_versions(records),
         :ok <- validate_import_changesets(world, city, department, records) do
      import_records(world, city, department, records)
    end
  end

  defp normalize_import_records(records) when is_list(records) do
    if Enum.all?(records, &is_map/1) do
      {:ok, records}
    else
      {:error, [%{index: nil, error: :invalid_import_payload}]}
    end
  end

  defp normalize_import_records(record) when is_map(record), do: {:ok, [record]}

  defp normalize_import_records(_payload),
    do: {:error, [%{index: nil, error: :invalid_import_payload}]}

  defp validate_schema_versions(records) do
    if Enum.any?(records, &(schema_version(&1) not in [nil, 1])) do
      {:error, :unsupported_schema_version}
    else
      :ok
    end
  end

  defp validate_import_changesets(
         %World{} = world,
         %City{} = city,
         %Department{} = department,
         records
       ) do
    records
    |> Enum.with_index()
    |> Enum.reduce([], fn {record, index}, errors ->
      attrs = import_attrs(record)

      changeset =
        %Lemming{world_id: world.id, city_id: city.id, department_id: department.id}
        |> Lemming.changeset(attrs)

      if changeset.valid? do
        errors
      else
        [%{index: index, error: changeset} | errors]
      end
    end)
    |> Enum.reverse()
    |> validation_result()
  end

  defp validation_result([]), do: :ok
  defp validation_result(errors), do: {:error, errors}

  defp import_records(_world, _city, _department, []), do: {:ok, []}

  defp import_records(%World{} = world, %City{} = city, %Department{} = department, records) do
    multi =
      records
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {record, index}, multi ->
        Multi.run(multi, {:lemming, index}, fn _repo, _changes ->
          Lemmings.create_lemming(world, city, department, import_attrs(record))
        end)
      end)

    case Repo.transaction(multi) do
      {:ok, results} -> {:ok, collect_imported_lemmings(results)}
      {:error, {:lemming, index}, reason, _changes} -> {:error, [%{index: index, error: reason}]}
    end
  end

  defp collect_imported_lemmings(results) do
    results
    |> Enum.sort_by(fn {{:lemming, index}, _lemming} -> index end)
    |> Enum.map(fn {_key, lemming} -> lemming end)
  end

  defp import_attrs(record) do
    %{}
    |> maybe_put_import_attr(:name, record, "name")
    |> maybe_put_import_attr(:slug, record, "slug")
    |> maybe_put_import_attr(:description, record, "description")
    |> maybe_put_import_attr(:instructions, record, "instructions")
    |> maybe_put_import_attr(:status, record, "status")
    |> maybe_put_import_attr(:limits_config, record, "limits_config")
    |> maybe_put_import_attr(:runtime_config, record, "runtime_config")
    |> maybe_put_import_attr(:costs_config, record, "costs_config")
    |> maybe_put_import_attr(:models_config, record, "models_config")
    |> maybe_put_import_attr(:tools_config, record, "tools_config")
  end

  defp maybe_put_import_attr(attrs, field, record, key) do
    case fetch_import_value(record, field, key) do
      :missing -> attrs
      value -> Map.put(attrs, field, value)
    end
  end

  defp fetch_import_value(record, field, key) do
    cond do
      Map.has_key?(record, key) -> Map.get(record, key)
      Map.has_key?(record, field) -> Map.get(record, field)
      true -> :missing
    end
  end

  defp schema_version(record) do
    case fetch_import_value(record, :schema_version, "schema_version") do
      :missing -> nil
      value -> value
    end
  end

  defp validate_city_in_world(world_id, %City{world_id: world_id}), do: :ok
  defp validate_city_in_world(_world_id, %City{}), do: {:error, :department_not_in_city_world}

  defp validate_department_in_city_world(
         world_id,
         city_id,
         %Department{world_id: world_id, city_id: city_id}
       ),
       do: :ok

  defp validate_department_in_city_world(_world_id, _city_id, %Department{}),
    do: {:error, :department_not_in_city_world}

  defp export_bucket(nil), do: %{}

  defp export_bucket(%CostsConfig{} = config) do
    config
    |> Map.from_struct()
    |> Map.update(:budgets, %{}, &export_bucket/1)
    |> stringify_keys()
    |> prune_nil_export_values()
  end

  defp export_bucket(%_{} = config) do
    config
    |> Map.from_struct()
    |> stringify_keys()
    |> prune_nil_export_values()
  end

  defp export_bucket(map) when is_map(map) do
    map
    |> stringify_keys()
    |> prune_nil_export_values()
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), stringify_value(value))
    end)
  end

  defp stringify_value(value) when is_map(value),
    do: value |> stringify_keys() |> prune_nil_export_values()

  defp stringify_value(value), do: value

  defp prune_nil_export_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {_key, value}, acc when value == [] ->
        acc

      {key, value}, acc when is_map(value) ->
        case prune_nil_export_values(value) do
          empty when empty == %{} -> acc
          pruned_value -> Map.put(acc, key, pruned_value)
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end
end
