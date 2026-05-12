defmodule LemmingsOs.Tools.Adapters.Email.GmailClientTest do
  use ExUnit.Case, async: true

  alias LemmingsOs.Tools.Adapters.Email.GmailClient

  doctest GmailClient

  test "does not expose public Gmail send, read, list, sync, or delete functions" do
    refute function_exported?(GmailClient, :send_message, 3)
    refute function_exported?(GmailClient, :send_email, 3)
    refute function_exported?(GmailClient, :read_message, 2)
    refute function_exported?(GmailClient, :list_messages, 2)
    refute function_exported?(GmailClient, :sync_messages, 2)
    refute function_exported?(GmailClient, :delete_message, 2)
  end

  test "exchange_refresh_token/4 returns access token on success" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/token", fn conn ->
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")
      Plug.Conn.resp(conn, 200, ~s({"access_token":"token-123","token_type":"Bearer"}))
    end)

    assert {:ok, "token-123"} =
             GmailClient.exchange_refresh_token(
               "client-id",
               "client-secret",
               "refresh-token",
               token_url: "http://localhost:#{bypass.port}/token"
             )
  end

  test "exchange_refresh_token/4 returns auth_failed on non-success status" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/token", fn conn ->
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")
      Plug.Conn.resp(conn, 400, ~s({"error":"invalid_grant"}))
    end)

    assert {:error, :auth_failed} =
             GmailClient.exchange_refresh_token(
               "client-id",
               "client-secret",
               "refresh-token",
               token_url: "http://localhost:#{bypass.port}/token"
             )
  end

  test "create_draft/3 returns draft descriptor on success" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/drafts", fn conn ->
      assert ["Bearer access-token-123"] == Plug.Conn.get_req_header(conn, "authorization")
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"message" => %{"raw" => "raw-message"}} = Jason.decode!(body)
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")
      Plug.Conn.resp(conn, 200, ~s({"id":"draft-42","message":{"id":"message-42"}}))
    end)

    assert {:ok, %{draft_id: "draft-42", message_id: "message-42"}} =
             GmailClient.create_draft(
               "access-token-123",
               "raw-message",
               drafts_url: "http://localhost:#{bypass.port}/drafts"
             )
  end

  test "create_draft/3 returns draft_failed when response body is invalid" do
    bypass = Bypass.open()

    Bypass.expect_once(bypass, "POST", "/drafts", fn conn ->
      conn = Plug.Conn.put_resp_content_type(conn, "application/json")
      Plug.Conn.resp(conn, 200, ~s({"message":{"id":"message-only"}}))
    end)

    assert {:error, :draft_failed} =
             GmailClient.create_draft(
               "access-token-123",
               "raw-message",
               drafts_url: "http://localhost:#{bypass.port}/drafts"
             )
  end
end
