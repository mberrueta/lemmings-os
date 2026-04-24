defmodule LemmingsOs.ModelRuntime.ResponseTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.ModelRuntime.Response

  test "S01: builds a response struct from attrs" do
    response =
      Response.new(
        action: :reply,
        reply: "hello",
        provider: "ollama",
        model: "llama3.2",
        raw: %{content: "ok"}
      )

    assert response.reply == "hello"
    assert response.provider == "ollama"
    assert response.model == "llama3.2"
    assert response.raw == %{content: "ok"}
  end

  test "S02: builds a lemming_call response struct" do
    response =
      Response.new(
        action: :lemming_call,
        lemming_target: "researcher",
        lemming_request: "Find risks",
        continue_call_id: nil,
        provider: "ollama",
        model: "llama3.2",
        raw: %{}
      )

    assert response.action == :lemming_call
    assert response.lemming_target == "researcher"
    assert response.lemming_request == "Find risks"
  end
end
