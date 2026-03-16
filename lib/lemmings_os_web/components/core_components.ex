defmodule LemmingsOsWeb.CoreComponents do
  @moduledoc """
  Shared UI primitives for the LemmingsOS interface.
  """

  use Phoenix.Component
  use Gettext, backend: LemmingsOsWeb.Gettext

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
        "flash-card",
        @kind == :info && "flash-card--info",
        @kind == :error && "flash-card--error"
      ]}
      {@rest}
    >
      <div class="flash-card__icon">
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5" />
        <.icon :if={@kind == :error} name="hero-exclamation-triangle" class="size-5" />
      </div>
      <div class="flash-card__content">
        <p :if={@title} class="flash-card__title">{@title}</p>
        <p>{msg}</p>
      </div>
      <button type="button" class="flash-card__close" aria-label={dgettext("errors", ".aria_close")}>
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type phx-click)

  attr :variant, :string, default: "primary", values: ~w(primary secondary ghost quiet)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :button_class, [
        "ui-button",
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
    <label class="ui-checkbox">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value="true"
        checked={@checked}
        class={@class || "ui-checkbox__input"}
        {@rest}
      />
      <span>{@label}</span>
      <.error :for={msg <- @errors}>{msg}</.error>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="ui-field">
      <label :if={@label} for={@id} class="ui-field__label">{@label}</label>
      <select
        id={@id}
        name={@name}
        class={[@class || "ui-select", @errors != [] && (@error_class || "ui-field--error")]}
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
    <div class="ui-field">
      <label :if={@label} for={@id} class="ui-field__label">{@label}</label>
      <textarea
        id={@id}
        name={@name}
        class={[@class || "ui-textarea", @errors != [] && (@error_class || "ui-field--error")]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="ui-field">
      <label :if={@label} for={@id} class="ui-field__label">{@label}</label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[@class || "ui-input", @errors != [] && (@error_class || "ui-field--error")]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  defp error(assigns) do
    ~H"""
    <p class="ui-field__error">
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
        class="pixel-panel__header flex flex-col gap-[0.8rem] border-b-[3px] border-[var(--border-soft)] p-4"
      >
        <div class="pixel-panel__heading flex min-w-0 flex-col gap-1">
          <h2
            :if={@title != []}
            class="pixel-panel__title font-[var(--font-display)] text-[0.95rem] leading-[1.5] text-[var(--accent)]"
          >
            {render_slot(@title)}
          </h2>
          <p
            :if={@subtitle != []}
            class="pixel-panel__subtitle text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]"
          >
            {render_slot(@subtitle)}
          </p>
        </div>
        <div :if={@actions != []} class="pixel-panel__actions flex flex-wrap gap-[0.6rem]">
          {render_slot(@actions)}
        </div>
      </div>
      <div class="pixel-panel__body flex flex-col gap-4">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def content_container(assigns) do
    ~H"""
    <div class={["page-stack flex flex-col gap-4", @class]}>{render_slot(@inner_block)}</div>
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

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, default: nil
  attr :tone, :string, default: "default", values: ~w(default accent info warning danger)

  def stat_item(assigns) do
    ~H"""
    <div class={["stat-tile", "stat-tile--#{@tone}"]}>
      <p class="stat-tile__label">{@label}</p>
      <p class="stat-tile__value">{@value}</p>
      <p :if={@detail} class="stat-tile__detail">{@detail}</p>
    </div>
    """
  end

  attr :tone, :string, default: "default", values: ~w(default accent info success warning danger)
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["ui-badge", "ui-badge--#{@tone}", @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :copy, :string, required: true
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="empty-state">
      <.icon name="hero-sparkles" class="size-5" />
      <p class="empty-state__title">{@title}</p>
      <p class="empty-state__copy">{@copy}</p>
      <div :if={@action != []}>{render_slot(@action)}</div>
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
      class="terminal-bar flex flex-col gap-3 border-[3px] border-[var(--border)] bg-[linear-gradient(180deg,rgba(12,22,15,0.98),rgba(16,25,18,0.98))] px-4 py-[0.85rem] shadow-[7px_7px_0_0_var(--shadow)]"
    >
      <div class="terminal-bar__path flex flex-wrap items-center gap-3 gap-x-0 text-[0.86rem] text-[var(--accent)]">
        <span class="terminal-bar__prompt-user text-[var(--accent)]">{@shell_user}</span><span>@</span><span class="terminal-bar__prompt-host text-[var(--accent-2)]">{@shell_host}</span><span>:</span><span class="terminal-bar__prompt-root text-[var(--muted)]">/</span><span :if={
          @breadcrumb == []
        }>~</span><span :for={{segment, index} <- Enum.with_index(@breadcrumb)}><span
          :if={index > 0}
          class="terminal-bar__separator text-[var(--muted)]"
        >/</span><.link
          navigate={segment.to}
          class="terminal-bar__crumb text-[var(--accent)] transition-colors hover:text-[var(--accent-2)]"
        >{segment.label}</.link></span><span>$</span><span class="terminal-bar__cursor">█</span>
      </div>
      <div class="terminal-bar__meta flex flex-wrap items-center gap-3 text-[0.86rem] text-[var(--muted)]">
        <span class="terminal-bar__title text-[var(--text)]">{@title}</span>
        <span :for={metric <- @metrics}>{metric}</span>
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
      Gettext.dngettext(LemmingsOsWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LemmingsOsWeb.Gettext, "errors", msg, opts)
    end
  end

  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  defp button_variant("primary"), do: "ui-button--primary"
  defp button_variant("secondary"), do: "ui-button--secondary"
  defp button_variant("ghost"), do: "ui-button--ghost"
  defp button_variant("quiet"), do: "ui-button--quiet"

  defp panel_tone("default"), do: nil
  defp panel_tone("accent"), do: "pixel-panel--accent border-[var(--accent)]"
  defp panel_tone("info"), do: "pixel-panel--info border-[var(--accent-2)]"
  defp panel_tone("warning"), do: "pixel-panel--warning border-[var(--accent-3)]"
  defp panel_tone("danger"), do: "pixel-panel--danger border-[var(--danger)]"

  defp panel_classes(tone, class) do
    [
      "pixel-panel relative min-w-0 border-[3px] border-[var(--border)] bg-[linear-gradient(180deg,rgba(24,40,29,0.96),rgba(14,24,17,0.98))] shadow-[7px_7px_0_0_var(--shadow)]",
      panel_tone(tone),
      class
    ]
  end

  defp grid_variant("default"), do: nil
  defp grid_variant("two"), do: "md:grid-cols-2"
  defp grid_variant("three"), do: "md:grid-cols-3"
  defp grid_variant("sidebar"), do: "lg:grid-cols-[minmax(0,1.4fr)_minmax(19rem,0.95fr)]"
end
