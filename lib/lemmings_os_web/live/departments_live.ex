defmodule LemmingsOsWeb.DepartmentsLive do
  use LemmingsOsWeb, :live_view

  import LemmingsOsWeb.MockShell

  alias LemmingsOs.MockData

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_shell(:departments, dgettext("layout", ".page_title_departments"))
     |> assign(:departments, MockData.departments())
     |> assign(:selected_department, nil)}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :selected_department, MockData.find_department(params["dept"]))}
  end
end
