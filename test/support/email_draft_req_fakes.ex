defmodule LemmingsOs.TestSupport.EmailDraftReqSuccess do
  @moduledoc false

  def post(url, _opts) when is_binary(url) do
    cond do
      String.ends_with?(url, "/token") ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "access_token" => "test-access-token",
             "token_type" => "Bearer"
           }
         }}

      String.ends_with?(url, "/drafts") ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "id" => "draft-123",
             "message" => %{"id" => "message-123"}
           }
         }}

      true ->
        {:ok, %Req.Response{status: 404, body: %{}}}
    end
  end
end

defmodule LemmingsOs.TestSupport.EmailDraftReqFailure do
  @moduledoc false

  def post(_url, _opts) do
    {:ok, %Req.Response{status: 401, body: %{"error" => "unauthorized"}}}
  end
end

defmodule LemmingsOs.TestSupport.EmailDraftGmailClientSuccess do
  @moduledoc false

  def exchange_refresh_token(_client_id, _client_secret, _refresh_token, opts) do
    if pid = Keyword.get(opts, :test_pid) do
      send(pid, {:email_draft_exchange_called, Keyword.get(opts, :access_token, "access-token")})
    end

    {:ok, Keyword.get(opts, :access_token, "access-token")}
  end

  def create_draft(access_token, raw_message, opts) do
    if pid = Keyword.get(opts, :test_pid) do
      send(pid, {:email_draft_create_called, access_token, raw_message})
    end

    {:ok,
     %{
       draft_id: "draft-abc",
       message_id: "message-abc"
     }}
  end
end

defmodule LemmingsOs.TestSupport.EmailDraftGmailClientAuthFailure do
  @moduledoc false

  def exchange_refresh_token(_client_id, _client_secret, _refresh_token, _opts) do
    {:error, :auth_failed}
  end

  def create_draft(_access_token, _raw_message, _opts) do
    {:ok, %{draft_id: "not-used"}}
  end
end

defmodule LemmingsOs.TestSupport.EmailDraftGmailClientDraftFailure do
  @moduledoc false

  def exchange_refresh_token(_client_id, _client_secret, _refresh_token, opts) do
    {:ok, Keyword.get(opts, :access_token, "access-token")}
  end

  def create_draft(_access_token, _raw_message, _opts) do
    {:error, :draft_failed}
  end
end
