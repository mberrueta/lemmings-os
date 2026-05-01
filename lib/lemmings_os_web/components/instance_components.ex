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
  attr :speaker_name, :string, default: nil
  attr :speaker_avatar_label, :string, default: nil
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
            {message_avatar_label(@message_role, @speaker_avatar_label)}
          </span>
          <span>{message_role_label(@message_role, @speaker_name)}</span>
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

  attr :id, :string, required: true
  attr :tool_execution, :map, required: true
  attr :world_id, :string, default: nil
  attr :promotion_candidate, :map, default: nil
  attr :promoted_artifact, :map, default: nil
  attr :promotion_action, :atom, default: :none
  attr :promotion_message, :map, default: nil
  attr :display_now, :any, default: nil
  attr :class, :string, default: nil

  def tool_execution_card(assigns) do
    status = normalize_tool_status(assigns.tool_execution.status)

    assigns =
      assigns
      |> assign(:tool_status, status)
      |> assign(:tool_details_id, "tool-execution-details-#{assigns.tool_execution.id}")
      |> assign(:args_payload, tool_payload_json(assigns.tool_execution.args))
      |> assign(:result_payload, tool_payload_json(assigns.tool_execution.result))
      |> assign(:error_payload, tool_payload_json(assigns.tool_execution.error))
      |> assign(:artifact_link, tool_artifact_link(assigns.tool_execution, assigns.world_id))
      |> assign(:promotion_form_id, "artifact-promotion-form-#{assigns.tool_execution.id}")
      |> assign(:promotion_status_id, "artifact-promotion-status-#{assigns.tool_execution.id}")
      |> assign(:promotion_heading_id, "artifact-promotion-heading-#{assigns.tool_execution.id}")
      |> assign(:promotion_help_id, "artifact-promotion-help-#{assigns.tool_execution.id}")
      |> assign(
        :promotion_help_summary_id,
        "artifact-promotion-help-summary-#{assigns.tool_execution.id}"
      )
      |> assign(
        :promotion_help_text_id,
        "artifact-promotion-help-text-#{assigns.tool_execution.id}"
      )
      |> assign(:artifact_reference_id, "artifact-reference-#{assigns.tool_execution.id}")
      |> assign(
        :artifact_notes_toggle_id,
        "artifact-reference-notes-toggle-#{assigns.tool_execution.id}"
      )
      |> assign(
        :artifact_notes_summary_id,
        "artifact-reference-notes-summary-#{assigns.tool_execution.id}"
      )
      |> assign(:artifact_notes_id, "artifact-reference-notes-#{assigns.tool_execution.id}")

    ~H"""
    <article
      id={@id}
      class={["flex w-full justify-start", @class]}
      data-role="tool"
      data-status={@tool_status}
    >
      <div class="grid w-full max-w-[80%] min-w-[18rem] justify-items-start gap-2">
        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class={[
            "inline-flex size-8 items-center justify-center rounded-full border text-xs font-semibold",
            tool_avatar_tone(@tool_status)
          ]}>
            {dgettext("lemmings", "Tool")}
          </span>
          <span>{dgettext("lemmings", "Tool run")}</span>
          <.badge tone={tool_status_badge_tone(@tool_status)}>
            {tool_status_label(@tool_status)}
          </.badge>
        </div>

        <div class={[
          "w-full rounded-2xl border px-4 py-3",
          tool_card_tone(@tool_status)
        ]}>
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="min-w-0 space-y-1">
              <p class="font-mono text-sm font-semibold text-zinc-100">
                {@tool_execution.tool_name}
              </p>
              <p
                id={"tool-execution-summary-#{@tool_execution.id}"}
                class="text-sm leading-6 text-zinc-200"
              >
                <span :if={@artifact_link}>
                  {tool_summary_prefix(@tool_execution)}
                  <.link
                    href={@artifact_link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="font-mono text-sky-300 underline decoration-sky-400/40 underline-offset-4 hover:text-sky-200"
                  >
                    {@artifact_link.label}
                  </.link>
                </span>
                <span :if={!@artifact_link}>
                  {tool_summary(@tool_execution)}
                </span>
              </p>
            </div>

            <div class="flex shrink-0 flex-wrap justify-end gap-2">
              <.badge tone="muted">
                {tool_argument_count_label(@tool_execution.args)}
              </.badge>
              <.badge :if={tool_duration_label(@tool_execution)} tone="muted">
                {tool_duration_label(@tool_execution)}
              </.badge>
            </div>
          </div>

          <p
            :if={tool_preview(@tool_execution)}
            id={"tool-execution-preview-#{@tool_execution.id}"}
            class="mt-3 border-t border-zinc-800 pt-3 text-sm leading-6 text-zinc-400"
          >
            {tool_preview(@tool_execution)}
          </p>

          <div
            :if={@promotion_candidate}
            class="mt-3 rounded-xl border border-zinc-800 bg-zinc-950/70 p-3"
            role="region"
            aria-labelledby={@promotion_heading_id}
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div class="space-y-1">
                <div class="flex items-center gap-4">
                  <p
                    id={@promotion_heading_id}
                    class="text-xs uppercase tracking-widest text-zinc-500"
                  >
                    {dgettext("lemmings", "Artifact promotion")}
                  </p>
                  <details id={@promotion_help_id} class="relative">
                    <summary
                      id={@promotion_help_summary_id}
                      aria-controls={@promotion_help_text_id}
                      class="inline-flex size-6 cursor-pointer list-none items-center justify-center rounded-full border border-zinc-700 bg-zinc-900/70 text-xs font-semibold text-zinc-300 hover:border-zinc-500 hover:text-zinc-100"
                    >
                      <span aria-hidden="true">i</span>
                      <span class="sr-only">
                        {dgettext("lemmings", "Show Artifact help")}
                      </span>
                    </summary>
                    <p
                      id={@promotion_help_text_id}
                      class="mt-2 max-w-sm rounded-lg border border-zinc-700 bg-zinc-950 px-2 py-1 text-xs leading-6 text-zinc-300"
                    >
                      {dgettext(
                        "lemmings",
                        "An Artifact is a promoted, durable file reference with tracked metadata and lifecycle state."
                      )}
                    </p>
                  </details>
                </div>
                <p
                  id={"artifact-promotion-source-#{@tool_execution.id}"}
                  class="break-words font-mono text-xs leading-6 text-zinc-400"
                >
                  {@promotion_candidate.relative_path}
                </p>
              </div>
              <.badge :if={@promoted_artifact} tone="success">
                {dgettext("lemmings", "Promoted")}
              </.badge>
            </div>

            <form
              :if={@promotion_action in [:promote, :update_existing]}
              id={@promotion_form_id}
              class="mt-3 flex flex-wrap gap-2"
              phx-submit="promote_workspace_artifact"
              aria-describedby={"artifact-promotion-source-#{@tool_execution.id} #{@promotion_help_text_id} #{@promotion_status_id}"}
            >
              <input
                id={"artifact-promotion-tool-execution-id-#{@tool_execution.id}"}
                type="hidden"
                name="artifact_promotion[tool_execution_id]"
                value={@tool_execution.id}
              />
              <input
                id={"artifact-promotion-relative-path-#{@tool_execution.id}"}
                type="hidden"
                name="artifact_promotion[relative_path]"
                value={@promotion_candidate.relative_path}
              />

              <button
                :if={@promotion_action == :promote}
                id={"artifact-promote-button-#{@tool_execution.id}"}
                type="submit"
                phx-disable-with={dgettext("lemmings", "Promoting...")}
                aria-label={dgettext("lemmings", "Promote workspace file to Artifact")}
                aria-describedby={@promotion_status_id}
                class="inline-flex min-h-10 items-center gap-2 border border-emerald-400/40 bg-emerald-400/10 px-3 py-2 text-xs font-medium uppercase tracking-widest text-emerald-300 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-300 hover:text-emerald-200"
              >
                <.icon name="hero-arrow-up-tray" class="size-4" />
                {dgettext("lemmings", "Promote to Artifact")}
              </button>

              <button
                :if={@promotion_action == :update_existing}
                id={"artifact-update-button-#{@tool_execution.id}"}
                type="submit"
                name="artifact_promotion[mode]"
                value="update_existing"
                phx-disable-with={dgettext("lemmings", "Updating...")}
                aria-label={dgettext("lemmings", "Update existing Artifact from workspace file")}
                aria-describedby={@promotion_status_id}
                class="inline-flex min-h-10 items-center gap-2 border border-amber-400/40 bg-amber-400/10 px-3 py-2 text-xs font-medium uppercase tracking-widest text-amber-200 transition duration-150 ease-out hover:-translate-y-px hover:border-amber-300 hover:text-amber-100"
              >
                <.icon name="hero-arrow-path" class="size-4" />
                {dgettext("lemmings", "Update Artifact")}
              </button>

              <button
                :if={@promotion_action == :update_existing}
                id={"artifact-promote-as-new-button-#{@tool_execution.id}"}
                type="submit"
                name="artifact_promotion[mode]"
                value="promote_as_new"
                phx-disable-with={dgettext("lemmings", "Promoting...")}
                aria-label={dgettext("lemmings", "Promote as new Artifact from workspace file")}
                aria-describedby={@promotion_status_id}
                class="inline-flex min-h-10 items-center gap-2 border border-sky-400/40 bg-sky-400/10 px-3 py-2 text-xs font-medium uppercase tracking-widest text-sky-200 transition duration-150 ease-out hover:-translate-y-px hover:border-sky-300 hover:text-sky-100"
              >
                <.icon name="hero-document-duplicate" class="size-4" />
                {dgettext("lemmings", "Promote as New Artifact")}
              </button>
            </form>

            <p
              :if={@promotion_message}
              id={@promotion_status_id}
              class={[
                "mt-3 text-sm",
                if(@promotion_message.kind == :error, do: "text-red-300", else: "text-emerald-300")
              ]}
              role={if(@promotion_message.kind == :error, do: "alert", else: "status")}
              aria-live={if(@promotion_message.kind == :error, do: "assertive", else: "polite")}
              aria-atomic="true"
              tabindex="-1"
              phx-mounted={Phoenix.LiveView.JS.focus(to: "##{@promotion_status_id}")}
            >
              {@promotion_message.text}
            </p>
            <section
              :if={@promoted_artifact}
              id={@artifact_reference_id}
              class="mt-3 rounded-xl border border-emerald-400/20 bg-emerald-950/20 p-3"
            >
              <div class="flex flex-wrap items-center justify-between gap-3 text-xs">
                <p
                  id={"artifact-reference-summary-#{@tool_execution.id}"}
                  class="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-zinc-200"
                >
                  <span class="font-mono text-emerald-200">{@promoted_artifact.filename}</span>
                  <span class="text-zinc-500">({@promoted_artifact.status})</span>
                  <span class="text-zinc-300">{@promoted_artifact.type}</span>
                  <span class="text-zinc-500">-</span>
                  <span class="text-zinc-300">
                    {artifact_size_label(@promoted_artifact.size_bytes)}
                  </span>
                  <span class="text-zinc-500">.</span>
                  <span class="text-zinc-400">
                    {dgettext("lemmings", "Created")} {artifact_created_at_label(
                      @promoted_artifact.inserted_at
                    )}
                  </span>
                </p>
                <.link
                  :if={artifact_download_link(@tool_execution, @promoted_artifact, @world_id)}
                  id={"artifact-reference-download-#{@tool_execution.id}"}
                  href={artifact_download_link(@tool_execution, @promoted_artifact, @world_id)}
                  aria-label={
                    dgettext("lemmings", "Download Artifact %{filename}",
                      filename: @promoted_artifact.filename
                    )
                  }
                  class="text-xs uppercase tracking-widest text-sky-300 underline decoration-sky-400/40 underline-offset-4 hover:text-sky-200"
                >
                  {dgettext("lemmings", "Download")}
                </.link>
              </div>

              <details
                :if={present_text?(@promoted_artifact.notes)}
                id={@artifact_notes_toggle_id}
                class="mt-3 border-t border-emerald-400/20 pt-3"
              >
                <summary
                  id={@artifact_notes_summary_id}
                  aria-controls={@artifact_notes_id}
                  class="cursor-pointer text-xs uppercase tracking-widest text-zinc-400"
                >
                  {dgettext("lemmings", "Notes")}
                </summary>
                <p
                  id={@artifact_notes_id}
                  class="mt-2 whitespace-pre-wrap break-words text-sm text-zinc-200"
                >
                  {@promoted_artifact.notes}
                </p>
              </details>
            </section>
          </div>

          <details id={@tool_details_id} class="mt-3 border-t border-zinc-800 pt-3">
            <summary class="cursor-pointer text-xs uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", "Inspect persisted details")}
            </summary>

            <div class="mt-3 grid gap-3">
              <div>
                <p class="text-xs uppercase tracking-widest text-zinc-500">
                  {dgettext("lemmings", "Arguments")}
                </p>
                <pre
                  id={"tool-execution-args-#{@tool_execution.id}"}
                  class="mt-2 overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950/80 p-3 text-xs leading-6 text-zinc-300"
                >{@args_payload}</pre>
              </div>

              <div :if={@tool_execution.result}>
                <p class="text-xs uppercase tracking-widest text-zinc-500">
                  {dgettext("lemmings", "Result")}
                </p>
                <pre
                  id={"tool-execution-result-#{@tool_execution.id}"}
                  class="mt-2 overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950/80 p-3 text-xs leading-6 text-zinc-300"
                >{@result_payload}</pre>
              </div>

              <div :if={@tool_execution.error}>
                <p class="text-xs uppercase tracking-widest text-zinc-500">
                  {dgettext("lemmings", "Error")}
                </p>
                <pre
                  id={"tool-execution-error-#{@tool_execution.id}"}
                  class="mt-2 overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950/80 p-3 text-xs leading-6 text-zinc-300"
                >{@error_payload}</pre>
              </div>
            </div>
          </details>
        </div>

        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="text-zinc-400">{message_clock_label(@tool_execution.inserted_at)}</span>
          <span class="text-zinc-600">
            {message_age_label(@tool_execution.inserted_at, @display_now)}
          </span>
        </div>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :call, :map, required: true
  attr :display_now, :any, default: nil

  def delegation_intent_row(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex w-full justify-start"
      data-role="delegation-intent"
    >
      <div class="grid w-fit max-w-[80%] min-w-[18rem] justify-items-start gap-2">
        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="inline-flex size-8 items-center justify-center rounded-full border border-emerald-400/30 bg-emerald-400/10 text-xs font-semibold text-emerald-300">
            {delegation_avatar_label(@call.caller_label)}
          </span>
          <span>{header_name(@call.caller_label)}</span>
          <.badge tone="info">{dgettext("lemmings", "Manager")}</.badge>
        </div>

        <div class="w-full rounded-2xl rounded-tl-md border border-emerald-400/15 bg-gradient-to-b from-emerald-950/45 to-zinc-950/95 px-4 py-3">
          <p
            id={"delegation-intent-copy-#{@call.id}"}
            class="whitespace-pre-wrap break-words text-sm leading-6 text-zinc-100"
          >
            {delegation_intent_copy(@call)}
          </p>
        </div>

        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="text-zinc-400">{message_clock_label(@call.requested_at)}</span>
          <span class="text-zinc-600">{message_age_label(@call.requested_at, @display_now)}</span>
        </div>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :call, :map, required: true
  attr :display_now, :any, default: nil

  def manager_request_row(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex w-full justify-start"
      data-role="manager-request"
    >
      <div class="grid w-fit max-w-[80%] min-w-[18rem] justify-items-start gap-2">
        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="inline-flex size-8 items-center justify-center rounded-full border border-emerald-400/30 bg-emerald-400/10 text-xs font-semibold text-emerald-300">
            {delegation_avatar_label(@call.caller_label)}
          </span>
          <span>{header_name(@call.caller_label)}</span>
          <.badge tone="info">{dgettext("lemmings", "Manager")}</.badge>
        </div>

        <div class="w-full rounded-2xl rounded-tl-md border border-emerald-400/15 bg-gradient-to-b from-emerald-950/45 to-zinc-950/95 px-4 py-3">
          <p
            id={"manager-request-copy-#{@call.id}"}
            class="whitespace-pre-wrap break-words text-sm leading-6 text-zinc-100"
          >
            {@call.request_text}
          </p>
        </div>

        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="text-zinc-400">{message_clock_label(@call.requested_at)}</span>
          <span class="text-zinc-600">{message_age_label(@call.requested_at, @display_now)}</span>
        </div>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :call, :map, required: true
  attr :manager_view?, :boolean, default: false
  attr :display_now, :any, default: nil

  def delegated_call_row(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex w-full justify-start"
      data-role="delegated"
      data-state={@call.ui_state}
    >
      <div class="grid w-full max-w-[80%] min-w-[18rem] justify-items-start gap-2">
        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="inline-flex size-8 shrink-0 items-center justify-center rounded-full border border-amber-400/30 bg-amber-400/10 text-xs font-semibold text-amber-200">
            {delegation_avatar_label(@call.callee_label)}
          </span>
          <span>{header_name(@call.callee_label)}</span>
          <.badge tone="warning">{dgettext("lemmings", "Delegated")}</.badge>
          <.badge id={"delegated-call-state-#{@call.id}"} tone={@call.ui_state_tone}>
            {@call.ui_state_label}
          </.badge>
          <.badge :if={@call.callee_role == "manager"} tone="info">
            {dgettext("lemmings", "Manager")}
          </.badge>
          <.badge :if={@call.callee_role == "worker"} tone="muted">
            {dgettext("lemmings", "Worker")}
          </.badge>
        </div>

        <div class="w-full rounded-2xl border border-amber-400/20 bg-gradient-to-b from-amber-950/20 to-zinc-950/95 px-4 py-3">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 space-y-1">
              <p id={"delegated-call-relationship-#{@call.id}"} class="text-sm text-zinc-200">
                {@call.relationship_copy}
              </p>
              <p id={"delegated-call-request-#{@call.id}"} class="text-sm leading-6 text-zinc-400">
                {@call.request_text}
              </p>
            </div>

            <.link
              :if={@call.callee_instance_path}
              id={"delegated-call-open-child-#{@call.id}"}
              navigate={@call.callee_instance_path}
              class="inline-flex items-center gap-2 text-xs uppercase tracking-widest text-sky-300 hover:text-sky-200"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              {dgettext("lemmings", "Open child")}
            </.link>
          </div>

          <div
            :if={@call.state_copy}
            class="mt-3 rounded-xl border border-zinc-800 bg-zinc-950/70 px-3 py-3"
          >
            <p id={"delegated-call-state-copy-#{@call.id}"} class="text-sm leading-6 text-zinc-300">
              {@call.state_copy}
            </p>
          </div>

          <div class="mt-3 grid gap-2 text-xs uppercase tracking-widest text-zinc-500 sm:grid-cols-2">
            <div id={"delegated-call-requested-at-#{@call.id}"}>
              {dgettext("lemmings", "Requested")} {message_clock_label(@call.requested_at)}
            </div>
            <div id={"delegated-call-completed-at-#{@call.id}"}>
              {dgettext("lemmings", "Completed")} {message_clock_label(@call.completed_at)}
            </div>
          </div>

          <details
            id={"delegated-call-details-#{@call.id}"}
            class="mt-3 border-t border-zinc-800 pt-3"
            open={@call.ui_state in ["queued", "running", "retrying", "recovery_pending"]}
          >
            <summary class="cursor-pointer text-xs uppercase tracking-widest text-zinc-500">
              {dgettext("lemmings", "Inspect delegated work")}
            </summary>

            <div class="mt-3 grid gap-3">
              <div
                :if={@call.result_summary}
                id={"delegated-call-result-#{@call.id}"}
                class="rounded-xl border border-emerald-400/20 bg-emerald-950/20 px-3 py-3"
              >
                <p class="text-xs uppercase tracking-widest text-emerald-300">
                  {dgettext("lemmings", "Result summary")}
                </p>
                <p class="mt-2 text-sm leading-6 text-zinc-200">{@call.result_summary}</p>
              </div>

              <div
                :if={@call.error_summary}
                id={"delegated-call-error-#{@call.id}"}
                class="rounded-xl border border-red-400/20 bg-red-950/20 px-3 py-3"
              >
                <p class="text-xs uppercase tracking-widest text-red-300">
                  {dgettext("lemmings", "Error summary")}
                </p>
                <p class="mt-2 text-sm leading-6 text-zinc-200">{@call.error_summary}</p>
              </div>

              <div class="grid gap-3 sm:grid-cols-2">
                <div
                  id={"delegated-call-caller-#{@call.id}"}
                  class="rounded-xl border border-zinc-800 bg-zinc-950/80 px-3 py-3"
                >
                  <p class="text-xs uppercase tracking-widest text-zinc-500">
                    {dgettext("lemmings", "Caller")}
                  </p>
                  <p class="mt-2 text-sm text-zinc-100">{@call.caller_label}</p>
                  <p class="mt-1 text-xs uppercase tracking-widest text-zinc-500">
                    {@call.caller_role}
                    <span :if={@call.caller_department}>
                      / {@call.caller_department}
                    </span>
                  </p>
                  <.link
                    :if={!@manager_view? and @call.caller_instance_path}
                    id={"delegated-call-open-parent-#{@call.id}"}
                    navigate={@call.caller_instance_path}
                    class="mt-3 inline-flex items-center gap-2 text-xs uppercase tracking-widest text-sky-300 hover:text-sky-200"
                  >
                    <.icon name="hero-arrow-left" class="size-4" />
                    {dgettext("lemmings", "Open manager")}
                  </.link>
                </div>

                <div
                  id={"delegated-call-callee-#{@call.id}"}
                  class="rounded-xl border border-zinc-800 bg-zinc-950/80 px-3 py-3"
                >
                  <p class="text-xs uppercase tracking-widest text-zinc-500">
                    {dgettext("lemmings", "Child")}
                  </p>
                  <p class="mt-2 text-sm text-zinc-100">{@call.callee_label}</p>
                  <p class="mt-1 text-xs uppercase tracking-widest text-zinc-500">
                    {@call.callee_role}
                    <span :if={@call.callee_department}>
                      / {@call.callee_department}
                    </span>
                  </p>
                </div>
              </div>
            </div>
          </details>
        </div>

        <div class="flex items-center gap-2 px-1 text-xs uppercase tracking-widest text-zinc-500">
          <span class="text-zinc-400">{message_clock_label(@call.requested_at)}</span>
          <span class="text-zinc-600">{message_age_label(@call.requested_at, @display_now)}</span>
        </div>
      </div>
    </article>
    """
  end

  defp normalize_status(status) when is_binary(status), do: status
  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(_status), do: "created"

  defp normalize_tool_status(status) when is_binary(status), do: status
  defp normalize_tool_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_tool_status(_status), do: "running"

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

  defp message_role_label(role, speaker_name)
       when role in ["assistant", :assistant] and is_binary(speaker_name) and speaker_name != "" do
    String.upcase(speaker_name)
  end

  defp message_role_label(role, _speaker_name) when role in ["assistant", :assistant],
    do: dgettext("lemmings", "Assistant")

  defp message_role_label(_role, _speaker_name), do: dgettext("lemmings", "User")

  defp message_bubble_tone(role) when role in ["assistant", :assistant],
    do: "border-emerald-400/15 bg-gradient-to-b from-emerald-950/45 to-zinc-950/95 rounded-tl-md"

  defp message_bubble_tone(_role),
    do: "border-sky-400/20 bg-gradient-to-b from-sky-950/40 to-zinc-950/95 rounded-tr-md"

  defp message_avatar_tone(role) when role in ["assistant", :assistant],
    do: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"

  defp message_avatar_tone(_role),
    do: "border-sky-400/30 bg-sky-400/10 text-sky-300"

  defp message_avatar_label(role, speaker_avatar_label)
       when role in ["assistant", :assistant] and is_binary(speaker_avatar_label) and
              speaker_avatar_label != "" do
    speaker_avatar_label
  end

  defp message_avatar_label(role, _speaker_avatar_label) when role in ["assistant", :assistant],
    do: "AI"

  defp message_avatar_label(_role, _speaker_avatar_label), do: "You"

  defp tool_card_tone("running"),
    do: "border-amber-400/20 bg-gradient-to-b from-amber-950/30 to-zinc-950/95"

  defp tool_card_tone("ok"),
    do: "border-emerald-400/20 bg-gradient-to-b from-emerald-950/30 to-zinc-950/95"

  defp tool_card_tone("error"),
    do: "border-red-400/20 bg-gradient-to-b from-red-950/25 to-zinc-950/95"

  defp tool_card_tone(_status), do: "border-zinc-800 bg-zinc-950/95"

  defp tool_avatar_tone("running"), do: "border-amber-400/30 bg-amber-400/10 text-amber-200"
  defp tool_avatar_tone("ok"), do: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300"
  defp tool_avatar_tone("error"), do: "border-red-400/30 bg-red-400/10 text-red-300"
  defp tool_avatar_tone(_status), do: "border-zinc-700 bg-zinc-900/80 text-zinc-300"

  defp tool_status_badge_tone("running"), do: "warning"
  defp tool_status_badge_tone("ok"), do: "success"
  defp tool_status_badge_tone("error"), do: "danger"
  defp tool_status_badge_tone(_status), do: "muted"

  defp tool_status_label("running"), do: dgettext("lemmings", "Running")
  defp tool_status_label("ok"), do: dgettext("lemmings", "Completed")
  defp tool_status_label("error"), do: dgettext("lemmings", "Failed")
  defp tool_status_label(status), do: status

  defp tool_summary(%{summary: summary}) when is_binary(summary) and summary != "", do: summary

  defp tool_summary(%{status: "running"}),
    do: dgettext("lemmings", "Tool execution is still running.")

  defp tool_summary(%{status: "ok"}),
    do: dgettext("lemmings", "Tool execution completed successfully.")

  defp tool_summary(%{status: "error"} = tool_execution) do
    tool_error_code = tool_execution |> Map.get(:error, %{}) |> Map.get("code")

    if is_binary(tool_error_code) and tool_error_code != "" do
      dgettext("lemmings", "Tool execution failed with code %{code}.", code: tool_error_code)
    else
      dgettext("lemmings", "Tool execution failed.")
    end
  end

  defp tool_summary(_tool_execution), do: dgettext("lemmings", "Tool execution recorded.")

  defp tool_summary_prefix(%{summary: summary} = tool_execution)
       when is_binary(summary) and summary != "" do
    case tool_execution.tool_name do
      "fs.write_text_file" ->
        "Wrote file "

      "fs.read_text_file" ->
        "Read file "

      _tool_name ->
        case tool_artifact_label(tool_execution) do
          label when is_binary(label) ->
            String.replace(summary, label, "")
            |> String.trim()
            |> ensure_trailing_space()

          _label ->
            ensure_trailing_space(summary)
        end
    end
  end

  defp tool_summary_prefix(tool_execution),
    do: ensure_trailing_space(tool_summary(tool_execution))

  defp tool_preview(%{preview: preview}) when is_binary(preview) and preview != "", do: preview

  defp tool_preview(%{status: "error", error: error}) when is_map(error) do
    error
    |> Map.get("message")
    |> normalize_preview_copy()
  end

  defp tool_preview(%{result: result}) when is_map(result) do
    result
    |> Map.get("path")
    |> normalize_preview_copy()
  end

  defp tool_preview(_tool_execution), do: nil

  defp tool_artifact_link(tool_execution, world_id) do
    with true <- tool_execution.tool_name == "fs.write_text_file",
         true <- is_binary(world_id) and world_id != "",
         label when is_binary(label) <- tool_artifact_label(tool_execution),
         true <- Path.type(label) == :relative,
         path_segments when is_list(path_segments) <- String.split(label, "/", trim: true),
         true <- path_segments != [] do
      %{
        label: label,
        href:
          ~p"/lemmings/instances/#{tool_execution.lemming_instance_id}/artifacts/#{path_segments}?#{%{world: world_id}}"
      }
    else
      _ -> nil
    end
  end

  defp tool_artifact_label(%{args: %{"path" => path}}) when is_binary(path) and path != "",
    do: path

  defp tool_artifact_label(%{args: %{path: path}}) when is_binary(path) and path != "", do: path

  defp tool_artifact_label(%{result: %{"path" => path}}) when is_binary(path) and path != "",
    do: path

  defp tool_artifact_label(%{result: %{path: path}}) when is_binary(path) and path != "", do: path
  defp tool_artifact_label(_tool_execution), do: nil

  defp artifact_download_link(
         %{lemming_instance_id: instance_id},
         %{id: artifact_id, status: "ready"},
         world_id
       )
       when is_binary(instance_id) and is_binary(artifact_id) and is_binary(world_id) and
              world_id != "" do
    ~p"/lemmings/instances/#{instance_id}/artifacts/#{artifact_id}/download?#{%{world: world_id}}"
  end

  defp artifact_download_link(_tool_execution, _artifact, _world_id), do: nil

  defp artifact_size_label(size_bytes) when is_integer(size_bytes) and size_bytes >= 0,
    do: dgettext("lemmings", "%{count} bytes", count: size_bytes)

  defp artifact_size_label(_size_bytes), do: dgettext("lemmings", "Unknown size")

  defp artifact_created_at_label(%DateTime{} = inserted_at),
    do: Calendar.strftime(inserted_at, "%Y-%m-%d %H:%M UTC")

  defp artifact_created_at_label(_inserted_at), do: dgettext("lemmings", "Unknown time")

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false

  defp ensure_trailing_space(value) when is_binary(value) and value != "" do
    if String.ends_with?(value, " "), do: value, else: value <> " "
  end

  defp ensure_trailing_space(_value), do: ""

  defp normalize_preview_copy(value) when is_binary(value) and value != "", do: value
  defp normalize_preview_copy(_value), do: nil

  defp tool_duration_label(%{duration_ms: duration_ms})
       when is_integer(duration_ms) and duration_ms >= 0 do
    dgettext("lemmings", "%{count} ms", count: duration_ms)
  end

  defp tool_duration_label(_tool_execution), do: nil

  defp tool_argument_count_label(args) when is_map(args) do
    dgettext("lemmings", "%{count} args", count: map_size(args))
  end

  defp tool_argument_count_label(_args), do: dgettext("lemmings", "0 args")

  defp tool_payload_json(nil), do: "{}"

  defp tool_payload_json(payload) when is_map(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp tool_payload_json(payload), do: inspect(payload, pretty: true)

  defp assistant_metadata?(role) when role in ["assistant", :assistant], do: true
  defp assistant_metadata?(_role), do: false

  defp delegation_avatar_label(label) when is_binary(label) do
    label
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "AI"
      first_char -> String.upcase(first_char)
    end
  end

  defp delegation_avatar_label(_label), do: "AI"

  defp delegation_intent_copy(%{
         caller_label: caller_label,
         callee_label: callee_label,
         request_text: request_text
       })
       when is_binary(caller_label) and is_binary(callee_label) and is_binary(request_text) do
    "#{caller_label} is delegating to #{callee_label}: #{request_text}"
  end

  defp delegation_intent_copy(%{callee_label: callee_label, request_text: request_text})
       when is_binary(callee_label) and is_binary(request_text) do
    "Delegating to #{callee_label}: #{request_text}"
  end

  defp delegation_intent_copy(_call),
    do: dgettext("lemmings", "Delegating work to a child lemming.")

  defp header_name(label) when is_binary(label) do
    label
    |> String.trim()
    |> case do
      "" -> dgettext("lemmings", "Unknown")
      value -> String.upcase(value)
    end
  end

  defp header_name(_label), do: dgettext("lemmings", "UNKNOWN")

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
