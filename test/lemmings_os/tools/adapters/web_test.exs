defmodule LemmingsOs.Tools.Adapters.WebTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.Tools.Adapters.Web

  setup do
    old_endpoint = Application.get_env(:lemmings_os, :tools_web_search_endpoint)

    on_exit(fn ->
      if old_endpoint do
        Application.put_env(:lemmings_os, :tools_web_search_endpoint, old_endpoint)
      else
        Application.delete_env(:lemmings_os, :tools_web_search_endpoint)
      end
    end)

    :ok
  end

  test "S01: search returns normalized success payload with preview" do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :tools_web_search_endpoint,
      "http://localhost:#{bypass.port}/search"
    )

    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")

      Plug.Conn.resp(
        conn,
        200,
        ~s({"RelatedTopics":[{"Text":"Phoenix Framework","FirstURL":"https://www.phoenixframework.org"}]})
      )
    end)

    assert {:ok, result} = Web.search(%{"query" => "phoenix"})
    assert result.summary == "Search completed with 1 result(s)"
    assert result.preview == "Phoenix Framework"

    assert [%{title: "Phoenix Framework", url: "https://www.phoenixframework.org"}] =
             result.result.results
  end

  test "S02: search returns empty normalized results when upstream has no topics" do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :tools_web_search_endpoint,
      "http://localhost:#{bypass.port}/search"
    )

    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")
      Plug.Conn.resp(conn, 200, ~s({"RelatedTopics":[]}))
    end)

    assert {:ok, result} = Web.search(%{"query" => "no-results"})
    assert result.summary == "Search completed with 0 result(s)"
    assert result.preview == nil
    assert result.result.results == []
  end

  test "S03: search validates required query argument" do
    assert {:error, %{code: "tool.validation.invalid_args", details: %{required: ["query"]}}} =
             Web.search(%{})
  end

  test "S04: search returns normalized bad_status for non-2xx responses" do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :tools_web_search_endpoint,
      "http://localhost:#{bypass.port}/search"
    )

    Bypass.expect(bypass, "GET", "/search", fn conn ->
      Plug.Conn.resp(conn, 500, "boom")
    end)

    capture_log(fn ->
      assert {:error, %{code: "tool.web.bad_status", details: %{status: 500}}} =
               Web.search(%{"query" => "phoenix"})
    end)
  end

  test "S05: fetch returns normalized success payload" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/content", fn conn ->
      Plug.Conn.resp(conn, 200, "runtime tools fetch payload")
    end)

    assert {:ok, result} = Web.fetch(%{"url" => "http://localhost:#{bypass.port}/content"})
    assert result.summary == "Fetched http://localhost:#{bypass.port}/content"
    assert result.preview == "runtime tools fetch payload"
    assert result.result.status == 200
    assert result.result.body == "runtime tools fetch payload"
  end

  test "S06: fetch validates URL format" do
    assert {:error, %{code: "tool.web.invalid_url", details: %{url: "file:///etc/passwd"}}} =
             Web.fetch(%{"url" => "file:///etc/passwd"})
  end

  test "S07: fetch returns normalized bad_status for non-2xx responses" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "GET", "/missing", fn conn ->
      Plug.Conn.resp(conn, 404, "not found")
    end)

    assert {:error, %{code: "tool.web.bad_status", details: %{status: 404}}} =
             Web.fetch(%{"url" => "http://localhost:#{bypass.port}/missing"})
  end

  test "S08: fetch returns request_failed on transport errors" do
    bypass = Bypass.open()
    port = bypass.port
    Bypass.down(bypass)

    capture_log(fn ->
      assert {:error, %{code: "tool.web.request_failed", message: "Web fetch request failed"}} =
               Web.fetch(%{"url" => "http://localhost:#{port}/content"})
    end)
  end
end
