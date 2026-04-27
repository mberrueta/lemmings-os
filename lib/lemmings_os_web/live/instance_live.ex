defmodule LemmingsOsWeb.InstanceLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.LemmingCalls.PubSub, as: LemmingCallPubSub
  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.PubSub, as: InstancePubSub
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.Helpers
  alias LemmingsOs.Runtime
  alias LemmingsOs.Tools.WorkArea
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.PageData.InstanceDelegationSnapshot

  @status_tick_interval 1_000
  @default_max_retries 3

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign_shell(:lemmings, dgettext("lemmings", "Instance Session"))
      |> assign(
        world: nil,
        instance: nil,
        runtime_state: fallback_runtime_state(),
        message_count: 0,
        total_tokens: nil,
        conversation_provider: nil,
        conversation_model: nil,
        status_now: DateTime.utc_now() |> DateTime.truncate(:second),
        parent_lemming_path: nil,
        waiting_for_first_response?: false,
        instance_not_found?: false,
        follow_up_form: follow_up_form(%{}),
        follow_up_submit_disabled?: true,
        follow_up_error: nil,
        status_tick_ref: nil,
        delegated_work_mode: :none,
        delegated_work_available_targets: [],
        delegated_work_active_count: 0,
        delegated_work_historical_count: 0,
        delegated_parent_instance_path: nil
      )
      |> stream(:messages, [], reset: true)

    if connected?(socket) and is_binary(params["id"]) do
      _ = InstancePubSub.subscribe_instance(params["id"])
      _ = InstancePubSub.subscribe_instance_messages(params["id"])
      _ = LemmingCallPubSub.subscribe_instance_calls(params["id"])
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

  def handle_info(
        {:tool_execution_upserted, %{instance_id: instance_id}},
        %{assigns: %{instance: %{id: instance_id}}} = socket
      ) do
    {:noreply, load_instance(socket, instance_id, %{"world" => current_world_id(socket)})}
  end

  def handle_info({:lemming_call_upserted, _payload}, socket) do
    {:noreply, reload_current_instance(socket)}
  end

  def handle_info({:lemming_call_status_changed, _payload}, socket) do
    {:noreply, reload_current_instance(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_follow_up_request", %{"follow_up_request" => params}, socket) do
    request_text = Map.get(params, "request_text", "")

    {:noreply,
     socket
     |> assign(
       follow_up_form: follow_up_form(params, :validate),
       follow_up_submit_disabled?: Helpers.blank?(request_text),
       follow_up_error: nil
     )}
  end

  def handle_event("submit_follow_up_request", %{"follow_up_request" => params}, socket) do
    request_text = Map.get(params, "request_text", "")
    form = follow_up_form(params, :validate)
    status = socket.assigns.instance |> instance_status()

    cond do
      Helpers.blank?(request_text) ->
        {:noreply,
         socket
         |> assign(
           follow_up_form: form,
           follow_up_submit_disabled?: true,
           follow_up_error: nil
         )}

      not follow_up_input_enabled?(status) ->
        {:noreply,
         socket
         |> assign(
           follow_up_form: form,
           follow_up_submit_disabled?: true,
           follow_up_error: follow_up_submission_error(status)
         )}

      true ->
        case LemmingInstances.enqueue_work(socket.assigns.instance, request_text, []) do
          {:ok, _instance} ->
            socket =
              socket
              |> assign(
                follow_up_form: follow_up_form(%{}),
                follow_up_submit_disabled?: true,
                follow_up_error: nil
              )
              |> load_instance(socket.assigns.instance.id, %{"world" => current_world_id(socket)})

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(
               follow_up_form: form,
               follow_up_submit_disabled?: Helpers.blank?(request_text),
               follow_up_error: follow_up_error(reason)
             )}
        end
    end
  end

  def handle_event("retry_instance", _params, %{assigns: %{instance: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("lemmings", "Unable to retry this instance right now."))}
  end

  def handle_event("retry_instance", _params, socket) do
    case Runtime.retry_session(socket.assigns.instance) do
      {:ok, _instance} ->
        {:noreply,
         put_flash(socket, :info, dgettext("lemmings", "Retry requested for this instance."))}

      {:error, :instance_not_failed} ->
        {:noreply,
         socket
         |> load_instance(socket.assigns.instance.id, %{"world" => current_world_id(socket)})
         |> put_flash(:error, dgettext("lemmings", "Only failed instances can be retried."))}

      {:error, :no_pending_request} ->
        {:noreply,
         put_flash(socket, :error, dgettext("lemmings", "There is no failed request to retry."))}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("lemmings", "Unable to retry this instance right now.")
         )}
    end
  end

  def handle_event("open_workspace", _params, %{assigns: %{instance: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("lemmings", "Workspace is unavailable right now."))}
  end

  def handle_event("open_workspace", _params, socket) do
    path = instance_workspace_path(socket.assigns.instance, socket.assigns.runtime_state)

    case open_workspace_path(path) do
      :ok ->
        {:noreply, put_flash(socket, :info, dgettext("lemmings", "Workspace open requested."))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("lemmings", "Workspace could not be opened."))}
    end
  end

  def handle_event("workspace_path_copied", _params, socket) do
    {:noreply, put_flash(socket, :info, dgettext("lemmings", "Workspace path copied."))}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp load_instance(socket, id, params) do
    case resolve_world(params) do
      %World{} = world ->
        case LemmingInstances.get_instance(id, world: world, preload: [:lemming]) do
          {:ok, instance} ->
            messages = LemmingInstances.list_messages(instance)
            tool_executions = LemmingTools.list_tool_executions(world, instance)
            delegated_work = InstanceDelegationSnapshot.build(instance)
            runtime_state = runtime_state(instance)
            status_now = DateTime.utc_now() |> DateTime.truncate(:second)

            socket
            |> assign(
              world: world,
              instance: instance,
              runtime_state: runtime_state,
              message_count: length(messages),
              total_tokens: transcript_total_tokens(messages),
              conversation_provider: transcript_provider(messages),
              conversation_model: transcript_model(messages),
              status_now: status_now,
              parent_lemming_path: parent_lemming_path(instance),
              waiting_for_first_response?: waiting_for_first_response?(messages),
              instance_not_found?: false,
              status_tick_ref: nil,
              delegated_work_mode: delegated_work.mode,
              delegated_work_available_targets: delegated_work.available_targets,
              delegated_work_active_count: delegated_work.active_count,
              delegated_work_historical_count: delegated_work.historical_count,
              delegated_parent_instance_path: delegated_parent_instance_path(delegated_work)
            )
            |> stream(
              :messages,
              transcript_entries(
                messages,
                tool_executions,
                delegated_work.calls,
                delegated_work.mode,
                instance
              ),
              reset: true
            )
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
    |> assign(
      world: nil,
      instance: nil,
      runtime_state: fallback_runtime_state(),
      message_count: 0,
      total_tokens: nil,
      conversation_provider: nil,
      conversation_model: nil,
      status_now: DateTime.utc_now() |> DateTime.truncate(:second),
      parent_lemming_path: nil,
      waiting_for_first_response?: false,
      instance_not_found?: true,
      follow_up_form: follow_up_form(%{}),
      follow_up_submit_disabled?: true,
      follow_up_error: nil,
      status_tick_ref: nil,
      delegated_work_mode: :none,
      delegated_work_available_targets: [],
      delegated_work_active_count: 0,
      delegated_work_historical_count: 0,
      delegated_parent_instance_path: nil
    )
    |> stream(:messages, [], reset: true)
    |> cancel_status_tick()
    |> put_shell_breadcrumb(default_shell_breadcrumb(:lemmings))
  end

  defp current_world_id(%{assigns: %{world: %{id: world_id}}}) when is_binary(world_id),
    do: world_id

  defp current_world_id(%{assigns: %{instance: %{world_id: world_id}}}) when is_binary(world_id),
    do: world_id

  defp current_world_id(_socket), do: nil

  defp reload_current_instance(%{assigns: %{instance: %{id: instance_id}}} = socket) do
    load_instance(socket, instance_id, %{"world" => current_world_id(socket)})
  end

  defp reload_current_instance(socket), do: socket

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

  defp instance_raw_path(%{id: id}, %{id: world_id})
       when is_binary(id) and is_binary(world_id) do
    ~p"/lemmings/instances/#{id}/raw?#{%{world: world_id}}"
  end

  defp instance_raw_path(%{id: id, world_id: world_id}, _world)
       when is_binary(id) and is_binary(world_id) do
    ~p"/lemmings/instances/#{id}/raw?#{%{world: world_id}}"
  end

  defp instance_raw_path(_instance, _world), do: nil

  defp instance_workspace_path(%{id: instance_id}, runtime_state)
       when is_binary(instance_id) and is_map(runtime_state) do
    work_area_ref =
      case Map.get(runtime_state, :work_area_ref) do
        work_area_ref when is_binary(work_area_ref) and work_area_ref != "" -> work_area_ref
        _other -> instance_id
      end

    WorkArea.root_path(work_area_ref)
  end

  defp instance_workspace_path(_instance, _runtime_state), do: nil

  defp open_workspace_path(path) when is_binary(path) do
    with :ok <- File.mkdir_p(path),
         {command, args} <- workspace_open_command(path),
         {_output, 0} <- System.cmd(command, args, stderr_to_stdout: true) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      {_output, status} -> {:error, {:exit_status, status}}
    end
  rescue
    exception -> {:error, exception}
  end

  defp open_workspace_path(_path), do: {:error, :invalid_path}

  defp workspace_open_command(path) do
    case Application.get_env(:lemmings_os, :workspace_open_command) do
      {command, args} when is_binary(command) and is_list(args) -> {command, args ++ [path]}
      command when is_binary(command) -> {command, [path]}
      _other -> default_workspace_open_command(path)
    end
  end

  defp default_workspace_open_command(path) do
    case :os.type() do
      {:unix, :darwin} -> {"open", [path]}
      _other -> {"xdg-open", [path]}
    end
  end

  defp parent_lemming_name(%{lemming: %{name: name}}) when is_binary(name) and name != "",
    do: name

  defp parent_lemming_name(%{lemming: %{id: id}}) when is_binary(id), do: id
  defp parent_lemming_name(%{lemming_id: lemming_id}) when is_binary(lemming_id), do: lemming_id
  defp parent_lemming_name(_instance), do: dgettext("world", ".label_not_available")

  defp waiting_for_first_response?(messages) do
    match?([%{role: "user"}], messages)
  end

  defp runtime_state(%{id: instance_id, world_id: world_id} = instance) do
    case LemmingInstances.get_runtime_state(instance_id, world_id: world_id) do
      {:ok, state} ->
        %{
          retry_count: Map.get(state, :retry_count, 0),
          max_retries: Map.get(state, :max_retries, 3),
          queue_depth: Map.get(state, :queue_depth, 0),
          work_area_ref: Map.get(state, :work_area_ref),
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
      work_area_ref: nil,
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
    instance_status_detail(copy)
  end

  defp instance_status_detail(_instance, _runtime_state, _now),
    do: dgettext("lemmings", "Runtime status")

  defp instance_status_detail(""), do: dgettext("lemmings", "Runtime status")
  defp instance_status_detail(copy), do: copy

  defp last_activity_detail(%{current_item: nil}),
    do: dgettext("lemmings", "Latest runtime move")

  defp last_activity_detail(%{current_item: current_item}) do
    dgettext("lemmings", "Current item: %{item}",
      item: runtime_current_item_label(%{current_item: current_item})
    )
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
    retry_info(retry_count, max_retries)
  end

  defp retry_info(retry_count, max_retries) when is_integer(retry_count) and retry_count >= 0 do
    dgettext("lemmings", "Retry attempt %{count} of %{max}",
      count: retry_count,
      max: max_retries
    )
  end

  defp retry_info(_retry_count, _max_retries), do: nil

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

    elapsed_label(started_at, now)
  end

  defp elapsed_label(%DateTime{} = started_at, %DateTime{} = now) do
    DateTime.diff(now, started_at, :second)
    |> max(0)
    |> format_duration()
  end

  defp elapsed_label(_started_at, _now), do: dgettext("lemmings", "unknown")

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

  defp follow_up_form(params, :validate) when is_map(params) do
    changeset = follow_up_changeset(params)
    to_form(%{changeset | action: :validate}, as: :follow_up_request)
  end

  defp follow_up_form(params, _action) when is_map(params),
    do: to_form(follow_up_changeset(params), as: :follow_up_request)

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

  defp follow_up_submission_error("failed"), do: follow_up_terminal_error("failed")
  defp follow_up_submission_error("expired"), do: follow_up_terminal_error("expired")

  defp follow_up_submission_error(status) when is_binary(status),
    do: follow_up_status_copy(status)

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

  defp transcript_entries(messages, tool_executions, delegated_calls, mode, instance)
       when is_list(messages) and is_list(tool_executions) and is_list(delegated_calls) do
    messages
    |> transcript_message_entries(delegated_calls, mode, instance)
    |> Kernel.++(transcript_tool_execution_entries(tool_executions))
    |> Kernel.++(transcript_delegated_call_entries(delegated_calls, mode))
    |> Enum.sort_by(&transcript_sort_key/1)
    |> inject_transcript_day_dividers()
  end

  defp transcript_total_tokens(messages) when is_list(messages) do
    total =
      Enum.reduce(messages, 0, fn
        %{total_tokens: value}, acc when is_integer(value) and value > 0 -> acc + value
        _message, acc -> acc
      end)

    if total > 0, do: total, else: nil
  end

  defp transcript_provider(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(&assistant_metadata_value(&1, :provider))
  end

  defp transcript_model(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(&assistant_metadata_value(&1, :model))
  end

  defp assistant_metadata_value(%{role: "assistant"} = message, field) do
    case Map.get(message, field) do
      value when is_binary(value) and value != "" -> value
      _value -> nil
    end
  end

  defp assistant_metadata_value(_message, _field), do: nil

  defp message_date(%{inserted_at: %DateTime{} = inserted_at}), do: DateTime.to_date(inserted_at)
  defp message_date(_message), do: nil

  defp tool_execution_date(%{inserted_at: %DateTime{} = inserted_at}),
    do: DateTime.to_date(inserted_at)

  defp tool_execution_date(_tool_execution), do: nil

  defp transcript_message_entries(messages, delegated_calls, mode, instance) do
    messages
    |> Enum.reject(&omit_message_from_transcript?(&1, delegated_calls, mode))
    |> Enum.map(fn message ->
      %{
        id: "message-#{message.id}",
        type: :message,
        inserted_at: Map.get(message, :inserted_at),
        message: message,
        speaker_name: transcript_message_speaker_name(message, mode, instance),
        speaker_avatar_label: transcript_message_speaker_avatar_label(message, mode, instance)
      }
    end)
  end

  defp transcript_tool_execution_entries(tool_executions) do
    Enum.map(tool_executions, fn tool_execution ->
      %{
        id: "tool-execution-#{tool_execution.id}",
        type: :tool_execution,
        inserted_at: Map.get(tool_execution, :inserted_at),
        tool_execution: tool_execution
      }
    end)
  end

  defp transcript_delegated_call_entries(delegated_calls, :child) do
    Enum.flat_map(delegated_calls, fn delegated_call ->
      requested_at = Map.get(delegated_call, :requested_at)

      [
        %{
          id: "manager-request-#{delegated_call.id}",
          type: :manager_request,
          inserted_at: requested_at,
          delegated_call: delegated_call
        }
      ]
    end)
  end

  defp transcript_delegated_call_entries(delegated_calls, _mode) do
    Enum.flat_map(delegated_calls, fn delegated_call ->
      requested_at = Map.get(delegated_call, :requested_at)

      [
        %{
          id: "delegation-intent-#{delegated_call.id}",
          type: :delegation_intent,
          inserted_at: requested_at,
          delegated_call: delegated_call
        },
        %{
          id: "delegated-call-#{delegated_call.id}",
          type: :delegated_call,
          inserted_at: requested_at,
          delegated_call: delegated_call
        }
      ]
    end)
  end

  defp transcript_sort_key(%{type: type, inserted_at: inserted_at, id: id}) do
    {transcript_timestamp_sort_value(inserted_at), transcript_type_rank(type), id}
  end

  defp transcript_timestamp_sort_value(%DateTime{} = inserted_at),
    do: DateTime.to_unix(inserted_at, :microsecond)

  defp transcript_timestamp_sort_value(_inserted_at), do: 0

  defp transcript_type_rank(:day_divider), do: 0
  defp transcript_type_rank(:message), do: 1
  defp transcript_type_rank(:tool_execution), do: 2
  defp transcript_type_rank(:delegation_intent), do: 3
  defp transcript_type_rank(:manager_request), do: 3
  defp transcript_type_rank(:delegated_call), do: 4
  defp transcript_type_rank(_type), do: 5

  defp inject_transcript_day_dividers(entries) do
    entries
    |> Enum.reduce({[], nil}, fn entry, {acc, previous_date} ->
      current_date = transcript_entry_date(entry)

      next_entries =
        case current_date do
          %Date{} = date when date != previous_date ->
            separator = %{id: "day-#{Date.to_iso8601(date)}", type: :day_divider, date: date}
            acc ++ [separator, entry]

          _date ->
            acc ++ [entry]
        end

      {next_entries, current_date || previous_date}
    end)
    |> elem(0)
  end

  defp transcript_entry_date(%{type: :message, message: message}), do: message_date(message)

  defp transcript_entry_date(%{type: :tool_execution, tool_execution: tool_execution}),
    do: tool_execution_date(tool_execution)

  defp transcript_entry_date(%{type: :delegation_intent, delegated_call: delegated_call}),
    do: message_date(%{inserted_at: delegated_call.requested_at})

  defp transcript_entry_date(%{type: :manager_request, delegated_call: delegated_call}),
    do: message_date(%{inserted_at: delegated_call.requested_at})

  defp transcript_entry_date(%{type: :delegated_call, delegated_call: delegated_call}),
    do: message_date(%{inserted_at: delegated_call.requested_at})

  defp transcript_entry_date(%{date: %Date{} = date}), do: date
  defp transcript_entry_date(_entry), do: nil

  defp transcript_day_label(%Date{} = date) do
    Calendar.strftime(date, "%A · %b %-d")
    |> String.upcase()
  end

  defp transcript_day_label(_date), do: nil

  defp omit_message_from_transcript?(%{role: "user", content: content}, delegated_calls, :child)
       when is_binary(content) do
    Enum.any?(delegated_calls, &(&1.request_text == content))
  end

  defp omit_message_from_transcript?(_message, _delegated_calls, _mode), do: false

  defp transcript_message_speaker_name(%{role: "assistant"}, :child, instance),
    do: instance_heading(instance)

  defp transcript_message_speaker_name(_message, _mode, _instance), do: nil

  defp transcript_message_speaker_avatar_label(%{role: "assistant"}, :child, instance) do
    instance
    |> instance_heading()
    |> String.first()
    |> case do
      nil -> nil
      value -> String.upcase(value)
    end
  end

  defp transcript_message_speaker_avatar_label(_message, _mode, _instance), do: nil

  defp delegated_parent_instance_path(%InstanceDelegationSnapshot{
         mode: :child,
         calls: [call | _calls]
       }),
       do: Map.get(call, :caller_instance_path)

  defp delegated_parent_instance_path(_delegated_work), do: nil
end
