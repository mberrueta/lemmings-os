defmodule LemmingsOsWeb.LogsLiveTest do
  use LemmingsOsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LemmingsOs.Runtime.ActivityLog

  setup do
    ActivityLog.clear()
    :ok
  end

  test "renders runtime snapshot and activity feed", %{conn: conn} do
    :ok =
      ActivityLog.record(:system, "runtime", "Runtime recovery completed", %{
        recovered_count: 2
      })

    {:ok, view, _html} = live(conn, ~p"/logs")

    assert has_element?(view, "#logs-runtime-overview")
    assert has_element?(view, "#logs-runtime-pending")
    assert has_element?(view, "#logs-activity-feed")
    assert has_element?(view, "[id^='logs-feed-item-']", "Runtime recovery completed")
  end
end
