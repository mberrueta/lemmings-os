defmodule LemmingsOs.LemmingInstances.PubSub do
  @moduledoc """
  PubSub helpers for runtime signals between instance executors, schedulers,
  and session views.

  This module is intentionally stateless. It centralizes topic construction,
  subscriptions, and broadcast payload shapes while using the existing
  `LemmingsOs.PubSub` server.
  """

  @pubsub_server LemmingsOs.PubSub

  @doc """
  Builds the Department scheduler topic for a department ID.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.scheduler_topic("dept-1")
      "department:dept-1:scheduler"
  """
  @spec scheduler_topic(binary()) :: String.t()
  def scheduler_topic(department_id) when is_binary(department_id) do
    "department:#{department_id}:scheduler"
  end

  @doc """
  Builds the instance status topic for an instance ID.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.instance_topic("instance-1")
      "instance:instance-1:status"
  """
  @spec instance_topic(binary()) :: String.t()
  def instance_topic(instance_id) when is_binary(instance_id) do
    "instance:#{instance_id}:status"
  end

  @doc """
  Builds the instance transcript topic for an instance ID.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.instance_messages_topic("instance-1")
      "instance:instance-1:messages"
  """
  @spec instance_messages_topic(binary()) :: String.t()
  def instance_messages_topic(instance_id) when is_binary(instance_id) do
    "instance:#{instance_id}:messages"
  end

  @doc """
  Builds the global capacity topic used to wake schedulers after releases.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.capacity_topic()
      "runtime:capacity"
  """
  @spec capacity_topic() :: String.t()
  def capacity_topic, do: "runtime:capacity"

  @doc """
  Subscribes the caller to a Department scheduler topic.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.subscribe_scheduler("dept-1")
      :ok
  """
  @spec subscribe_scheduler(binary()) :: :ok | {:error, term()}
  def subscribe_scheduler(department_id) when is_binary(department_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, scheduler_topic(department_id))
  end

  @doc """
  Subscribes the caller to an instance status topic.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.subscribe_instance("instance-1")
      :ok
  """
  @spec subscribe_instance(binary()) :: :ok | {:error, term()}
  def subscribe_instance(instance_id) when is_binary(instance_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, instance_topic(instance_id))
  end

  @doc """
  Subscribes the caller to an instance transcript topic.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.subscribe_instance_messages("instance-1")
      :ok
  """
  @spec subscribe_instance_messages(binary()) :: :ok | {:error, term()}
  def subscribe_instance_messages(instance_id) when is_binary(instance_id) do
    Phoenix.PubSub.subscribe(@pubsub_server, instance_messages_topic(instance_id))
  end

  @doc """
  Subscribes the caller to global capacity release notifications.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.subscribe_capacity()
      :ok
  """
  @spec subscribe_capacity() :: :ok | {:error, term()}
  def subscribe_capacity do
    Phoenix.PubSub.subscribe(@pubsub_server, capacity_topic())
  end

  @doc """
  Broadcasts that work is available for a department.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.broadcast_work_available("dept-1")
      :ok
  """
  @spec broadcast_work_available(binary()) :: :ok | {:error, term()}
  def broadcast_work_available(department_id) when is_binary(department_id) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      scheduler_topic(department_id),
      {:work_available, %{department_id: department_id}}
    )
  end

  @doc """
  Broadcasts that capacity was released for a department/resource pair.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.broadcast_capacity_released("dept-1", "ollama:llama3.2")
      :ok
  """
  @spec broadcast_capacity_released(binary(), binary()) :: :ok | {:error, term()}
  def broadcast_capacity_released(department_id, resource_key)
      when is_binary(department_id) and is_binary(resource_key) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      scheduler_topic(department_id),
      {:capacity_released, %{department_id: department_id, resource_key: resource_key}}
    )
  end

  @doc """
  Broadcasts that capacity was released for a resource key globally.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.broadcast_capacity_released("ollama:llama3.2")
      :ok
  """
  @spec broadcast_capacity_released(binary()) :: :ok | {:error, term()}
  def broadcast_capacity_released(resource_key) when is_binary(resource_key) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      capacity_topic(),
      {:capacity_released, %{resource_key: resource_key}}
    )
  end

  @doc """
  Broadcasts a status change for a runtime instance.

  The `metadata` map is optional and should stay small.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.broadcast_status_change("instance-1", "queued")
      :ok
  """
  @spec broadcast_status_change(binary(), binary(), map()) :: :ok | {:error, term()}
  def broadcast_status_change(instance_id, status, metadata \\ %{})
      when is_binary(instance_id) and is_binary(status) and is_map(metadata) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      instance_topic(instance_id),
      {:status_changed, %{instance_id: instance_id, status: status, metadata: metadata}}
    )
  end

  @doc """
  Broadcasts that a new transcript message has been appended for an instance.
  """
  @spec broadcast_message_appended(binary(), binary(), binary()) :: :ok | {:error, term()}
  def broadcast_message_appended(instance_id, message_id, role)
      when is_binary(instance_id) and is_binary(message_id) and is_binary(role) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      instance_messages_topic(instance_id),
      {:message_appended, %{instance_id: instance_id, message_id: message_id, role: role}}
    )
  end

  @doc """
  Broadcasts that a tool execution lifecycle row was created or updated.
  """
  @spec broadcast_tool_execution_upserted(binary(), binary(), binary()) :: :ok | {:error, term()}
  def broadcast_tool_execution_upserted(instance_id, tool_execution_id, status)
      when is_binary(instance_id) and is_binary(tool_execution_id) and is_binary(status) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      instance_messages_topic(instance_id),
      {:tool_execution_upserted,
       %{instance_id: instance_id, tool_execution_id: tool_execution_id, status: status}}
    )
  end

  @doc """
  Broadcasts a scheduler admission signal to an executor.

  ## Examples

      iex> LemmingsOs.LemmingInstances.PubSub.broadcast_scheduler_admit("dept-1", "instance-1")
      :ok
  """
  @spec broadcast_scheduler_admit(binary(), binary()) :: :ok | {:error, term()}
  def broadcast_scheduler_admit(department_id, instance_id)
      when is_binary(department_id) and is_binary(instance_id) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      scheduler_topic(department_id),
      {:scheduler_admit, %{department_id: department_id, instance_id: instance_id}}
    )
  end

  @doc """
  Broadcasts a scheduler admission signal with the resolved resource key.
  """
  @spec broadcast_scheduler_admit(binary(), binary(), binary()) :: :ok | {:error, term()}
  def broadcast_scheduler_admit(department_id, instance_id, resource_key)
      when is_binary(department_id) and is_binary(instance_id) and is_binary(resource_key) do
    Phoenix.PubSub.broadcast(
      @pubsub_server,
      scheduler_topic(department_id),
      {:scheduler_admit,
       %{department_id: department_id, instance_id: instance_id, resource_key: resource_key}}
    )
  end
end
