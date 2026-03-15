defmodule LemmingsOsWeb.MockShell do
  @moduledoc false

  import Phoenix.Component

  alias LemmingsOs.MockData

  def assign_shell(socket, page_key, page_title) do
    socket
    |> assign(:current_scope, nil)
    |> assign(:page_key, page_key)
    |> assign(:page_title, page_title)
    |> assign(:summary, MockData.summary())
  end
end
