import Config

work_areas_path =
  System.get_env("LEMMINGS_WORK_AREAS_PATH") ||
    Application.get_env(
      :lemmings_os,
      :work_areas_path,
      Path.expand("../priv/runtime/workspace", __DIR__)
    )

artifact_storage = Application.get_env(:lemmings_os, :artifact_storage, [])

artifact_storage_root_path =
  System.get_env("LEMMINGS_ARTIFACT_STORAGE_ROOT") ||
    Keyword.get(artifact_storage, :root_path, Path.expand("../priv/runtime/storage", __DIR__))

artifact_storage_max_file_size_bytes =
  Keyword.get(artifact_storage, :max_file_size_bytes, 100 * 1024 * 1024)

runtime_city_node_name = System.get_env("LEMMINGS_CITY_NODE_NAME") || Atom.to_string(node())
runtime_city_heartbeat = Application.get_env(:lemmings_os, :runtime_city_heartbeat, [])

config :lemmings_os, :work_areas_path, work_areas_path

config :lemmings_os, :artifact_storage,
  backend: :local,
  root_path: artifact_storage_root_path,
  max_file_size_bytes: artifact_storage_max_file_size_bytes

documents = Application.get_env(:lemmings_os, :documents, [])

config :lemmings_os, :documents,
  gotenberg_url:
    System.get_env("LEMMINGS_GOTENBERG_URL") ||
      Keyword.get(documents, :gotenberg_url, "http://gotenberg:3000"),
  pdf_timeout_ms:
    System.get_env("LEMMINGS_DOCUMENTS_PDF_TIMEOUT_MS") ||
      Keyword.get(documents, :pdf_timeout_ms, 30_000),
  pdf_connect_timeout_ms:
    System.get_env("LEMMINGS_DOCUMENTS_PDF_CONNECT_TIMEOUT_MS") ||
      Keyword.get(documents, :pdf_connect_timeout_ms, 5_000),
  pdf_retries:
    System.get_env("LEMMINGS_DOCUMENTS_PDF_RETRIES") || Keyword.get(documents, :pdf_retries, 1),
  max_source_bytes:
    System.get_env("LEMMINGS_DOCUMENTS_MAX_SOURCE_BYTES") ||
      Keyword.get(documents, :max_source_bytes, 10 * 1024 * 1024),
  max_pdf_bytes:
    System.get_env("LEMMINGS_DOCUMENTS_MAX_PDF_BYTES") ||
      Keyword.get(documents, :max_pdf_bytes, 50 * 1024 * 1024),
  max_fallback_bytes:
    System.get_env("LEMMINGS_DOCUMENTS_MAX_FALLBACK_BYTES") ||
      Keyword.get(documents, :max_fallback_bytes, 1 * 1024 * 1024),
  default_header_path:
    System.get_env("LEMMINGS_DOCUMENTS_DEFAULT_HEADER_PATH") ||
      Keyword.get(documents, :default_header_path),
  default_footer_path:
    System.get_env("LEMMINGS_DOCUMENTS_DEFAULT_FOOTER_PATH") ||
      Keyword.get(documents, :default_footer_path),
  default_css_path:
    System.get_env("LEMMINGS_DOCUMENTS_DEFAULT_CSS_PATH") ||
      Keyword.get(documents, :default_css_path)

config :lemmings_os, :runtime_city,
  node_name: runtime_city_node_name,
  slug: System.get_env("LEMMINGS_CITY_SLUG"),
  name: System.get_env("LEMMINGS_CITY_NAME"),
  host: System.get_env("LEMMINGS_CITY_HOST"),
  distribution_port: System.get_env("LEMMINGS_CITY_DISTRIBUTION_PORT"),
  epmd_port: System.get_env("LEMMINGS_CITY_EPMD_PORT")

config :lemmings_os, :runtime_city_heartbeat,
  interval_ms:
    System.get_env("LEMMINGS_CITY_HEARTBEAT_INTERVAL_MS") ||
      Keyword.get(runtime_city_heartbeat, :interval_ms),
  freshness_threshold_seconds:
    System.get_env("LEMMINGS_CITY_STALE_AFTER_SECONDS") ||
      Keyword.get(runtime_city_heartbeat, :freshness_threshold_seconds)

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/lemmings_os start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :lemmings_os, LemmingsOsWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :lemmings_os, LemmingsOs.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  secret_bank_key =
    "LEMMINGS_SECRET_BANK_KEY_BASE64"
    |> System.fetch_env!()
    |> Base.decode64!()

  if byte_size(secret_bank_key) != 32 do
    raise "LEMMINGS_SECRET_BANK_KEY_BASE64 must decode to exactly 32 bytes"
  end

  config :lemmings_os, LemmingsOs.Vault,
    json_library: Jason,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: secret_bank_key}
    ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || System.get_env("MIX_PORT") || "4000")

  config :lemmings_os, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :lemmings_os, LemmingsOsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :lemmings_os, LemmingsOsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :lemmings_os, LemmingsOsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
