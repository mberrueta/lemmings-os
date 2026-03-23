defmodule LemmingsOsWeb.HomeLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOsWeb.PageData.HomeDashboardSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:home, dgettext("layout", ".page_title_home"))
     |> assign(:snapshot, HomeDashboardSnapshot.build())}
  end

  defp mini_card_class do
    "h-full border-2 border-zinc-700 bg-zinc-950/70 p-4 transition duration-150 ease-out hover:-translate-y-px hover:border-emerald-400"
  end

  defp mini_card_title_class do
    "flex items-center gap-2 text-base font-medium text-zinc-100"
  end

  defp mini_card_meta_class do
    "text-xs uppercase tracking-widest text-zinc-400"
  end
end
