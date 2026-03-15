defmodule LemmingsOsWeb.CreateLemmingLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  @available_tools [
    "code_editor",
    "terminal",
    "git",
    "web_search",
    "browser",
    "database",
    "email",
    "slack"
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("lemmings", ".page_title_create_lemming"))
     |> assign(:available_tools, @available_tools)
     |> assign(:selected_tools, ["code_editor", "terminal"])
     |> assign(:form, build_form(default_params()))}
  end

  def handle_event("validate", %{"lemming" => params}, socket) do
    {:noreply, assign(socket, :form, build_form(params))}
  end

  def handle_event("toggle_tool", %{"tool" => tool}, socket) do
    selected_tools =
      if tool in socket.assigns.selected_tools do
        Enum.reject(socket.assigns.selected_tools, &(&1 == tool))
      else
        socket.assigns.selected_tools ++ [tool]
      end

    {:noreply, assign(socket, :selected_tools, selected_tools)}
  end

  def handle_event("save", %{"lemming" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, build_form(params))
     |> put_flash(:info, dgettext("lemmings", ".flash_deploy_mock"))}
  end

  defp build_form(params), do: to_form(params, as: :lemming)

  defp default_params do
    %{
      "model" => "gpt-4o",
      "name" => "",
      "role" => "",
      "system_prompt" => "You are a pragmatic software engineer focused on stable deliveries."
    }
  end
end
