defmodule LemmingsOsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LemmingsOsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :page_key, :atom, default: :home
  attr :page_title, :string, default: "Home"
  attr :shell_user, :string, default: "operator"
  attr :shell_host, :string, default: "world_a"
  attr :shell_breadcrumb, :list, default: []
  attr :summary, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app-shell grid min-h-screen grid-cols-1 gap-4 p-4 md:grid-cols-[5.5rem_minmax(0,1fr)] md:items-start lg:grid-cols-[18.5rem_minmax(0,1fr)]">
      <SidebarComponents.sidebar active_page={@page_key} summary={@summary} />

      <div
        id="mobile-backdrop"
        class="mobile-backdrop fixed inset-0 z-[99] cursor-pointer bg-black/65 opacity-0 pointer-events-none transition-opacity duration-[220ms]"
        phx-click={close_mobile_nav()}
      />

      <div class="app-main min-w-0 flex flex-col gap-4">
        <div class="mobile-header flex items-center justify-between gap-3 border-[3px] border-[var(--border)] bg-[linear-gradient(180deg,rgba(12,22,15,0.98),rgba(16,25,18,0.98))] px-[0.85rem] py-[0.65rem] shadow-[7px_7px_0_0_var(--shadow)] md:hidden">
          <button
            id="mobile-nav-toggle"
            class="mobile-burger inline-flex items-center justify-center border border-[var(--border-soft)] bg-transparent p-[0.35rem] text-[var(--text)] transition duration-150 hover:border-[var(--accent)] hover:text-[var(--accent)]"
            phx-click={toggle_mobile_nav()}
            aria-label={dgettext("layout", ".aria_open_navigation")}
            aria-controls="app-sidebar"
            aria-expanded="false"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <span class="mobile-header__brand font-[var(--font-display)] text-[0.78rem] uppercase tracking-[0.08em] text-[var(--accent)]">
            {dgettext("layout", ".brand_name")}
          </span>
        </div>

        <.terminal_bar
          id="app-terminal-bar"
          shell_user={@shell_user}
          shell_host={@shell_host}
          breadcrumb={@shell_breadcrumb}
          title={@page_title}
          metrics={[
            dgettext("layout", ".terminal_mem", value: @summary.mem),
            dgettext("layout", ".terminal_tick", value: @summary.tick),
            dgettext("layout", ".terminal_agents",
              current: @summary.agents_count,
              max: @summary.max_agents
            )
          ]}
        />

        <main class="app-content min-w-0">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="flash-stack" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={dgettext("errors", ".error_no_internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {dgettext("errors", ".error_attempting_reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={dgettext("errors", ".error_something_went_wrong")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {dgettext("errors", ".error_attempting_reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp toggle_mobile_nav do
    JS.toggle_class("mobile-open", to: "#app-sidebar")
    |> JS.toggle_class("mobile-open", to: "#mobile-backdrop")
    |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "#mobile-nav-toggle")
  end

  defp close_mobile_nav do
    JS.remove_class("mobile-open", to: "#app-sidebar")
    |> JS.remove_class("mobile-open", to: "#mobile-backdrop")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-nav-toggle")
  end
end
