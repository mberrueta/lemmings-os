defmodule LemmingsOsWeb.CoreComponents do
  @moduledoc """
  Shared UI primitives for the LemmingsOS interface.
  """

  use Phoenix.Component
  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Worlds.World
  alias Phoenix.LiveView.JS

  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "grid w-full max-w-sm cursor-pointer grid-cols-3 gap-3 border-2 bg-zinc-950/95 p-4 shadow-xl",
        @kind == :info && "border-sky-400",
        @kind == :error && "border-red-400",
        @kind not in [:info, :error] && "border-zinc-700"
      ]}
      {@rest}
    >
      <div class="flex items-start pt-1">
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 text-sky-400" />
        <.icon :if={@kind == :error} name="hero-exclamation-triangle" class="size-5 text-red-400" />
      </div>
      <div class="flex flex-col gap-1">
        <p :if={@title} class="font-bold text-zinc-100">{@title}</p>
        <p class="text-sm text-zinc-200">{msg}</p>
      </div>
      <button
        type="button"
        class="text-zinc-400 hover:text-zinc-100"
        aria-label={dgettext("errors", ".aria_close")}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form phx-click)

  attr :variant, :string,
    default: "primary",
    values: ~w(primary secondary accent neutral ghost quiet)

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :button_class, [
        "inline-flex min-h-11 items-center justify-center gap-2 px-4 py-2 text-sm font-medium transition-all duration-200 hover:-translate-y-px hover:brightness-110",
        button_variant(assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@button_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <label class="inline-flex items-center gap-2.5 cursor-pointer text-zinc-300 hover:text-zinc-100 transition-colors">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class={
          @class ||
            "size-4 border-2 border-zinc-700 bg-zinc-950 text-emerald-400 focus:ring-emerald-400 focus:ring-offset-zinc-950 rounded-none"
        }
        {@rest}
      />
      <span class="text-sm font-medium">{@label}</span>
      <.error :for={msg <- @errors}>{msg}</.error>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <label
        :if={@label}
        for={@id}
        class="text-xs font-bold uppercase tracking-widest text-zinc-500"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "w-full border-2 border-zinc-700 bg-zinc-950/80 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-emerald-400 transition-all",
          @class,
          @errors != [] && (@error_class || "border-red-400 focus:border-red-400")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <label
        :if={@label}
        for={@id}
        class="text-xs font-bold uppercase tracking-widest text-zinc-500"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "w-full min-h-32 border-2 border-zinc-700 bg-zinc-950/80 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-emerald-400 transition-all resize-vertical",
          @class,
          @errors != [] && (@error_class || "border-red-400 focus:border-red-400")
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="flex flex-col gap-1.5">
      <label
        :if={@label}
        for={@id}
        class="text-xs font-bold uppercase tracking-widest text-zinc-500"
      >
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "w-full border-2 border-zinc-700 bg-zinc-950/80 px-3 py-2.5 text-sm text-zinc-100 outline-none focus:border-emerald-400 transition-all",
          @class,
          @errors != [] && (@error_class || "border-red-400 focus:border-red-400")
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp error(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 mt-1 text-xs font-medium text-red-400">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="page-header">
      <div>
        <h1 class="page-header__title">{render_slot(@inner_block)}</h1>
        <p :if={@subtitle != []} class="page-header__subtitle">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="page-header__actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :id, :string, default: nil
  attr :class, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default accent info warning danger)
  slot :title
  slot :subtitle
  slot :actions
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section id={@id} class={panel_classes(@tone, @class)}>
      <div
        :if={@title != [] || @subtitle != [] || @actions != []}
        class="flex flex-col gap-3 border-b-2 border-zinc-800 p-4 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="flex min-w-0 flex-col gap-1">
          <h2
            :if={@title != []}
            class="font-mono text-base font-medium leading-relaxed text-emerald-400"
          >
            {render_slot(@title)}
          </h2>
          <p
            :if={@subtitle != []}
            class="text-xs uppercase tracking-widest text-zinc-400"
          >
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :if={@actions != []} class="flex flex-wrap gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div class="flex flex-col gap-4 p-4">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def content_container(assigns) do
    ~H"""
    <div class={["flex flex-col gap-4", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  attr :id, :string, default: nil
  attr :columns, :string, default: "two", values: ~w(default two three sidebar)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def content_grid(assigns) do
    ~H"""
    <div id={@id} class={["content-grid grid gap-4", grid_variant(@columns), @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default accent info warning danger)

  def stat_item(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "border-2 border-zinc-800 bg-zinc-950/70 p-4 transition duration-150 hover:border-zinc-700",
        stat_item_tone(@tone)
      ]}
    >
      <p class="text-xs uppercase tracking-widest text-zinc-400">{@label}</p>
      <p class="font-mono text-base font-medium text-zinc-100">{@value}</p>
      <p :if={@detail} class="mt-1 text-xs text-zinc-500">{@detail}</p>
    </div>
    """
  end

  defp stat_item_tone("default"), do: ""
  defp stat_item_tone("accent"), do: "border-emerald-400/30"
  defp stat_item_tone("info"), do: "border-sky-400/30"
  defp stat_item_tone("warning"), do: "border-amber-400/30"
  defp stat_item_tone("danger"), do: "border-red-400/30"

  attr :id, :string, default: nil

  attr :tone, :string,
    default: "default",
    values: ~w(default accent info success warning danger muted)

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex items-center justify-center min-h-7 px-2 py-0.5 border text-xs uppercase tracking-widest font-medium bg-zinc-950/80",
        badge_tone(@tone),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_tone("default"), do: "border-zinc-700 text-zinc-300"
  defp badge_tone("accent"), do: "border-emerald-400/50 text-emerald-400"
  defp badge_tone("info"), do: "border-sky-400/50 text-sky-400"
  defp badge_tone("success"), do: "border-emerald-400/50 text-emerald-400"
  defp badge_tone("warning"), do: "border-amber-400/50 text-amber-400"
  defp badge_tone("danger"), do: "border-red-400/50 text-red-400"
  defp badge_tone("muted"), do: "border-zinc-700 text-zinc-500"

  attr :id, :string, default: nil
  attr :kind, :atom, required: true, values: [:world, :city, :lemming, :instance, :issue]
  attr :value, :any, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def status(assigns) do
    assigns = assign(assigns, :status, status_details(assigns.kind, assigns.value))

    ~H"""
    <.badge
      id={@id}
      tone={@status.tone}
      class={@class}
      data-status={@status.value}
      data-tone={@status.tone}
      {@rest}
    >
      {@status.label}
    </.badge>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :copy, :string, required: true
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-center gap-3 p-8 text-center text-zinc-400">
      <.icon name="hero-sparkles" class="size-6 text-emerald-400/60" />
      <p class="font-bold text-zinc-100">{@title}</p>
      <p class="text-sm">{@copy}</p>
      <div :if={@action != []} class="mt-2">{render_slot(@action)}</div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :shell_user, :string, default: "operator"
  attr :shell_host, :string, default: "world_a"
  attr :breadcrumb, :list, default: []
  attr :title, :string, required: true
  attr :metrics, :list, default: []

  def terminal_bar(assigns) do
    ~H"""
    <div
      id={@id}
      class="flex flex-col gap-3 border-2 border-zinc-800 bg-zinc-950/95 p-4 shadow-xl"
    >
      <div class="flex flex-wrap items-center gap-2 font-mono text-sm text-emerald-400">
        <span class="text-emerald-400">{@shell_user}</span><span>@</span><span class="text-sky-400">{@shell_host}</span><span class="text-zinc-500">:</span><span class="text-zinc-500">/</span><span :if={
          @breadcrumb == []
        }>~</span><span :for={{segment, index} <- Enum.with_index(@breadcrumb)}><span
          :if={index > 0}
          class="text-zinc-600"
        >/</span><.link
          navigate={segment.to}
          class="transition-colors hover:text-sky-400"
        >{segment.label}</.link></span><span class="text-emerald-400">$</span><span class="animate-pulse">█</span>
      </div>
      <div class="flex flex-wrap items-center gap-4 text-sm text-zinc-400">
        <span class="font-bold text-zinc-100">{@title}</span>
        <span :for={metric <- @metrics} class="text-zinc-500">{metric}</span>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 250,
      transition:
        {"transition-all ease-out duration-200", "opacity-0 translate-y-2",
         "opacity-100 translate-y-0"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 180,
      transition:
        {"transition-all ease-in duration-150", "opacity-100 translate-y-0",
         "opacity-0 translate-y-2"}
    )
  end

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(LemmingsOs.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LemmingsOs.Gettext, "errors", msg, opts)
    end
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  defp button_variant("primary"),
    do:
      "border-2 border-emerald-400/50 bg-emerald-400/10 text-emerald-400 shadow-lg shadow-emerald-400/10"

  defp button_variant("secondary"),
    do: "border-2 border-sky-400/50 bg-sky-400/10 text-sky-400 shadow-lg shadow-sky-400/10"

  defp button_variant("accent"),
    do: "border-2 border-emerald-400/60 bg-transparent text-emerald-400 shadow-none"

  defp button_variant("neutral"),
    do: "border-2 border-zinc-700 bg-zinc-950/80 text-zinc-100 shadow-none"

  defp button_variant("ghost"),
    do: "border-2 border-zinc-700 bg-transparent text-zinc-300 shadow-none"

  defp button_variant("quiet"),
    do:
      "border-2 border-transparent bg-transparent text-zinc-400 shadow-none hover:text-zinc-100 hover:border-zinc-800"

  defp panel_tone("default"), do: "border-zinc-800"
  defp panel_tone("accent"), do: "border-emerald-400/60 shadow-emerald-400/5"
  defp panel_tone("info"), do: "border-sky-400/60 shadow-sky-400/5"
  defp panel_tone("warning"), do: "border-amber-400/60 shadow-amber-400/5"
  defp panel_tone("danger"), do: "border-red-400/60 shadow-red-400/5"

  defp panel_classes(tone, class) do
    [
      "relative min-w-0 border-2 bg-zinc-950/95 shadow-xl transition-all",
      panel_tone(tone),
      class
    ]
  end

  defp status_details(:world, status) do
    %{
      tone: world_status_tone(status),
      label: World.translate_status(status),
      value: status_value(status)
    }
  end

  defp status_details(:city, status) do
    %{
      tone: city_status_tone(status),
      label: city_status_label(status),
      value: status_value(status)
    }
  end

  defp status_details(:lemming, status) do
    %{
      tone: lemming_status_tone(status),
      label: lemming_status_label(status),
      value: status_value(status)
    }
  end

  defp status_details(:instance, status) do
    %{
      tone: instance_status_tone(status),
      label: instance_status_label(status),
      value: status_value(status)
    }
  end

  defp status_details(:issue, severity) do
    %{
      tone: issue_status_tone(severity),
      label: issue_status_label(severity),
      value: status_value(severity)
    }
  end

  defp world_status_tone("ok"), do: "success"
  defp world_status_tone("degraded"), do: "warning"
  defp world_status_tone("unavailable"), do: "danger"
  defp world_status_tone("invalid"), do: "danger"
  defp world_status_tone("unknown"), do: "default"
  defp world_status_tone(_status), do: "default"

  defp city_status_tone(:online), do: "success"
  defp city_status_tone(:degraded), do: "warning"
  defp city_status_tone(:offline), do: "danger"
  defp city_status_tone("online"), do: "success"
  defp city_status_tone("degraded"), do: "warning"
  defp city_status_tone("offline"), do: "danger"
  defp city_status_tone("active"), do: "success"
  defp city_status_tone("disabled"), do: "danger"
  defp city_status_tone("draining"), do: "warning"
  defp city_status_tone(_status), do: "default"

  defp city_status_label(:online), do: dgettext("world", ".status_online")
  defp city_status_label(:degraded), do: dgettext("world", ".status_degraded")
  defp city_status_label(:offline), do: dgettext("world", ".status_offline")
  defp city_status_label("online"), do: dgettext("world", ".status_online")
  defp city_status_label("degraded"), do: dgettext("world", ".status_degraded")
  defp city_status_label("offline"), do: dgettext("world", ".status_offline")
  defp city_status_label("active"), do: City.translate_status("active")
  defp city_status_label("disabled"), do: City.translate_status("disabled")
  defp city_status_label("draining"), do: City.translate_status("draining")
  defp city_status_label(_status), do: City.translate_status(nil)

  defp lemming_status_tone(:running), do: "success"
  defp lemming_status_tone(:thinking), do: "warning"
  defp lemming_status_tone(:error), do: "danger"
  defp lemming_status_tone("running"), do: "success"
  defp lemming_status_tone("thinking"), do: "warning"
  defp lemming_status_tone("error"), do: "danger"
  defp lemming_status_tone("draft"), do: "default"
  defp lemming_status_tone("active"), do: "success"
  defp lemming_status_tone("archived"), do: "muted"
  defp lemming_status_tone(_status), do: "default"

  defp lemming_status_label(:running), do: dgettext("lemmings", ".status_running")
  defp lemming_status_label(:thinking), do: dgettext("lemmings", ".status_thinking")
  defp lemming_status_label(:error), do: dgettext("lemmings", ".status_error")
  defp lemming_status_label(:idle), do: dgettext("lemmings", ".status_idle")
  defp lemming_status_label("running"), do: dgettext("lemmings", ".status_running")
  defp lemming_status_label("thinking"), do: dgettext("lemmings", ".status_thinking")
  defp lemming_status_label("error"), do: dgettext("lemmings", ".status_error")
  defp lemming_status_label("idle"), do: dgettext("lemmings", ".status_idle")
  defp lemming_status_label("draft"), do: dgettext("default", ".lemming_status_draft")
  defp lemming_status_label("active"), do: dgettext("default", ".lemming_status_active")
  defp lemming_status_label("archived"), do: dgettext("default", ".lemming_status_archived")

  defp lemming_status_label(status) when is_atom(status) do
    status |> Atom.to_string() |> String.upcase()
  end

  defp lemming_status_label(status) when is_binary(status), do: String.upcase(status)

  defp instance_status_tone("created"), do: "info"
  defp instance_status_tone("queued"), do: "warning"
  defp instance_status_tone("processing"), do: "success"
  defp instance_status_tone("retrying"), do: "warning"
  defp instance_status_tone("idle"), do: "accent"
  defp instance_status_tone("failed"), do: "danger"
  defp instance_status_tone("expired"), do: "muted"
  defp instance_status_tone(_status), do: "default"

  defp instance_status_label(status) when is_atom(status),
    do: status |> Atom.to_string() |> instance_status_label()

  defp instance_status_label(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp issue_status_tone("error"), do: "danger"
  defp issue_status_tone("warning"), do: "warning"
  defp issue_status_tone("info"), do: "info"
  defp issue_status_tone(:error), do: "danger"
  defp issue_status_tone(:warning), do: "warning"
  defp issue_status_tone(:info), do: "info"
  defp issue_status_tone(_severity), do: "default"

  defp issue_status_label("error"), do: dgettext("errors", ".issue_severity_error")
  defp issue_status_label("warning"), do: dgettext("errors", ".issue_severity_warning")
  defp issue_status_label("info"), do: dgettext("errors", ".issue_severity_info")
  defp issue_status_label(:error), do: dgettext("errors", ".issue_severity_error")
  defp issue_status_label(:warning), do: dgettext("errors", ".issue_severity_warning")
  defp issue_status_label(:info), do: dgettext("errors", ".issue_severity_info")

  defp issue_status_label(severity) when is_atom(severity) do
    severity |> Atom.to_string() |> String.upcase()
  end

  defp issue_status_label(severity) when is_binary(severity), do: String.upcase(severity)

  defp status_value(value) when is_atom(value), do: Atom.to_string(value)
  defp status_value(value) when is_binary(value), do: value
  defp status_value(value), do: to_string(value)

  defp grid_variant("default"), do: nil
  defp grid_variant("two"), do: "md:grid-cols-2"
  defp grid_variant("three"), do: "md:grid-cols-3"
  defp grid_variant("sidebar"), do: "lg:grid-cols-2"
end
