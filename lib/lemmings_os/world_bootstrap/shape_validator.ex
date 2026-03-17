defmodule LemmingsOs.WorldBootstrap.ShapeValidator do
  @moduledoc """
  Validates the frozen bootstrap YAML shape for World ingestion.

  This validator checks the task's frozen contract, emits normalized warnings
  for unknown keys, and returns normalized errors for missing or invalid data.
  It does not perform import/sync or treat YAML as the system of record.
  """

  use Gettext, backend: LemmingsOs.Gettext

  @top_level_keys ~w(world infrastructure cities tools models limits costs runtime)
  @world_keys ~w(id slug name)
  @infrastructure_keys ~w(postgres)
  @postgres_keys ~w(url_env)
  @models_keys ~w(providers profiles)
  @provider_keys ~w(enabled base_url api_key_env default_billing_mode allowed_models)
  @profile_keys ~w(provider model fallbacks)
  @fallback_keys ~w(provider model)
  @limits_keys ~w(max_cities max_departments_per_city max_lemmings_per_department)
  @costs_keys ~w(budgets)
  @budget_keys ~w(monthly_usd daily_tokens)
  @runtime_keys ~w(idle_ttl_seconds cross_city_communication)

  @type issue :: %{
          severity: String.t(),
          code: String.t(),
          summary: String.t(),
          detail: String.t(),
          source: String.t(),
          path: String.t(),
          action_hint: String.t()
        }

  @type validation_result :: %{config: map(), issues: [issue()]}

  @doc """
  Validates a parsed bootstrap config against the frozen Task 03 contract.
  """
  @spec validate(map()) :: {:ok, validation_result()} | {:error, validation_result()}
  def validate(config) when is_map(config) do
    config
    |> collect_issues()
    |> validation_result(config)
  end

  def validate(config) do
    issues = [
      error_issue(
        "invalid_root_type",
        dgettext("errors", ".shape_invalid_root_type_summary"),
        dgettext("errors", ".shape_invalid_root_type_detail"),
        "$",
        dgettext("errors", ".shape_invalid_root_type_action_hint")
      )
    ]

    {:error, %{config: config, issues: issues}}
  end

  defp collect_issues(config) do
    unknown_key_warnings(config, @top_level_keys, "$") ++
      required_top_level_issues(config) ++
      world_issues(config) ++
      infrastructure_issues(config) ++
      placeholder_section_issues(config, "cities") ++
      placeholder_section_issues(config, "tools") ++
      models_issues(config) ++
      limits_issues(config) ++
      costs_issues(config) ++
      runtime_issues(config)
  end

  defp validation_result(issues, config),
    do: validation_result(issues, config, has_errors?(issues))

  defp validation_result(issues, config, true), do: {:error, %{config: config, issues: issues}}
  defp validation_result(issues, config, false), do: {:ok, %{config: config, issues: issues}}

  defp has_errors?(issues), do: Enum.any?(issues, &(&1.severity == "error"))

  defp required_top_level_issues(config) do
    @top_level_keys
    |> Enum.reject(&Map.has_key?(config, &1))
    |> Enum.map(&missing_section_issue(&1))
  end

  defp world_issues(config),
    do: config |> Map.get("world") |> validate_map_section("world", &validate_world_section/1)

  defp infrastructure_issues(config) do
    config
    |> Map.get("infrastructure")
    |> validate_map_section("infrastructure", &validate_infrastructure_section/1)
  end

  defp placeholder_section_issues(config, section_name) do
    config
    |> Map.get(section_name)
    |> validate_map_section(section_name, &unknown_key_warnings(&1, [], section_name))
  end

  defp models_issues(config),
    do: config |> Map.get("models") |> validate_map_section("models", &validate_models_section/1)

  defp limits_issues(config),
    do: config |> Map.get("limits") |> validate_map_section("limits", &validate_limits_section/1)

  defp costs_issues(config),
    do: config |> Map.get("costs") |> validate_map_section("costs", &validate_costs_section/1)

  defp runtime_issues(config),
    do:
      config |> Map.get("runtime") |> validate_map_section("runtime", &validate_runtime_section/1)

  defp validate_map_section(nil, path, _validator), do: [missing_section_issue(path)]

  defp validate_map_section(section, _path, validator) when is_map(section),
    do: validator.(section)

  defp validate_map_section(_, path, _validator), do: [invalid_type_issue(path, "map")]

  defp validate_world_section(section) do
    unknown_key_warnings(section, @world_keys, "world") ++
      required_string_issues(section, "world", @world_keys)
  end

  defp validate_infrastructure_section(section) do
    unknown_key_warnings(section, @infrastructure_keys, "infrastructure") ++
      validate_postgres_section(Map.get(section, "postgres"))
  end

  defp validate_postgres_section(section),
    do: validate_map_section(section, "infrastructure.postgres", &do_validate_postgres_section/1)

  defp do_validate_postgres_section(section) do
    unknown_key_warnings(section, @postgres_keys, "infrastructure.postgres") ++
      required_string_issues(section, "infrastructure.postgres", @postgres_keys)
  end

  defp validate_models_section(section) do
    unknown_key_warnings(section, @models_keys, "models") ++
      validate_providers_section(Map.get(section, "providers")) ++
      validate_profiles_section(Map.get(section, "profiles"))
  end

  defp validate_providers_section(section),
    do: validate_map_section(section, "models.providers", &do_validate_providers_section/1)

  defp do_validate_providers_section(section) do
    section
    |> Enum.flat_map(fn {provider_name, provider_config} ->
      validate_provider_entry(provider_name, provider_config)
    end)
  end

  defp validate_provider_entry(provider_name, provider_config) do
    path = "models.providers.#{provider_name}"

    validate_map_section(provider_config, path, fn section ->
      unknown_key_warnings(section, @provider_keys, path) ++
        required_string_list_issue(section, path, "allowed_models") ++
        optional_boolean_issue(section, path, "enabled") ++
        optional_string_issue(section, path, "base_url") ++
        optional_string_issue(section, path, "api_key_env") ++
        optional_string_issue(section, path, "default_billing_mode")
    end)
  end

  defp validate_profiles_section(section),
    do: validate_map_section(section, "models.profiles", &do_validate_profiles_section/1)

  defp do_validate_profiles_section(section) do
    section
    |> Enum.flat_map(fn {profile_name, profile_config} ->
      validate_profile_entry(profile_name, profile_config)
    end)
  end

  defp validate_profile_entry(profile_name, profile_config) do
    path = "models.profiles.#{profile_name}"

    validate_map_section(profile_config, path, fn section ->
      unknown_key_warnings(section, @profile_keys, path) ++
        required_string_issues(section, path, ~w(provider model)) ++
        profile_fallback_issues(section, path)
    end)
  end

  defp profile_fallback_issues(section, path),
    do: optional_fallbacks_issues(Map.get(section, "fallbacks"), path)

  defp optional_fallbacks_issues(nil, _path), do: []

  defp optional_fallbacks_issues(fallbacks, path) when is_list(fallbacks) do
    fallbacks
    |> Enum.with_index()
    |> Enum.flat_map(fn {fallback, index} ->
      validate_fallback_entry(fallback, "#{path}.fallbacks.#{index}")
    end)
  end

  defp optional_fallbacks_issues(_, path), do: [invalid_type_issue("#{path}.fallbacks", "list")]

  defp validate_fallback_entry(fallback, path) do
    validate_map_section(fallback, path, fn section ->
      unknown_key_warnings(section, @fallback_keys, path) ++
        required_string_issues(section, path, @fallback_keys)
    end)
  end

  defp validate_limits_section(section) do
    unknown_key_warnings(section, @limits_keys, "limits") ++
      required_integer_issues(section, "limits", @limits_keys)
  end

  defp validate_costs_section(section) do
    unknown_key_warnings(section, @costs_keys, "costs") ++
      validate_budget_section(Map.get(section, "budgets"))
  end

  defp validate_budget_section(section),
    do: validate_map_section(section, "costs.budgets", &do_validate_budget_section/1)

  defp do_validate_budget_section(section) do
    unknown_key_warnings(section, @budget_keys, "costs.budgets") ++
      required_number_issue(section, "costs.budgets", "monthly_usd") ++
      required_integer_issues(section, "costs.budgets", ~w(daily_tokens))
  end

  defp validate_runtime_section(section) do
    unknown_key_warnings(section, @runtime_keys, "runtime") ++
      required_integer_issues(section, "runtime", ~w(idle_ttl_seconds)) ++
      required_boolean_issue(section, "runtime", "cross_city_communication")
  end

  defp required_string_issues(section, path, keys),
    do: Enum.flat_map(keys, &required_string_issue(section, path, &1))

  defp required_string_issue(section, path, key),
    do:
      validate_required_value(Map.get(section, key), "#{path}.#{key}", "string", &valid_string?/1)

  defp required_integer_issues(section, path, keys),
    do: Enum.flat_map(keys, &required_integer_issue(section, path, &1))

  defp required_integer_issue(section, path, key),
    do: validate_required_value(Map.get(section, key), "#{path}.#{key}", "integer", &is_integer/1)

  defp required_number_issue(section, path, key),
    do: validate_required_value(Map.get(section, key), "#{path}.#{key}", "number", &is_number/1)

  defp required_boolean_issue(section, path, key),
    do: validate_required_value(Map.get(section, key), "#{path}.#{key}", "boolean", &is_boolean/1)

  defp required_string_list_issue(section, path, key),
    do:
      validate_required_value(
        Map.get(section, key),
        "#{path}.#{key}",
        "list_of_strings",
        &string_list?/1
      )

  defp optional_string_issue(section, path, key),
    do: optional_typed_issue(Map.get(section, key), "#{path}.#{key}", "string", &valid_string?/1)

  defp optional_boolean_issue(section, path, key),
    do: optional_typed_issue(Map.get(section, key), "#{path}.#{key}", "boolean", &is_boolean/1)

  defp validate_required_value(nil, path, _expected_type, _predicate),
    do: [missing_value_issue(path)]

  defp validate_required_value(value, path, expected_type, predicate),
    do: validate_predicate_result(predicate.(value), path, expected_type)

  defp optional_typed_issue(nil, _path, _expected_type, _predicate), do: []

  defp optional_typed_issue(value, path, expected_type, predicate),
    do: optional_predicate_result(predicate.(value), path, expected_type)

  defp validate_predicate_result(true, _path, _expected_type), do: []

  defp validate_predicate_result(false, path, expected_type),
    do: [invalid_type_issue(path, expected_type)]

  defp optional_predicate_result(true, _path, _expected_type), do: []

  defp optional_predicate_result(false, path, expected_type),
    do: [invalid_type_issue(path, expected_type)]

  defp valid_string?(value), do: is_binary(value) and value != ""
  defp string_list?(values) when is_list(values), do: Enum.all?(values, &is_binary/1)
  defp string_list?(_), do: false

  defp unknown_key_warnings(section, allowed_keys, path) do
    section
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed_keys))
    |> Enum.map(&unknown_key_issue(path, &1))
  end

  defp missing_section_issue(path) do
    error_issue(
      "missing_required_section",
      dgettext("errors", ".shape_missing_required_section_summary"),
      dgettext("errors", ".shape_missing_required_section_detail", path: path),
      path,
      dgettext("errors", ".shape_missing_required_section_action_hint")
    )
  end

  defp missing_value_issue(path) do
    error_issue(
      "missing_required_value",
      dgettext("errors", ".shape_missing_required_value_summary"),
      dgettext("errors", ".shape_missing_required_value_detail", path: path),
      path,
      dgettext("errors", ".shape_missing_required_value_action_hint")
    )
  end

  defp invalid_type_issue(path, expected_type) do
    error_issue(
      "invalid_value_type",
      dgettext("errors", ".shape_invalid_value_type_summary"),
      dgettext("errors", ".shape_invalid_value_type_detail",
        path: path,
        expected_type: expected_type
      ),
      path,
      dgettext("errors", ".shape_invalid_value_type_action_hint")
    )
  end

  defp unknown_key_issue(path, key) do
    issue_path = build_path(path, key)

    %{
      severity: "warning",
      code: "unknown_key",
      summary: dgettext("errors", ".shape_unknown_key_summary"),
      detail: dgettext("errors", ".shape_unknown_key_detail", path: issue_path),
      source: "shape_validation",
      path: issue_path,
      action_hint: dgettext("errors", ".shape_unknown_key_action_hint")
    }
  end

  defp error_issue(code, summary, detail, path, action_hint) do
    %{
      severity: "error",
      code: code,
      summary: summary,
      detail: detail,
      source: "shape_validation",
      path: path,
      action_hint: action_hint
    }
  end

  defp build_path("$", key), do: key
  defp build_path(path, key), do: "#{path}.#{key}"
end
