defmodule LemmingsOs.LemmingInstances.Executor.ModelStepPayloadTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.ModelStepPayload
  alias LemmingsOs.ModelRuntime.Response

  test "sanitize_json_map/1 normalizes maps, structs, tuples, and atoms" do
    input = %{
      atom_key: :ok,
      tuple: {:a, 1},
      nested: %{now: ~N[2026-01-01 00:00:00]},
      struct: Response.new(action: :reply, provider: "fake", model: "m", raw: %{}, reply: "hi")
    }

    sanitized = ModelStepPayload.sanitize_json_map(input)

    assert sanitized["atom_key"] == "ok"
    assert sanitized["tuple"] == %{"tuple" => ["a", 1]}
    assert sanitized["nested"]["now"] == "2026-01-01T00:00:00"
    assert sanitized["struct"]["action"] == "reply"
    assert sanitized["struct"]["provider"] == "fake"
  end

  test "sanitize_json_map/1 redacts secrets and local paths and caps large strings" do
    oversized = String.duplicate("x", 16_010)

    sanitized =
      ModelStepPayload.sanitize_json_map(%{
        token: "super-secret",
        output:
          "Bearer abc123 path=/home/matt/project/.env api_key=abc123 " <>
            oversized
      })

    assert sanitized["token"] == "[REDACTED]"
    assert sanitized["output"] =~ "Bearer [REDACTED]"
    assert sanitized["output"] =~ "api_key=[REDACTED]"
    assert sanitized["output"] =~ "<local-path>"
    assert sanitized["output"] =~ "[TRUNCATED "
  end

  test "model_step_result_attrs/3 returns ok payload for reply actions" do
    response =
      Response.new(
        action: :reply,
        reply: "done",
        provider: "fake",
        model: "model-x",
        total_tokens: 42,
        raw: %{content: "{\"action\":\"reply\",\"reply\":\"done\"}"}
      )

    completed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = ModelStepPayload.model_step_result_attrs({:ok, response}, completed_at, 7)

    assert attrs.status == "ok"
    assert attrs.provider == "fake"
    assert attrs.model == "model-x"
    assert attrs.total_tokens == 42
    assert attrs.parsed_output == %{"action" => "reply", "reply" => "done"}
    assert attrs.duration_ms == 7
    assert attrs.completed_at == completed_at
  end

  test "model_step_result_attrs/3 stores unified tool_call and lemming_call parsed_output shapes" do
    completed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    tool_response =
      Response.new(
        action: :tool_call,
        tool_name: "fs.write_text_file",
        tool_args: %{"path" => "quote.md", "content" => "hello"},
        provider: "fake",
        model: "model-x",
        raw: %{}
      )

    lemming_response =
      Response.new(
        action: :lemming_call,
        lemming_target: "sales_web_researcher",
        lemming_request: "Find current USD/BRL exchange rate.",
        provider: "fake",
        model: "model-x",
        raw: %{}
      )

    tool_attrs = ModelStepPayload.model_step_result_attrs({:ok, tool_response}, completed_at, 2)

    assert tool_attrs.parsed_output == %{
             "action" => "tool_call",
             "target" => "fs.write_text_file",
             "args" => %{"path" => "quote.md", "content" => "hello"}
           }

    lemming_attrs =
      ModelStepPayload.model_step_result_attrs({:ok, lemming_response}, completed_at, 3)

    assert lemming_attrs.parsed_output == %{
             "action" => "lemming_call",
             "target" => "sales_web_researcher",
             "args" => %{"request" => "Find current USD/BRL exchange rate."}
           }
  end

  test "model_step_result_attrs/3 preserves invalid structured output diagnostics" do
    reason =
      {:invalid_structured_output,
       %{
         provider: "fake",
         model: "broken-model",
         content: "not-json",
         raw: %{content: "not-json", provider: "fake", model: "broken-model"}
       }}

    completed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = ModelStepPayload.model_step_result_attrs({:error, reason}, completed_at, 5)

    assert attrs.status == "error"
    assert attrs.provider == "fake"
    assert attrs.model == "broken-model"

    assert attrs.response_payload == %{
             "content" => "not-json",
             "provider" => "fake",
             "model" => "broken-model"
           }

    assert attrs.error["kind"] == "invalid_structured_output"
    assert attrs.error["content"] == "not-json"
    assert attrs.duration_ms == 5
    assert attrs.completed_at == completed_at
  end

  test "model_step_result_attrs/3 preserves structured provider failure diagnostics" do
    reason =
      {:provider_invalid_response,
       %{
         provider: "fake",
         model: "broken-model",
         reason: "missing_content",
         raw: %{provider: "fake", model: "broken-model", token: "secret-value"}
       }}

    completed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = ModelStepPayload.model_step_result_attrs({:error, reason}, completed_at, 5)

    assert attrs.status == "error"
    assert attrs.provider == "fake"
    assert attrs.model == "broken-model"
    assert attrs.error["kind"] == "provider_invalid_response"
    assert attrs.error["reason"] == "missing_content"
    assert attrs.response_payload["provider"] == "fake"
    assert attrs.response_payload["token"] == "[REDACTED]"
  end
end
