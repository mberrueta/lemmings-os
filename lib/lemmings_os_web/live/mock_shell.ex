defmodule LemmingsOsWeb.MockShell do
  @moduledoc false

  import Phoenix.Component

  alias LemmingsOs.MockData

  def assign_shell(socket, page_key, page_title) do
    socket
    |> assign(:current_scope, nil)
    |> assign(:page_key, page_key)
    |> assign(:page_title, page_title)
    |> assign(:shell_user, "operator")
    |> assign(:shell_host, "world_a")
    |> assign(:shell_breadcrumb, default_shell_breadcrumb(page_key))
    |> assign(:summary, MockData.summary())
  end

  def put_shell_breadcrumb(socket, breadcrumb) do
    assign(socket, :shell_breadcrumb, breadcrumb)
  end

  def shell_item(label, to) do
    %{label: shell_label(label), to: to}
  end

  def default_shell_breadcrumb(:home), do: [%{label: "home", to: "/"}]
  def default_shell_breadcrumb(:world), do: [%{label: "world", to: "/world"}]
  def default_shell_breadcrumb(:cities), do: [%{label: "cities", to: "/cities"}]
  def default_shell_breadcrumb(:departments), do: [%{label: "departments", to: "/departments"}]
  def default_shell_breadcrumb(:lemmings), do: [%{label: "lemmings", to: "/lemmings"}]
  def default_shell_breadcrumb(:tools), do: [%{label: "tools", to: "/tools"}]
  def default_shell_breadcrumb(:logs), do: [%{label: "logs", to: "/logs"}]
  def default_shell_breadcrumb(:settings), do: [%{label: "settings", to: "/settings"}]
  def default_shell_breadcrumb(_page_key), do: []

  def shell_label(nil), do: ""

  def shell_label(label) when is_atom(label) do
    label |> Atom.to_string() |> shell_label()
  end

  def shell_label(label) when is_binary(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end
end
