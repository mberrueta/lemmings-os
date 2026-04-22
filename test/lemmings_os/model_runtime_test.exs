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
         content: ~s({"action":"unknown"}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule ToolCallProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s({"action":"tool_call","tool_name":"web.fetch","args":{"url":"https://example.com"}}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule LemmingCallProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s({"action":"lemming_call","target":"researcher","request":"Find three risks","continue_call_id":null}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  test "S01: run/3 assembles the prompt and validates the reply" do
    config_snapshot = %{
      name: "Budget Brief",
      description: "Creates budget artifacts for operators.",
      instructions: "Be concise.",
      provider_module: FakeProvider,
      model: "test-model"
    }

    history = [%{role: "user", content: "Hello"}]
    current_request = %{content: "Hello"}

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, history, current_request)

    assert response.reply == "ok"
    assert response.action == :reply
    assert response.provider == "fake"
    assert response.model == "test-model"
    assert response.input_tokens == 1
    assert response.output_tokens == 2
    assert response.total_tokens == 3
    assert response.usage == %{prompt_eval_count: 1, eval_count: 2}
    assert %{role: "system", content: system_prompt} = Enum.at(response.raw.messages, 0)
    assert String.contains?(system_prompt, "Platform Runtime Context:")
    assert String.contains?(system_prompt, "Configured Lemming Identity:")
    assert String.contains?(system_prompt, "Name: Budget Brief")
    assert String.contains?(system_prompt, "Description: Creates budget artifacts for operators.")
    assert String.contains?(system_prompt, "Instructions:\nBe concise.")
    assert String.contains?(system_prompt, "{\"action\":\"reply\"")
    assert String.contains?(system_prompt, "fs.write_text_file")
    assert String.contains?(system_prompt, "Loop State Semantics:")
    assert String.contains?(system_prompt, "Assistant requested tool <tool_name> with arguments:")

    assert String.contains?(
             system_prompt,
             "Tool result for <tool_name>: status=<status> payload=<json>"
           )

    assert String.contains?(system_prompt, "Immediate Response Instruction:")

    assert String.contains?(
             system_prompt,
             "Return exactly one JSON object matching the output contract below."
           )

    assert String.contains?(system_prompt, "IMPORTANT: RESPOND WITH JSON ONLY.")

    assert String.contains?(
             system_prompt,
             "Decide what to do next by returning exactly one JSON shape:"
           )

    assert String.contains?(system_prompt, "Option A: final reply to the user.")
    assert String.contains?(system_prompt, "Option B: one tool call for the runtime to execute.")

    assert String.contains?(
             system_prompt,
             "For file creation or file updates, use fs.write_text_file."
           )

    assert %{role: "user", content: "Hello"} = List.last(response.raw.messages)
    assert_receive {:provider_request, %{format: "json", model: "test-model"}}
  end

  test "S02: run/3 rejects invalid structured output" do
    config_snapshot = %{
      provider_module: InvalidJsonProvider,
      model: "test-model"
    }

    assert {:error,
            {:invalid_structured_output,
             %{
               provider: "fake",
               model: "test-model",
               content: "not-json",
               raw: %{messages: _, format: "json", model: "test-model"},
               reason: _
             }}} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S03: run/3 supports tool_call structured output" do
    config_snapshot = %{
      provider_module: ToolCallProvider,
      model: "test-model"
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :tool_call
    assert response.tool_name == "web.fetch"
    assert response.tool_args == %{"url" => "https://example.com"}
  end

  test "S03a: run/3 supports lemming_call structured output for manager targets" do
    config_snapshot = %{
      provider_module: LemmingCallProvider,
      model: "test-model",
      lemming_call_targets: [
        %{
          slug: "researcher",
          capability: "ops/researcher",
          role: "worker",
          department_slug: "ops",
          description: "Research bounded tasks"
        }
      ]
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :lemming_call
    assert response.lemming_target == "researcher"
    assert response.lemming_request == "Find three risks"
    assert response.continue_call_id == nil

    assert %{role: "system", content: system_prompt} = Enum.at(response.raw.messages, 0)
    assert String.contains?(system_prompt, "Available Lemming Calls:")
    assert String.contains?(system_prompt, "ops/researcher")
  end

  test "S03b: run/3 rejects unknown actions" do
    config_snapshot = %{
      provider_module: UnknownActionProvider,
      model: "test-model"
    }

    assert {:error,
            {:unknown_action,
             %{
               provider: "fake",
               model: "test-model",
               content: ~s({"action":"unknown"}),
               raw: %{messages: _, format: "json", model: "test-model"}
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S04: exposes the structured output contract and runtime rules" do
    assert String.contains?(ModelRuntime.structured_output_contract(), "\"action\":\"reply\"")
    assert String.contains?(ModelRuntime.runtime_rules(), "Return valid JSON only")
  end

  test "S05: Response.new/1 builds a runtime response struct" do
    response =
      Response.new(
        action: :reply,
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

  test "S07: run/3 resolves the active model from the shared config-snapshot contract" do
    config_snapshot = %{
      provider_module: FakeProvider,
      models_config: %{
        profiles: %{
          beta: %{provider: "ollama", model: "beta-model"},
          alpha: %{provider: "ollama", model: "alpha-model"}
        }
      }
    }

    assert {:ok, %Response{model: "alpha-model"}} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert_receive {:provider_request, %{format: "json", model: "alpha-model"}}
  end

  test "S08: debug_request/3 exposes the assembled provider payload" do
    config_snapshot = %{
      name: "Writer",
      description: "Writes files on request.",
      instructions: "Be concise.",
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{
        allowed_tools: ["fs.write_text_file", "web.fetch"],
        denied_tools: ["fs.read_text_file"]
      }
    }

    history = [%{role: "user", content: "Create the file"}]
    current_request = %{content: "Write notes/output.md"}

    assert {:ok,
            %{
              provider: "Elixir.LemmingsOs.ModelRuntimeTest.FakeProvider",
              model: "test-model",
              request: request
            }} =
             ModelRuntime.debug_request(config_snapshot, history, current_request)

    assert request.format == "json"
    assert %{role: "system", content: system_prompt} = Enum.at(request.messages, 0)

    assert String.contains?(
             system_prompt,
             "Available Tools:\n- fs.write_text_file: Write UTF-8 text files inside the instance work area.\n- web.fetch: Fetch HTTP(S) content from a single URL."
           )

    assert List.last(request.messages) == %{role: "user", content: "Write notes/output.md"}
  end

  test "S09: debug_request/3 keeps one user message when current request already exists in history" do
    config_snapshot = %{
      name: "Budget Brief",
      instructions: "Write useful budget examples.",
      provider_module: FakeProvider,
      model: "test-model"
    }

    history = [
      %{role: "user", content: "Create sample.md", request_id: "req-1"},
      %{
        role: "assistant",
        content:
          "Assistant requested tool fs.write_text_file with arguments: {\"path\":\"sample.md\"}"
      },
      %{
        role: "assistant",
        content:
          "As response to your previous tool request, the runtime executed fs.write_text_file. Tool result for fs.write_text_file: status=ok payload={\"summary\":\"Wrote file sample.md\",\"path\":\"sample.md\",\"preview\":\"sample preview\"}. Decide what to do next."
      }
    ]

    current_request = %{content: "Create sample.md", request_id: "req-1"}

    assert {:ok, %{request: request}} =
             ModelRuntime.debug_request(config_snapshot, history, current_request)

    user_messages = Enum.filter(request.messages, &(&1.role == "user"))

    assert [%{role: "user", content: "Create sample.md"}] = user_messages

    assert Enum.any?(
             request.messages,
             &(&1.role == "assistant" and
                 String.contains?(&1.content, "Assistant requested tool fs.write_text_file"))
           )

    assert Enum.any?(
             request.messages,
             &(&1.role == "assistant" and
                 String.contains?(&1.content, "As response to your previous tool request"))
           )
  end
end
