defmodule LemmingsOs.LemmingInstances.Executor.TransitionsData do
  @moduledoc """
  Pure helpers for executor transition/error data shaping.
  """

  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.LemmingInstances.Executor.ModelStepPayload
  alias LemmingsOs.LemmingInstances.Telemetry

  @doc """
  Returns the user-facing runtime error message for an internal reason.
  """
  @spec last_error_message(term()) :: binary()
  def last_error_message(:provider_error),
    do: dgettext("errors", "Model request failed. Retry or inspect logs.")

  def last_error_message({:assistant_message_persist_failed, _reason}),
    do: dgettext("errors", "Assistant response could not be persisted. Retry or inspect logs.")

  def last_error_message({:provider_http_error, %{provider: provider} = metadata}) do
    provider_label = provider_label(provider)
    status_copy = provider_status_copy(metadata)

    dgettext("errors", "%{provider} request failed%{status_copy}. Retry or inspect logs.",
      provider: provider_label,
      status_copy: status_copy
    )
  end

  def last_error_message({:provider_timeout, %{provider: provider}}),
    do:
      dgettext("errors", "%{provider} request timed out. Retry or inspect logs.",
        provider: provider_label(provider)
      )

  def last_error_message({:provider_network_error, %{provider: provider}}),
    do:
      dgettext("errors", "%{provider} request failed. Retry or inspect logs.",
        provider: provider_label(provider)
      )

  def last_error_message({:provider_invalid_response, %{provider: provider}}),
    do:
      dgettext("errors", "%{provider} returned an invalid response. Retry or inspect logs.",
        provider: provider_label(provider)
      )

  def last_error_message(:network_error),
    do: dgettext("errors", "Model provider request failed due to a network error.")

  def last_error_message(:timeout),
    do: dgettext("errors", "Model provider request timed out.")

  def last_error_message(:invalid_structured_output),
    do: dgettext("errors", "Model returned invalid structured output.")

  def last_error_message({:invalid_structured_output, _metadata}),
    do: dgettext("errors", "Model returned invalid structured output.")

  def last_error_message(:unknown_action),
    do: dgettext("errors", "Model returned an unsupported action.")

  def last_error_message({:unknown_action, _metadata}),
    do: dgettext("errors", "Model returned an unsupported action.")

  def last_error_message(:missing_model),
    do: dgettext("errors", "Runtime config is missing a model.")

  def last_error_message(:unsupported_provider),
    do: dgettext("errors", "Runtime config uses an unsupported provider.")

  def last_error_message(:model_runtime_unavailable),
    do: dgettext("errors", "Model runtime is unavailable.")

  def last_error_message(:model_crash),
    do: dgettext("errors", "Executor model task crashed.")

  def last_error_message(:model_timeout),
    do: dgettext("errors", "Executor model task timed out.")

  def last_error_message(:invalid_provider_response),
    do: dgettext("errors", "Model provider returned an invalid response payload.")

  def last_error_message(:tool_execution_unavailable),
    do: dgettext("errors", "Tool execution persistence is unavailable.")

  def last_error_message({:tool_execution_create_failed, _reason}),
    do: dgettext("errors", "Tool execution could not be persisted.")

  def last_error_message({:tool_execution_update_failed, _reason}),
    do: dgettext("errors", "Tool execution could not be updated.")

  def last_error_message(:tool_iteration_limit_reached),
    do: dgettext("errors", "Tool iteration limit reached before final reply.")

  def last_error_message(:invalid_world_scope),
    do: dgettext("errors", "Runtime world scope is invalid.")

  def last_error_message(:unexpected_model_result),
    do: dgettext("errors", "Executor received an unexpected model result.")

  def last_error_message(reason) when is_atom(reason),
    do: dgettext("errors", "Runtime error: %{reason}.", reason: Atom.to_string(reason))

  def last_error_message(_reason), do: dgettext("errors", "Runtime error. Retry or inspect logs.")

  @doc """
  Returns internal error details payload for diagnostics.
  """
  @spec internal_error_details(term()) :: map() | binary()
  def internal_error_details({:provider_http_error, metadata}) when is_map(metadata) do
    Map.put(metadata, :kind, :provider_http_error)
  end

  def internal_error_details({:provider_timeout, metadata}) when is_map(metadata) do
    Map.put(metadata, :kind, :provider_timeout)
  end

  def internal_error_details({:provider_network_error, metadata}) when is_map(metadata) do
    Map.put(metadata, :kind, :provider_network_error)
  end

  def internal_error_details({:provider_invalid_response, metadata}) when is_map(metadata) do
    Map.put(metadata, :kind, :provider_invalid_response)
  end

  def internal_error_details({:invalid_structured_output, metadata}) when is_map(metadata) do
    metadata
    |> ModelStepPayload.sanitize_json_map()
    |> Map.put("kind", "invalid_structured_output")
  end

  def internal_error_details({:unknown_action, metadata}) when is_map(metadata) do
    metadata
    |> ModelStepPayload.sanitize_json_map()
    |> Map.put("kind", "unknown_action")
  end

  def internal_error_details({:assistant_message_persist_failed, reason}) do
    %{kind: :assistant_message_persist_failed, reason: inspect(reason)}
  end

  def internal_error_details({:tool_execution_create_failed, reason}) do
    %{kind: :tool_execution_create_failed, reason: inspect(reason)}
  end

  def internal_error_details({:tool_execution_update_failed, reason}) do
    %{kind: :tool_execution_update_failed, reason: inspect(reason)}
  end

  def internal_error_details(reason) when is_atom(reason), do: %{kind: reason}
  def internal_error_details(reason), do: inspect(reason)

  @doc """
  Maps transition status to telemetry atom.
  """
  @spec status_atom(binary(), map()) :: atom()
  def status_atom(status, status_atoms) when is_binary(status) and is_map(status_atoms) do
    Map.fetch!(status_atoms, status)
  end

  @doc """
  Returns transition log level for target status.
  """
  @spec transition_log_level(binary()) :: :info | :warning | :error
  def transition_log_level("retrying"), do: :warning
  def transition_log_level("failed"), do: :error
  def transition_log_level(_status), do: :info

  @doc """
  Returns normalized transition reason token for telemetry/logging.
  """
  @spec transition_reason(map(), binary()) :: binary() | nil
  def transition_reason(state, "retrying"),
    do: Telemetry.reason_token(Map.get(state, :last_error))

  def transition_reason(state, "failed"), do: Telemetry.reason_token(Map.get(state, :last_error))
  def transition_reason(_state, _status), do: nil

  @doc """
  Returns transition telemetry measurements.
  """
  @spec transition_measurements(map(), binary()) :: map()
  def transition_measurements(state, "processing") do
    %{count: 1, duration_ms: current_item_wait_ms(state)}
  end

  def transition_measurements(_state, _status), do: %{count: 1}

  defp current_item_wait_ms(%{
         current_item: %{inserted_at: %DateTime{} = inserted_at},
         now_fun: now_fun
       }) do
    DateTime.diff(now_fun.(), inserted_at, :millisecond)
  end

  defp current_item_wait_ms(_state), do: 0

  defp provider_label(provider) when is_binary(provider) and provider != "", do: provider
  defp provider_label(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_label(_provider), do: "model"

  defp provider_status_copy(%{status: status}) when is_integer(status), do: " (HTTP #{status})"
  defp provider_status_copy(_metadata), do: ""
end
