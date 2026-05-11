defmodule LemmingsOs.Connections.GmailOAuth.Client do
  @moduledoc """
  Req-backed Google OAuth token exchange client.

  This module is intentionally narrow: it exchanges an authorization code for
  OAuth tokens, then supports a safe profile email lookup from Gmail.
  """

  @token_url "https://oauth2.googleapis.com/token"
  @profile_url "https://gmail.googleapis.com/gmail/v1/users/me/profile"
  @type token_payload :: map()

  @doc """
  Exchanges a Google OAuth authorization code for token payload data.

  `opts` accepts `:req` to inject a Req-compatible module in tests.

  ## Examples

      iex> {:ok, payload} =
      ...>   LemmingsOs.Connections.GmailOAuth.Client.exchange_code(
      ...>     "client-id",
      ...>     "client-secret",
      ...>     "auth-code",
      ...>     "https://example.test/oauth/callback",
      ...>     req: LemmingsOs.TestSupport.GmailOAuthReqSuccess
      ...>   )
      iex> payload["refresh_token"]
      "test-refresh-token"

      iex> LemmingsOs.Connections.GmailOAuth.Client.exchange_code(
      ...>   "client-id",
      ...>   "client-secret",
      ...>   "auth-code",
      ...>   "https://example.test/oauth/callback",
      ...>   req: LemmingsOs.TestSupport.GmailOAuthReqFailure
      ...> )
      {:error, :oauth_exchange_failed}
  """
  @spec exchange_code(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, token_payload()} | {:error, :oauth_exchange_failed}
  def exchange_code(client_id, client_secret, code, redirect_uri, opts \\ []) do
    req = Keyword.get(opts, :req, Req)

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    case req.post(@token_url, form: body) do
      {:ok, %Req.Response{status: 200, body: %{} = payload}} -> {:ok, payload}
      _ -> {:error, :oauth_exchange_failed}
    end
  end

  @doc """
  Fetches the authenticated Gmail account email from `users.getProfile`.

  `opts` accepts `:req` to inject a Req-compatible module in tests.

  ## Examples

      iex> LemmingsOs.Connections.GmailOAuth.Client.fetch_profile(
      ...>   "test-access-token",
      ...>   req: LemmingsOs.TestSupport.GmailOAuthReqSuccess
      ...> )
      {:ok, "owner@example.test"}

      iex> LemmingsOs.Connections.GmailOAuth.Client.fetch_profile(
      ...>   "test-access-token",
      ...>   req: LemmingsOs.TestSupport.GmailOAuthReqFailure
      ...> )
      {:error, :profile_lookup_failed}
  """
  @spec fetch_profile(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :profile_lookup_failed}
  def fetch_profile(access_token, opts \\ []) when is_binary(access_token) do
    req = Keyword.get(opts, :req, Req)

    case req.get(@profile_url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"emailAddress" => email}}}
      when is_binary(email) and email != "" ->
        {:ok, email}

      _ ->
        {:error, :profile_lookup_failed}
    end
  end
end
