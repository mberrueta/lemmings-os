defmodule LemmingsOs.LemmingInstances.Executor.TransitionsDataTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.TransitionsData

  test "last_error_message/1 returns sanitized provider http copy" do
    assert TransitionsData.last_error_message(
             {:provider_http_error, %{provider: "ollama", status: 500}}
           ) ==
             "ollama request failed (HTTP 500). Retry or inspect logs."
  end

  test "internal_error_details/1 includes kind and sanitized metadata for structured output errors" do
    details =
      TransitionsData.internal_error_details(
        {:invalid_structured_output, %{provider: "fake", raw: %{content: "not-json"}}}
      )

    assert details["kind"] == "invalid_structured_output"
    assert details["provider"] == "fake"
    assert details["raw"]["content"] == "not-json"
  end

  test "status_atom/2 maps known statuses" do
    assert TransitionsData.status_atom("queued", %{"queued" => :queued}) == :queued
  end

  test "transition helpers return expected levels, reasons, and measurements" do
    now = ~U[2026-04-25 12:00:00Z]

    state = %{
      last_error: :model_timeout,
      current_item: %{inserted_at: DateTime.add(now, -50, :millisecond)},
      now_fun: fn -> now end
    }

    assert TransitionsData.transition_log_level("retrying") == :warning
    assert TransitionsData.transition_log_level("failed") == :error
    assert TransitionsData.transition_log_level("idle") == :info

    assert TransitionsData.transition_reason(state, "failed") == "model_timeout"
    assert TransitionsData.transition_reason(state, "idle") == nil

    assert TransitionsData.transition_measurements(state, "processing") == %{
             count: 1,
             duration_ms: 50
           }

    assert TransitionsData.transition_measurements(state, "idle") == %{count: 1}
  end
end
