defmodule LemmingsOsWeb.InstanceLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.Helpers
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @status_tick_interval 1_000
  @default_max_retries 3

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign_shell(:lemmings, dgettext("lemmings", "Instance Session"))
      |> assign(:world, nil)
      |> assign(:instance, nil)
      |> assign(:runtime_state, fallback_runtime_state())
      |> assign(:message_count, 0)
      |> assign(:status_now, DateTime.utc_now() |> DateTime.truncate(:second))
      |> assign(:parent_lemming_path, nil)
      |> assign(:waiting_for_first_response?, false)
      |> assign(:instance_not_found?, false)
      |> assign(:follow_up_form, follow_up_form(%{}))
      |> assign(:follow_up_submit_disabled?, true)
      |> assign(:follow_up_error, nil)
      |> assign(:status_tick_ref, nil)
      |> stream(:messages, [], reset: true)

    if connected?(socket) and is_binary(params["id"]) do
      _ = PubSub.subscribe_instance(params["id"])
      _ = PubSub.subscribe_instance_messages(params["id"])
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    {:noreply, load_instance(socket, id, params)}
  end

  @impl true
  def handle_info(
        :status_tick,
        %{assigns: %{instance: %{status: status}}} = socket
      )
      when status in ["processing", "retrying", "idle"] do
    socket =
      socket
      |> assign(:status_now, DateTime.utc_now() |> DateTime.truncate(:second))
      |> schedule_status_tick()

    {:noreply, socket}
  end

  def handle_info(:status_tick, socket) do
    {:noreply, cancel_status_tick(socket)}
  end

  @impl true
  def handle_info(
        {:status_changed, %{instance_id: instance_id}},
        %{assigns: %{instance: %{id: instance_id}}} = socket
      ) do
    {:noreply, load_instance(socket, instance_id, %{"world" => current_world_id(socket)})}
  end

  def handle_info(
        {:message_appended, %{instance_id: instance_id}},
        %{assigns: %{instance: %{id: instance_id}}} = socket
      ) do
    {:noreply, load_instance(socket, instance_id, %{"world" => current_world_id(socket)})}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_follow_up_request", %{"follow_up_request" => params}, socket) do
    request_text = Map.get(params, "request_text", "")

    {:noreply,
     socket
     |> assign(:follow_up_form, follow_up_form(params, :validate))
     |> assign(:follow_up_submit_disabled?, Helpers.blank?(request_text))
     |> assign(:follow_up_error, nil)}
  end

  def handle_event("submit_follow_up_request", %{"follow_up_request" => params}, socket) do
    request_text = Map.get(params, "request_text", "")
    form = follow_up_form(params, :validate)

    cond do
      Helpers.blank?(request_text) ->
        {:noreply,
         socket
         |> assign(:follow_up_form, form)
         |> assign(:follow_up_submit_disabled?, true)
         |> assign(:follow_up_error, nil)}

      match?(%{status: "failed"}, socket.assigns.instance) ->
        {:noreply,
         socket
         |> assign(:follow_up_form, form)
         |> assign(:follow_up_submit_disabled?, true)
         |> assign(:follow_up_error, follow_up_terminal_error("failed"))}

      match?(%{status: "expired"}, socket.assigns.instance) ->
        {:noreply,
         socket
         |> assign(:follow_up_form, form)
         |> assign(:follow_up_submit_disabled?, true)
         |> assign(:follow_up_error, follow_up_terminal_error("expired"))}

      true ->
        case LemmingInstances.enqueue_work(socket.assigns.instance, request_text, []) do
          {:ok, _instance} ->
            socket =
              socket
              |> assign(:follow_up_form, follow_up_form(%{}))
              |> assign(:follow_up_submit_disabled?, true)
              |> assign(:follow_up_error, nil)
              |> load_instance(socket.assigns.instance.id, %{"world" => current_world_id(socket)})

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:follow_up_form, form)
             |> assign(:follow_up_submit_disabled?, Helpers.blank?(request_text))
             |> assign(:follow_up_error, follow_up_error(reason))}
        end
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp load_instance(socket, id, params) do
    case resolve_world(params) do
      %World{} = world ->
        case LemmingInstances.get_instance(id, world: world, preload: [:lemming]) do
          {:ok, instance} ->
            messages = LemmingInstances.list_messages(instance)
            runtime_state = runtime_state(instance)
            status_now = DateTime.utc_now() |> DateTime.truncate(:second)

            socket
            |> assign(:world, world)
            |> assign(:instance, instance)
            |> assign(:runtime_state, runtime_state)
            |> assign(:message_count, length(messages))
            |> assign(:status_now, status_now)
            |> assign(:parent_lemming_path, parent_lemming_path(instance))
            |> assign(:waiting_for_first_response?, waiting_for_first_response?(messages))
            |> assign(:instance_not_found?, false)
            |> assign(:status_tick_ref, nil)
            |> stream(:messages, messages, reset: true)
            |> schedule_status_tick()
            |> put_shell_breadcrumb(build_shell_breadcrumb(instance))

          {:error, :not_found} ->
            assign_not_found(socket)
        end

      nil ->
        assign_not_found(socket)
    end
  end

  defp resolve_world(%{"world" => world_id}) when is_binary(world_id) and world_id != "" do
    Worlds.get_world(world_id)
  end

  defp resolve_world(_params), do: Worlds.get_default_world()

  defp assign_not_found(socket) do
    socket
    |> assign(:world, nil)
    |> assign(:instance, nil)
    |> assign(:runtime_state, fallback_runtime_state())
    |> assign(:message_count, 0)
    |> assign(:status_now, DateTime.utc_now() |> DateTime.truncate(:second))
    |> assign(:parent_lemming_path, nil)
    |> assign(:waiting_for_first_response?, false)
    |> assign(:instance_not_found?, true)
    |> assign(:follow_up_form, follow_up_form(%{}))
    |> assign(:follow_up_submit_disabled?, true)
    |> assign(:follow_up_error, nil)
    |> assign(:status_tick_ref, nil)
    |> stream(:messages, [], reset: true)
    |> cancel_status_tick()
    |> put_shell_breadcrumb(default_shell_breadcrumb(:lemmings))
  end

  defp current_world_id(%{assigns: %{world: %{id: world_id}}}) when is_binary(world_id),
    do: world_id

  defp current_world_id(%{assigns: %{instance: %{world_id: world_id}}}) when is_binary(world_id),
    do: world_id

  defp current_world_id(_socket), do: nil

  defp build_shell_breadcrumb(%{} = instance) do
    [
      shell_item(:lemmings, "/lemmings"),
      shell_item(parent_lemming_name(instance), parent_lemming_path(instance)),
      shell_item(instance.id, ~p"/lemmings/instances/#{instance.id}")
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

  defp waiting_for_first_response?(messages) do
    match?([%{role: "user"}], messages)
  end

  defp runtime_state(%{id: instance_id} = instance) do
    case LemmingInstances.get_runtime_state(instance_id) do
      {:ok, state} ->
        %{
          retry_count: Map.get(state, :retry_count, 0),
          max_retries: Map.get(state, :max_retries, 3),
          queue_depth: Map.get(state, :queue_depth, 0),
          current_item: Map.get(state, :current_item),
          last_error: Map.get(state, :last_error),
          status: Map.get(state, :status),
          started_at: Map.get(state, :started_at) || instance.started_at,
          last_activity_at: Map.get(state, :last_activity_at) || instance.last_activity_at
        }

      {:error, :not_found} ->
        fallback_runtime_state(instance)
    end
  end

  defp fallback_runtime_state(instance \\ nil) do
    {status, started_at, last_activity_at} =
      case instance do
        %{status: status, started_at: started_at, last_activity_at: last_activity_at} ->
          {status, started_at, last_activity_at}

        _ ->
          {nil, nil, nil}
      end

    %{
      retry_count: 0,
      max_retries: 3,
      queue_depth: 0,
      current_item: nil,
      last_error: nil,
      status: status,
      started_at: started_at,
      last_activity_at: last_activity_at
    }
  end

  defp world_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp world_label(_world), do: dgettext("lemmings", "World")

  defp instance_label(%{lemming: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp instance_label(%{lemming_id: lemming_id}) when is_binary(lemming_id), do: lemming_id
  defp instance_label(%{id: id}) when is_binary(id), do: id
  defp instance_label(_instance), do: dgettext("lemmings", "Instance")

  defp instance_heading(%{lemming: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp instance_heading(%{id: id}) when is_binary(id), do: id
  defp instance_heading(_instance), do: dgettext("lemmings", "Instance session")

  defp instance_summary(%{lemming: %{description: description}}, _runtime_state)
       when is_binary(description) and description != "",
       do: description

  defp instance_summary(_instance, runtime_state) do
    parts =
      [
        runtime_state_summary(runtime_state),
        dgettext("lemmings", "Use the transcript to review the latest runtime activity.")
      ]
      |> Enum.reject(&Helpers.blank?/1)

    Enum.join(parts, " ")
  end

  defp runtime_state_summary(runtime_state) do
    status = Map.get(runtime_state, :status)
    retry_info = retry_info(runtime_state)

    cond do
      retry_info != nil and status == "retrying" ->
        retry_info

      is_binary(status) and status != "" ->
        dgettext("lemmings", "Current status: %{status}",
          status: status_label(status, runtime_state)
        )

      true ->
        nil
    end
  end

  defp page_key_label(%{id: id}) when is_binary(id),
    do: dgettext("lemmings", "Instance %{id}", id: id)

  defp page_key_label(_instance), do: dgettext("lemmings", "Instance session")

  defp instance_status(%{status: status}) when is_binary(status) and status != "", do: status
  defp instance_status(_instance), do: "created"

  defp runtime_started_at(%{started_at: %DateTime{} = started_at}, _runtime_state),
    do: started_at

  defp runtime_started_at(_instance, %{started_at: %DateTime{} = started_at}),
    do: started_at

  defp runtime_started_at(_instance, _runtime_state), do: nil

  defp runtime_last_activity_at(
         %{last_activity_at: %DateTime{} = last_activity_at},
         _runtime_state
       ),
       do: last_activity_at

  defp runtime_last_activity_at(_instance, %{last_activity_at: %DateTime{} = last_activity_at}),
    do: last_activity_at

  defp runtime_last_activity_at(_instance, _runtime_state), do: nil

  defp instance_status_detail(%{status: status}, runtime_state, now) when not is_nil(status) do
    copy = status_copy(instance_status(%{status: status}), runtime_state, now)

    if copy == "" do
      dgettext("lemmings", "Runtime status")
    else
      copy
    end
  end

  defp instance_status_detail(_instance, _runtime_state, _now),
    do: dgettext("lemmings", "Runtime status")

  defp last_activity_detail(runtime_state) do
    case Map.get(runtime_state, :current_item) do
      nil ->
        dgettext("lemmings", "Latest runtime move")

      current_item ->
        dgettext("lemmings", "Current item: %{item}",
          item: runtime_current_item_label(%{current_item: current_item})
        )
    end
  end

  defp runtime_current_item_label(%{current_item: %{content: content}})
       when is_binary(content) and content != "",
       do: content

  defp runtime_current_item_label(%{current_item: %{content: content}}), do: inspect(content)

  defp runtime_current_item_label(%{current_item: current_item}) when is_binary(current_item),
    do: current_item

  defp runtime_current_item_label(%{current_item: current_item}), do: inspect(current_item)

  defp retry_info(runtime_state) when is_map(runtime_state) do
    retry_count = Map.get(runtime_state, :retry_count)
    max_retries = Map.get(runtime_state, :max_retries, @default_max_retries)

    if is_integer(retry_count) and retry_count >= 0 do
      dgettext("lemmings", "Retry attempt %{count} of %{max}",
        count: retry_count,
        max: max_retries
      )
    else
      nil
    end
  end

  defp status_label("created", _runtime_state), do: dgettext("lemmings", "Starting...")
  defp status_label("queued", _runtime_state), do: dgettext("lemmings", "Waiting for capacity...")
  defp status_label("processing", _runtime_state), do: dgettext("lemmings", "Processing")

  defp status_label("retrying", runtime_state) do
    retry_count = Map.get(runtime_state, :retry_count, 0)
    max_retries = Map.get(runtime_state, :max_retries, @default_max_retries)

    dgettext("lemmings", "Retrying (%{count}/%{max})", count: retry_count, max: max_retries)
  end

  defp status_label("idle", _runtime_state), do: dgettext("lemmings", "Idle")
  defp status_label("failed", _runtime_state), do: dgettext("lemmings", "Failed")
  defp status_label("expired", _runtime_state), do: dgettext("lemmings", "Expired")
  defp status_label(_status, _runtime_state), do: dgettext("lemmings", "Starting...")

  defp status_copy("created", _runtime_state, _now), do: dgettext("lemmings", "Starting...")

  defp status_copy("queued", _runtime_state, _now),
    do: dgettext("lemmings", "Waiting for capacity...")

  defp status_copy("processing", runtime_state, now) do
    dgettext("lemmings", "Processing for %{elapsed}",
      elapsed: elapsed_label(runtime_state, now, :started_at)
    )
  end

  defp status_copy("retrying", runtime_state, _now) do
    dgettext("lemmings", "Retry attempt %{count} of %{max}",
      count: Map.get(runtime_state, :retry_count, 0),
      max: Map.get(runtime_state, :max_retries, @default_max_retries)
    )
  end

  defp status_copy("idle", runtime_state, now) do
    dgettext("lemmings", "Idle for %{elapsed}",
      elapsed: elapsed_label(runtime_state, now, :last_activity_at)
    )
  end

  defp status_copy("failed", _runtime_state, _now), do: dgettext("lemmings", "Runtime failed.")
  defp status_copy("expired", _runtime_state, _now), do: dgettext("lemmings", "Runtime expired.")
  defp status_copy(_status, _runtime_state, _now), do: dgettext("lemmings", "Starting...")

  defp elapsed_label(runtime_state, now, reference_key) do
    started_at =
      Map.get(runtime_state, reference_key) || Map.get(runtime_state, :started_at) ||
        Map.get(runtime_state, :last_activity_at)

    case {started_at, now} do
      {%DateTime{} = started_at, %DateTime{} = now} ->
        DateTime.diff(now, started_at, :second)
        |> max(0)
        |> format_duration()

      _ ->
        dgettext("lemmings", "unknown")
    end
  end

  defp format_duration(seconds) when is_integer(seconds) and seconds < 60 do
    dgettext("lemmings", "%{seconds}s", seconds: seconds)
  end

  defp format_duration(seconds) when is_integer(seconds) and seconds < 3_600 do
    minutes = div(seconds, 60)
    remaining = rem(seconds, 60)
    dgettext("lemmings", "%{minutes}m %{seconds}s", minutes: minutes, seconds: remaining)
  end

  defp format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3_600)
    minutes = seconds |> rem(3_600) |> div(60)
    remaining = rem(seconds, 60)

    dgettext("lemmings", "%{hours}h %{minutes}m %{seconds}s",
      hours: hours,
      minutes: minutes,
      seconds: remaining
    )
  end

  defp schedule_status_tick(%{assigns: %{instance: %{status: status}}} = socket)
       when status in ["processing", "retrying", "idle"] do
    cancel_status_tick(socket)
    ref = Process.send_after(self(), :status_tick, @status_tick_interval)
    assign(socket, :status_tick_ref, ref)
  end

  defp schedule_status_tick(socket), do: cancel_status_tick(socket)

  defp cancel_status_tick(%{assigns: %{status_tick_ref: nil}} = socket), do: socket

  defp cancel_status_tick(%{assigns: %{status_tick_ref: ref}} = socket) do
    _ = Process.cancel_timer(ref)
    assign(socket, :status_tick_ref, nil)
  end

  defp follow_up_form(params) when is_map(params), do: follow_up_form(params, nil)

  defp follow_up_form(params, action) when is_map(params) do
    changeset = follow_up_changeset(params)
    changeset = if action == :validate, do: %{changeset | action: :validate}, else: changeset
    to_form(changeset, as: :follow_up_request)
  end

  defp follow_up_changeset(params) when is_map(params) do
    {%{request_text: ""}, %{request_text: :string}}
    |> Ecto.Changeset.cast(params, [:request_text])
    |> Ecto.Changeset.validate_required([:request_text],
      message: dgettext("errors", ".required")
    )
  end

  defp follow_up_terminal_error("failed"), do: dgettext("lemmings", "Instance has failed")
  defp follow_up_terminal_error("expired"), do: dgettext("lemmings", "Instance has expired")

  defp follow_up_terminal_error(_status),
    do: dgettext("lemmings", "Instance cannot accept follow-up requests")

  defp follow_up_error(:executor_unavailable),
    do: dgettext("lemmings", "Unable to queue the follow-up request right now.")

  defp follow_up_error(%Ecto.Changeset{}),
    do: dgettext("lemmings", "Unable to save the follow-up request.")

  defp follow_up_error(_reason),
    do: dgettext("lemmings", "Unable to queue the follow-up request right now.")

  defp follow_up_input_enabled?("idle"), do: true
  defp follow_up_input_enabled?(_status), do: false

  defp follow_up_terminal?("failed"), do: true
  defp follow_up_terminal?("expired"), do: true
  defp follow_up_terminal?(_status), do: false

  defp follow_up_status_copy("created"), do: dgettext("lemmings", "Starting...")
  defp follow_up_status_copy("queued"), do: dgettext("lemmings", "Waiting for capacity...")
  defp follow_up_status_copy("processing"), do: dgettext("lemmings", "Processing...")
  defp follow_up_status_copy("retrying"), do: dgettext("lemmings", "Retrying...")
  defp follow_up_status_copy("idle"), do: dgettext("lemmings", "Ready for another request.")
  defp follow_up_status_copy("failed"), do: dgettext("lemmings", "Instance has failed")
  defp follow_up_status_copy("expired"), do: dgettext("lemmings", "Instance has expired")
  defp follow_up_status_copy(_status), do: dgettext("lemmings", "Starting...")

  defp follow_up_helper_copy("idle"),
    do: dgettext("lemmings", "This request will reuse the current transcript context.")

  defp follow_up_helper_copy(status), do: follow_up_status_copy(status)
end
