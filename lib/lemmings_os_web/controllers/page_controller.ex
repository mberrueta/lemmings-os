defmodule LemmingsOsWeb.PageController do
  use LemmingsOsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
