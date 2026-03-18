import Config

test_port = System.get_env("TEST_PORT") || System.get_env("LIVE_DEBUGGER_PORT") || "4002"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :lemmings_os, LemmingsOs.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "lemmings_os_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :lemmings_os, LemmingsOsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(test_port)],
  secret_key_base: "CGExhyMoul9DcsNJN+Ta6z04ZJ2wIHo1/VuILb0ZggDKm0ioAt9vkWQkAAvPFYZQ",
  server: false

config :lemmings_os, :world_bootstrap_import_on_startup, false

config :lemmings_os, :tools_runtime_fetcher, LemmingsOs.Tools.MockRuntimeFetcher
config :lemmings_os, :tools_policy_fetcher, LemmingsOs.Tools.MockPolicyFetcher

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
