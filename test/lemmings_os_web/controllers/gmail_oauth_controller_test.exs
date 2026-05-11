defmodule LemmingsOsWeb.GmailOAuthControllerTest do
  use LemmingsOsWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import LemmingsOs.Factory

  alias LemmingsOs.Connections
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank

  @compose_scope "https://www.googleapis.com/auth/gmail.compose"
  @session_key "gmail_oauth_state"

  defmodule FakeOAuthClient do
    def exchange_code(_client_id, _client_secret, "valid_code", _redirect_uri) do
      {:ok,
       %{
         "refresh_token" => "dev_only_refresh_token_1",
         "access_token" => "dev_only_access_token_1"
       }}
    end

    def exchange_code(_client_id, _client_secret, "valid_code_2", _redirect_uri) do
      {:ok,
       %{
         "refresh_token" => "dev_only_refresh_token_2",
         "access_token" => "dev_only_access_token_profile_failure"
       }}
    end

    def exchange_code(_client_id, _client_secret, _code, _redirect_uri) do
      {:error, :oauth_exchange_failed}
    end

    def fetch_profile("dev_only_access_token_1"), do: {:ok, "owner@example.test"}

    def fetch_profile("dev_only_access_token_profile_failure"),
      do: {:error, :profile_lookup_failed}

    def fetch_profile(_access_token), do: {:error, :profile_lookup_failed}
  end

  setup do
    previous = Application.get_env(:lemmings_os, :gmail_oauth_client)
    Application.put_env(:lemmings_os, :gmail_oauth_client, FakeOAuthClient)

    on_exit(fn ->
      if previous do
        Application.put_env(:lemmings_os, :gmail_oauth_client, previous)
      else
        Application.delete_env(:lemmings_os, :gmail_oauth_client)
      end
    end)

    :ok
  end

  test "start stores session state and redirects with compose scope", %{conn: conn} do
    world = insert(:world)
    {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_ID", "dev_only_client_id")

    response =
      get(conn, ~p"/connections/gmail/oauth/start", %{
        "world_id" => world.id,
        "client_id" => "$GMAIL_CLIENT_ID",
        "client_secret" => "$GMAIL_CLIENT_SECRET"
      })

    redirect_url = redirected_to(response, 302)
    assert redirect_url =~ "https://accounts.google.com/o/oauth2/v2/auth?"
    session_state = get_session(response, @session_key)
    assert session_state
    assert is_binary(session_state["state"])
    assert is_integer(session_state["expires_at_unix"])
    assert session_state["config"]["client_id"] == "$GMAIL_CLIENT_ID"
    assert session_state["config"]["client_secret"] == "$GMAIL_CLIENT_SECRET"
    refute inspect(session_state) =~ "dev_only_client_id"

    %URI{query: query} = URI.parse(redirect_url)
    query_params = URI.decode_query(query || "")

    assert query_params["scope"] == @compose_scope
    assert query_params["scope"] == String.trim(query_params["scope"])
    refute String.contains?(query_params["scope"], " ")
  end

  test "callback success stores refresh token ref only and creates gmail connection", %{
    conn: conn
  } do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code",
        "state" => state["state"]
      })

    assert redirected_to(callback_conn) == "/settings"

    connection = Connections.get_connection_by_type(world, "gmail")
    assert connection.type == "gmail"
    assert connection.config["provider"] == "gmail"
    assert connection.config["scopes"] == [@compose_scope]
    assert connection.config["client_id"] == "$GMAIL_CLIENT_ID"
    assert connection.config["client_secret"] == "$GMAIL_CLIENT_SECRET"
    assert connection.config["account_email"] == "owner@example.test"
    assert String.starts_with?(connection.config["refresh_token"], "$GMAIL_REFRESH_TOKEN_WORLD_")

    assert {:ok, resolved_refresh} =
             SecretBank.resolve_runtime_secret(world, connection.config["refresh_token"])

    assert resolved_refresh.value == "dev_only_refresh_token_1"
    refute inspect(connection.config) =~ "dev_only_refresh_token_1"
    refute inspect(connection.config) =~ "dev_only_access_token_not_for_storage"

    [event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_succeeded"],
        limit: 1
      )

    assert event.payload["connection_id"] == connection.id
    refute inspect(event.payload) =~ "dev_only_refresh_token_1"
    refute inspect(event.payload) =~ "dev_only_access_token_1"
    refute inspect(event.payload) =~ "valid_code"
    refute inspect(event.payload) =~ "dev_only_client_secret"
  end

  test "callback updates existing gmail connection at selected scope", %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    _first_callback =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code",
        "state" => state["state"]
      })

    original = Connections.get_connection_by_type(world, "gmail")
    assert original

    restarted = oauth_start(conn, world)
    state_two = get_session(restarted, @session_key)

    _second_callback =
      restarted
      |> recycle()
      |> init_test_session(%{@session_key => state_two})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code_2",
        "state" => state_two["state"]
      })

    updated = Connections.get_connection_by_type(world, "gmail")
    assert updated.id == original.id
    assert updated.config["account_email"] == "owner@example.test"

    assert {:ok, resolved_refresh} =
             SecretBank.resolve_runtime_secret(world, updated.config["refresh_token"])

    assert resolved_refresh.value == "dev_only_refresh_token_2"

    [profile_failure_event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_profile_lookup_failed"],
        limit: 1
      )

    assert profile_failure_event.payload["reason"] == "profile_lookup_failed"
  end

  test "profile lookup failure does not fail oauth and leaves account email blank when no prior value",
       %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code_2",
        "state" => state["state"]
      })

    assert redirected_to(callback_conn) == "/settings"

    connection = Connections.get_connection_by_type(world, "gmail")
    assert connection.config["account_email"] == ""

    [profile_failure_event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_profile_lookup_failed"],
        limit: 1
      )

    assert profile_failure_event.payload["reason"] == "profile_lookup_failed"
    refute inspect(profile_failure_event.payload) =~ "dev_only_access_token_profile_failure"
  end

  test "callback rejects missing session state", %{conn: conn} do
    world = insert(:world)

    callback_conn =
      conn
      |> init_test_session(%{})
      |> get(~p"/connections/gmail/oauth/callback", %{"code" => "valid_code", "state" => "nonce"})

    assert redirected_to(callback_conn) == "/settings"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == "Gmail OAuth failed."

    assert [] ==
             Events.list_recent_events(world,
               event_types: ["connection.gmail.oauth_failed"],
               limit: 1
             )
  end

  test "callback rejects invalid state", %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code",
        "state" => "tampered"
      })

    assert redirected_to(callback_conn) == "/settings"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == "Gmail OAuth failed."

    [event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_failed"],
        limit: 1
      )

    assert event.payload["reason"] == "invalid_state"
    refute inspect(event.payload) =~ "tampered"
  end

  test "callback rejects missing state param", %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{"code" => "valid_code"})

    assert redirected_to(callback_conn) == "/settings"

    [event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_failed"],
        limit: 1
      )

    assert event.payload["reason"] == "invalid_state"
  end

  test "callback rejects expired state", %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)
    expired_state = Map.put(state, "expires_at_unix", DateTime.to_unix(DateTime.utc_now()) - 1)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => expired_state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code",
        "state" => state["state"]
      })

    assert redirected_to(callback_conn) == "/settings"

    [event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_failed"],
        limit: 1
      )

    assert event.payload["reason"] == "invalid_state"
  end

  test "callback ignores tampered callback scope params and keeps session scope", %{conn: conn} do
    world = insert(:world)
    other_world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    callback_conn =
      started
      |> recycle()
      |> init_test_session(%{@session_key => state})
      |> get(~p"/connections/gmail/oauth/callback", %{
        "code" => "valid_code",
        "state" => state["state"],
        "world_id" => other_world.id
      })

    assert redirected_to(callback_conn) == "/settings"
    assert Connections.get_connection_by_type(world, "gmail")
    assert is_nil(Connections.get_connection_by_type(other_world, "gmail"))
  end

  test "callback failure does not leak token-like values", %{conn: conn} do
    world = insert(:world)
    seed_google_client_secrets(world)

    started = oauth_start(conn, world)
    state = get_session(started, @session_key)

    log =
      capture_log(fn ->
        callback_conn =
          started
          |> recycle()
          |> init_test_session(%{@session_key => state})
          |> get(~p"/connections/gmail/oauth/callback", %{
            "code" => "provider_failure_code_dev_only_refresh_token_1",
            "state" => state["state"]
          })

        send(self(), {:callback_conn, callback_conn})
      end)

    assert_receive {:callback_conn, callback_conn}

    assert redirected_to(callback_conn) == "/settings"
    assert Phoenix.Flash.get(callback_conn.assigns.flash, :error) == "Gmail OAuth failed."

    [event] =
      Events.list_recent_events(world,
        event_types: ["connection.gmail.oauth_failed"],
        limit: 1
      )

    assert event.payload["reason"] == "oauth_exchange_failed"
    refute inspect(event.payload) =~ "dev_only_refresh_token_1"
    refute inspect(event.payload) =~ "provider_failure_code_dev_only_refresh_token_1"
    refute inspect(event.payload) =~ "dev_only_client_secret"
    refute log =~ "dev_only_refresh_token_1"
    refute log =~ "provider_failure_code_dev_only_refresh_token_1"
    refute log =~ "dev_only_client_secret"
    refute log =~ "valid_code"
  end

  defp oauth_start(conn, world) do
    get(conn, ~p"/connections/gmail/oauth/start", %{
      "world_id" => world.id,
      "client_id" => "$GMAIL_CLIENT_ID",
      "client_secret" => "$GMAIL_CLIENT_SECRET"
    })
  end

  defp seed_google_client_secrets(world) do
    {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_ID", "dev_only_client_id")
    {:ok, _} = SecretBank.upsert_secret(world, "GMAIL_CLIENT_SECRET", "dev_only_client_secret")
  end
end
