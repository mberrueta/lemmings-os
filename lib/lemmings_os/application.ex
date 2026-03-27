defmodule LemmingsOs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        LemmingsOsWeb.Telemetry,
        LemmingsOs.Repo,
        {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.ExecutorRegistry},
        {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.SchedulerRegistry},
        {Registry, keys: :unique, name: LemmingsOs.LemmingInstances.PoolRegistry},
        LemmingsOs.LemmingInstances.DetsStore,
        {LemmingsOs.Worlds.Cache, []},
        {DNSCluster, query: Application.get_env(:lemmings_os, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: LemmingsOs.PubSub}
      ] ++ runtime_city_heartbeat_child() ++ [LemmingsOsWeb.Endpoint]

    opts = [strategy: :one_for_one, name: LemmingsOs.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _supervisor} = result ->
        maybe_run_world_bootstrap_import()
        maybe_sync_runtime_city()
        result

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LemmingsOsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_run_world_bootstrap_import do
    if Application.get_env(:lemmings_os, :world_bootstrap_import_on_startup, true) do
      run_world_bootstrap_import()
    end
  end

  defp run_world_bootstrap_import do
    case LemmingsOs.WorldBootstrap.Importer.sync_default_world() do
      {:ok, result} -> log_bootstrap_result(result, :info, "world bootstrap sync completed")
      {:error, result} -> log_bootstrap_result(result, :error, "world bootstrap sync failed")
    end
  end

  defp maybe_sync_runtime_city do
    if Application.get_env(:lemmings_os, :runtime_city_registration_on_startup, true) do
      LemmingsOs.Cities.Runtime.sync_runtime_city!()
    end
  end

  defp runtime_city_heartbeat_child do
    if Application.get_env(:lemmings_os, :runtime_city_heartbeat_on_startup, true) do
      [{LemmingsOs.Cities.Heartbeat, []}]
    else
      []
    end
  end

  defp log_bootstrap_result(result, level, message) do
    Logger.log(level, message,
      event: "world_bootstrap.sync",
      status: result.operation_status,
      bootstrap_path: result.path,
      issue_count: length(result.issues),
      world_id: world_id(result.world)
    )
  end

  defp world_id(%LemmingsOs.Worlds.World{id: id}), do: id
  defp world_id(nil), do: nil
end
