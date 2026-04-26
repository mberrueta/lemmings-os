defmodule LemmingsOs.LemmingInstances.Executor.ModelStepRuntime do
  @moduledoc """
  Pure model-result routing for executor runtime.

  This module converts model outputs into explicit action tokens for `Executor`
  to execute. No process lifecycle or external side effects are owned here.

  It is an internal decision helper used by `Executor`.
  """

  alias LemmingsOs.LemmingInstances.Executor.FinalizationDecision
  alias LemmingsOs.ModelRuntime.Response

  @type route_action ::
          {:reply, Response.t()}
          | :reply_repair
          | :tool_call_during_finalization
          | {:tool_call, Response.t()}
          | {:lemming_call, Response.t()}
          | {:error, term()}
          | :invalid_provider_response
          | :unexpected_model_result

  @doc """
  Routes a model result into an executor action token.

  ## Examples

      iex> response =
      ...>   LemmingsOs.ModelRuntime.Response.new(
      ...>     action: :reply,
      ...>     reply: "ok",
      ...>     provider: "fake",
      ...>     model: "fake-model",
      ...>     raw: %{}
      ...>   )
      iex> state = %{phase: :action_selection, finalization_repair_attempted?: false}
      iex> LemmingsOs.LemmingInstances.Executor.ModelStepRuntime.route_model_result(state, {:ok, response})
      {:reply, response}
  """
  @spec route_model_result(map(), term()) :: route_action()
  def route_model_result(
        %{phase: phase, finalization_repair_attempted?: repair_attempted?},
        {:ok, %Response{action: :reply} = response}
      ) do
    case FinalizationDecision.empty_final_reply_action(phase, response.reply, repair_attempted?) do
      :repair -> :reply_repair
      :continue -> {:reply, response}
    end
  end

  def route_model_result(%{phase: :finalizing}, {:ok, %Response{action: :tool_call}}),
    do: :tool_call_during_finalization

  def route_model_result(_state, {:ok, %Response{action: :tool_call} = response}),
    do: {:tool_call, response}

  def route_model_result(_state, {:ok, %Response{action: :lemming_call} = response}),
    do: {:lemming_call, response}

  def route_model_result(_state, {:ok, %Response{}}), do: :invalid_provider_response
  def route_model_result(_state, {:error, reason}), do: {:error, reason}
  def route_model_result(_state, _unexpected), do: :unexpected_model_result
end
