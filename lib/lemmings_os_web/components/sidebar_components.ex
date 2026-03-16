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
    <aside
      id="app-sidebar"
      class="app-sidebar fixed top-0 left-0 z-[100] flex h-[100dvh] w-[min(18.5rem,85vw)] -translate-x-[110%] flex-col gap-5 overflow-y-auto border-[3px] border-[var(--border)] bg-[linear-gradient(180deg,rgba(24,40,29,0.96),rgba(14,24,17,0.98))] p-4 shadow-[7px_7px_0_0_var(--shadow)] transition-transform duration-[220ms] md:sticky md:top-4 md:z-auto md:h-auto md:w-auto md:max-h-[calc(100vh-2rem)] md:translate-x-0 md:overflow-hidden lg:max-h-none lg:overflow-visible"
      phx-click-away={
        JS.remove_class("mobile-open", to: "#app-sidebar")
        |> JS.remove_class("mobile-open", to: "#mobile-backdrop")
        |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-nav-toggle")
      }
    >
      <.app_version_badge />

      <div class="sidebar-brand border-b-[3px] border-[var(--border-soft)] bg-[linear-gradient(180deg,rgba(12,22,15,0.98),rgba(16,25,18,0.98))] pb-4 flex items-start justify-between gap-4">
        <div class="sidebar-brand__identity flex items-center gap-[0.8rem]">
          <LemmingComponents.lemming_logo
            size={32}
            animation="blink"
            class="sidebar-brand__mark shrink-0"
          />
          <div>
            <p class="sidebar-brand__eyebrow text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("layout", ".sidebar_eyebrow")}
            </p>
            <h1 class="sidebar-brand__title font-[var(--font-display)] text-[0.95rem] leading-[1.5] text-[var(--accent)]">
              <LemmingComponents.brand_wordmark />
            </h1>
          </div>
        </div>
      </div>

      <div :for={group <- navigation_groups()} class="sidebar-section flex flex-col gap-[0.6rem]">
        <p class="sidebar-section__title text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
          {group.title}
        </p>
        <nav class="sidebar-nav flex flex-col gap-2">
          <.link
            :for={item <- group.items}
            id={"sidebar-nav-#{item.key}"}
            navigate={item.path}
            title={item.label}
            class={[
              "sidebar-nav__item flex items-center gap-[0.65rem] border-2 border-transparent bg-[rgba(19,32,24,0.9)] px-[0.9rem] py-[0.85rem] text-[0.92rem] transition duration-150 hover:border-[var(--accent)] hover:bg-[rgba(73,242,142,0.08)] hover:text-[var(--accent)]",
              @active_page == item.key &&
                "sidebar-nav__item--active border-[var(--accent)] bg-[rgba(73,242,142,0.08)] text-[var(--accent)]"
            ]}
          >
            <.icon name={item.icon} class="size-4" />
            <span class="sidebar-label">{item.label}</span>
          </.link>
        </nav>
      </div>

      <div class="sidebar-action pt-1">
        <.button navigate={~p"/lemmings/new"} class="w-full sidebar-action__full">
          <.icon name="hero-plus-circle" class="size-4" />
          <span class="sidebar-action__label">{dgettext("layout", ".button_new_lemming")}</span>
        </.button>
      </div>

      <button
        class="sidebar-collapse-btn mt-auto hidden size-[1.6rem] shrink-0 self-center items-center justify-center border border-[var(--border-soft)] bg-transparent text-[var(--muted)] transition duration-150 hover:border-[var(--accent)] hover:text-[var(--accent)] lg:flex"
        phx-click={JS.toggle_class("app-sidebar--collapsed", to: "#app-sidebar")}
        aria-label={dgettext("layout", ".aria_toggle_sidebar")}
      >
        <.icon name="hero-chevron-double-left" class="size-3" />
      </button>

      <div class="sidebar-footer mt-auto flex flex-col gap-[0.8rem] border-t-[3px] border-[var(--border-soft)] bg-[linear-gradient(180deg,rgba(12,22,15,0.98),rgba(16,25,18,0.98))] pt-4">
        <div class="sidebar-footer__grid grid grid-cols-2 gap-3">
          <div>
            <p class="sidebar-footer__label text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("layout", ".footer_agents")}
            </p>
            <p class="sidebar-footer__value mt-[0.15rem] text-base text-[var(--text)]">
              {@summary.agents_count}/{@summary.max_agents}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("layout", ".footer_nodes")}
            </p>
            <p class="sidebar-footer__value mt-[0.15rem] text-base text-[var(--text)]">
              {@summary.online_cities_count}/{@summary.cities_count}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("layout", ".footer_cpu")}
            </p>
            <p class="sidebar-footer__value mt-[0.15rem] text-base text-[var(--text)]">
              {@summary.cpu}
            </p>
          </div>
          <div>
            <p class="sidebar-footer__label text-[0.72rem] uppercase tracking-[0.08em] text-[var(--muted)]">
              {dgettext("layout", ".footer_tools")}
            </p>
            <p class="sidebar-footer__value mt-[0.15rem] text-base text-[var(--text)]">
              {@summary.tools_count}
            </p>
          </div>
        </div>

        <div class="sidebar-footer__status flex items-center gap-[0.55rem] text-[0.86rem] text-[var(--accent)]">
          <span class="sidebar-footer__dot inline-block size-[0.65rem] bg-[var(--accent)] shadow-[0_0_12px_rgba(73,242,142,0.45)]">
          </span>
          {dgettext("layout", ".footer_cluster_online")}
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
