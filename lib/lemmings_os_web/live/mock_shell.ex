defmodule LemmingsOsWeb.MockShell do
  @moduledoc false

  import Phoenix.Component
  use Gettext, backend: LemmingsOs.Gettext

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

  def default_shell_breadcrumb(:home), do: [shell_item(:home, "/")]
  def default_shell_breadcrumb(:world), do: [shell_item(:world, "/world")]
  def default_shell_breadcrumb(:cities), do: [shell_item(:cities, "/cities")]
  def default_shell_breadcrumb(:departments), do: [shell_item(:departments, "/departments")]
  def default_shell_breadcrumb(:lemmings), do: [shell_item(:lemmings, "/lemmings")]
  def default_shell_breadcrumb(:tools), do: [shell_item(:tools, "/tools")]
  def default_shell_breadcrumb(:logs), do: [shell_item(:logs, "/logs")]
  def default_shell_breadcrumb(:settings), do: [shell_item(:settings, "/settings")]
  def default_shell_breadcrumb(_page_key), do: []

  def shell_label(nil), do: ""

  def shell_label(:home), do: translated_shell_label(dgettext("layout", ".nav_home"))
  def shell_label(:world), do: translated_shell_label(dgettext("layout", ".nav_world"))
  def shell_label(:cities), do: translated_shell_label(dgettext("layout", ".nav_cities"))

  def shell_label(:departments),
    do: translated_shell_label(dgettext("layout", ".nav_departments"))

  def shell_label(:lemmings), do: translated_shell_label(dgettext("layout", ".nav_lemmings"))
  def shell_label(:tools), do: translated_shell_label(dgettext("layout", ".nav_tools"))
  def shell_label(:logs), do: translated_shell_label(dgettext("layout", ".nav_logs"))
  def shell_label(:settings), do: translated_shell_label(dgettext("layout", ".nav_settings"))
  def shell_label(label) when is_atom(label), do: label |> Atom.to_string() |> shell_label()
  def shell_label("new"), do: translated_shell_label(dgettext("layout", ".breadcrumb_new"))

  def shell_label(label) when is_binary(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp translated_shell_label(label) do
    label
    |> String.downcase()
    |> String.replace(" ", "_")
  end
end
