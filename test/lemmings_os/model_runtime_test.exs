defmodule LemmingsOs.ModelRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.ModelRuntime.Response
  alias LemmingsOs.Tools.Catalog

  doctest LemmingsOs.ModelRuntime

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

  defmodule BlankContentProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:blank_content_provider_request, request})
      {:ok, %{content: "", provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule MissingContentProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok, %{provider: "fake", model: request.model, raw: request}}
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
           ~s({"action":"tool_call","target":"web.fetch","args":{"url":"https://example.com"}}),
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
           ~s({"action":"lemming_call","target":"researcher","args":{"request":"Find three risks"}}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule ProseJsonLemmingCallProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s(I will delegate next.\n{"action":"lemming_call","target":"researcher","args":{"request":"Find three risks"}}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule LegacyJsonLemmingRequestProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s({"action":"lemming_call","target":"researcher","request":"Find three risks"}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule InvalidTargetThenRepairProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:repair_provider_request, request})

      content =
        if request.messages
           |> List.last()
           |> Map.get(:content, "")
           |> String.contains?("Correction required") do
          ~s({"action":"lemming_call","target":"researcher","args":{"request":"Find three risks"}})
        else
          ~s({"action":"lemming_call","target":"invented","args":{"request":"Find three risks"}})
        end

      {:ok, %{content: content, provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule InvalidJsonThenRepairProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:invalid_json_repair_request, request})

      content =
        if request.messages
           |> List.last()
           |> Map.get(:content, "")
           |> String.contains?("Correction required") do
          ~s({"action":"reply","reply":"repaired"})
        else
          "not-json"
        end

      {:ok, %{content: content, provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule EmptyObjectThenRepairProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:empty_object_repair_request, request})

      content =
        if request.messages
           |> List.last()
           |> Map.get(:content, "")
           |> String.contains?("Correction required") do
          ~s({"action":"tool_call","target":"web.search","args":{"query":"USD BRL exchange rate Buenos Aires quotation"}})
        else
          "{}"
        end

      {:ok, %{content: content, provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule EmptyObjectAlwaysProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:empty_object_provider_request, request})
      {:ok, %{content: "{}", provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule InvalidToolArgsThenRepairProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      content =
        if request.messages
           |> List.last()
           |> Map.get(:content, "")
           |> String.contains?("Correction required") do
          ~s({"action":"tool_call","target":"web.fetch","args":{"url":"https://example.com"}})
        else
          ~s({"action":"tool_call","target":"web.fetch","args":{}})
        end

      {:ok, %{content: content, provider: "fake", model: request.model, raw: request}}
    end
  end

  defmodule UnavailableActionProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s({"action":"lemming_call","target":"researcher","args":{"request":"Find three risks"}}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule LegacyJsonToolCallProvider do
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

  defmodule LegacyLemmingCallProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s(Assistant requested lemming_call with arguments: {"target":"researcher","request":"Find three risks","continue_call_id":null}),
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule LegacyCompatLemmingCallProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      {:ok,
       %{
         content:
           ~s(Assistant requested lemming_call with arguments: {"target":"researcher","request":"Find three risks","continue_call_id":null}),
         legacy_structured_output: true,
         provider: "fake",
         model: request.model,
         raw: request
       }}
    end
  end

  defmodule FallbackSequenceProvider do
    @behaviour LemmingsOs.ModelRuntime.Provider

    @impl true
    def chat(request, _opts) do
      send(self(), {:provider_request, request.model})

      case request.model do
        "primary-model" ->
          {:ok, %{content: "", provider: "fake", model: request.model, raw: request}}

        "fallback-model" ->
          {:ok,
           %{
             content: ~s({"action":"reply","reply":"rescued by fallback"}),
             provider: "fake",
             model: request.model,
             raw: request
           }}
      end
    end
  end

  test "S01: manager prompt with no tools and available lemming calls is conditional and explicit" do
    config_snapshot = %{
      name: "Budget Brief",
      slug: "budget-brief",
      department_slug: "finance",
      collaboration_role: "manager",
      description: "Creates budget artifacts for operators.",
      instructions: "Be concise.",
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{allowed_tools: [], denied_tools: Enum.map(Catalog.list_tools(), & &1.id)},
      lemming_call_targets: [
        %{
          slug: "sales_knowledge_librarian",
          capability: "sales/sales_knowledge_librarian",
          role: "worker",
          department_slug: "sales",
          description:
            "internal sales knowledge, memories, templates, price lists, policies, prior examples."
        },
        %{
          slug: "sales_web_researcher",
          capability: "sales/sales_web_researcher",
          role: "worker",
          department_slug: "sales",
          description:
            "external sales-related research such as exchange rates, public prices, market references, events, logistics, and travel context."
        },
        %{
          slug: "sales_quote_specialist",
          capability: "sales/sales_quote_specialist",
          role: "worker",
          department_slug: "sales",
          description:
            "prepares complete customer quotations, including document files and Gmail drafts."
        }
      ]
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
    assert String.contains?(system_prompt, "Lemming Identity:")
    assert String.contains?(system_prompt, "- Name: Budget Brief")
    assert String.contains?(system_prompt, "- Slug: budget-brief")
    assert String.contains?(system_prompt, "- Department: finance")
    assert String.contains?(system_prompt, "- Effective role: manager")

    assert String.contains?(
             system_prompt,
             "- Purpose/description: Creates budget artifacts for operators."
           )

    assert String.contains?(system_prompt, "Lemming Instructions:\nBe concise.")
    assert String.contains?(system_prompt, "Manager Planning Rules:")
    refute String.contains?(system_prompt, "Effective Tool Availability:")
    refute String.contains?(system_prompt, "Available Tools:")
    refute String.contains?(system_prompt, "fs.write_text_file")
    refute String.contains?(system_prompt, ~s({"action":"tool_call"))

    assert String.contains?(system_prompt, "Available Lemming Calls:")
    assert String.contains?(system_prompt, "sales_knowledge_librarian")
    assert String.contains?(system_prompt, "sales_web_researcher")
    assert String.contains?(system_prompt, "sales_quote_specialist")
    assert String.contains?(system_prompt, ~s({"action":"lemming_call"))
    assert String.contains?(system_prompt, ~s("target":"<available-lemming-slug>"))
    assert String.contains?(system_prompt, ~s("args":{"request":"bounded task text"}))
    refute String.contains?(system_prompt, "continue_call_id")
    refute String.contains?(system_prompt, "slug-or-capability")

    refute String.contains?(
             system_prompt,
             ~s({"action":"lemming_call","target":"slug-or-capability","request":"bounded task text","continue_call_id":null})
           )

    assert String.contains?(system_prompt, "Loop State Semantics:")
    assert String.contains?(system_prompt, "Assistant requested lemming_call with arguments:")

    assert String.contains?(system_prompt, "Immediate Response Instruction:")
    assert String.contains?(system_prompt, "Lemming Call Rules:")
    refute String.contains?(system_prompt, "Tool Response Rules:")
    refute String.contains?(system_prompt, "Knowledge Tool Rules:")

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

  test "S02a: run/3 records raw invalid JSON, parse error, and retries once" do
    config_snapshot = %{
      provider_module: InvalidJsonThenRepairProvider,
      model: "test-model"
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :reply
    assert response.reply == "repaired"
    assert response.raw.retry_attempted == true
    assert response.raw.invalid_output == "not-json"
    assert response.raw.retry_output == ~s({"action":"reply","reply":"repaired"})
    assert response.raw.raw_model_output == ~s({"action":"reply","reply":"repaired"})
    assert response.raw.parser_result.parse_status == "ok"

    assert_receive {:invalid_json_repair_request, %{messages: first_messages}}
    assert_receive {:invalid_json_repair_request, %{messages: repair_messages}}

    assert length(repair_messages) == length(first_messages) + 1
    repair_prompt = repair_messages |> List.last() |> Map.fetch!(:content)
    assert repair_prompt =~ "Correction required"
    assert repair_prompt =~ "Invalid output:\nnot-json"
  end

  test "S02b: run/3 treats blank model content as invalid structured output and retries once" do
    config_snapshot = %{
      provider_module: BlankContentProvider,
      model: "test-model"
    }

    assert {:error,
            {:invalid_structured_output,
             %{
               provider: "fake",
               model: "test-model",
               content: "",
               raw_model_output: "",
               retry_attempted: true,
               retry_output: "",
               final_parse_error: final_parse_error,
               parser_result: %{parse_status: "error", parse_error: parse_error}
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert is_binary(parse_error)
    assert is_binary(final_parse_error)

    assert_receive {:blank_content_provider_request, %{messages: first_messages}}
    assert_receive {:blank_content_provider_request, %{messages: repair_messages}}
    refute_receive {:blank_content_provider_request, _request}

    assert length(repair_messages) == length(first_messages) + 1
    assert repair_messages |> List.last() |> Map.fetch!(:content) =~ "Correction required"
  end

  test "S02d: run/3 treats empty JSON object as missing action validation failure and retries once" do
    config_snapshot = %{
      provider_module: EmptyObjectThenRepairProvider,
      model: "test-model",
      tools_config: %{allowed_tools: ["web.search"], denied_tools: []}
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{
               content: "Get current USD/BRL exchange rate for the Buenos Aires quotation"
             })

    assert response.action == :tool_call
    assert response.tool_name == "web.search"
    assert response.raw.retry_attempted == true
    assert response.raw.invalid_output == "{}"

    assert_receive {:empty_object_repair_request, %{messages: first_messages}}
    assert_receive {:empty_object_repair_request, %{messages: repair_messages}}

    assert length(repair_messages) == length(first_messages) + 1
    repair_prompt = repair_messages |> List.last() |> Map.fetch!(:content)
    assert repair_prompt =~ "missing_action"
    assert repair_prompt =~ "Invalid output:\n{}"
  end

  test "S02e: run/3 records missing_action details when corrective retry is exhausted" do
    config_snapshot = %{
      provider_module: EmptyObjectAlwaysProvider,
      model: "test-model",
      tools_config: %{allowed_tools: ["web.search"], denied_tools: []}
    }

    assert {:error,
            {:invalid_structured_output,
             %{
               raw_model_output: "{}",
               retry_attempted: true,
               retry_output: "{}",
               final_parse_error: "missing_action",
               validation_result: %{
                 validation_error: "missing_action",
                 validation_error_details: %{
                   code: "missing_action",
                   message: message,
                   parsed_payload: %{},
                   expected_actions: ["reply", "tool_call"],
                   expected_targets: %{"tool_call" => ["web.search"]},
                   provider: "fake",
                   model: "test-model"
                 }
               }
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert message =~ "action"
    assert_receive {:empty_object_provider_request, _request}
    assert_receive {:empty_object_provider_request, _request}
    refute_receive {:empty_object_provider_request, _request}
  end

  test "S02c: run/3 reports provider responses with no content as invalid provider responses" do
    config_snapshot = %{
      provider_module: MissingContentProvider,
      model: "test-model"
    }

    assert {:error,
            {:provider_invalid_response,
             %{
               provider: "fake",
               model: "test-model",
               reason: "missing_content",
               content: nil,
               raw: %{messages: _, format: "json", model: "test-model"}
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
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

  test "S03c: run/3 retries valid JSON with invalid tool args" do
    config_snapshot = %{
      provider_module: InvalidToolArgsThenRepairProvider,
      model: "test-model",
      tools_config: %{allowed_tools: ["web.fetch"], denied_tools: []}
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Fetch example"})

    assert response.action == :tool_call
    assert response.tool_name == "web.fetch"
    assert response.raw.retry_attempted == true
    assert response.raw.invalid_output =~ ~s("args":{})
    assert response.raw.retry_output =~ "https://example.com"
  end

  test "S03z: run/3 still accepts legacy JSON tool_call shape for compatibility" do
    config_snapshot = %{
      provider_module: LegacyJsonToolCallProvider,
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
    assert String.contains?(system_prompt, "- researcher: Research bounded tasks")

    assert String.contains?(
             system_prompt,
             ~s({"action":"lemming_call","target":"<available-lemming-slug>")
           )

    assert String.contains?(system_prompt, ~s("args":{"request":"bounded task text"}))
  end

  test "S03a1: run/3 extracts lemming_call JSON from prose" do
    config_snapshot = manager_target_config(ProseJsonLemmingCallProvider)

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :lemming_call
    assert response.lemming_target == "researcher"
    assert response.lemming_request == "Find three risks"
    assert response.raw.parser_result.parse_status == "ok"
    assert response.raw.parser_result.parse_source == "extracted_json"
    assert response.raw.parser_result.normalized_action == "lemming_call"
  end

  test "S03a2: run/3 normalizes legacy top-level lemming_call request JSON" do
    config_snapshot = manager_target_config(LegacyJsonLemmingRequestProvider)

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :lemming_call
    assert response.lemming_target == "researcher"
    assert response.lemming_request == "Find three risks"

    assert response.raw.parser_result.extracted_json == %{
             "action" => "lemming_call",
             "target" => "researcher",
             "request" => "Find three risks"
           }
  end

  test "S03a3: run/3 rejects invalid lemming target and retries with correction prompt" do
    config_snapshot = manager_target_config(InvalidTargetThenRepairProvider)

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :lemming_call
    assert response.lemming_target == "researcher"
    assert response.raw.retry_attempted == true
    assert response.raw.invalid_output =~ ~s("target":"invented")
    assert response.raw.retry_output =~ ~s("target":"researcher")

    assert_receive {:repair_provider_request, %{messages: first_messages}}
    assert_receive {:repair_provider_request, %{messages: repair_messages}}

    assert length(repair_messages) == length(first_messages) + 1
    assert repair_messages |> List.last() |> Map.get(:content) =~ "Correction required"
    assert repair_messages |> List.last() |> Map.get(:content) =~ "lemming_target_unavailable"
    assert repair_messages |> List.last() |> Map.get(:content) =~ "researcher"
  end

  test "S03a4: run/3 rejects unavailable action" do
    config_snapshot = %{
      provider_module: UnavailableActionProvider,
      model: "test-model",
      tools_config: %{allowed_tools: [], denied_tools: Enum.map(Catalog.list_tools(), & &1.id)}
    }

    assert {:error,
            {:invalid_structured_output,
             %{
               validation_result: %{
                 validation_error: "action_unavailable",
                 valid_actions: ["reply"]
               },
               retry_attempted: true,
               final_parse_error: "action_unavailable"
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S03aa: manager prompt with no delegation targets omits lemming_call action but keeps planning rules" do
    config_snapshot = %{
      provider_module: FakeProvider,
      model: "test-model",
      collaboration_role: "manager",
      tools_config: %{allowed_tools: [], denied_tools: Enum.map(Catalog.list_tools(), & &1.id)}
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert %{role: "system", content: system_prompt} = Enum.at(response.raw.messages, 0)
    assert String.contains?(system_prompt, "Manager Planning Rules:")
    refute String.contains?(system_prompt, "Available Lemming Calls:")
    refute String.contains?(system_prompt, "\"action\":\"lemming_call\"")

    assert String.contains?(
             system_prompt,
             ~s({"action":"reply","reply":"visible user-facing text"})
           )
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
    assert String.contains?(ModelRuntime.structured_output_contract(), "\"action\":\"tool_call\"")

    assert String.contains?(
             ModelRuntime.structured_output_contract(),
             "\"target\":\"<available-tool-id>\""
           )

    assert String.contains?(ModelRuntime.structured_output_contract(), "\"args\":{}")

    assert String.contains?(
             ModelRuntime.structured_output_contract(),
             "\"action\":\"lemming_call\""
           )

    assert String.contains?(ModelRuntime.runtime_rules(), "Return valid JSON only")
  end

  test "S04aa: debug_request/3 does not duplicate a single persisted user request" do
    config_snapshot = %{
      provider_module: FakeProvider,
      model: "test-model"
    }

    task = "Get current USD/BRL exchange rate for the Buenos Aires quotation"

    assert {:ok, %{request: request}} =
             ModelRuntime.debug_request(
               config_snapshot,
               [%{role: "user", content: task}],
               %{id: Ecto.UUID.generate(), content: task}
             )

    user_messages = Enum.filter(request.messages, &(&1.role == "user" and &1.content == task))
    assert length(user_messages) == 1
  end

  test "S04a: run/3 rejects legacy lemming_call text output by default" do
    config_snapshot = %{
      provider_module: LegacyLemmingCallProvider,
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

    assert {:error,
            {:invalid_structured_output,
             %{
               content: "Assistant requested lemming_call with arguments: " <> _legacy_payload
             }}} = ModelRuntime.run(config_snapshot, [], %{content: "Hello"})
  end

  test "S04b: run/3 accepts legacy lemming_call text output only behind compatibility flag" do
    config_snapshot = %{
      provider_module: LegacyCompatLemmingCallProvider,
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
  end

  test "S04c: run/3 retries configured fallback models after invalid provider output" do
    config_snapshot = %{
      provider_module: FallbackSequenceProvider,
      models_config: %{
        profiles: %{
          default: %{
            provider: "ollama",
            model: "primary-model",
            fallbacks: [
              %{provider: "ollama", model: "fallback-model"}
            ]
          }
        }
      }
    }

    assert {:ok, %Response{} = response} =
             ModelRuntime.run(config_snapshot, [], %{content: "Hello"})

    assert response.action == :reply
    assert response.reply == "rescued by fallback"
    assert response.model == "fallback-model"

    assert_receive {:provider_request, "primary-model"}
    assert_receive {:provider_request, "fallback-model"}
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

    assert String.contains?(system_prompt, "Available Tools:")
    assert String.contains?(system_prompt, "- fs.write_text_file:")
    assert String.contains?(system_prompt, "required `path`")
    assert String.contains?(system_prompt, "- web.fetch:")
    assert String.contains?(system_prompt, "required `url`")
    assert String.contains?(system_prompt, "Use exact argument keys from each contract.")

    assert String.contains?(
             system_prompt,
             "For file creation or file updates, use fs.write_text_file."
           )

    assert String.contains?(
             system_prompt,
             ~s({"action":"tool_call","target":"<available-tool-id>","args":{}})
           )

    refute String.contains?(system_prompt, "\"action\":\"lemming_call\"")

    assert List.last(request.messages) == %{role: "user", content: "Write notes/output.md"}
  end

  test "S08a: debug_request/3 exposes email draft argument contract" do
    config_snapshot = %{
      name: "Customer Follow-up",
      description: "Prepares customer updates after support triage completes.",
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{allowed_tools: ["email.create_draft"]}
    }

    assert {:ok, %{request: request}} =
             ModelRuntime.debug_request(config_snapshot, [], %{content: "Draft a follow-up"})

    assert %{role: "system", content: system_prompt} = Enum.at(request.messages, 0)

    assert String.contains?(system_prompt, "- email.create_draft:")
    assert String.contains?(system_prompt, "required `connection_ref`")
    assert String.contains?(system_prompt, "`to` (recipient email string")
    assert String.contains?(system_prompt, "optional `cc`/`bcc`")
    assert String.contains?(system_prompt, "optional `body_format` (`text/plain` default")
    assert String.contains?(system_prompt, "Creates a Gmail draft only; never sends email.")
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

  test "S10: debug_request/3 includes retrieval policy when knowledge tools are available" do
    config_snapshot = %{
      name: "Sales Assistant",
      instructions: "Find factual answers in available sources.",
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{
        allowed_tools: ["knowledge.search", "knowledge.read"],
        denied_tools: []
      }
    }

    assert {:ok, %{request: request}} =
             ModelRuntime.debug_request(config_snapshot, [], %{
               content: "What is the dish rack price?"
             })

    assert %{role: "system", content: system_prompt} = Enum.at(request.messages, 0)

    assert String.contains?(system_prompt, "Retrieval Decision Policy:")
    assert String.contains?(system_prompt, "broad department-scoped query")
    assert String.contains?(system_prompt, "Do not over-constrain the first search")
    assert String.contains?(system_prompt, "explicitly allowed placeholders")
    assert String.contains?(system_prompt, "must call `knowledge.read` on candidate chunks")
    assert String.contains?(system_prompt, "do not finalize from snippets alone")
    assert String.contains?(system_prompt, "Knowledge Tool Rules:")
    assert String.contains?(system_prompt, "knowledge.search result includes chunk references")
  end

  test "S11: specialist prompt with tools and no lemming calls includes only tool actions" do
    config_snapshot = %{
      collaboration_role: "worker",
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{
        allowed_tools: ["web.fetch"],
        denied_tools: ["fs.read_text_file", "fs.write_text_file", "web.search"]
      }
    }

    assert {:ok, %{request: request}} =
             ModelRuntime.debug_request(config_snapshot, [], %{content: "Fetch the page"})

    assert %{role: "system", content: system_prompt} = Enum.at(request.messages, 0)

    assert String.contains?(system_prompt, "Available Tools:")
    assert String.contains?(system_prompt, "- web.fetch:")
    refute String.contains?(system_prompt, "- fs.write_text_file:")

    refute String.contains?(
             system_prompt,
             "For file creation or file updates, use fs.write_text_file."
           )

    refute String.contains?(system_prompt, "Available Lemming Calls:")
    refute String.contains?(system_prompt, "\"action\":\"lemming_call\"")
    assert String.contains?(system_prompt, "\"action\":\"tool_call\"")
  end

  test "S12: knowledge rules are conditional on knowledge.search plus knowledge.read availability" do
    with_knowledge = %{
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{
        allowed_tools: ["knowledge.search", "knowledge.read"],
        denied_tools: []
      }
    }

    without_knowledge = %{
      provider_module: FakeProvider,
      model: "test-model",
      tools_config: %{allowed_tools: ["web.fetch"], denied_tools: []}
    }

    assert {:ok, %{request: with_request}} =
             ModelRuntime.debug_request(with_knowledge, [], %{content: "Find this price"})

    assert {:ok, %{request: without_request}} =
             ModelRuntime.debug_request(without_knowledge, [], %{content: "Find this price"})

    assert %{role: "system", content: with_prompt} = Enum.at(with_request.messages, 0)
    assert %{role: "system", content: without_prompt} = Enum.at(without_request.messages, 0)

    assert String.contains?(with_prompt, "Knowledge Tool Rules:")
    assert String.contains?(with_prompt, "knowledge.search")
    assert String.contains?(with_prompt, "knowledge.read")
    refute String.contains?(without_prompt, "Knowledge Tool Rules:")
    refute String.contains?(without_prompt, "knowledge.search")
    refute String.contains?(without_prompt, "knowledge.read")
  end

  defp manager_target_config(provider_module) do
    %{
      provider_module: provider_module,
      model: "test-model",
      tools_config: %{allowed_tools: [], denied_tools: Enum.map(Catalog.list_tools(), & &1.id)},
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
  end
end
