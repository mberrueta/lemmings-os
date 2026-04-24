defmodule LemmingsOs.LemmingCalls.PubSub do
  @moduledoc """
  PubSub helpers for durable lemming call lifecycle updates.
  """

  alias LemmingsOs.LemmingCalls.LemmingCall

  @pubsub_server LemmingsOs.PubSub

  @spec call_topic(binary()) :: String.t()
  def call_topic(call_id) when is_binary(call_id) do
    "lemming_call:#{call_id}"
  end

  @spec caller_instance_topic(binary()) :: String.t()
  def caller_instance_topic(instance_id) when is_binary(instance_id) do
    "instance:#{instance_id}:lemming_calls"
  end

  @spec callee_instance_topic(binary()) :: String.t()
  def callee_instance_topic(instance_id) when is_binary(instance_id) do
    "instance:#{instance_id}:lemming_calls"
  end

  @spec subscribe_call(binary()) :: :ok | {:error, term()}
  def subscribe_call(call_id) when is_binary(call_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, call_topic(call_id))
  end

  @spec subscribe_instance_calls(binary()) :: :ok | {:error, term()}
  def subscribe_instance_calls(instance_id) when is_binary(instance_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, caller_instance_topic(instance_id))
  end

  @spec broadcast_call_upserted(LemmingCall.t()) :: :ok
  def broadcast_call_upserted(%LemmingCall{} = call) do
    payload = %{
      lemming_call_id: call.id,
      status: call.status,
      world_id: call.world_id,
      city_id: call.city_id,
      caller_department_id: call.caller_department_id,
      callee_department_id: call.callee_department_id,
      caller_instance_id: call.caller_instance_id,
      callee_instance_id: call.callee_instance_id,
      recovery_status: call.recovery_status
    }

    broadcast_many(topics(call), {:lemming_call_upserted, payload})
  end

  @spec broadcast_status_changed(LemmingCall.t(), String.t() | nil) :: :ok
  def broadcast_status_changed(%LemmingCall{} = call, previous_status) do
    payload = %{
      lemming_call_id: call.id,
      previous_status: previous_status,
      status: call.status,
      world_id: call.world_id,
      city_id: call.city_id,
      caller_department_id: call.caller_department_id,
      callee_department_id: call.callee_department_id,
      caller_instance_id: call.caller_instance_id,
      callee_instance_id: call.callee_instance_id,
      recovery_status: call.recovery_status
    }

    broadcast_many(topics(call), {:lemming_call_status_changed, payload})
  end

  defp topics(%LemmingCall{} = call) do
    [
      call_topic(call.id),
      caller_instance_topic(call.caller_instance_id),
      callee_instance_topic(call.callee_instance_id)
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp broadcast_many(topics, payload) do
    Enum.each(topics, fn topic ->
      Phoenix.PubSub.broadcast(@pubsub_server, topic, payload)
    end)

    :ok
  end
end
