defmodule LemmingsOs.Config.ResolverTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Config.RuntimeConfig

  describe "resolve/1 for worlds" do
    test "returns the world config buckets as effective config" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 3},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 3600},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{monthly_usd: 10.0, daily_tokens: 1_000}
          },
          models_config: %ModelsConfig{
            providers: %{"ollama" => %{"enabled" => true}},
            profiles: %{"default" => %{"provider" => "ollama"}}
          }
        )

      resolved = Resolver.resolve(world)

      assert resolved.limits_config.max_cities == 3
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.costs_config.budgets.monthly_usd == 10.0
      assert resolved.costs_config.budgets.daily_tokens == 1_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.models_config.profiles["default"]["provider"] == "ollama"
    end
  end

  describe "resolve/1 for cities" do
    test "merges city overrides on top of world config" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 3, max_departments_per_city: 20},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 3600, cross_city_communication: false},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{monthly_usd: 10.0, daily_tokens: 1_000}
          },
          models_config: %ModelsConfig{
            providers: %{
              "ollama" => %{"enabled" => true, "allowed_models" => ["llama3.2"]}
            },
            profiles: %{"default" => %{"provider" => "ollama", "model" => "llama3.2"}}
          }
        )

      city =
        build(:city,
          world: world,
          limits_config: %LimitsConfig{max_departments_per_city: 5},
          runtime_config: %RuntimeConfig{cross_city_communication: true},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{daily_tokens: 5_000}
          },
          models_config: %ModelsConfig{
            providers: %{
              "ollama" => %{"allowed_models" => ["qwen2.5:7b"]},
              "openai" => %{"enabled" => false}
            },
            profiles: %{"fast" => %{"provider" => "ollama", "model" => "qwen2.5:7b"}}
          }
        )

      resolved = Resolver.resolve(city)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.monthly_usd == 10.0
      assert resolved.costs_config.budgets.daily_tokens == 5_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.models_config.providers["ollama"]["allowed_models"] == ["qwen2.5:7b"]
      assert resolved.models_config.providers["openai"]["enabled"] == false
      assert resolved.models_config.profiles["default"]["model"] == "llama3.2"
      assert resolved.models_config.profiles["fast"]["model"] == "qwen2.5:7b"
    end

    test "keeps world values when the city has empty config buckets" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 3},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 3600},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{daily_tokens: 1_000}
          },
          models_config: %ModelsConfig{
            providers: %{"ollama" => %{"enabled" => true}}
          }
        )

      city = build(:city, world: world)

      resolved = Resolver.resolve(city)

      assert resolved.limits_config.max_cities == 3
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.costs_config.budgets.daily_tokens == 1_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
    end
  end
end
