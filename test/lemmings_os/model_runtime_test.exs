defmodule LemmingsOs.ModelRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.ModelRuntime.Response

  defmodule FakeProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:provider_request, request})

      {:ok,
       %{
         content: ~s({"action":"reply","reply":"ok"}),
         provider: "fake",
         model: request.model,
         input_tokens: 1,
         output_tokens: 2,
         total_tokens: 3,
         usage: %{prompt_eval_count: 1, eval_count: 2},
         raw: request
       }}
    end
  end

  defmodule InvalidJsonProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok, %{content: "not-json", provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule UnknownActionProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content: ~s({"action":"tool_call","reply":"nope"}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  test "S01: run/3 assembles the prompt and validates the reply" do
    config_snapshot = %{
      instructions: "Be concise.",
      provider_module: FakeProvider,
      model: "test-model"
    }

    history = [%{role: "user", content: "Hello"}]
    current_request = %{content: "Hello"}

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, history, current_request)

    assert response.reply == "ok"
    assert response.provider == "fake"
    assert response.model == "test-model"
    assert response.input_tokens == 1
    assert response.output_tokens == 2
    assert response.total_tokens == 3
    assert response.usage == %{prompt_eval_count: 1, eval_count: 2}
    assert %{role: "system", content: system_prompt} = Enum.at(response.raw.messages, 0)
    assert String.contains?(system_prompt, "Be concise.")
    assert String.contains?(system_prompt, "{\"action\":\"reply\"")
    assert %{role: "user", content: "Hello"} = List.last(response.raw.messages)
    assert_receive {:provider_request, %{format: "json", model: "test-model"}}
  end

  test "S02: run/3 rejects invalid structured output" do
    config_snapshot = %{
      provider_module: InvalidJsonProvider,
      model: "test-model"
    }

    assert {:error, :invalid_structured_output} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S03: run/3 rejects unknown actions" do
    config_snapshot = %{
      provider_module: UnknownActionProvider,
      model: "test-model"
    }

    assert {:error, :unknown_action} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S04: exposes the structured output contract and runtime rules" do
    assert String.contains?(ModelRuntime.structured_output_contract(), "\"action\":\"reply\"")
    assert String.contains?(ModelRuntime.runtime_rules(), "Return valid JSON only")
  end

  test "S05: Response.new/1 builds a runtime response struct" do
    response =
      Response.new(
        reply: "hello",
        provider: "ollama",
        model: "llama3.2",
        raw: %{}
      )

    assert %Response{reply: "hello", provider: "ollama", model: "llama3.2"} = response
  end

  test "S06: run/3 returns :missing_model when no model is configured" do
    previous_runtime_config = Application.get_env(:lemmings_os, :model_runtime, [])
    runtime_config_without_model = Keyword.delete(previous_runtime_config, :default_model)
    Application.put_env(:lemmings_os, :model_runtime, runtime_config_without_model)

    on_exit(fn ->
      Application.put_env(:lemmings_os, :model_runtime, previous_runtime_config)
    end)

    config_snapshot = %{provider_module: FakeProvider}

    assert {:error, :missing_model} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end
end
