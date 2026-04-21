defmodule LemmingsOsWeb.InstanceRawLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.LemmingInstances
  alias LemmingsOs.LemmingInstances.Executor
  alias LemmingsOs.LemmingInstances.Message
  alias LemmingsOs.LemmingInstances.PubSub
  alias LemmingsOs.LemmingInstances.ToolExecution
  alias LemmingsOs.LemmingTools
  alias LemmingsOs.ModelRuntime
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @max_live_steps 40

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
    case LemmingInstances.get_instance(id, world: world, preload: [:lemming]) do
      {:ok, instance} ->
        runtime_state = load_runtime_state(instance, world)
        messages = load_messages(instance, world)
        tool_executions = load_tool_executions(instance, world)
        model_steps = load_model_steps(instance)

        {interaction_timeline, interaction_timeline_source} =
          build_interaction_timeline(model_steps, messages, tool_executions)

        {model_request, model_request_source} =
          load_model_request(instance, runtime_state, model_steps, messages)

        session_path = ~p"/lemmings/instances/#{instance.id}?#{%{world: world.id}}"
        raw_path = ~p"/lemmings/instances/#{instance.id}/raw?#{%{world: world.id}}"

        socket
        |> maybe_subscribe_instance(instance)
        |> assign(
          world: world,
          instance: instance,
          runtime_state: runtime_state,
          model_steps: model_steps,
          interaction_timeline: interaction_timeline,
          interaction_timeline_source: interaction_timeline_source,
          model_request: model_request,
          model_request_source: model_request_source,
          instance_not_found?: false,
          parent_lemming_path: parent_lemming_path(instance),
          session_path: session_path,
          shell_breadcrumb: build_shell_breadcrumb(instance, session_path, raw_path)
        )

      {:error, :not_found} ->
        assign_not_found(socket)
    end
  end

  defp load_runtime_state(instance, world) do
    case LemmingInstances.get_runtime_state(instance.id, world: world) do
      {:ok, state} -> state
      {:error, :not_found} -> %{}
    end
  end

  defp load_messages(instance, world) do
    LemmingInstances.list_messages(instance, world: world)
  end

  defp load_tool_executions(instance, world) do
    LemmingTools.list_tool_executions(world, instance)
  end

  defp load_model_steps(instance) do
    case Registry.lookup(LemmingsOs.LemmingInstances.ExecutorRegistry, instance.id) do
      [{_pid, _value}] ->
        instance.id
        |> Executor.snapshot()
        |> Map.get(:model_steps, [])
        |> Enum.take(-@max_live_steps)

      [] ->
        []
    end
  catch
    :exit, _reason -> []
  end

  defp load_model_request(instance, runtime_state, model_steps, messages)
       when is_list(model_steps) do
    case List.last(model_steps) do
      %{request_payload: payload} when is_map(payload) ->
        {payload, :live_executor_trace}

      _other ->
        fallback_model_request(instance, runtime_state, messages)
    end
  end

  defp fallback_model_request(instance, runtime_state, messages) do
    case build_model_request(instance, runtime_state) do
      {:ok, request} ->
        {request, :runtime_state}

      {:error, _reason} ->
        case build_model_request_from_transcript(instance, messages) do
          {:ok, request} -> {request, :transcript_reconstruction}
          {:error, reason} -> {%{error: inspect(reason)}, :unavailable}
        end
    end
  end

  defp build_model_request(instance, runtime_state) do
    history = Map.get(runtime_state, :context_messages, [])
    current_item = Map.get(runtime_state, :current_item)

    ModelRuntime.debug_request(instance.config_snapshot || %{}, history, current_item)
  end

  defp build_model_request_from_transcript(instance, messages) do
    case split_transcript_for_request(messages) do
      {:ok, history, current_request} ->
        ModelRuntime.debug_request(instance.config_snapshot || %{}, history, current_request)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp split_transcript_for_request(messages) do
    user_messages =
      Enum.filter(messages, fn
        %Message{role: "user"} -> true
        _message -> false
      end)

    case List.last(user_messages) do
      %Message{} = current_request ->
        history =
          messages
          |> Enum.take_while(&(&1.id != current_request.id))
          |> Enum.map(&message_to_context_message/1)

        {:ok, history, %{content: current_request.content}}

      nil ->
        {:error, :invalid_request}
    end
  end

  defp message_to_context_message(%Message{role: role, content: content}) do
    %{role: role, content: content}
  end

  defp build_interaction_timeline(model_steps, messages, tool_executions)
       when is_list(model_steps) and model_steps != [] do
    executions_by_id = Map.new(tool_executions, &{&1.id, &1})

    timeline =
      [
        build_user_request_entry(model_steps, messages)
        | build_live_timeline_entries(model_steps, executions_by_id)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> renumber_timeline()

    {timeline, :live_executor_trace}
  end

  defp build_interaction_timeline(_model_steps, messages, tool_executions) do
    timeline =
      messages
      |> build_persisted_timeline(tool_executions)
      |> Enum.reject(&is_nil/1)
      |> renumber_timeline()

    {timeline, :persisted_history_only}
  end

  defp build_user_request_entry(model_steps, messages) do
    content =
      model_steps
      |> List.first()
      |> extract_current_request_content()
      |> case do
        nil -> latest_user_message_content(messages)
        value -> value
      end

    if present?(content) do
      %{
        id: "user-request",
        kind: :user_request,
        title: "1. User -> App",
        summary: "Operator request received",
        body: content,
        timestamp: latest_user_message_at(messages),
        meta: [],
        status: nil,
        raw_sections: []
      }
    end
  end

  defp build_live_timeline_entries(model_steps, executions_by_id) do
    model_steps
    |> Enum.chunk_by(&Map.get(&1, :request_payload))
    |> Enum.flat_map(fn request_group ->
      build_live_request_group_entries(request_group, executions_by_id)
    end)
  end

  defp build_live_request_group_entries([first_step | _rest] = request_group, executions_by_id) do
    [
      build_llm_request_entry(first_step)
      | Enum.with_index(request_group, 1)
        |> Enum.flat_map(fn {model_step, retry_attempt} ->
          build_live_step_entries(model_step, executions_by_id, retry_attempt)
        end)
    ]
  end

  defp build_live_step_entries(model_step, executions_by_id, retry_attempt) do
    tool_execution =
      model_step
      |> Map.get(:tool_execution_id)
      |> then(&Map.get(executions_by_id, &1))

    [
      build_llm_response_entry(model_step, retry_attempt)
      | build_tool_entries(model_step, tool_execution)
    ]
  end

  defp build_llm_request_entry(model_step) do
    request_payload = Map.get(model_step, :request_payload, %{})
    request = request_payload["request"] || %{}
    messages = request["messages"] || []
    non_system_count = Enum.count(messages, &(&1["role"] != "system"))

    %{
      id: "step-#{model_step.step_index}-llm-request",
      kind: :llm_request,
      title: "App -> LLM",
      summary:
        "Send provider request with system prompt, tools catalog, and #{non_system_count} context message(s)",
      body: request_messages_body(messages),
      timestamp: Map.get(model_step, :started_at),
      meta: request_meta(request_payload, messages),
      status: Map.get(model_step, :status),
      raw_sections: [
        %{label: "Provider request", payload: request_payload},
        %{label: "System prompt", payload: extract_system_prompt(messages)}
      ]
    }
  end

  defp build_llm_response_entry(model_step, retry_attempt) do
    parsed_output = Map.get(model_step, :parsed_output) || %{}
    {summary, body} = llm_response_summary_and_body(model_step, parsed_output)

    %{
      id: "step-#{model_step.step_index}-llm-response",
      kind: :llm_response,
      title: llm_response_title(retry_attempt),
      summary: summary,
      body: body,
      timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
      meta: response_meta(model_step),
      status: Map.get(model_step, :status),
      raw_sections: [
        %{label: "Parsed response", payload: parsed_output},
        %{label: "Provider raw response", payload: model_step.response_payload},
        %{label: "Error", payload: model_step.error}
      ]
    }
  end

  defp llm_response_summary_and_body(_model_step, %{"action" => "tool_call"} = parsed_output) do
    tool_name = parsed_output["tool_name"] || "unknown tool"
    {"LLM requested tool #{tool_name}", format_tool_args_body(parsed_output["args"] || %{})}
  end

  defp llm_response_summary_and_body(_model_step, %{"action" => "reply"} = parsed_output) do
    {"LLM returned final reply", parsed_output["reply"]}
  end

  defp llm_response_summary_and_body(model_step, parsed_output) do
    {"LLM returned an unexpected payload", llm_error_body(model_step, parsed_output)}
  end

  defp llm_error_body(_model_step, parsed_output) when map_size(parsed_output) > 0 do
    Jason.encode!(parsed_output, pretty: true)
  end

  defp llm_error_body(model_step, _parsed_output) do
    error = Map.get(model_step, :error) || %{}
    response_payload = Map.get(model_step, :response_payload) || %{}

    cond do
      is_binary(error["content"]) and error["content"] != "" ->
        error["content"]

      is_binary(response_payload["content"]) ->
        response_payload["content"]

      map_size(error) > 0 ->
        Jason.encode!(error, pretty: true)

      true ->
        "%{}"
    end
  end

  defp build_tool_entries(
         %{parsed_output: %{"action" => "tool_call"} = parsed_output} = model_step,
         tool_execution
       ) do
    tool_name = parsed_output["tool_name"] || "unknown tool"
    tool_args = parsed_output["args"] || %{}

    [
      %{
        id: "step-#{model_step.step_index}-tool-call",
        kind: :tool_call,
        title: "App -> Tool",
        summary: "Execute #{tool_name}",
        body: format_tool_args_body(tool_args),
        timestamp: tool_entry_timestamp(tool_execution),
        meta: tool_call_meta(tool_execution),
        status: tool_execution_status(tool_execution),
        raw_sections: [
          %{label: "Tool arguments", payload: tool_args}
        ]
      },
      build_tool_result_entry(model_step, tool_execution)
    ]
  end

  defp build_tool_entries(_model_step, _tool_execution), do: []

  defp build_tool_result_entry(model_step, nil) do
    %{
      id: "step-#{model_step.step_index}-tool-result-missing",
      kind: :tool_result,
      title: "Tool -> App",
      summary: "Tool result not available in persistence",
      body: "Live model step exists, but no durable tool row was found.",
      timestamp: Map.get(model_step, :completed_at) || Map.get(model_step, :started_at),
      meta: [],
      status: "error",
      raw_sections: []
    }
  end

  defp build_tool_result_entry(model_step, %ToolExecution{} = tool_execution) do
    %{
      id: "step-#{model_step.step_index}-tool-result",
      kind: :tool_result,
      title: "Tool -> App",
      summary: tool_result_summary(tool_execution),
      body: tool_result_body(tool_execution),
      timestamp: tool_result_timestamp(tool_execution),
      meta: tool_result_meta(tool_execution),
      status: tool_execution.status,
      raw_sections: [
        %{label: "Persisted tool arguments", payload: tool_execution.args},
        %{label: "Persisted tool result", payload: tool_execution.result},
        %{label: "Persisted tool error", payload: tool_execution.error}
      ]
    }
  end

  defp build_persisted_timeline(messages, tool_executions) do
    [
      build_persisted_user_entry(messages),
      Enum.map(tool_executions, &build_persisted_tool_entry/1),
      build_persisted_reply_entry(messages)
    ]
    |> List.flatten()
  end

  defp build_persisted_user_entry(messages) do
    case latest_user_message_content(messages) do
      nil ->
        nil

      content ->
        %{
          id: "persisted-user-request",
          kind: :user_request,
          title: "User -> App",
          summary: "Persisted user request",
          body: content,
          timestamp: latest_user_message_at(messages),
          meta: [],
          status: nil,
          raw_sections: []
        }
    end
  end

  defp build_persisted_tool_entry(tool_execution) do
    %{
      id: "persisted-tool-#{tool_execution.id}",
      kind: :tool_result,
      title: "Persisted tool execution",
      summary: tool_result_summary(tool_execution),
      body: tool_result_body(tool_execution),
      timestamp: tool_result_timestamp(tool_execution),
      meta: tool_result_meta(tool_execution),
      status: tool_execution.status,
      raw_sections: [
        %{label: "Persisted tool arguments", payload: tool_execution.args},
        %{label: "Persisted tool result", payload: tool_execution.result},
        %{label: "Persisted tool error", payload: tool_execution.error}
      ]
    }
  end

  defp build_persisted_reply_entry(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(fn
      %Message{role: "assistant"} -> true
      _message -> false
    end)
    |> case do
      %Message{} = message ->
        %{
          id: "persisted-final-reply",
          kind: :final_reply,
          title: "LLM -> App",
          summary: "Final assistant reply stored in transcript",
          body: message.content,
          timestamp: message.inserted_at,
          meta: persisted_message_meta(message),
          status: nil,
          raw_sections: []
        }

      nil ->
        nil
    end
  end

  defp latest_user_message_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: "user", content: content} -> content
      _message -> nil
    end)
  end

  defp latest_user_message_at(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Message{role: "user", inserted_at: inserted_at} -> inserted_at
      _message -> nil
    end)
  end

  defp extract_current_request_content(nil), do: nil

  defp extract_current_request_content(%{request_payload: request_payload}) do
    request_payload
    |> Map.get("request", %{})
    |> Map.get("messages", [])
    |> List.last()
    |> case do
      %{"content" => content} when is_binary(content) -> content
      _other -> nil
    end
  end

  defp request_messages_body(messages) when is_list(messages) and messages != [] do
    Enum.map_join(messages, "\n\n", fn message ->
      role =
        message
        |> Map.get("role", "unknown")
        |> to_string()
        |> String.upcase()

      content =
        case Map.get(message, "content") do
          value when is_binary(value) and value != "" -> value
          _other -> "(empty)"
        end

      "#{role}\n#{content}"
    end)
  end

  defp request_messages_body(_messages), do: "Request messages unavailable."

  defp request_meta(request_payload, messages) do
    [
      provider_value(request_payload),
      model_value(request_payload),
      "#{length(messages)} total message(s)"
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp response_meta(model_step) do
    [
      Map.get(model_step, :provider),
      Map.get(model_step, :model),
      tokens_meta(model_step),
      duration_meta(Map.get(model_step, :duration_ms))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp tool_call_meta(nil), do: []

  defp tool_call_meta(tool_execution) do
    [
      tool_execution.id,
      duration_meta(tool_execution.duration_ms)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp tool_result_meta(tool_execution) do
    [
      tool_execution.tool_name,
      duration_meta(tool_execution.duration_ms)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp persisted_message_meta(%Message{} = message) do
    [message.provider, message.model, tokens_meta(message)]
    |> Enum.reject(&is_nil/1)
  end

  defp tokens_meta(%{input_tokens: input_tokens, output_tokens: output_tokens})
       when is_integer(input_tokens) and is_integer(output_tokens) do
    "#{input_tokens} in / #{output_tokens} out"
  end

  defp tokens_meta(%{total_tokens: total_tokens}) when is_integer(total_tokens) do
    "#{total_tokens} total tokens"
  end

  defp tokens_meta(_payload), do: nil

  defp duration_meta(duration_ms) when is_integer(duration_ms), do: "#{duration_ms} ms"
  defp duration_meta(_duration_ms), do: nil

  defp provider_value(%{"provider" => provider}) when is_binary(provider), do: provider
  defp provider_value(_payload), do: nil

  defp model_value(%{"model" => model}) when is_binary(model), do: model
  defp model_value(_payload), do: nil

  defp format_tool_args_body(args) when is_map(args) and map_size(args) == 0 do
    "Tool called without arguments."
  end

  defp format_tool_args_body(args) when is_map(args) do
    Enum.map_join(args, "\n\n", fn {key, value} ->
      case render_tool_arg_value(value) do
        {:inline, rendered} ->
          "- `#{key}`: #{rendered}"

        {:block, rendered} ->
          "- `#{key}`:\n#{indent_block(rendered, 2)}"
      end
    end)
  end

  defp format_tool_args_body(_args), do: "Tool arguments unavailable."

  defp render_tool_arg_value(value) when is_binary(value) do
    if String.contains?(value, "\n") do
      {:block, value}
    else
      {:inline, value}
    end
  end

  defp render_tool_arg_value(value) when is_map(value) or is_list(value) do
    {:block, Jason.encode!(value, pretty: true)}
  end

  defp render_tool_arg_value(value), do: {:inline, inspect(value)}

  defp indent_block(content, spaces)
       when is_binary(content) and is_integer(spaces) and spaces > 0 do
    prefix = String.duplicate(" ", spaces)

    content
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp tool_result_summary(%ToolExecution{status: "ok", tool_name: tool_name}) do
    "#{tool_name} completed"
  end

  defp tool_result_summary(%ToolExecution{status: "error", tool_name: tool_name}) do
    "#{tool_name} failed"
  end

  defp tool_result_summary(%ToolExecution{tool_name: tool_name}), do: tool_name

  defp tool_result_body(%ToolExecution{} = tool_execution) do
    cond do
      present?(tool_execution.preview) and present?(tool_execution.summary) ->
        "#{tool_execution.summary}\n\n#{tool_execution.preview}"

      present?(tool_execution.summary) ->
        tool_execution.summary

      present?(tool_execution.preview) ->
        tool_execution.preview

      is_map(tool_execution.error) ->
        map_message(tool_execution.error) || inspect(tool_execution.error)

      true ->
        "Tool execution finished without a summary."
    end
  end

  defp map_message(%{"message" => message}) when is_binary(message), do: message
  defp map_message(%{message: message}) when is_binary(message), do: message
  defp map_message(_value), do: nil

  defp tool_execution_status(nil), do: "running"
  defp tool_execution_status(%ToolExecution{status: status}), do: status

  defp tool_entry_timestamp(nil), do: nil
  defp tool_entry_timestamp(%ToolExecution{started_at: %DateTime{} = started_at}), do: started_at

  defp tool_entry_timestamp(%ToolExecution{inserted_at: %DateTime{} = inserted_at}),
    do: inserted_at

  defp tool_entry_timestamp(_tool_execution), do: nil

  defp tool_result_timestamp(%ToolExecution{completed_at: %DateTime{} = completed_at}),
    do: completed_at

  defp tool_result_timestamp(%ToolExecution{updated_at: %DateTime{} = updated_at}), do: updated_at

  defp tool_result_timestamp(%ToolExecution{inserted_at: %DateTime{} = inserted_at}),
    do: inserted_at

  defp tool_result_timestamp(_tool_execution), do: nil

  defp extract_system_prompt(messages) do
    messages
    |> Enum.find(fn message -> message["role"] == "system" end)
    |> case do
      %{"content" => content} -> content
      _other -> nil
    end
  end

  defp llm_response_title(1), do: "LLM -> App"
  defp llm_response_title(retry_attempt), do: "LLM -> App (retry #{retry_attempt})"

  defp renumber_timeline(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} ->
      Map.put(entry, :title, "#{index}. #{strip_timeline_prefix(entry.title)}")
    end)
  end

  defp strip_timeline_prefix(title) when is_binary(title) do
    Regex.replace(~r/^\d+\.\s+/, title, "")
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false

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

  defp timeline_entry_status_class("error"), do: "border-rose-400/40 bg-rose-400/10 text-rose-200"

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
