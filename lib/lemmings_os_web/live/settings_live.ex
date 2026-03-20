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
end
