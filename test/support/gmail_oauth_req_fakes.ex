defmodule LemmingsOs.TestSupport.GmailOAuthReqSuccess do
  @moduledoc false

  def post(_url, _opts) do
    {:ok,
     %Req.Response{
       status: 200,
       body: %{
         "access_token" => "test-access-token",
         "refresh_token" => "test-refresh-token",
         "token_type" => "Bearer"
       }
     }}
  end

  def get(_url, _opts) do
    {:ok, %Req.Response{status: 200, body: %{"emailAddress" => "owner@example.test"}}}
  end
end

defmodule LemmingsOs.TestSupport.GmailOAuthReqFailure do
  @moduledoc false

  def post(_url, _opts) do
    {:ok, %Req.Response{status: 400, body: %{"error" => "invalid_grant"}}}
  end

  def get(_url, _opts) do
    {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "unauthorized"}}}}
  end
end
