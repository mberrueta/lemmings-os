defmodule LemmingsOs.Config.ResolverTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.Config.CostsConfig
  alias LemmingsOs.Config.LimitsConfig
  alias LemmingsOs.Config.ModelsConfig
  alias LemmingsOs.Config.Resolver
  alias LemmingsOs.Config.RuntimeConfig
  alias LemmingsOs.Config.ToolsConfig

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

  describe "resolve/1 for departments" do
    test "merges department overrides on top of city and world config" do
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

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 8},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 90},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{monthly_usd: 25.0}
          },
          models_config: %ModelsConfig{
            providers: %{
              "ollama" => %{"allowed_models" => ["mistral-small"]},
              "anthropic" => %{"enabled" => true}
            },
            profiles: %{
              "fast" => %{"provider" => "ollama", "model" => "mistral-small"},
              "reasoning" => %{"provider" => "anthropic", "model" => "claude-sonnet"}
            }
          }
        )

      resolved = Resolver.resolve(department)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.limits_config.max_lemmings_per_department == 8
      assert resolved.runtime_config.idle_ttl_seconds == 90
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.monthly_usd == 25.0
      assert resolved.costs_config.budgets.daily_tokens == 5_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.models_config.providers["ollama"]["allowed_models"] == ["mistral-small"]
      assert resolved.models_config.providers["openai"]["enabled"] == false
      assert resolved.models_config.providers["anthropic"]["enabled"] == true
      assert resolved.models_config.profiles["default"]["model"] == "llama3.2"
      assert resolved.models_config.profiles["fast"]["model"] == "mistral-small"
      assert resolved.models_config.profiles["reasoning"]["model"] == "claude-sonnet"
    end

    test "keeps inherited city/world values when the department has empty config buckets" do
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

      city =
        build(:city,
          world: world,
          limits_config: %LimitsConfig{max_departments_per_city: 5},
          runtime_config: %RuntimeConfig{cross_city_communication: true}
        )

      department = build(:department, world: world, city: city)

      resolved = Resolver.resolve(department)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.daily_tokens == 1_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
    end

    test "uses department.world when city.world is not preloaded" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 3, max_departments_per_city: 20},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 3600, cross_city_communication: false}
        )

      city =
        build(:city,
          world: nil,
          limits_config: %LimitsConfig{max_departments_per_city: 5},
          runtime_config: %RuntimeConfig{cross_city_communication: true}
        )

      city = %{
        city
        | world: %Ecto.Association.NotLoaded{__field__: :world, __owner__: city.__struct__}
      }

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 8}
        )

      resolved = Resolver.resolve(department)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.limits_config.max_lemmings_per_department == 8
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.runtime_config.cross_city_communication == true
    end
  end

  describe "resolve/1 for lemmings" do
    test "merges lemming overrides on top of department, city, and world config" do
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

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 8},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 90},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{monthly_usd: 25.0}
          },
          models_config: %ModelsConfig{
            providers: %{
              "ollama" => %{"allowed_models" => ["mistral-small"]},
              "anthropic" => %{"enabled" => true}
            },
            profiles: %{
              "fast" => %{"provider" => "ollama", "model" => "mistral-small"},
              "reasoning" => %{"provider" => "anthropic", "model" => "claude-sonnet"}
            }
          }
        )

      lemming =
        build(:lemming,
          world: world,
          city: city,
          department: department,
          limits_config: %LimitsConfig{max_lemmings_per_department: 3},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 30},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{daily_tokens: 250}
          },
          models_config: %ModelsConfig{
            providers: %{
              "ollama" => %{"allowed_models" => ["gpt-oss:20b"]}
            },
            profiles: %{
              "reasoning" => %{"provider" => "ollama", "model" => "gpt-oss:20b"}
            }
          },
          tools_config: %ToolsConfig{
            allowed_tools: ["github", "filesystem"],
            denied_tools: ["shell"]
          }
        )

      resolved = Resolver.resolve(lemming)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.limits_config.max_lemmings_per_department == 3
      assert resolved.runtime_config.idle_ttl_seconds == 30
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.monthly_usd == 25.0
      assert resolved.costs_config.budgets.daily_tokens == 250
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.models_config.providers["ollama"]["allowed_models"] == ["gpt-oss:20b"]
      assert resolved.models_config.providers["openai"]["enabled"] == false
      assert resolved.models_config.providers["anthropic"]["enabled"] == true
      assert resolved.models_config.profiles["default"]["model"] == "llama3.2"
      assert resolved.models_config.profiles["fast"]["model"] == "mistral-small"
      assert resolved.models_config.profiles["reasoning"]["model"] == "gpt-oss:20b"
      assert resolved.tools_config.allowed_tools == ["github", "filesystem"]
      assert resolved.tools_config.denied_tools == ["shell"]
    end

    test "keeps inherited values when the lemming has empty config buckets" do
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

      city =
        build(:city,
          world: world,
          limits_config: %LimitsConfig{max_departments_per_city: 5},
          runtime_config: %RuntimeConfig{cross_city_communication: true}
        )

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 8}
        )

      lemming = build(:lemming, world: world, city: city, department: department)

      resolved = Resolver.resolve(lemming)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.limits_config.max_lemmings_per_department == 8
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.daily_tokens == 1_000
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.tools_config == %ToolsConfig{}
    end

    test "uses lemming.world when city and department parent chains are not fully preloaded" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 3, max_departments_per_city: 20},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 3600, cross_city_communication: false}
        )

      city =
        build(:city,
          world: nil,
          limits_config: %LimitsConfig{max_departments_per_city: 5},
          runtime_config: %RuntimeConfig{cross_city_communication: true}
        )

      city = %{
        city
        | world: %Ecto.Association.NotLoaded{__field__: :world, __owner__: city.__struct__}
      }

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 8}
        )

      department = %{
        department
        | city: %Ecto.Association.NotLoaded{__field__: :city, __owner__: department.__struct__}
      }

      lemming =
        build(:lemming,
          world: world,
          city: city,
          department: department,
          tools_config: %ToolsConfig{allowed_tools: ["github"]}
        )

      resolved = Resolver.resolve(lemming)

      assert resolved.limits_config.max_cities == 3
      assert resolved.limits_config.max_departments_per_city == 5
      assert resolved.limits_config.max_lemmings_per_department == 8
      assert resolved.runtime_config.idle_ttl_seconds == 3600
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.tools_config.allowed_tools == ["github"]
      assert resolved.tools_config.denied_tools == []
    end

    test "uses the lemming.world fallback when city.world and department.city.world are nil" do
      world =
        build(:world,
          limits_config: %LimitsConfig{max_cities: 4, max_departments_per_city: 16},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 7200, cross_city_communication: false},
          costs_config: %CostsConfig{
            budgets: %CostsConfig.Budgets{monthly_usd: 50.0, daily_tokens: 500}
          },
          models_config: %ModelsConfig{
            providers: %{"ollama" => %{"enabled" => true}},
            profiles: %{"default" => %{"provider" => "ollama", "model" => "llama3.2"}}
          }
        )

      city =
        build(:city,
          world: nil,
          limits_config: %LimitsConfig{max_departments_per_city: 6},
          runtime_config: %RuntimeConfig{cross_city_communication: true}
        )

      department =
        build(:department,
          world: world,
          city: city,
          limits_config: %LimitsConfig{max_lemmings_per_department: 2},
          runtime_config: %RuntimeConfig{idle_ttl_seconds: 60}
        )

      lemming =
        build(:lemming,
          world: world,
          city: city,
          department: department,
          tools_config: %ToolsConfig{
            allowed_tools: ["filesystem"],
            denied_tools: ["shell"]
          }
        )

      resolved = Resolver.resolve(lemming)

      assert resolved.limits_config.max_cities == 4
      assert resolved.limits_config.max_departments_per_city == 6
      assert resolved.limits_config.max_lemmings_per_department == 2
      assert resolved.runtime_config.idle_ttl_seconds == 60
      assert resolved.runtime_config.cross_city_communication == true
      assert resolved.costs_config.budgets.monthly_usd == 50.0
      assert resolved.costs_config.budgets.daily_tokens == 500
      assert resolved.models_config.providers["ollama"]["enabled"] == true
      assert resolved.models_config.profiles["default"]["model"] == "llama3.2"
      assert resolved.tools_config.allowed_tools == ["filesystem"]
      assert resolved.tools_config.denied_tools == ["shell"]
    end

    test "does not add tools_config to world city or department resolution" do
      world = build(:world)
      city = build(:city, world: world)
      department = build(:department, world: world, city: city)

      refute Map.has_key?(Resolver.resolve(world), :tools_config)
      refute Map.has_key?(Resolver.resolve(city), :tools_config)
      refute Map.has_key?(Resolver.resolve(department), :tools_config)
    end
  end
end
