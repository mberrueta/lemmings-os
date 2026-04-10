defmodule LemmingsOsWeb.InstanceComponents do
  @moduledoc """
  Components for runtime instance sessions.
  """

  use LemmingsOsWeb, :html

  @default_max_retries 3

  attr :id, :string, default: nil
  attr :status, :string, required: true
  attr :runtime_state, :map, default: %{}
  attr :status_now, :any, default: nil
  attr :class, :string, default: nil
  slot :actions

  def status_banner(assigns) do
    assigns =
      assigns
      |> assign(:status, normalize_status(assigns.status))
      |> assign(:status_border_class, status_panel_border(normalize_status(assigns.status)))

    ~H"""
    <section
      id={@id}
      class={[
        "border-2 bg-zinc-950/85 p-4 shadow-lg",
        @status_border_class,
        @class
      ]}
    >
      <div class="flex items-start gap-3">
        <.icon name={status_icon(@status)} class={icon_class(@status)} />
        <div class="min-w-0 space-y-2">
          <.status
            id="instance-status-badge"
            kind={:instance}
            value={@status}
          />
          <p class="text-xs uppercase tracking-widest text-zinc-400">
            {status_copy(@status, @runtime_state, @status_now)}
          </p>
        </div>
      </div>

      <div class="mt-4 grid gap-2 sm:grid-cols-2">
        <div
          :if={failure_detail(@status, @runtime_state)}
          class="border border-red-400/30 bg-red-950/30 px-3 py-2 sm:col-span-2"
        >
          <p class="text-xs uppercase tracking-widest text-red-300">
            {dgettext("lemmings", "Failure detail")}
          </p>
          <p class="mt-1 break-words font-mono text-sm text-zinc-100">
            {failure_detail(@status, @runtime_state)}
          </p>
        </div>

        <div
          :if={Map.get(@runtime_state, :current_item)}
          class="border border-zinc-800 bg-zinc-950/70 px-3 py-2"
        >
          <p class="text-xs uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", "Current item")}
          </p>
          <p class="mt-1 break-words font-mono text-sm text-zinc-100">
            {runtime_current_item_preview(@runtime_state)}
          </p>
        </div>

        <div
          :if={queue_depth(@runtime_state) > 0}
          class="border border-zinc-800 bg-zinc-950/70 px-3 py-2"
        >
          <p class="text-xs uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", "Queue depth")}
          </p>
          <p class="mt-1 font-mono text-sm text-zinc-100">
            {queue_depth(@runtime_state)}
          </p>
        </div>

        <div
          :if={retry_info(@runtime_state) != nil}
          class="border border-zinc-800 bg-zinc-950/70 px-3 py-2"
        >
          <p class="text-xs uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", "Retry state")}
          </p>
          <p class="mt-1 font-mono text-sm text-zinc-100">
            {retry_info(@runtime_state)}
          </p>
        </div>

        <div
          :if={status_elapsed(@status, @runtime_state, @status_now) != nil}
          class="border border-zinc-800 bg-zinc-950/70 px-3 py-2"
        >
          <p class="text-xs uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", "Elapsed")}
          </p>
          <p class="mt-1 font-mono text-sm text-zinc-100">
            {status_elapsed(@status, @runtime_state, @status_now)}
          </p>
        </div>

        <div
          :if={@actions != []}
          class="border border-zinc-800 bg-zinc-950/70 px-3 py-2 sm:col-span-2"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", "Operator action")}
              </p>
              <p class="mt-1 text-sm text-zinc-400">
                {dgettext("lemmings", "Retry the latest failed request.")}
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              {render_slot(@actions)}
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :message, :map, required: true
  attr :display_now, :any, default: nil
  attr :class, :string, default: nil

  def message_bubble(assigns) do
    assigns = assign(assigns, :message_role, normalize_role(assigns.message.role))

    ~H"""
    <article
      id={@id}
      class={["flex w-full", message_alignment(@message_role), @class]}
      data-role={@message_role}
    >
      <div class={[
        "grid w-fit max-w-[80%] min-w-[18rem] gap-2",
        message_grid_alignment(@message_role)
      ]}>
        <div class={[
          "flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500",
          message_meta_alignment(@message_role)
        ]}>
          <span class={[
            "inline-flex size-8 items-center justify-center rounded-full border text-xs font-semibold",
            message_avatar_tone(@message_role)
          ]}>
            {message_avatar_label(@message_role)}
          </span>
          <span>{message_role_label(@message_role)}</span>
        </div>

        <div class={[
          "instance-session-message-surface w-full rounded-2xl border px-4 py-3",
          message_bubble_tone(@message_role)
        ]}>
          <p class="whitespace-pre-wrap break-words text-sm leading-6 text-zinc-100">
            {@message.content}
          </p>

          <div
            :if={assistant_metadata?(@message_role)}
            class="mt-4 space-y-3 border-t border-zinc-800 pt-3"
          >
            <div class="flex flex-wrap gap-2">
              <.badge :if={@message.input_tokens != nil} tone="muted">
                {dgettext("lemmings", "Input %{count} tokens", count: @message.input_tokens)}
              </.badge>
              <.badge :if={@message.output_tokens != nil} tone="muted">
                {dgettext("lemmings", "Output %{count} tokens", count: @message.output_tokens)}
              </.badge>
              <.badge :if={@message.total_tokens != nil} tone="success">
                {dgettext("lemmings", "Total %{count} tokens", count: @message.total_tokens)}
              </.badge>
            </div>
          </div>
        </div>

        <div class={[
          "flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500",
          message_meta_alignment(@message_role)
        ]}>
          <span class="text-zinc-400">{message_clock_label(@message.inserted_at)}</span>
          <span class="text-zinc-600">{message_age_label(@message.inserted_at, @display_now)}</span>
        </div>
      </div>
    </article>
    """
  end

  defp normalize_status(status) when is_binary(status), do: status
  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(_status), do: "created"

  defp normalize_role(role) when is_binary(role), do: role
  defp normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  defp normalize_role(_role), do: "user"

  defp queue_depth(runtime_state) when is_map(runtime_state) do
    case Map.get(runtime_state, :queue_depth) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  end

  defp queue_depth(_runtime_state), do: 0

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

  defp retry_info(_runtime_state), do: nil

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

  defp failure_detail(status, runtime_state) when status in ["retrying", "failed"] do
    case Map.get(runtime_state, :last_error) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp failure_detail(_status, _runtime_state), do: nil

  defp status_elapsed("processing", runtime_state, now),
    do: elapsed_label(runtime_state, now, :started_at)

  defp status_elapsed("idle", runtime_state, now),
    do: elapsed_label(runtime_state, now, :last_activity_at)

  defp status_elapsed(_status, _runtime_state, _now), do: nil

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

  defp status_panel_border("created"), do: "border-zinc-800"
  defp status_panel_border("queued"), do: "border-sky-400/40"
  defp status_panel_border("processing"), do: "border-emerald-400/40"
  defp status_panel_border("retrying"), do: "border-amber-400/40"
  defp status_panel_border("idle"), do: "border-emerald-400/40"
  defp status_panel_border("failed"), do: "border-red-400/40"
  defp status_panel_border("expired"), do: "border-zinc-700"
  defp status_panel_border(_status), do: "border-zinc-800"

  defp status_icon("created"), do: "hero-arrow-path"
  defp status_icon("queued"), do: "hero-clock"
  defp status_icon("processing"), do: "hero-arrow-path"
  defp status_icon("retrying"), do: "hero-arrow-path"
  defp status_icon("idle"), do: "hero-check-circle"
  defp status_icon("failed"), do: "hero-exclamation-triangle"
  defp status_icon("expired"), do: "hero-no-symbol"
  defp status_icon(_status), do: "hero-question-mark-circle"

  defp status_icon_class("created"), do: "text-zinc-400 motion-safe:animate-spin"
  defp status_icon_class("queued"), do: "text-sky-400"
  defp status_icon_class("processing"), do: "text-emerald-400 motion-safe:animate-spin"
  defp status_icon_class("retrying"), do: "text-amber-400 motion-safe:animate-spin"
  defp status_icon_class("idle"), do: "text-emerald-400"
  defp status_icon_class("failed"), do: "text-red-400"
  defp status_icon_class("expired"), do: "text-zinc-500"
  defp status_icon_class(_status), do: "text-zinc-400"

  defp message_alignment(role) when role in ["assistant", :assistant], do: "justify-start"
  defp message_alignment(_role), do: "justify-end"

  defp message_grid_alignment(role) when role in ["assistant", :assistant],
    do: "justify-items-start"

  defp message_grid_alignment(_role), do: "justify-items-end"

  defp message_meta_alignment(role) when role in ["assistant", :assistant],
    do: "justify-start text-left"

  defp message_meta_alignment(_role), do: "justify-end text-right"

  defp message_role_label(role) when role in ["assistant", :assistant],
    do: dgettext("lemmings", "Assistant")

  defp message_role_label(_role), do: dgettext("lemmings", "User")

  defp message_bubble_tone(role) when role in ["assistant", :assistant],
    do: "border-emerald-400/15 bg-gradient-to-b from-emerald-950/45 to-zinc-950/95 rounded-tl-md"

  defp message_bubble_tone(_role),
    do: "border-sky-400/20 bg-gradient-to-b from-sky-950/40 to-zinc-950/95 rounded-tr-md"

  defp message_avatar_tone(role) when role in ["assistant", :assistant],
    do: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"

  defp message_avatar_tone(_role),
    do: "border-sky-400/30 bg-sky-400/10 text-sky-300"

  defp message_avatar_label(role) when role in ["assistant", :assistant], do: "AI"
  defp message_avatar_label(_role), do: "You"

  defp assistant_metadata?(role) when role in ["assistant", :assistant], do: true
  defp assistant_metadata?(_role), do: false

  defp icon_class(status) do
    Enum.join(["mt-0.5 size-5 shrink-0", status_icon_class(status)], " ")
  end

  defp runtime_current_item_label(%{current_item: %{content: content}})
       when is_binary(content) and content != "",
       do: content

  defp runtime_current_item_label(%{current_item: %{content: content}}), do: inspect(content)

  defp runtime_current_item_label(%{current_item: current_item}) when is_binary(current_item),
    do: current_item

  defp runtime_current_item_label(%{current_item: current_item}), do: inspect(current_item)

  defp runtime_current_item_preview(runtime_state) do
    runtime_state
    |> runtime_current_item_label()
    |> truncate_words(6)
  end

  defp truncate_words(value, max_words) when is_binary(value) and max_words > 0 do
    words = String.split(value, ~r/\s+/, trim: true)

    case Enum.split(words, max_words) do
      {[], _rest} -> value
      {visible_words, []} -> Enum.join(visible_words, " ")
      {visible_words, _rest} -> Enum.join(visible_words, " ") <> " ..."
    end
  end

  defp truncate_words(value, _max_words), do: value

  defp message_clock_label(%DateTime{} = inserted_at), do: Calendar.strftime(inserted_at, "%H:%M")

  defp message_clock_label(_inserted_at), do: dgettext("lemmings", "Unknown time")

  defp message_age_label(%DateTime{} = inserted_at, %DateTime{} = display_now) do
    seconds = max(DateTime.diff(display_now, inserted_at, :second), 0)

    cond do
      seconds < 60 -> dgettext("lemmings", "now")
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp message_age_label(%DateTime{} = inserted_at, _display_now) do
    message_age_label(inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp message_age_label(_inserted_at, _display_now), do: nil
end
