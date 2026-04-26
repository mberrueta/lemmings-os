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
end
