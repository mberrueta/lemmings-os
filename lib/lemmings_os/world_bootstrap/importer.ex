defmodule LemmingsOs.WorldBootstrap.Importer do
  @moduledoc """
  Imports bootstrap YAML into the persisted World domain.

  This module treats bootstrap YAML as ingestion input. It loads the bootstrap
  file, validates the frozen shape, and synchronizes the persisted World record
  with create-or-update semantics for this implementation slice.
  """

  alias LemmingsOs.World
  alias LemmingsOs.WorldBootstrap.Loader
  alias LemmingsOs.WorldBootstrap.ShapeValidator
  alias LemmingsOs.Worlds
  alias LemmingsOsWeb.Gettext, as: AppGettext

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

      iex> LemmingsOs.Repo.delete_all(LemmingsOs.World)
      iex> path = LemmingsOs.WorldBootstrapTestHelpers.write_temp_file!(
      ...>   LemmingsOs.WorldBootstrapTestHelpers.valid_bootstrap_yaml()
      ...> )
      iex> {:ok, result} = LemmingsOs.WorldBootstrap.Importer.sync_default_world(path: path, source: "direct")
      iex> {result.operation_status, result.world.slug, result.persisted_last_import_status}
      {"ok", "local", "ok"}
  """
  @spec sync_default_world(keyword()) :: {:ok, sync_result()} | {:error, sync_result()}
  def sync_default_world(opts \\ []) do
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
    |> world_attrs(validation_result, operation_status)
    |> Worlds.upsert_bootstrap_world()
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

  defp sync_persist_result({:error, changeset}, load_result, issues, _operation_status) do
    persistence_issue = persistence_issue(changeset)
    all_issues = issues ++ [persistence_issue]

    {:error, sync_result(load_result, "invalid", all_issues, nil)}
  end

  defp persist_failure_metadata(load_result, operation_status) do
    load_result
    |> failure_attrs(operation_status)
    |> Worlds.upsert_world()
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

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
  end
end
