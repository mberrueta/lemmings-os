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
      class="fixed top-0 left-0 z-[100] flex h-[100dvh] w-[min(18.5rem,85vw)] -translate-x-[110%] flex-col gap-5 overflow-y-auto border-2 border-zinc-800 bg-zinc-950/95 p-4 shadow-2xl transition-[transform,width,padding] duration-[220ms] md:sticky md:top-4 md:z-auto md:h-auto md:w-auto md:max-h-[calc(100vh-2rem)] md:translate-x-0 md:overflow-hidden lg:max-h-none lg:overflow-visible"
      phx-click-away={
        JS.remove_class("mobile-open", to: "#app-sidebar")
        |> JS.remove_class("mobile-open", to: "#mobile-backdrop")
        |> JS.set_attribute({"aria-expanded", "false"}, to: "#mobile-nav-toggle")
      }
    >
      <.app_version_badge />

      <div class="sidebar-brand border-b-2 border-zinc-800 bg-zinc-900/50 pb-4 flex items-start justify-between gap-4">
        <div class="flex items-center gap-3">
          <LemmingImageComponents.lemming_logo
            size={32}
            animation="blink"
            class="shrink-0"
          />
          <div class="sidebar-brand__identity">
            <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold">
              {dgettext("layout", ".sidebar_eyebrow")}
            </p>
            <h1 class="font-mono text-sm font-medium leading-relaxed text-emerald-400">
              <LemmingImageComponents.brand_wordmark />
            </h1>
          </div>
        </div>
      </div>

      <div :for={group <- navigation_groups()} class="flex flex-col gap-2">
        <p class="sidebar-label px-2 text-xs uppercase tracking-widest text-zinc-500 font-bold">
          {group.title}
        </p>
        <nav class="flex flex-col gap-1.5">
          <.link
            :for={item <- group.items}
            id={"sidebar-nav-#{item.key}"}
            navigate={item.path}
            title={item.label}
            class={[
              "sidebar-nav-link group flex items-center gap-3 border-2 border-transparent bg-zinc-900/40 px-3 py-2.5 text-sm transition-all duration-150 hover:border-emerald-400/40 hover:bg-emerald-400/5 hover:text-emerald-400",
              @active_page == item.key &&
                "border-emerald-400/60 bg-emerald-400/10 text-emerald-400 shadow-md"
            ]}
          >
            <.icon name={item.icon} class="size-4" />
            <span class="sidebar-label font-medium">{item.label}</span>
          </.link>
        </nav>
      </div>

      <div class="pt-1">
        <.button navigate={~p"/lemmings/new"} class="w-full">
          <.icon name="hero-plus-circle" class="size-4" />
          <span class="sidebar-label">{dgettext("layout", ".button_new_lemming")}</span>
        </.button>
      </div>

      <button
        class="mt-auto hidden size-8 shrink-0 self-center items-center justify-center border border-zinc-800 bg-transparent text-zinc-500 transition duration-150 hover:border-emerald-400 hover:text-emerald-400 lg:flex"
        phx-click={
          JS.toggle_class("app-sidebar--collapsed", to: "#app-sidebar")
          |> JS.toggle_class("app-shell--sidebar-collapsed", to: "#app-shell")
        }
        aria-label={dgettext("layout", ".aria_toggle_sidebar")}
      >
        <.icon
          name="hero-chevron-double-left"
          class="sidebar-collapse-icon size-3 transition-transform duration-300"
        />
      </button>

      <div class="sidebar-footer mt-auto flex flex-col gap-3 border-t-2 border-zinc-800 bg-zinc-900/50 pt-4">
        <div class="grid grid-cols-2 gap-3 px-1">
          <div>
            <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold">
              {dgettext("layout", ".footer_agents")}
            </p>
            <p class="text-sm font-medium text-zinc-100">
              {@summary.agents_count}/{@summary.max_agents}
            </p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold">
              {dgettext("layout", ".footer_nodes")}
            </p>
            <p class="text-sm font-medium text-zinc-100">
              {@summary.online_cities_count}/{@summary.cities_count}
            </p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold">
              {dgettext("layout", ".footer_cpu")}
            </p>
            <p class="text-sm font-medium text-zinc-100">
              {@summary.cpu}
            </p>
          </div>
          <div>
            <p class="text-xs uppercase tracking-widest text-zinc-500 font-bold">
              {dgettext("layout", ".footer_tools")}
            </p>
            <p class="text-sm font-medium text-zinc-100">
              {@summary.tools_count}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2 px-1 text-xs font-medium text-emerald-400">
          <span class="inline-block size-2 bg-emerald-400 shadow-[0_0_8px_rgba(73,242,142,0.4)] animate-pulse">
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
    <span class="app-version-badge absolute bottom-0 right-2 z-10">
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
