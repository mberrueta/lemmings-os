defmodule LemmingsOs.Connections.GmailOAuthTest do
  use LemmingsOs.DataCase, async: true

  import LemmingsOs.Factory

  alias LemmingsOs.Connections.GmailOAuth
  alias LemmingsOs.SecretBank

  doctest GmailOAuth

  defmodule ExplodingOAuthClient do
    def exchange_code(_client_id, _client_secret, _code, _redirect_uri) do
      raise "OAuth exchange should not run for invalid state"
    end
  end

  test "complete/4 rejects a session state bound to a different scope before token exchange" do
    world = insert(:world)
    other_world = insert(:world)

    {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_ID", "dev_only_client_id")

    assert {:ok, %{session_state: session_state}} =
             GmailOAuth.start(
               world,
               %{
                 "client_id" => "$GMAIL_CLIENT_ID",
                 "client_secret" => "$GMAIL_CLIENT_SECRET"
               },
               redirect_uri: "https://example.test/oauth/callback"
             )

    assert {:error, :invalid_state} =
             GmailOAuth.complete(
               other_world,
               %{"code" => "valid-code", "state" => session_state["state"]},
               session_state,
               redirect_uri: "https://example.test/oauth/callback",
               oauth_client: ExplodingOAuthClient
             )
  end
end
