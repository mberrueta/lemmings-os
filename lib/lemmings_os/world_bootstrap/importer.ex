defmodule LemmingsOs.WorldBootstrap.Importer do
  @moduledoc """
  Imports bootstrap YAML into the persisted World domain.

  This module treats bootstrap YAML as ingestion input. It loads the bootstrap
  file, validates the frozen shape, and synchronizes the persisted World record
  with create-or-update semantics for this implementation slice.
  """

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Gettext, as: AppGettext
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.Repo
  alias LemmingsOs.WorldBootstrap.Loader
  alias LemmingsOs.WorldBootstrap.ShapeValidator
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.Cache
  alias LemmingsOs.Worlds.World

  @type issue :: Loader.issue() | ShapeValidator.issue()

  @type sync_result :: %{
          operation_status: String.t(),
          source: String.t(),
          path: String.t(),
          issues: [issue()],
          world: World.t() | nil,
          persisted_last_import_status: String.t() | nil
        }

  @doc """
  Loads, validates, and syncs the default world bootstrap into persistence.

  ## Examples

      iex> LemmingsOs.Repo.delete_all(LemmingsOs.Worlds.World)
      iex> path = LemmingsOs.WorldBootstrapTestHelpers.write_temp_file!(
      ...>   LemmingsOs.WorldBootstrapTestHelpers.valid_bootstrap_yaml()
      ...> )
      iex> {:ok, result} = LemmingsOs.WorldBootstrap.Importer.sync_default_world(path: path, source: "direct")
      iex> {result.operation_status, result.world.slug, result.persisted_last_import_status}
      {"ok", "local", "ok"}
  """
  @spec sync_default_world(keyword()) :: {:ok, sync_result()} | {:error, sync_result()}
  def sync_default_world(opts \\ []) do
    Cache.invalidate_all()

    case Loader.load(opts) do
      {:ok, load_result} -> sync_loaded_result(load_result)
      {:error, load_error} -> sync_failed_load(load_error)
    end
  end

  defp sync_loaded_result(%{config: config} = load_result) do
    case ShapeValidator.validate(config) do
      {:ok, validation_result} -> persist_valid_world(load_result, validation_result)
      {:error, validation_result} -> persist_invalid_world(load_result, validation_result)
    end
  end

  defp persist_valid_world(load_result, %{issues: issues} = validation_result) do
    operation_status = successful_operation_status(issues)

    load_result
    |> upsert_bootstrap_config(validation_result, operation_status)
    |> sync_persist_result(load_result, issues, operation_status)
  end

  defp persist_invalid_world(load_result, %{issues: issues}) do
    operation_status = "invalid"
    persisted_world = persist_failure_metadata(load_result, operation_status)

    {:error, sync_result(load_result, operation_status, issues, persisted_world)}
  end

  defp sync_failed_load(%{issues: issues} = load_error) do
    operation_status = failed_load_status(issues)
    persisted_world = persist_failure_metadata(load_error, operation_status)

    {:error, sync_result(load_error, operation_status, issues, persisted_world)}
  end

  defp sync_persist_result({:ok, world}, load_result, issues, operation_status),
    do: {:ok, sync_result(load_result, operation_status, issues, world)}

  defp sync_persist_result(
         {:error, {:bootstrap_sync_failed, changeset}},
         load_result,
         issues,
         _status
       ),
       do: sync_persist_result({:error, changeset}, load_result, issues, "invalid")

  defp sync_persist_result({:error, changeset}, load_result, issues, _operation_status) do
    persistence_issue = persistence_issue(changeset)
    all_issues = issues ++ [persistence_issue]

    {:error, sync_result(load_result, "invalid", all_issues, nil)}
  end

  # On failure paths (missing file, parse error, invalid shape), slug and name
  # are unavailable so a new world row cannot be created. We only update an
  # existing record if one can be located via the bootstrap lookup chain.
  # If no existing world is found, we return nil and the sync result carries
  # world: nil — the operator sees an honest unavailable/invalid state.
  defp persist_failure_metadata(load_result, operation_status) do
    load_result
    |> failure_attrs(operation_status)
    |> Worlds.update_existing_world()
    |> persisted_world_or_nil()
  end

  defp persisted_world_or_nil({:ok, world}), do: world
  defp persisted_world_or_nil({:error, _changeset}), do: nil

  defp world_attrs(load_result, %{config: config}, operation_status) do
    world_config = Map.fetch!(config, "world")

    %{
      slug: Map.fetch!(world_config, "slug"),
      name: Map.fetch!(world_config, "name"),
      status: operation_status,
      bootstrap_source: load_result.source,
      bootstrap_path: load_result.path,
      last_bootstrap_hash: bootstrap_hash(load_result.path),
      last_import_status: operation_status,
      last_imported_at: timestamp(),
      limits_config: Map.fetch!(config, "limits"),
      runtime_config: Map.fetch!(config, "runtime"),
      costs_config: Map.fetch!(config, "costs"),
      models_config: Map.fetch!(config, "models")
    }
  end

  defp failure_attrs(load_result, operation_status) do
    %{
      bootstrap_source: load_result.source,
      bootstrap_path: load_result.path,
      last_bootstrap_hash: bootstrap_hash(load_result.path),
      last_import_status: operation_status,
      last_imported_at: timestamp(),
      status: operation_status
    }
  end

  defp bootstrap_hash(path) do
    case File.read(path) do
      {:ok, contents} -> :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)
      {:error, _reason} -> nil
    end
  end

  defp successful_operation_status([]), do: "ok"
  defp successful_operation_status(_issues), do: "degraded"

  defp failed_load_status([%{code: "bootstrap_file_not_found"} | _rest]), do: "unavailable"
  defp failed_load_status(_issues), do: "invalid"

  defp sync_result(load_result, operation_status, issues, world) do
    %{
      operation_status: operation_status,
      source: load_result.source,
      path: load_result.path,
      issues: issues,
      world: world,
      persisted_last_import_status: persisted_last_import_status(world)
    }
  end

  defp persisted_last_import_status(%World{} = world), do: world.last_import_status
  defp persisted_last_import_status(nil), do: nil

  defp persistence_issue(changeset) do
    %{
      severity: "error",
      code: "bootstrap_persistence_failed",
      summary: Gettext.dgettext(AppGettext, "errors", ".bootstrap_persistence_failed_summary"),
      detail: inspect(changeset.errors),
      source: "import_sync",
      path: "world",
      action_hint:
        Gettext.dgettext(AppGettext, "errors", ".bootstrap_persistence_failed_action_hint")
    }
  end

  defp upsert_bootstrap_config(load_result, validation_result, operation_status) do
    Repo.transaction(fn ->
      with {:ok, world} <-
             load_result
             |> world_attrs(validation_result, operation_status)
             |> Worlds.upsert_bootstrap_world(),
           {:ok, _cities} <- sync_cities(world, validation_result.config) do
        world
      else
        {:error, reason} -> Repo.rollback({:bootstrap_sync_failed, reason})
      end
    end)
  end

  defp sync_cities(%World{} = world, %{"cities" => cities_config}) do
    cities_config
    |> Enum.reduce_while({:ok, []}, fn {_slug, city_config}, {:ok, cities} ->
      case upsert_city(world, city_config) do
        {:ok, city} ->
          sync_city_departments(world, city, city_config, cities)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_cities(_world, _config), do: {:ok, []}

  defp sync_city_departments(world, city, city_config, cities) do
    case sync_departments(world, city, city_config) do
      {:ok, _departments} -> {:cont, {:ok, [city | cities]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp sync_departments(%World{} = world, %City{} = city, %{"departments" => departments_config}) do
    departments_config
    |> Enum.reduce_while({:ok, []}, fn {_slug, department_config}, {:ok, departments} ->
      case upsert_department(world, city, department_config) do
        {:ok, department} ->
          sync_department_lemmings(world, city, department, department_config, departments)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_departments(_world, _city, _config), do: {:ok, []}

  defp sync_department_lemmings(world, city, department, department_config, departments) do
    case sync_lemmings(world, city, department, department_config) do
      {:ok, _lemmings} -> {:cont, {:ok, [department | departments]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp sync_lemmings(
         %World{} = world,
         %City{} = city,
         %Department{} = department,
         %{"lemmings" => lemmings_config}
       ) do
    lemmings_config
    |> Enum.reduce_while({:ok, []}, fn {_slug, lemming_config}, {:ok, lemmings} ->
      case upsert_lemming(world, city, department, lemming_config) do
        {:ok, lemming} -> {:cont, {:ok, [lemming | lemmings]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_lemmings(_world, _city, _department, _config), do: {:ok, []}

  defp upsert_city(%World{id: world_id}, city_config) do
    city =
      Repo.get_by(City, world_id: world_id, slug: Map.fetch!(city_config, "slug")) ||
        %City{world_id: world_id}

    city
    |> City.changeset(config_attrs(city_config))
    |> Repo.insert_or_update()
  end

  defp upsert_department(%World{id: world_id}, %City{id: city_id}, department_config) do
    department =
      Repo.get_by(Department, city_id: city_id, slug: Map.fetch!(department_config, "slug")) ||
        %Department{world_id: world_id, city_id: city_id}

    department
    |> Department.changeset(config_attrs(department_config))
    |> Repo.insert_or_update()
  end

  defp upsert_lemming(
         %World{id: world_id},
         %City{id: city_id},
         %Department{id: department_id},
         lemming_config
       ) do
    lemming =
      Repo.get_by(Lemming, department_id: department_id, slug: Map.fetch!(lemming_config, "slug")) ||
        %Lemming{world_id: world_id, city_id: city_id, department_id: department_id}

    lemming
    |> Lemming.changeset(config_attrs(lemming_config))
    |> Repo.insert_or_update()
  end

  defp config_attrs(config) do
    config
    |> Map.take(
      ~w(slug name node_name status notes tags collaboration_role description instructions)
    )
    |> Map.merge(
      Map.take(config, ~w(limits_config runtime_config costs_config models_config tools_config))
    )
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
