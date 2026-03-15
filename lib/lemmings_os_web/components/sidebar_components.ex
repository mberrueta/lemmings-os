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
            <p class="sidebar-brand__eyebrow">{dgettext("layout", ".sidebar_eyebrow")}</p>
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
          <span class="sidebar-action__label">{dgettext("layout", ".button_new_lemming")}</span>
        </.button>
      </div>

      <button
        class="sidebar-collapse-btn"
        phx-click={JS.toggle_class("app-sidebar--collapsed", to: "#app-sidebar")}
        aria-label={dgettext("layout", ".aria_toggle_sidebar")}
      >
        <.icon name="hero-chevron-double-left" class="size-3" />
      </button>

      <div class="sidebar-footer">
        <div class="sidebar-footer__grid">
          <div>
            <p class="sidebar-footer__label">{dgettext("layout", ".footer_agents")}</p>
            <p class="sidebar-footer__value">
              {@summary.agents_count}/{@summary.max_agents}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label">{dgettext("layout", ".footer_nodes")}</p>
            <p class="sidebar-footer__value">
              {@summary.online_cities_count}/{@summary.cities_count}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label">{dgettext("layout", ".footer_cpu")}</p>
            <p class="sidebar-footer__value">{@summary.cpu}</p>
          </div>
          <div>
            <p class="sidebar-footer__label">{dgettext("layout", ".footer_tools")}</p>
            <p class="sidebar-footer__value">{@summary.tools_count}</p>
          </div>
        </div>

        <div class="sidebar-footer__status">
          <span class="sidebar-footer__dot"></span> {dgettext("layout", ".footer_cluster_online")}
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
        title: dgettext("layout", ".nav_section_overview"),
        items: [
          %{key: :home, label: dgettext("layout", ".nav_home"), path: ~p"/", icon: "hero-home"},
          %{
            key: :world,
            label: dgettext("layout", ".nav_world"),
            path: ~p"/world",
            icon: "hero-globe-alt"
          },
          %{
            key: :cities,
            label: dgettext("layout", ".nav_cities"),
            path: ~p"/cities",
            icon: "hero-map"
          },
          %{
            key: :departments,
            label: dgettext("layout", ".nav_departments"),
            path: ~p"/departments",
            icon: "hero-building-office-2"
          },
          %{
            key: :lemmings,
            label: dgettext("layout", ".nav_lemmings"),
            path: ~p"/lemmings",
            icon: "hero-users"
          }
        ]
      },
      %{
        title: dgettext("layout", ".nav_section_operations"),
        items: [
          %{
            key: :tools,
            label: dgettext("layout", ".nav_tools"),
            path: ~p"/tools",
            icon: "hero-wrench-screwdriver"
          },
          %{
            key: :logs,
            label: dgettext("layout", ".nav_logs"),
            path: ~p"/logs",
            icon: "hero-clipboard-document-list"
          },
          %{
            key: :settings,
            label: dgettext("layout", ".nav_settings"),
            path: ~p"/settings",
            icon: "hero-cog-6-tooth"
          }
        ]
      }
    ]
  end
end
