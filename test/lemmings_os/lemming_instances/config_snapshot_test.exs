defmodule LemmingsOs.LemmingInstances.ConfigSnapshotTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.ConfigSnapshot

  test "selection/1 prefers explicit normalized runtime fields over profile maps" do
    config_snapshot = %{
      model_runtime: %{
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        resource_key: "anthropic:claude-sonnet-4-6"
      },
      models_config: %{
        profiles: %{
          default: %{provider: "ollama", model: "llama3.2"}
        }
      }
    }

    assert %{
             profile: nil,
             provider: "anthropic",
             model: "claude-sonnet-4-6",
             resource_key: "anthropic:claude-sonnet-4-6"
           } = ConfigSnapshot.selection(config_snapshot)
  end

  test "selection/1 falls back to the default profile and then deterministic sorted order" do
    with_default = %{
      models_config: %{
        profiles: %{
          default: %{provider: "ollama", model: "llama3.2"},
          fast: %{provider: "ollama", model: "qwen2.5:7b"}
        }
      }
    }

    assert %{
             profile: "default",
             provider: "ollama",
             model: "llama3.2",
             resource_key: "ollama:llama3.2"
           } = ConfigSnapshot.selection(with_default)

    without_default = %{
      models_config: %{
        profiles: %{
          zeta: %{provider: "openai", model: "gpt-4.1-mini"},
          alpha: %{provider: "ollama", model: "mistral-small"}
        }
      }
    }

    assert %{
             profile: "alpha",
             provider: "ollama",
             model: "mistral-small",
             resource_key: "ollama:mistral-small"
           } = ConfigSnapshot.selection(without_default)
  end

  test "enrich/1 persists the normalized active selection under model_runtime" do
    config_snapshot = %{
      models_config: %{
        profiles: %{
          default: %{provider: "ollama", model: "qwen2.5:7b"}
        }
      }
    }

    assert %{
             model_runtime: %{
               profile: "default",
               provider: "ollama",
               model: "qwen2.5:7b",
               resource_key: "ollama:qwen2.5:7b"
             }
           } = ConfigSnapshot.enrich(config_snapshot)
  end
end
