defmodule LemmingsOsWeb.SettingsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:settings, dgettext("layout", ".page_title_settings"))
     |> assign(:form, build_form(default_params()))}
  end

  def handle_event("validate", %{"settings" => params}, socket) do
    {:noreply, assign(socket, :form, build_form(params))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, build_form(params))
     |> put_flash(:info, dgettext("layout", ".flash_settings_mock"))}
  end

  defp build_form(params), do: to_form(params, as: :settings)

  defp default_params do
    %{
      "default_model" => "gpt-4o",
      "log_level" => "verbose",
      "max_agents" => "16",
      "world_name" => "Lemmings HQ"
    }
  end
end
