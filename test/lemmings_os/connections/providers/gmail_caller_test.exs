defmodule LemmingsOs.Connections.Providers.GmailCallerTest do
  use LemmingsOs.DataCase, async: true

  alias LemmingsOs.Connections.Providers.GmailCaller

  doctest GmailCaller

  describe "validate_config/1" do
    test "accepts only safe gmail metadata with secret refs" do
      assert :ok =
               GmailCaller.validate_config(%{
                 "provider" => "gmail",
                 "account_email" => "ops@example.test",
                 "scopes" => [GmailCaller.compose_scope()],
                 "client_id" => "$GMAIL_CLIENT_ID",
                 "client_secret" => "$GMAIL_CLIENT_SECRET",
                 "refresh_token" => "$GMAIL_REFRESH_TOKEN"
               })
    end

    test "rejects raw credential values" do
      assert {:error, :invalid_config} =
               GmailCaller.validate_config(%{
                 "provider" => "gmail",
                 "scopes" => [GmailCaller.compose_scope()],
                 "client_id" => "raw-client-id",
                 "client_secret" => "raw-client-secret",
                 "refresh_token" => "raw-refresh-token"
               })
    end

    test "rejects extra credential-like keys such as access_token and authorization header" do
      assert {:error, :invalid_config} =
               GmailCaller.validate_config(%{
                 "provider" => "gmail",
                 "scopes" => [GmailCaller.compose_scope()],
                 "client_id" => "$GMAIL_CLIENT_ID",
                 "client_secret" => "$GMAIL_CLIENT_SECRET",
                 "refresh_token" => "$GMAIL_REFRESH_TOKEN",
                 "access_token" => "raw-access-token",
                 "authorization" => "Bearer raw-header-value"
               })
    end

    test "rejects password-like secrets even when keys are expected" do
      assert {:error, :invalid_config} =
               GmailCaller.validate_config(%{
                 "provider" => "gmail",
                 "scopes" => [GmailCaller.compose_scope()],
                 "client_id" => "$GMAIL_CLIENT_ID",
                 "client_secret" => "password123!",
                 "refresh_token" => "$GMAIL_REFRESH_TOKEN"
               })
    end

    test "rejects non-compose or multi-scope lists" do
      assert {:error, :invalid_config} =
               GmailCaller.validate_config(%{
                 "provider" => "gmail",
                 "scopes" => [
                   GmailCaller.compose_scope(),
                   "https://www.googleapis.com/auth/gmail.readonly"
                 ],
                 "client_id" => "$GMAIL_CLIENT_ID",
                 "client_secret" => "$GMAIL_CLIENT_SECRET",
                 "refresh_token" => "$GMAIL_REFRESH_TOKEN"
               })
    end
  end
end
