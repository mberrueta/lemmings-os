defmodule LemmingsOsWeb.InstanceLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.PubSub

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, "Instance Session")
     |> assign(:instance, nil)
     |> assign(:messages, [])
     |> assign(:instance_not_found?, false)}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    {:noreply, load_instance(socket, id, params)}
  end

  @impl true
  def handle_info(
        {:status_changed, %{instance_id: instance_id}},
        %{assigns: %{instance: %{id: instance_id}}} = socket
      ) do
    {:noreply, refresh_instance(socket)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_key={@page_key}
      page_title={@page_title}
      shell_user={@shell_user}
      shell_host={@shell_host}
      shell_breadcrumb={@shell_breadcrumb}
      summary={@summary}
    >
      <.content_container>
        <.panel id="instance-session-page" tone="accent">
          <:title>Instance session</:title>
          <:subtitle>Runtime state and transcript</:subtitle>

          <div :if={@instance} class="space-y-4">
            <div class="flex items-start justify-between gap-4">
              <div class="space-y-1">
                <p class="text-lg font-medium text-zinc-100">{@instance.id}</p>
                <p class="text-sm text-zinc-400">
                  Created {Helpers.format_datetime(@instance.inserted_at, nil_label: "Unknown")}
                </p>
              </div>

              <.status kind={:instance} value={@instance.status} />
            </div>

            <div id="instance-session-transcript" class="grid gap-3">
              <div :for={message <- @messages} class="border-2 border-zinc-800 bg-zinc-950/70 p-4">
                <p class="text-xs font-bold uppercase tracking-widest text-zinc-500">
                  {String.capitalize(message.role)}
                </p>
                <p class="mt-2 whitespace-pre-wrap text-sm text-zinc-100">{message.content}</p>
              </div>
            </div>
          </div>

          <.empty_state
            :if={@instance_not_found?}
            id="instance-session-not-found"
            title="Instance not found"
            copy="The requested runtime session could not be loaded."
          />
        </.panel>
      </.content_container>
    </Layouts.app>
    """
  end

  defp load_instance(socket, id, params) do
    world_id = Map.get(params, "world")

    case LemmingsOs.LemmingInstances.get_instance(id, world_id: world_id) do
      {:ok, instance} ->
        _ = PubSub.subscribe_instance(instance.id)

        socket
        |> assign(:instance, instance)
        |> assign(:messages, LemmingsOs.LemmingInstances.list_messages(instance))
        |> assign(:instance_not_found?, false)
        |> put_shell_breadcrumb([
          shell_item(:lemmings, "/lemmings"),
          shell_item(instance.id, instance_path(instance, world_id))
        ])

      {:error, :not_found} ->
        socket
        |> assign(:instance, nil)
        |> assign(:messages, [])
        |> assign(:instance_not_found?, true)
        |> put_shell_breadcrumb([shell_item(:lemmings, "/lemmings")])
    end
  end

  defp refresh_instance(%{assigns: %{instance: %{id: id}}} = socket) do
    load_instance(socket, id, %{"world" => current_world_id(socket)})
  end

  defp current_world_id(%{assigns: %{instance: %{world_id: world_id}}}), do: world_id
  defp current_world_id(_socket), do: nil

  defp instance_path(%{id: id}, world_id) do
    ~p"/lemmings/instances/#{id}?#{%{world: world_id}}"
  end
end
