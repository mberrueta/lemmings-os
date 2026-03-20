defmodule LemmingsOs.Release do
  @moduledoc """
  Release tasks for LemmingsOS.

  Used by the release entrypoint to run migrations before starting
  the application server.

  ## Usage

      /app/bin/lemmings_os eval "LemmingsOs.Release.migrate()"
  """

  @app :lemmings_os

  @doc """
  Create the database if it doesn't exist, then run all pending migrations.
  Used by the Docker entrypoint.
  """
  def create_and_migrate do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, reason} -> raise "could not create database: #{inspect(reason)}"
      end

      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Run all pending Ecto migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Roll back the last migration for the given repo.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
