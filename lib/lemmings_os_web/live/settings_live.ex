defmodule LemmingsOsWeb.SettingsLive do
  use LemmingsOsWeb, :live_view

  alias LemmingsOs.Helpers
  alias LemmingsOs.Worlds.World
  import LemmingsOsWeb.MockShell
  alias LemmingsOsWeb.PageData.SettingsPageSnapshot

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:settings, dgettext("layout", ".page_title_settings"))
     |> assign(:snapshot, SettingsPageSnapshot.build())}
  end

  defp validation_detail(0), do: dgettext("layout", ".settings_validation_summary_zero")
  defp validation_detail(1), do: dgettext("layout", ".settings_validation_summary_one")

  defp validation_detail(issue_count),
    do: dgettext("layout", ".settings_validation_summary_many", count: issue_count)

  defp status_label(status), do: World.translate_status(status)

  defp help_link_label("world"), do: dgettext("layout", ".settings_help_link_world")
  defp help_link_label("logs"), do: dgettext("layout", ".settings_help_link_logs")
  defp help_link_label("tools"), do: dgettext("layout", ".settings_help_link_tools")
  defp help_link_label(_link_id), do: dgettext("layout", ".title_environment_notes")

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
