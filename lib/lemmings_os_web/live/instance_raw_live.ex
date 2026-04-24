defmodule LemmingsOsWeb.InstanceRawLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOsWeb.PageData.InstanceRawSnapshot
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("lemmings", "Instance Raw Context"))
     |> assign(
       world: nil,
       instance: nil,
       runtime_state: nil,
       model_steps: [],
       delegation_state: nil,
       interaction_timeline: [],
       interaction_timeline_source: nil,
       model_request: nil,
       model_request_source: nil,
       subscribed_instance_id: nil,
       instance_not_found?: false,
       parent_lemming_path: nil,
       session_path: nil,
       shell_breadcrumb: default_shell_breadcrumb(:lemmings)
     )}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    {:noreply, load_instance(socket, id, params)}
  end

  @impl true
  def handle_info({:message_appended, %{instance_id: instance_id}}, socket) do
    {:noreply, maybe_reload_instance(socket, instance_id)}
  end

  @impl true
  def handle_info({:tool_execution_upserted, %{instance_id: instance_id}}, socket) do
    {:noreply, maybe_reload_instance(socket, instance_id)}
  end

  @impl true
  def handle_info({:model_step_upserted, %{instance_id: instance_id}}, socket) do
    {:noreply, maybe_reload_instance(socket, instance_id)}
  end

  @impl true
  def handle_info({:status_changed, %{instance_id: instance_id}}, socket) do
    {:noreply, maybe_reload_instance(socket, instance_id)}
  end

  defp load_instance(socket, id, params) do
    case resolve_world(params) do
      %World{} = world -> load_world_instance(socket, id, world)
      nil -> assign_not_found(socket)
    end
  end

  defp load_world_instance(socket, id, world) do
    case InstanceRawSnapshot.build(instance_id: id, world: world) do
      {:ok, snapshot} ->
        session_path = ~p"/lemmings/instances/#{snapshot.instance.id}?#{%{world: world.id}}"
        raw_path = ~p"/lemmings/instances/#{snapshot.instance.id}/raw?#{%{world: world.id}}"

        socket
        |> maybe_subscribe_instance(snapshot.instance)
        |> assign(
          world: world,
          instance: snapshot.instance,
          runtime_state: snapshot.runtime_state,
          model_steps: snapshot.model_steps,
          delegation_state: snapshot.delegation_state,
          interaction_timeline: snapshot.interaction_timeline,
          interaction_timeline_source: snapshot.interaction_timeline_source,
          model_request: snapshot.model_request,
          model_request_source: snapshot.model_request_source,
          instance_not_found?: false,
          parent_lemming_path: parent_lemming_path(snapshot.instance),
          session_path: session_path,
          shell_breadcrumb: build_shell_breadcrumb(snapshot.instance, session_path, raw_path)
        )

      {:error, :not_found} ->
        assign_not_found(socket)
    end
  end

  defp interaction_timeline_source_copy(:live_executor_trace) do
    "Source: live executor trace"
  end

  defp interaction_timeline_source_copy(:persisted_history_only) do
    "Source: persisted transcript/tool history only"
  end

  defp interaction_timeline_source_copy(_source) do
    "Source: unavailable"
  end

  defp model_request_source_copy(:live_executor_trace) do
    "Source: exact latest live request"
  end

  defp model_request_source_copy(:runtime_state) do
    "Source: live executor snapshot"
  end

  defp model_request_source_copy(:transcript_reconstruction) do
    "Source: reconstructed from persisted transcript"
  end

  defp model_request_source_copy(_source) do
    "Source: unavailable"
  end

  defp timeline_timestamp(nil), do: nil
  defp timeline_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%H:%M:%S")

  defp timeline_entry_status_class("ok"),
    do: "border-emerald-400/40 bg-emerald-400/10 text-emerald-200"

  defp timeline_entry_status_class("error"),
    do: "border-rose-400/40 bg-rose-400/10 text-rose-200"

  defp timeline_entry_status_class("running"),
    do: "border-amber-300/40 bg-amber-300/10 text-amber-100"

  defp timeline_entry_status_class(_status), do: "border-zinc-700 bg-zinc-900 text-zinc-300"

  defp resolve_world(%{"world" => world_id}) when is_binary(world_id) and world_id != "" do
    Worlds.get_world(world_id)
  end

  defp resolve_world(_params), do: Worlds.get_default_world()

  defp maybe_subscribe_instance(socket, instance) do
    connected? = connected?(socket)
    subscribed_instance_id = socket.assigns.subscribed_instance_id

    if connected? and subscribed_instance_id != instance.id do
      :ok = PubSub.subscribe_instance(instance.id)
      :ok = PubSub.subscribe_instance_messages(instance.id)
      assign(socket, subscribed_instance_id: instance.id)
    else
      socket
    end
  end

  defp maybe_reload_instance(
         %{assigns: %{instance: %{id: instance_id}, world: world}} = socket,
         instance_id
       )
       when is_struct(world, World) do
    load_world_instance(socket, instance_id, world)
  end

  defp maybe_reload_instance(socket, _instance_id), do: socket

  defp assign_not_found(socket) do
    assign(socket,
      world: nil,
      instance: nil,
      runtime_state: nil,
      model_steps: [],
      delegation_state: nil,
      interaction_timeline: [],
      interaction_timeline_source: nil,
      model_request: nil,
      model_request_source: nil,
      subscribed_instance_id: nil,
      instance_not_found?: true,
      parent_lemming_path: nil,
      session_path: nil,
      shell_breadcrumb: default_shell_breadcrumb(:lemmings)
    )
  end

  defp build_shell_breadcrumb(instance, session_path, raw_path) do
    [
      shell_item(:lemmings, "/lemmings"),
      shell_item(parent_lemming_name(instance), parent_lemming_path(instance)),
      shell_item(instance.id, session_path),
      shell_item(dgettext("lemmings", "Raw Context"), raw_path)
    ]
  end

  defp parent_lemming_path(%{lemming_id: lemming_id}) when is_binary(lemming_id),
    do: ~p"/lemmings/#{lemming_id}"

  defp parent_lemming_path(_instance), do: ~p"/lemmings"

  defp parent_lemming_name(%{lemming: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp parent_lemming_name(%{lemming: %{id: id}}) when is_binary(id), do: id
  defp parent_lemming_name(%{lemming_id: lemming_id}) when is_binary(lemming_id), do: lemming_id
  defp parent_lemming_name(_instance), do: dgettext("world", ".label_not_available")

  defp json_payload(nil), do: "{}"
  defp json_payload(payload), do: Jason.encode!(payload, pretty: true)
end
