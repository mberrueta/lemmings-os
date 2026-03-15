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
  attr :summary, :map, default: %{}
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:summary, fn -> LemmingsOs.MockData.summary() end)
      |> assign(:terminal_path, "C:\\LEMMINGS_OS\\#{page_segment(assigns.page_key)}")

    ~H"""
    <div class="app-shell">
      <SidebarComponents.sidebar active_page={@page_key} summary={@summary} />

      <div id="mobile-backdrop" class="mobile-backdrop" phx-click={toggle_mobile_nav()} />

      <div class="app-main">
        <div class="mobile-header">
          <button
            class="mobile-burger"
            phx-click={toggle_mobile_nav()}
            aria-label="Open navigation"
            aria-controls="app-sidebar"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <span class="mobile-header__brand">LemmingsOS</span>
        </div>

        <.terminal_bar
          id="app-terminal-bar"
          path={@terminal_path}
          title={@page_title}
          metrics={[
            "MEM: #{@summary.mem}",
            "TICK: #{@summary.tick}",
            "AGENTS: #{@summary.agents_count}/#{@summary.max_agents}"
          ]}
        />

        <main class="app-content">
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
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp toggle_mobile_nav do
    JS.toggle_class("mobile-open", to: "#app-sidebar")
    |> JS.toggle_class("mobile-open", to: "#mobile-backdrop")
  end

  defp page_segment(page_key) do
    page_key |> Atom.to_string() |> String.upcase()
  end
end
