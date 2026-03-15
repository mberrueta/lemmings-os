defmodule LemmingsOsWeb.SidebarComponents do
  @moduledoc """
  Shared navigation and shell layout pieces.
  """

  use LemmingsOsWeb, :html

  @app_version Mix.Project.config()[:version]

  attr :active_page, :atom, required: true
  attr :summary, :map, required: true

  def sidebar(assigns) do
    ~H"""
    <aside id="app-sidebar" class="app-sidebar">
      <.app_version_badge />

      <div class="sidebar-brand">
        <div class="sidebar-brand__identity">
          <LemmingComponents.lemming_logo size={32} animation="blink" class="sidebar-brand__mark" />
          <div>
            <p class="sidebar-brand__eyebrow">Cluster Control</p>
            <h1 class="sidebar-brand__title">
              <LemmingComponents.brand_wordmark />
            </h1>
          </div>
        </div>
      </div>

      <div :for={group <- navigation_groups()} class="sidebar-section">
        <p class="sidebar-section__title">{group.title}</p>
        <nav class="sidebar-nav">
          <.link
            :for={item <- group.items}
            id={"sidebar-nav-#{item.key}"}
            navigate={item.path}
            title={item.label}
            class={[
              "sidebar-nav__item",
              @active_page == item.key && "sidebar-nav__item--active"
            ]}
          >
            <.icon name={item.icon} class="size-4" />
            <span class="sidebar-label">{item.label}</span>
          </.link>
        </nav>
      </div>

      <div class="sidebar-action">
        <.button navigate={~p"/lemmings/new"} class="w-full sidebar-action__full">
          <.icon name="hero-plus-circle" class="size-4" />
          <span class="sidebar-action__label">New Lemming</span>
        </.button>
      </div>

      <button
        class="sidebar-collapse-btn"
        phx-click={JS.toggle_class("app-sidebar--collapsed", to: "#app-sidebar")}
        aria-label="Toggle sidebar"
      >
        <.icon name="hero-chevron-double-left" class="size-3" />
      </button>

      <div class="sidebar-footer">
        <div class="sidebar-footer__grid">
          <div>
            <p class="sidebar-footer__label">Agents</p>
            <p class="sidebar-footer__value">
              {@summary.agents_count}/{@summary.max_agents}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label">Nodes</p>
            <p class="sidebar-footer__value">
              {@summary.online_cities_count}/{@summary.cities_count}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label">CPU</p>
            <p class="sidebar-footer__value">{@summary.cpu}</p>
          </div>
          <div>
            <p class="sidebar-footer__label">Tools</p>
            <p class="sidebar-footer__value">{@summary.tools_count}</p>
          </div>
        </div>

        <div class="sidebar-footer__status">
          <span class="sidebar-footer__dot"></span> Cluster online
        </div>
      </div>
    </aside>
    """
  end

  defp app_version_badge(assigns) do
    assigns = assign(assigns, :app_version, @app_version)

    ~H"""
    <span class="app-version-badge absolute bottom-0 right-0 z-10">
      v{@app_version}
    </span>
    """
  end

  defp navigation_groups do
    [
      %{
        title: "Overview",
        items: [
          %{key: :home, label: "Home", path: ~p"/", icon: "hero-home"},
          %{key: :world, label: "World", path: ~p"/world", icon: "hero-globe-alt"},
          %{key: :cities, label: "Cities", path: ~p"/cities", icon: "hero-map"},
          %{
            key: :departments,
            label: "Departments",
            path: ~p"/departments",
            icon: "hero-building-office-2"
          },
          %{key: :lemmings, label: "Lemmings", path: ~p"/lemmings", icon: "hero-users"}
        ]
      },
      %{
        title: "Operations",
        items: [
          %{key: :tools, label: "Tools", path: ~p"/tools", icon: "hero-wrench-screwdriver"},
          %{key: :logs, label: "Logs", path: ~p"/logs", icon: "hero-clipboard-document-list"},
          %{key: :settings, label: "Settings", path: ~p"/settings", icon: "hero-cog-6-tooth"}
        ]
      }
    ]
  end
end
