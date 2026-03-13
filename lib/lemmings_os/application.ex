defmodule LemmingsOs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LemmingsOsWeb.Telemetry,
      LemmingsOs.Repo,
      {DNSCluster, query: Application.get_env(:lemmings_os, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LemmingsOs.PubSub},
      # Start a worker by calling: LemmingsOs.Worker.start_link(arg)
      # {LemmingsOs.Worker, arg},
      # Start to serve requests, typically the last entry
      LemmingsOsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LemmingsOs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LemmingsOsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
