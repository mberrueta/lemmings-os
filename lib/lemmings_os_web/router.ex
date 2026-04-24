defmodule LemmingsOsWeb.Router do
  use LemmingsOsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LemmingsOsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health probe — no pipeline, no session, no DB. Used by Docker and load balancers.
  scope "/", LemmingsOsWeb do
    get "/healthz", HealthController, :check
  end

  scope "/", LemmingsOsWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/world", WorldLive, :index
    live "/cities", CitiesLive, :index
    live "/departments", DepartmentsLive, :index
    live "/lemmings/new", CreateLemmingLive, :index
    live "/lemmings/import", ImportLemmingLive, :import
    live "/lemmings", LemmingsLive, :index
    live "/lemmings/:id", LemmingsLive, :show
    get "/lemmings/instances/:id/artifacts/*path", InstanceArtifactController, :show
    get "/lemmings/instances/:id/raw.md", InstanceRawSnapshotController, :show
    live "/lemmings/instances/:id/raw", InstanceRawLive, :show
    live "/lemmings/instances/:id", InstanceLive, :show
    live "/tools", ToolsLive, :index
    live "/logs", LogsLive, :index
    live "/settings", SettingsLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", LemmingsOsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:lemmings_os, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live "/runtime", LemmingsOsWeb.RuntimeDashboardLive, :index
      live_dashboard "/dashboard", metrics: LemmingsOsWeb.Telemetry
    end
  end
end
