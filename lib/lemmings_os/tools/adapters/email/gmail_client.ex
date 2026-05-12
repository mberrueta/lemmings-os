defmodule LemmingsOs.Tools.Adapters.Email.GmailClient do
  @moduledoc """
  Req-backed Gmail draft HTTP boundary for `email.create_draft`.

  This client is intentionally narrow:
  - exchange a refresh token for a short-lived access token
  - create a Gmail draft with a prebuilt MIME payload
  """

  @token_url "https://oauth2.googleapis.com/token"
  @drafts_url "https://gmail.googleapis.com/gmail/v1/users/me/drafts"

  @doc """
  Exchanges a Gmail refresh token for a temporary access token.

  ## Parameters

  - `client_id`: OAuth client id value.
  - `client_secret`: OAuth client secret value.
  - `refresh_token`: OAuth refresh token value.
  - `opts` (optional):
    - `:req` - Req-compatible module used for HTTP calls. Default: `Req`.
    - `:token_url` - OAuth token endpoint override (test-only). Default: Google endpoint.

  ## Examples

      iex> {:ok, token} =
      ...>   LemmingsOs.Tools.Adapters.Email.GmailClient.exchange_refresh_token(
      ...>     "client-id",
      ...>     "client-secret",
      ...>     "refresh-token",
      ...>     req: LemmingsOs.TestSupport.EmailDraftReqSuccess
      ...>   )
      iex> token
      "test-access-token"

      iex> LemmingsOs.Tools.Adapters.Email.GmailClient.exchange_refresh_token(
      ...>   "client-id",
      ...>   "client-secret",
      ...>   "refresh-token",
      ...>   req: LemmingsOs.TestSupport.EmailDraftReqFailure
      ...> )
      {:error, :auth_failed}
  """
  @spec exchange_refresh_token(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :auth_failed}
  def exchange_refresh_token(client_id, client_secret, refresh_token, opts \\ [])
      when is_binary(client_id) and is_binary(client_secret) and is_binary(refresh_token) and
             is_list(opts) do
    req = Keyword.get(opts, :req, Req)
    token_url = Keyword.get(opts, :token_url, @token_url)

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token,
      grant_type: "refresh_token"
    }

    case req.post(token_url, form: body) do
      {:ok, %Req.Response{status: status, body: %{"access_token" => access_token}}}
      when status in 200..299 and is_binary(access_token) and access_token != "" ->
        {:ok, access_token}

      _other ->
        {:error, :auth_failed}
    end
  end

  @doc """
  Creates a Gmail draft from a base64url-encoded MIME message.

  ## Parameters

  - `access_token`: short-lived OAuth access token.
  - `raw_message`: base64url-encoded RFC822 MIME payload.
  - `opts` (optional):
    - `:req` - Req-compatible module used for HTTP calls. Default: `Req`.
    - `:drafts_url` - Gmail drafts endpoint override (test-only). Default: Gmail endpoint.

  ## Examples

      iex> {:ok, draft} =
      ...>   LemmingsOs.Tools.Adapters.Email.GmailClient.create_draft(
      ...>     "test-access-token",
      ...>     "raw-message",
      ...>     req: LemmingsOs.TestSupport.EmailDraftReqSuccess
      ...>   )
      iex> draft.draft_id
      "draft-123"
      iex> draft.message_id
      "message-123"

      iex> LemmingsOs.Tools.Adapters.Email.GmailClient.create_draft(
      ...>   "test-access-token",
      ...>   "raw-message",
      ...>   req: LemmingsOs.TestSupport.EmailDraftReqFailure
      ...> )
      {:error, :draft_failed}
  """
  @spec create_draft(String.t(), String.t(), keyword()) ::
          {:ok, %{draft_id: String.t(), message_id: String.t() | nil}}
          | {:error, :draft_failed}
  def create_draft(access_token, raw_message, opts \\ [])
      when is_binary(access_token) and is_binary(raw_message) and is_list(opts) do
    req = Keyword.get(opts, :req, Req)
    drafts_url = Keyword.get(opts, :drafts_url, @drafts_url)

    request_body = %{message: %{raw: raw_message}}
    headers = [{"authorization", "Bearer #{access_token}"}]

    case req.post(drafts_url, headers: headers, json: request_body) do
      {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
        normalize_draft_response(body)

      _other ->
        {:error, :draft_failed}
    end
  end

  defp normalize_draft_response(%{"id" => draft_id} = body)
       when is_binary(draft_id) and draft_id != "" do
    {:ok,
     %{
       draft_id: draft_id,
       message_id: fetch_message_id(body)
     }}
  end

  defp normalize_draft_response(_body), do: {:error, :draft_failed}

  defp fetch_message_id(%{"message" => %{"id" => message_id}})
       when is_binary(message_id) and message_id != "",
       do: message_id

  defp fetch_message_id(_body), do: nil
end
