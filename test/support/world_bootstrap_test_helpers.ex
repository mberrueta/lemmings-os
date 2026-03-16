defmodule LemmingsOs.WorldBootstrapTestHelpers do
  @moduledoc false

  def valid_bootstrap_yaml do
    """
    world:
      id: "world_local"
      slug: "local"
      name: "Local World"

    infrastructure:
      postgres:
        url_env: "DATABASE_URL"

    cities: {}

    tools: {}

    models:
      providers:
        ollama:
          enabled: true
          base_url: "http://127.0.0.1:11434"
          default_billing_mode: "zero_cost"
          allowed_models:
            - "llama3.2"
            - "qwen2.5:7b"
      profiles:
        default:
          provider: "ollama"
          model: "qwen2.5:7b"
          fallbacks:
            - provider: "ollama"
              model: "gemma2"

    limits:
      max_cities: 1
      max_departments_per_city: 20
      max_lemmings_per_department: 50

    costs:
      budgets:
        monthly_usd: 0
        daily_tokens: 1000000

    runtime:
      idle_ttl_seconds: 3600
      cross_city_communication: false
    """
  end

  def valid_bootstrap_config do
    %{
      "world" => %{
        "id" => "world_local",
        "slug" => "local",
        "name" => "Local World"
      },
      "infrastructure" => %{
        "postgres" => %{"url_env" => "DATABASE_URL"}
      },
      "cities" => %{},
      "tools" => %{},
      "models" => %{
        "providers" => %{
          "ollama" => %{
            "enabled" => true,
            "base_url" => "http://127.0.0.1:11434",
            "default_billing_mode" => "zero_cost",
            "allowed_models" => ["llama3.2", "qwen2.5:7b"]
          }
        },
        "profiles" => %{
          "default" => %{
            "provider" => "ollama",
            "model" => "qwen2.5:7b",
            "fallbacks" => [
              %{"provider" => "ollama", "model" => "gemma2"}
            ]
          }
        }
      },
      "limits" => %{
        "max_cities" => 1,
        "max_departments_per_city" => 20,
        "max_lemmings_per_department" => 50
      },
      "costs" => %{
        "budgets" => %{
          "monthly_usd" => 0,
          "daily_tokens" => 1_000_000
        }
      },
      "runtime" => %{
        "idle_ttl_seconds" => 3600,
        "cross_city_communication" => false
      }
    }
  end

  def write_temp_file!(contents, suffix \\ ".yaml") do
    path =
      Path.join(
        System.tmp_dir!(),
        "world-bootstrap-#{System.unique_integer([:positive])}#{suffix}"
      )

    File.write!(path, contents)
    path
  end
end
