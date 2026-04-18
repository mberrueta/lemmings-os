defmodule LemmingsOsWeb.PageData.WorldPageSnapshot do
  @moduledoc """
  Operator-facing World page read model.

  This snapshot separates persisted World identity, declared bootstrap config,
  immediate import feedback, last persisted sync metadata, and cheap runtime
  checks so LiveViews and components do not depend on raw Ecto structs or raw
  YAML maps.
  """

  alias LemmingsOs.Repo
  alias LemmingsOs.Worlds.World
  alias LemmingsOs.WorldBootstrap.Loader
  alias LemmingsOs.WorldBootstrap.ShapeValidator
  alias LemmingsOs.Worlds
  alias LemmingsOs.Gettext, as: AppGettext

  @type issue :: map()

  @type provider :: %{
          name: String.t(),
          enabled: boolean() | nil,
          base_url: String.t() | nil,
          api_key_env: String.t() | nil,
          default_billing_mode: String.t() | nil,
          allowed_models: [String.t()]
        }

  @type profile_fallback :: %{provider: String.t() | nil, model: String.t() | nil}

  @type profile :: %{
          name: String.t(),
          provider: String.t() | nil,
          model: String.t() | nil,
          fallbacks: [profile_fallback()]
        }

  @type declared_config :: %{
          world: %{bootstrap_id: String.t() | nil, slug: String.t() | nil, name: String.t() | nil},
          infrastructure: %{postgres: %{url_env: String.t() | nil}},
          models: %{providers: [provider()], profiles: [profile()]},
          limits: %{
            max_cities: integer() | nil,
            max_departments_per_city: integer() | nil,
            max_lemmings_per_department: integer() | nil
          },
          costs: %{budgets: %{monthly_usd: number() | nil, daily_tokens: integer() | nil}},
          runtime: %{idle_ttl_seconds: integer() | nil, cross_city_communication: boolean() | nil},
          placeholders: %{cities_declared?: boolean(), tools_declared?: boolean()}
        }

  @type runtime_check :: %{
          code: String.t(),
          status: String.t(),
          status_label: String.t(),
          detail: map()
        }

  @type t :: %__MODULE__{
          world: map(),
          bootstrap: map(),
          immediate_import: map(),
          last_sync: map(),
          runtime: map()
        }

  defstruct [:world, :bootstrap, :immediate_import, :last_sync, :runtime]

  @doc """
  Builds the World page snapshot from persisted state plus bootstrap/runtime signals.

  Supported options:

  - `:world` - persisted `%World{}` to snapshot directly
  - `:world_id` - persisted world ID when a direct struct is not provided
  - `:loader_opts` - keyword options forwarded to `Loader.load/1`
  - `:immediate_import_result` - optional `Importer.sync_default_world/1` result
  - `:env_getter` - unary function used to resolve env vars for tests/runtime checks
  - `:postgres_check` - zero-arity function used to run the DB reachability probe

  ## Examples

      iex> path = LemmingsOs.WorldBootstrapTestHelpers.write_temp_file!(
      ...>   LemmingsOs.WorldBootstrapTestHelpers.valid_bootstrap_yaml()
      ...> )
      iex> world =
      ...>   LemmingsOs.Factory.insert(:world,
      ...>     bootstrap_path: path,
      ...>     bootstrap_source: "direct",
      ...>     last_import_status: "ok"
      ...>   )
      iex> {:ok, snapshot} =
      ...>   LemmingsOsWeb.PageData.WorldPageSnapshot.build(
      ...>     world: world,
      ...>     env_getter: fn env_var -> if env_var == "DATABASE_URL", do: "ecto://db" end,
      ...>     postgres_check: fn -> {:ok, %{rows: [[1]]}} end
      ...>   )
      iex> {snapshot.bootstrap.status, snapshot.immediate_import.status, snapshot.last_sync.status}
      {"ok", "unknown", "ok"}
  """
  @spec build(World.t() | keyword()) :: {:ok, t()} | {:error, :not_found}
  def build(arg \\ [])

  def build(%World{} = world), do: {:ok, build_snapshot(world, [])}

  def build(opts) when is_list(opts) do
    with {:ok, world} <- fetch_snapshot_world(opts) do
      {:ok, build_snapshot(world, opts)}
    end
  end

  defp build_snapshot(%World{} = world, opts) do
    bootstrap_snapshot = bootstrap_snapshot(world, opts)
    runtime_snapshot = runtime_snapshot(world, bootstrap_snapshot, opts)

    %__MODULE__{
      world: persisted_world_snapshot(world),
      bootstrap: bootstrap_snapshot,
      immediate_import: immediate_import_snapshot(Keyword.get(opts, :immediate_import_result)),
      last_sync: last_sync_snapshot(world),
      runtime: runtime_snapshot
    }
  end

  defp fetch_snapshot_world(opts), do: fetch_snapshot_world(Keyword.get(opts, :world), opts)
  defp fetch_snapshot_world(%World{} = world, _opts), do: {:ok, world}

  defp fetch_snapshot_world(nil, opts),
    do: fetch_snapshot_world_by_id(Keyword.get(opts, :world_id))

  defp fetch_snapshot_world_by_id(world_id) when is_binary(world_id) do
    case Worlds.get_world(world_id) do
      %World{} = world -> {:ok, world}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_snapshot_world_by_id(_world_id) do
    case Worlds.get_default_world() do
      %World{} = world -> {:ok, world}
      nil -> {:error, :not_found}
    end
  end

  defp persisted_world_snapshot(%World{} = world) do
    %{
      id: world.id,
      slug: world.slug,
      name: world.name,
      status: world.status,
      status_label: status_label(world.status)
    }
  end

  defp bootstrap_snapshot(%World{} = world, opts) do
    case snapshot_loader_opts(world, opts) do
      [] -> missing_bootstrap_snapshot(world)
      loader_opts -> loader_opts |> Loader.load() |> bootstrap_load_snapshot()
    end
  end

  defp snapshot_loader_opts(%World{} = world, opts) do
    case Keyword.get(opts, :loader_opts) do
      loader_opts when is_list(loader_opts) and loader_opts != [] -> loader_opts
      _loader_opts -> fallback_loader_opts(world)
    end
  end

  defp fallback_loader_opts(%World{bootstrap_path: path, bootstrap_source: source})
       when is_binary(path) and path != "" do
    [path: path, source: source || "persisted"]
  end

  defp fallback_loader_opts(_world), do: []

  defp missing_bootstrap_snapshot(%World{} = world) do
    issue =
      normalized_issue(
        "bootstrap_input_not_configured",
        Gettext.dgettext(AppGettext, "errors", ".bootstrap_input_not_configured_summary"),
        missing_bootstrap_detail(world),
        "bootstrap_file",
        world.bootstrap_path || "world.bootstrap_path",
        Gettext.dgettext(AppGettext, "errors", ".bootstrap_input_not_configured_action_hint")
      )

    %{
      source: world.bootstrap_source,
      path: world.bootstrap_path,
      status: "unknown",
      status_label: status_label("unknown"),
      issues: [issue],
      declared_config: nil
    }
  end

  defp bootstrap_load_snapshot({:ok, load_result}),
    do: validated_bootstrap_snapshot(load_result, ShapeValidator.validate(load_result.config))

  defp bootstrap_load_snapshot({:error, %{source: source, path: path, issues: issues}}) do
    %{
      source: source,
      path: path,
      status: failed_load_status(issues),
      status_label: status_label(failed_load_status(issues)),
      issues: issues,
      declared_config: nil
    }
  end

  defp validated_bootstrap_snapshot(load_result, {:ok, validation_result}),
    do:
      bootstrap_validation_snapshot(
        load_result,
        validation_result,
        successful_bootstrap_status(validation_result.issues)
      )

  defp validated_bootstrap_snapshot(load_result, {:error, validation_result}),
    do: bootstrap_validation_snapshot(load_result, validation_result, "invalid")

  defp bootstrap_validation_snapshot(load_result, validation_result, status) do
    %{
      source: load_result.source,
      path: load_result.path,
      status: status,
      status_label: status_label(status),
      issues: validation_result.issues,
      declared_config: declared_config_snapshot(validation_result.config)
    }
  end

  defp successful_bootstrap_status([]), do: "ok"
  defp successful_bootstrap_status(_issues), do: "degraded"
  defp failed_load_status([%{code: "bootstrap_file_not_found"} | _rest]), do: "unavailable"
  defp failed_load_status(_issues), do: "invalid"

  defp declared_config_snapshot(config) when is_map(config) do
    %{
      world: %{
        bootstrap_id: get_in(config, ["world", "id"]),
        slug: get_in(config, ["world", "slug"]),
        name: get_in(config, ["world", "name"])
      },
      infrastructure: %{
        postgres: %{
          url_env: get_in(config, ["infrastructure", "postgres", "url_env"])
        }
      },
      models: %{
        providers: normalize_providers(get_in(config, ["models", "providers"])),
        profiles: normalize_profiles(get_in(config, ["models", "profiles"]))
      },
      limits: %{
        max_cities: get_in(config, ["limits", "max_cities"]),
        max_departments_per_city: get_in(config, ["limits", "max_departments_per_city"]),
        max_lemmings_per_department: get_in(config, ["limits", "max_lemmings_per_department"])
      },
      costs: %{
        budgets: %{
          monthly_usd: get_in(config, ["costs", "budgets", "monthly_usd"]),
          daily_tokens: get_in(config, ["costs", "budgets", "daily_tokens"])
        }
      },
      runtime: %{
        idle_ttl_seconds: get_in(config, ["runtime", "idle_ttl_seconds"]),
        cross_city_communication: get_in(config, ["runtime", "cross_city_communication"])
      },
      placeholders: %{
        cities_declared?: is_map(Map.get(config, "cities")),
        tools_declared?: is_map(Map.get(config, "tools"))
      }
    }
  end

  defp normalize_providers(providers) when is_map(providers) do
    providers
    |> Enum.sort_by(fn {name, _config} -> name end)
    |> Enum.map(&normalize_provider/1)
  end

  defp normalize_providers(_providers), do: []

  defp normalize_provider({name, config}) when is_map(config) do
    %{
      name: name,
      enabled: Map.get(config, "enabled"),
      base_url: Map.get(config, "base_url"),
      api_key_env: Map.get(config, "api_key_env"),
      default_billing_mode: Map.get(config, "default_billing_mode"),
      allowed_models: normalize_allowed_models(Map.get(config, "allowed_models"))
    }
  end

  defp normalize_provider({name, _config}) do
    %{
      name: name,
      enabled: nil,
      base_url: nil,
      api_key_env: nil,
      default_billing_mode: nil,
      allowed_models: []
    }
  end

  defp normalize_allowed_models(models) when is_list(models),
    do: Enum.filter(models, &is_binary/1)

  defp normalize_allowed_models(_models), do: []

  defp normalize_profiles(profiles) when is_map(profiles) do
    profiles
    |> Enum.sort_by(fn {name, _config} -> name end)
    |> Enum.map(&normalize_profile/1)
  end

  defp normalize_profiles(_profiles), do: []

  defp normalize_profile({name, config}) when is_map(config) do
    %{
      name: name,
      provider: Map.get(config, "provider"),
      model: Map.get(config, "model"),
      fallbacks: normalize_fallbacks(Map.get(config, "fallbacks"))
    }
  end

  defp normalize_profile({name, _config}),
    do: %{name: name, provider: nil, model: nil, fallbacks: []}

  defp normalize_fallbacks(fallbacks) when is_list(fallbacks),
    do: Enum.map(fallbacks, &normalize_fallback/1)

  defp normalize_fallbacks(_fallbacks), do: []

  defp normalize_fallback(fallback) when is_map(fallback) do
    %{provider: Map.get(fallback, "provider"), model: Map.get(fallback, "model")}
  end

  defp normalize_fallback(_fallback), do: %{provider: nil, model: nil}

  defp immediate_import_snapshot(nil) do
    %{
      status: "unknown",
      status_label: status_label("unknown"),
      issues: [],
      source: nil,
      path: nil,
      persisted_last_import_status: nil,
      persisted_last_import_status_label: nil,
      available?: false
    }
  end

  defp immediate_import_snapshot({:ok, result}), do: immediate_import_snapshot(result)
  defp immediate_import_snapshot({:error, result}), do: immediate_import_snapshot(result)

  defp immediate_import_snapshot(%{} = result) do
    persisted_status =
      Map.get(result, :persisted_last_import_status) ||
        Map.get(result, "persisted_last_import_status")

    operation_status =
      Map.get(result, :operation_status) || Map.get(result, "operation_status") || "unknown"

    %{
      status: operation_status,
      status_label: status_label(operation_status),
      issues: Map.get(result, :issues) || Map.get(result, "issues") || [],
      source: Map.get(result, :source) || Map.get(result, "source"),
      path: Map.get(result, :path) || Map.get(result, "path"),
      persisted_last_import_status: persisted_status,
      persisted_last_import_status_label: persisted_status && status_label(persisted_status),
      available?: true
    }
  end

  defp last_sync_snapshot(%World{} = world) do
    %{
      status: world.last_import_status,
      status_label: status_label(world.last_import_status),
      imported_at: world.last_imported_at,
      bootstrap_source: world.bootstrap_source,
      bootstrap_path: world.bootstrap_path,
      bootstrap_hash: world.last_bootstrap_hash
    }
  end

  defp runtime_snapshot(%World{} = world, bootstrap_snapshot, opts) do
    checks = runtime_checks(world, bootstrap_snapshot, opts)
    status = aggregate_runtime_status(checks)

    %{
      status: status,
      status_label: status_label(status),
      checks: checks,
      deferred_sources: deferred_sources(checks)
    }
  end

  defp runtime_checks(world, bootstrap_snapshot, opts) do
    env_getter = Keyword.get(opts, :env_getter, &System.get_env/1)
    postgres_check = Keyword.get(opts, :postgres_check, &default_postgres_check/0)

    [
      bootstrap_file_check(world, bootstrap_snapshot),
      postgres_connection_check(bootstrap_snapshot, env_getter, postgres_check),
      provider_credentials_check(bootstrap_snapshot, env_getter),
      provider_reachability_check(bootstrap_snapshot)
    ]
  end

  defp bootstrap_file_check(%World{} = world, %{path: path})
       when is_binary(path) and path != "" do
    status = if File.exists?(path), do: "ok", else: "unavailable"

    %{
      code: "bootstrap_file",
      status: status,
      status_label: status_label(status),
      detail: %{path: path, persisted_path: world.bootstrap_path}
    }
  end

  defp bootstrap_file_check(%World{bootstrap_path: path}, _bootstrap_snapshot)
       when is_binary(path) and path != "" do
    status = if File.exists?(path), do: "ok", else: "unavailable"

    %{
      code: "bootstrap_file",
      status: status,
      status_label: status_label(status),
      detail: %{path: path, persisted_path: path}
    }
  end

  defp bootstrap_file_check(_world, _bootstrap_snapshot) do
    %{
      code: "bootstrap_file",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{path: nil, persisted_path: nil}
    }
  end

  defp postgres_connection_check(
         %{declared_config: %{infrastructure: %{postgres: %{url_env: url_env}}}},
         env_getter,
         postgres_check
       )
       when is_binary(url_env) and url_env != "" do
    postgres_connection_check_result(url_env, env_getter.(url_env), postgres_check)
  end

  defp postgres_connection_check(_bootstrap_snapshot, _env_getter, _postgres_check) do
    %{
      code: "postgres_connection",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{url_env: nil}
    }
  end

  defp postgres_connection_check_result(url_env, value, _postgres_check)
       when value in [nil, ""] do
    %{
      code: "postgres_connection",
      status: "unavailable",
      status_label: status_label("unavailable"),
      detail: %{url_env: url_env}
    }
  end

  defp postgres_connection_check_result(url_env, _value, postgres_check) do
    case postgres_check.() do
      {:ok, _result} ->
        %{
          code: "postgres_connection",
          status: "ok",
          status_label: status_label("ok"),
          detail: %{url_env: url_env}
        }

      {:error, reason} ->
        %{
          code: "postgres_connection",
          status: "unavailable",
          status_label: status_label("unavailable"),
          detail: %{url_env: url_env, reason: inspect(reason)}
        }
    end
  end

  defp provider_credentials_check(
         %{declared_config: %{models: %{providers: providers}}},
         env_getter
       )
       when is_list(providers) do
    providers
    |> Enum.filter(&provider_requires_credentials?/1)
    |> provider_credentials_snapshot(env_getter)
  end

  defp provider_credentials_check(_bootstrap_snapshot, _env_getter) do
    %{
      code: "provider_credentials",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{providers: [], missing_envs: []}
    }
  end

  defp provider_requires_credentials?(%{enabled: true, api_key_env: api_key_env}),
    do: is_binary(api_key_env) and api_key_env != ""

  defp provider_requires_credentials?(_provider), do: false

  defp provider_credentials_snapshot([], _env_getter) do
    %{
      code: "provider_credentials",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{providers: [], missing_envs: []}
    }
  end

  defp provider_credentials_snapshot(providers, env_getter) do
    missing_envs =
      providers
      |> Enum.filter(&missing_provider_env?(&1, env_getter))
      |> Enum.map(& &1.api_key_env)

    status = if missing_envs == [], do: "ok", else: "degraded"

    %{
      code: "provider_credentials",
      status: status,
      status_label: status_label(status),
      detail: %{providers: Enum.map(providers, & &1.name), missing_envs: missing_envs}
    }
  end

  defp missing_provider_env?(%{api_key_env: env_var}, env_getter),
    do: env_getter.(env_var) in [nil, ""]

  defp provider_reachability_check(%{declared_config: %{models: %{providers: providers}}})
       when is_list(providers) do
    enabled_provider_names =
      providers
      |> Enum.filter(&(&1.enabled == true))
      |> Enum.map(& &1.name)

    provider_reachability_snapshot(enabled_provider_names)
  end

  defp provider_reachability_check(_bootstrap_snapshot),
    do: provider_reachability_snapshot([])

  defp provider_reachability_snapshot([]) do
    %{
      code: "provider_reachability",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{providers: [], deferred?: true}
    }
  end

  defp provider_reachability_snapshot(provider_names) do
    %{
      code: "provider_reachability",
      status: "unknown",
      status_label: status_label("unknown"),
      detail: %{providers: provider_names, deferred?: true}
    }
  end

  defp aggregate_runtime_status(checks) do
    checks
    |> Enum.reject(&(&1.status == "unknown"))
    |> aggregate_known_runtime_status()
  end

  defp aggregate_known_runtime_status([]), do: "unknown"

  defp aggregate_known_runtime_status(checks) do
    statuses = Enum.map(checks, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == "ok")) -> "ok"
      Enum.all?(statuses, &(&1 == "unavailable")) -> "unavailable"
      "invalid" in statuses -> "invalid"
      "degraded" in statuses -> "degraded"
      "unavailable" in statuses -> "degraded"
      true -> "unknown"
    end
  end

  defp deferred_sources(checks) do
    checks
    |> Enum.filter(&get_in(&1, [:detail, :deferred?]))
    |> Enum.map(& &1.code)
  end

  defp default_postgres_check, do: Repo.query("SELECT 1", [])

  defp missing_bootstrap_detail(%World{bootstrap_path: nil}),
    do:
      Gettext.dgettext(
        AppGettext,
        "errors",
        ".bootstrap_input_not_configured_missing_path_detail"
      )

  defp missing_bootstrap_detail(%World{bootstrap_path: ""}),
    do:
      Gettext.dgettext(
        AppGettext,
        "errors",
        ".bootstrap_input_not_configured_empty_path_detail"
      )

  defp normalized_issue(code, summary, detail, source, path, action_hint) do
    %{
      severity: "error",
      code: code,
      summary: summary,
      detail: detail,
      source: source,
      path: path,
      action_hint: action_hint
    }
  end

  defp status_label(status), do: World.translate_status(status)
end
