import Ecto.Query

alias LemmingsOs.{Helpers, MockData, Repo, World, WorldCache, Worlds}
alias LemmingsOs.WorldBootstrap.{Importer, Loader, PathResolver, ShapeValidator}

defmodule Dev do
  @moduledoc false

  import Ecto.Query

  alias LemmingsOs.{Repo, World, WorldCache, Worlds}
  alias LemmingsOs.WorldBootstrap.{Importer, Loader, PathResolver, ShapeValidator}

  # Repo shortcuts for quick querying from the console.
  def all(queryable), do: Repo.all(queryable)

  def one(queryable), do: Repo.one(queryable)

  def count(queryable), do: Repo.aggregate(queryable, :count)

  def get(schema, id), do: Repo.get(schema, id)

  def get!(schema, id), do: Repo.get!(schema, id)

  def reload(struct), do: Repo.reload(struct)

  def reload!(struct), do: Repo.reload!(struct)

  # Fetch the newest records by a timestamp field, usually :inserted_at.
  def recent(queryable, limit \\ 10, field \\ :inserted_at) do
    queryable
    |> order_by([record], desc: field(record, ^field))
    |> limit(^limit)
    |> Repo.all()
  end

  def last(queryable, field \\ :inserted_at) do
    queryable
    |> recent(1, field)
    |> List.first()
  end

  # Inspect the SQL Ecto would send without executing the query.
  def sql(queryable), do: Ecto.Adapters.SQL.to_sql(:all, Repo, queryable)

  # Pull ids from a list of schemas to chain into other calls.
  def ids(records), do: Enum.map(records, & &1.id)

  # Quick schema introspection for table/fields/associations.
  def describe(schema) when is_atom(schema) do
    if function_exported?(schema, :__schema__, 1) do
      %{
        source: schema.__schema__(:source),
        fields: schema.__schema__(:fields),
        associations: schema.__schema__(:associations)
      }
    else
      {:error, :not_an_ecto_schema}
    end
  end

  def describe(_schema), do: {:error, :not_an_atom}

  # Domain helpers for the main persisted world flows.
  def worlds(opts \\ []), do: Worlds.list_worlds(opts)

  def world!(id), do: Worlds.get_world!(id)

  def default_world, do: Worlds.get_default_world()

  def latest_world do
    World
    |> order_by([world], desc: world.inserted_at, desc: world.id)
    |> limit(1)
    |> Repo.one()
  end

  def clear_world_cache, do: WorldCache.invalidate_all()

  def bootstrap_path, do: PathResolver.resolve()

  def load_bootstrap(opts \\ []), do: Loader.load(opts)

  def validate_bootstrap(opts \\ []) do
    with {:ok, %{config: config} = load_result} <- Loader.load(opts),
         validation_result <- ShapeValidator.validate(config) do
      {:ok, load_result, validation_result}
    end
  end

  def sync_world(opts \\ []), do: Importer.sync_default_world(opts)

  # Recompile the project from the current IEx session.
  def recompile!, do: recompile()

  # Logger helpers for noisy dev sessions. Query logs are emitted at :debug,
  # so switching between :info and :debug is usually enough.
  def log_level, do: Logger.level()

  def log_get, do: log_level()

  def logs(level) when level in [:debug, :info, :warning, :error] do
    :ok = Logger.configure(level: level)
    IO.puts("Logger level set to #{level}.")
    level
  end

  def log_set(level), do: logs(level)

  def verbose_logs, do: logs(:debug)

  def quiet_logs, do: logs(:info)

  def log_verbose, do: verbose_logs()

  def log_quiet, do: quiet_logs()

  def examples do
    IO.puts("""
    Copy/paste examples:

      Dev.quiet_logs()
      Dev.log_level()

      Dev.all(World)
      Dev.recent(World)
      Dev.describe(World)
      Dev.bootstrap_path()
      Dev.validate_bootstrap()
      Dev.sync_world()

      from(w in World, where: w.status == "ok") |> Dev.sql()
    """)
  end

  def help do
    IO.puts("""
    LemmingsOs IEx helpers

    Logs:
      Dev.log_level()      current level
      Dev.log_get()        alias of Dev.log_level()
      Dev.logs(:info)      set level (:debug | :info | :warning | :error)
      Dev.log_set(:info)   alias of Dev.logs/1
      Dev.quiet_logs()     hide verbose query/debug logs
      Dev.verbose_logs()   show query/debug logs again
      Dev.log_quiet()      alias of Dev.quiet_logs()
      Dev.log_verbose()    alias of Dev.verbose_logs()

    Data:
      Dev.all(query)       run World or from(...)
      Dev.one(query)       fetch one result
      Dev.count(query)     count rows
      Dev.recent(query)    newest rows
      Dev.last(query)      latest row
      Dev.get(Schema, id)  fetch by id
      Dev.describe(Schema) fields + associations
      Dev.sql(query)       inspect SQL

    Bootstrap:
      Dev.bootstrap_path()
      Dev.load_bootstrap()
      Dev.validate_bootstrap()
      Dev.sync_world()

    Examples:
      Dev.log_get()
      Dev.log_set(:info)
      Dev.all(World)
      Dev.recent(World)
      from(w in World, where: w.status == "ok") |> Dev.sql()

    Tip:
      Startup logs appear before `.iex.exs` runs, so these helpers only affect
      logs after you reach the IEx prompt.
      Run `Dev.examples()` for copy/paste-ready commands.
    """)
  end
end

IEx.configure(
  inspect: [
    pretty: true,
    limit: 200,
    printable_limit: 4_000,
    charlists: :as_lists
  ]
)

IO.puts("LemmingsOs IEx loaded. Run Dev.help() for shortcuts and examples.")
IO.puts("Try Dev.all(World), Dev.quiet_logs(), or Dev.examples().")
