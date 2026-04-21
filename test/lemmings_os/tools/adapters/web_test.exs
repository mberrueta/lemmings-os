defmodule LemmingsOs.Tools.Adapters.WebTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LemmingsOs.Tools.Adapters.Web

  setup do
    old_endpoint = Application.fetch_env(:lemmings_os, :tools_web_search_endpoint)
    old_allow_private_hosts = Application.fetch_env(:lemmings_os, :tools_web_allow_private_hosts)
    old_timeout = Application.fetch_env(:lemmings_os, :tools_web_timeout_ms)

    Application.put_env(:lemmings_os, :tools_web_allow_private_hosts, true)

    on_exit(fn ->
      restore_env(:tools_web_search_endpoint, old_endpoint)
      restore_env(:tools_web_allow_private_hosts, old_allow_private_hosts)
      restore_env(:tools_web_timeout_ms, old_timeout)
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

  test "S09: fetch blocks loopback and private host targets by default" do
    Application.put_env(:lemmings_os, :tools_web_allow_private_hosts, false)

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "localhost"}
            }} = Web.fetch(%{"url" => "http://localhost/admin"})

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "127.0.0.1"}
            }} = Web.fetch(%{"url" => "http://127.0.0.1/admin"})

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "169.254.169.254"}
            }} = Web.fetch(%{"url" => "http://169.254.169.254/latest/meta-data"})

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "10.0.0.12"}
            }} = Web.fetch(%{"url" => "http://10.0.0.12/internal"})

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "192.168.1.10"}
            }} = Web.fetch(%{"url" => "http://192.168.1.10/internal"})

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "::1"}
            }} = Web.fetch(%{"url" => "http://[::1]/admin"})
  end

  test "S10: search blocks private configured endpoints by default" do
    Application.put_env(:lemmings_os, :tools_web_allow_private_hosts, false)
    Application.put_env(:lemmings_os, :tools_web_search_endpoint, "http://localhost/search")

    assert {:error,
            %{
              code: "tool.web.egress_blocked",
              details: %{host: "localhost"}
            }} = Web.search(%{"query" => "phoenix"})
  end

  test "S11: fetch applies configured request timeout" do
    {:ok, port, server_pid} = start_silent_tcp_server()
    Application.put_env(:lemmings_os, :tools_web_timeout_ms, 10)

    capture_log(fn ->
      assert {:error, %{code: "tool.web.request_failed", message: "Web fetch request failed"}} =
               Web.fetch(%{"url" => "http://localhost:#{port}/slow"})
    end)

    send(server_pid, :close)
  end

  defp start_silent_tcp_server do
    parent = self()
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false])
    {:ok, port} = :inet.port(listen_socket)

    {:ok, pid} =
      Task.start(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        send(parent, :silent_tcp_server_accepted)
        _ = :gen_tcp.recv(socket, 0, 1_000)

        receive do
          :close -> :ok
        after
          5_000 -> :ok
        end

        :gen_tcp.close(socket)
        :gen_tcp.close(listen_socket)
      end)

    on_exit(fn ->
      send(pid, :close)
      :gen_tcp.close(listen_socket)
    end)

    {:ok, port, pid}
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:lemmings_os, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:lemmings_os, key)
end
