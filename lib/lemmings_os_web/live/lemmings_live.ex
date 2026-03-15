defmodule LemmingsOsWeb.LemmingsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:lemmings, dgettext("layout", ".page_title_lemmings"))
     |> assign(:lemmings, MockData.lemmings())
     |> assign(:selected_lemming, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :selected_lemming, MockData.find_lemming(params["lemming"]))}
  end
end
