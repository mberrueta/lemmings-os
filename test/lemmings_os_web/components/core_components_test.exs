defmodule LemmingsOsWeb.CoreComponentsTest do
  use LemmingsOsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LemmingsOsWeb.CoreComponents

  test "renders a world status badge with consistent tone and data-status" do
    html =
      render_component(&CoreComponents.status/1, %{id: "world-status", kind: :world, value: "ok"})

    assert html =~ ~s(id="world-status")
    assert html =~ ~s(data-status="ok")
    assert html =~ "ui-badge--success"
    assert html =~ "OK"
  end

  test "renders a lemming status badge with translated label" do
    html = render_component(&CoreComponents.status/1, %{kind: :lemming, value: :thinking})

    assert html =~ ~s(data-status="thinking")
    assert html =~ "ui-badge--warning"
    assert html =~ "THINKING"
  end

  test "renders an issue severity badge with translated label" do
    html = render_component(&CoreComponents.status/1, %{kind: :issue, value: "warning"})

    assert html =~ ~s(data-status="warning")
    assert html =~ "ui-badge--warning"
    assert html =~ "Warning"
  end
end
