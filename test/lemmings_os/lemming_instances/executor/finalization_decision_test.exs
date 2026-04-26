defmodule LemmingsOs.LemmingInstances.Executor.FinalizationDecisionTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.LemmingInstances.Executor.FinalizationDecision

  doctest FinalizationDecision

  test "empty_final_reply_action/3 only repairs blank replies in finalizing phase without prior repair" do
    assert :repair = FinalizationDecision.empty_final_reply_action(:finalizing, "   ", false)
    assert :continue = FinalizationDecision.empty_final_reply_action(:finalizing, "ok", false)
    assert :continue = FinalizationDecision.empty_final_reply_action(:finalizing, "   ", true)

    assert :continue =
             FinalizationDecision.empty_final_reply_action(:action_selection, "   ", false)
  end

  test "finalization_action/3 routes repairable and non-repairable errors correctly" do
    assert :repair =
             FinalizationDecision.finalization_action(:finalizing, :provider_error, false)

    assert :fail_without_retry =
             FinalizationDecision.finalization_action(:finalizing, :provider_error, true)

    assert :retry =
             FinalizationDecision.finalization_action(:finalizing, :model_timeout, false)

    assert :retry =
             FinalizationDecision.finalization_action(:action_selection, :provider_error, false)
  end
end
