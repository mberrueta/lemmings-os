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
config :lemmings_os, :runtime_city_registration_on_startup, false
config :lemmings_os, :runtime_city_heartbeat_on_startup, false
config :lemmings_os, :runtime_engine_on_startup, false
config :lemmings_os, dev_routes: true
config :lemmings_os, :runtime_dets, directory: Path.expand("../tmp/runtime/dets", __DIR__)
config :lemmings_os, :runtime_workspace_root, Path.expand("../tmp/runtime/workspace", __DIR__)
config :lemmings_os, :work_areas_path, Path.expand("../tmp/runtime/work_areas", __DIR__)

config :lemmings_os, :artifact_storage,
  backend: :local,
  root_path: Path.expand("../tmp/runtime/storage", __DIR__),
  max_file_size_bytes: 100 * 1024 * 1024

config :lemmings_os, :model_runtime,
  provider_module: LemmingsOs.ModelRuntime.Providers.Ollama,
  default_model: "llama3.2",
  timeout: 120_000,
  ollama: [base_url: System.get_env("OLLAMA_BASE_URL") || "http://127.0.0.1:11434"]

config :lemmings_os, :tools_runtime_fetcher, LemmingsOs.Tools.MockRuntimeFetcher
config :lemmings_os, :tools_policy_fetcher, LemmingsOs.Tools.MockPolicyFetcher

config :lemmings_os, :documents,
  gotenberg_url: "http://127.0.0.1:3999",
  pdf_timeout_ms: 30_000,
  pdf_connect_timeout_ms: 5_000,
  pdf_retries: 1,
  max_source_bytes: 10 * 1024 * 1024,
  max_pdf_bytes: 50 * 1024 * 1024,
  max_fallback_bytes: 1 * 1024 * 1024,
  default_header_path: nil,
  default_footer_path: nil,
  default_css_path: nil

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
