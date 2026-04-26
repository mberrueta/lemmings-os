defmodule LemmingsOs.LemmingInstances.Executor.ModelStepRuntimeTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.ModelStepRuntime
  alias LemmingsOs.ModelRuntime.Response

  doctest ModelStepRuntime

  test "route_model_result/2 routes reply, tool_call, and lemming_call actions" do
    reply =
      Response.new(
        action: :reply,
        reply: "done",
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    tool_call =
      Response.new(
        action: :tool_call,
        tool_name: "web.fetch",
        tool_args: %{"url" => "https://example.com"},
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    lemming_call =
      Response.new(
        action: :lemming_call,
        lemming_target: "ops-worker",
        lemming_request: "Draft notes",
        continue_call_id: nil,
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    base_state = %{phase: :action_selection, finalization_repair_attempted?: false}

    assert {:reply, ^reply} = ModelStepRuntime.route_model_result(base_state, {:ok, reply})

    assert {:tool_call, ^tool_call} =
             ModelStepRuntime.route_model_result(base_state, {:ok, tool_call})

    assert {:lemming_call, ^lemming_call} =
             ModelStepRuntime.route_model_result(base_state, {:ok, lemming_call})
  end

  test "route_model_result/2 marks repair paths and unexpected paths" do
    blank_reply =
      Response.new(
        action: :reply,
        reply: "   ",
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    tool_call =
      Response.new(
        action: :tool_call,
        tool_name: "web.fetch",
        tool_args: %{"url" => "https://example.com"},
        provider: "fake",
        model: "fake-model",
        raw: %{}
      )

    finalizing_state = %{phase: :finalizing, finalization_repair_attempted?: false}

    assert :reply_repair =
             ModelStepRuntime.route_model_result(finalizing_state, {:ok, blank_reply})

    assert :tool_call_during_finalization =
             ModelStepRuntime.route_model_result(finalizing_state, {:ok, tool_call})

    assert {:error, :model_timeout} =
             ModelStepRuntime.route_model_result(finalizing_state, {:error, :model_timeout})

    assert :unexpected_model_result =
             ModelStepRuntime.route_model_result(finalizing_state, :bad_value)
  end
end
