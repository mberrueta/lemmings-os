# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :lemmings_os,
  ecto_repos: [LemmingsOs.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :lemmings_os, :runtime_city_heartbeat,
  interval_ms: 30_000,
  freshness_threshold_seconds: 90

config :lemmings_os, :runtime_dets, directory: Path.expand("../priv/runtime/dets", __DIR__)
config :lemmings_os, :runtime_engine_on_startup, true

if config_env() in [:dev, :test] do
  config :lemmings_os, LemmingsOs.Vault,
    json_library: Jason,
    ciphers: [
      default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1",
         key: :crypto.hash(:sha256, "dev_test_only_secret_bank_key_material_do_not_use_in_prod")}
    ]
end

config :lemmings_os, LemmingsOs.SecretBank,
  allowed_env_vars: [
    "$GITHUB_TOKEN",
    "$OPENROUTER_API_KEY"
  ],
  env_fallbacks: [
    "$GITHUB_TOKEN",
    {"OPENROUTER_API_KEY", "$OPENROUTER_API_KEY"}
  ]

# TODO: temporary default selection
config :lemmings_os, :model_runtime,
  provider_module: LemmingsOs.ModelRuntime.Providers.Ollama,
  default_model: "qwen3.5:latest",
  timeout: 120_000,
  ollama: [base_url: System.get_env("OLLAMA_BASE_URL") || "http://localhost:11434"]

# Configures the endpoint
config :lemmings_os, LemmingsOsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LemmingsOsWeb.ErrorHTML, json: LemmingsOsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LemmingsOs.PubSub,
  live_view: [signing_salt: "oCA6s5RW"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  lemmings_os: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  lemmings_os: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :event,
    :status,
    :reason,
    :operation,
    :instance_id,
    :caller_instance_id,
    :callee_instance_id,
    :department_id,
    :caller_department_id,
    :callee_department_id,
    :resource_key,
    :admission_mode,
    :queue_depth,
    :current_item_id,
    :from_status,
    :to_status,
    :retry_count,
    :max_retries,
    :holder_pid,
    :executor_pid,
    :pool_current,
    :pool_max,
    :message_id,
    :lemming_call_id,
    :lemming_id,
    :duration_ms,
    :result_summary,
    :error_summary,
    :previous_call_id,
    :recovered_count,
    :skipped_count,
    :table,
    :path,
    :bootstrap_path,
    :issue_count,
    :world_id,
    :city_id,
    :node_name,
    :work_area_ref
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
