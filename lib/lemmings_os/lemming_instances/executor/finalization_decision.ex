defmodule LemmingsOs.LemmingInstances.Executor.FinalizationDecision do
  @moduledoc """
  Pure decision helpers for finalization repair routing.

  Keeps finalization error-branch decisions explicit while leaving side effects
  to the executor coordinator.
  """

  alias LemmingsOs.Helpers

  @type finalization_action :: :repair | :fail_without_retry | :retry

  @doc """
  Returns whether a model reply should be considered blank.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.blank_reply?("  ")
      true
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.blank_reply?("done")
      false
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.blank_reply?(nil)
      true
  """
  @spec blank_reply?(term()) :: boolean()
  def blank_reply?(reply) when is_binary(reply), do: Helpers.blank?(reply)
  def blank_reply?(_reply), do: true

  @doc """
  Returns whether the reason can be repaired during finalization.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.repairable_reason(:provider_error)
      true
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.repairable_reason(:model_timeout)
      false
  """
  @spec repairable_reason(term()) :: boolean()
  def repairable_reason({:invalid_structured_output, _metadata}), do: true
  def repairable_reason(:invalid_structured_output), do: true
  def repairable_reason({:unknown_action, _metadata}), do: true
  def repairable_reason(:unknown_action), do: true
  def repairable_reason(:provider_error), do: true
  def repairable_reason(:invalid_provider_response), do: true
  def repairable_reason(:unexpected_tool_call_during_finalization), do: true
  def repairable_reason(_reason), do: false

  @doc """
  Decides whether an empty reply during finalization should trigger repair.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.empty_final_reply_action(:finalizing, "   ", false)
      :repair
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.empty_final_reply_action(:finalizing, "ok", false)
      :continue
  """
  @spec empty_final_reply_action(atom(), term(), boolean()) :: :repair | :continue
  def empty_final_reply_action(:finalizing, reply, false) do
    if blank_reply?(reply), do: :repair, else: :continue
  end

  def empty_final_reply_action(_phase, _reply, _repair_attempted?), do: :continue

  @doc """
  Chooses finalization error action based on phase, reason, and repair attempts.

  ## Examples

      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.finalization_action(:finalizing, :provider_error, false)
      :repair
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.finalization_action(:finalizing, :provider_error, true)
      :fail_without_retry
      iex> LemmingsOs.LemmingInstances.Executor.FinalizationDecision.finalization_action(:action_selection, :provider_error, false)
      :retry
  """
  @spec finalization_action(atom(), term(), boolean()) :: finalization_action()
  def finalization_action(:finalizing, reason, repair_attempted?) do
    cond do
      repairable_reason(reason) and not repair_attempted? ->
        :repair

      repairable_reason(reason) ->
        :fail_without_retry

      true ->
        :retry
    end
  end

  def finalization_action(_phase, _reason, _repair_attempted?), do: :retry
end
