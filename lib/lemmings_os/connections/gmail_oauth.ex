defmodule LemmingsOs.Connections.GmailOAuth do
  @moduledoc """
  Gmail OAuth onboarding boundary for scope-local connection creation/update.
  """

  alias LemmingsOs.Cities.City
  alias LemmingsOs.Connections
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Connections.GmailOAuth.Client
  alias LemmingsOs.Connections.Providers.GmailCaller
  alias LemmingsOs.Departments.Department
  alias LemmingsOs.Events
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds.World

  @session_ttl_seconds 600

  @type scope_t :: World.t() | City.t() | Department.t()

  @doc """
  Builds Google OAuth authorization URL and safe session state.

  ## Parameters

  - `scope`:
    `%LemmingsOs.Worlds.World{}`, `%LemmingsOs.Cities.City{}`, or
    `%LemmingsOs.Departments.Department{}`.
  - `attrs`:
    - `"client_id"` (required): Secret Bank ref string (for example `"$GMAIL_CLIENT_ID"`).
    - `"client_secret"` (required): Secret Bank ref string (for example `"$GMAIL_CLIENT_SECRET"`).
    - `"account_email"` (optional): safe display label string. Default: `nil`.
  - `opts`:
    - `:redirect_uri` (required): OAuth callback URL.
    - default value for `opts`: `[]`.

  ## OAuth Request Defaults

  - `response_type = "code"`
  - `scope = "https://www.googleapis.com/auth/gmail.compose"`
  - `access_type = "offline"`
  - `prompt = "consent"`

  ## Examples

      iex> LemmingsOs.Connections.GmailOAuth.start(%{}, %{}, redirect_uri: "https://example.test/callback")
      {:error, :invalid_scope}
  """
  @spec start(scope_t(), map(), keyword()) ::
          {:ok, %{authorize_url: String.t(), session_state: map()}} | {:error, atom()}
  def start(scope, attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, scope_data} <- scope_data(scope),
         {:ok, client_id_ref} <- fetch_secret_ref(attrs, "client_id"),
         {:ok, client_secret_ref} <- fetch_secret_ref(attrs, "client_secret"),
         {:ok, redirect_uri} <- fetch_nonempty(opts, :redirect_uri),
         {:ok, client_id} <- SecretBank.resolve_runtime_secret(scope, client_id_ref) do
      state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      expires_at_unix =
        DateTime.utc_now() |> DateTime.add(@session_ttl_seconds, :second) |> DateTime.to_unix()

      query =
        URI.encode_query(%{
          response_type: "code",
          client_id: client_id.value,
          redirect_uri: redirect_uri,
          scope: GmailCaller.compose_scope(),
          access_type: "offline",
          prompt: "consent",
          state: state
        })

      {:ok,
       %{
         authorize_url: "https://accounts.google.com/o/oauth2/v2/auth?#{query}",
         session_state: %{
           "state" => state,
           "expires_at_unix" => expires_at_unix,
           "scope" => scope_data,
           "config" => %{
             "client_id" => client_id_ref,
             "client_secret" => client_secret_ref,
             "account_email" => safe_string(Map.get(attrs, "account_email")),
             "connection_id" => safe_string(Map.get(attrs, "connection_id"))
           }
         }
       }}
    end
  end

  @doc """
  Completes OAuth callback and upserts a scope-local Gmail connection.

  The returned temporary access token is used only for profile lookup and is
  never persisted.

  When profile lookup succeeds, `account_email` is populated from Gmail
  `users.getProfile`. When lookup fails, OAuth still succeeds and
  `account_email` falls back to the provided safe label (or blank).

  Returns `{:error, :oauth_failed}` for invalid or expired state, failed token
  exchange, or malformed callback payload.

  ## Parameters

  - `scope`:
    `%LemmingsOs.Worlds.World{}`, `%LemmingsOs.Cities.City{}`, or
    `%LemmingsOs.Departments.Department{}`.
  - `params`:
    - `"code"` (required): OAuth authorization code from Google callback.
    - `"state"` (required): callback state nonce; must match session nonce.
  - `session_state`:
    Map stored from `start/3`, containing:
    - `"state"` nonce
    - `"expires_at_unix"` unix timestamp
    - `"scope"` scope identity map
    - `"config"` map with `"client_id"`, `"client_secret"`, optional `"account_email"`
  - `opts`:
    - `:redirect_uri` (required): same callback URL used at `start/3`.
    - `:oauth_client` (optional): token exchange module implementing
      `exchange_code/5`.
      Default: `LemmingsOs.Connections.GmailOAuth.Client`.
    - default value for `opts`: `[]`.
  """
  @spec complete(scope_t(), map(), map(), keyword()) ::
          {:ok, Connection.t()} | {:error, atom() | Ecto.Changeset.t()}
  def complete(scope, params, session_state, opts \\ [])
      when is_map(params) and is_map(session_state) and is_list(opts) do
    oauth_client = Keyword.get(opts, :oauth_client, Client)

    with :ok <- validate_session_state(params, session_state),
         :ok <- validate_session_scope(scope, session_state),
         {:ok, code} <- fetch_nonempty_map(params, "code"),
         {:ok, redirect_uri} <- fetch_nonempty(opts, :redirect_uri),
         {:ok, config} <- fetch_oauth_config(session_state),
         {:ok, client_id} <- SecretBank.resolve_runtime_secret(scope, config.client_id_ref),
         {:ok, client_secret} <-
           SecretBank.resolve_runtime_secret(scope, config.client_secret_ref),
         {:ok, token_payload} <-
           oauth_client.exchange_code(
             client_id.value,
             client_secret.value,
             code,
             redirect_uri
           ),
         {:ok, refresh_token} <- fetch_nonempty_map(token_payload, "refresh_token"),
         {:ok, refresh_ref} <- upsert_refresh_token(scope, refresh_token),
         profile_email = resolve_profile_email(scope, oauth_client, token_payload),
         {:ok, connection} <-
           upsert_gmail_connection(scope, config, refresh_ref, profile_email) do
      {:ok, connection}
    else
      {:error, :invalid_state} -> {:error, :invalid_state}
      {:error, :invalid_config} -> {:error, :invalid_config}
      {:error, :oauth_exchange_failed} -> {:error, :oauth_exchange_failed}
      {:error, :missing_secret} -> {:error, :missing_secret}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      _ -> {:error, :oauth_failed}
    end
  end

  defp validate_session_scope(scope, session_state) do
    with {:ok, scope_data} <- scope_data(scope),
         %{} = session_scope <- Map.get(session_state, "scope"),
         true <- session_scope == scope_data do
      :ok
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp validate_session_state(params, session_state) do
    with {:ok, session_nonce} <- fetch_nonempty_map(session_state, "state"),
         {:ok, callback_nonce} <- fetch_nonempty_map(params, "state"),
         true <- session_nonce == callback_nonce,
         {:ok, expires_at_unix} <- fetch_integer_map(session_state, "expires_at_unix"),
         true <- DateTime.to_unix(DateTime.utc_now()) <= expires_at_unix do
      :ok
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp fetch_oauth_config(session_state) do
    with %{} = config <- Map.get(session_state, "config"),
         {:ok, client_id_ref} <- fetch_secret_ref(config, "client_id"),
         {:ok, client_secret_ref} <- fetch_secret_ref(config, "client_secret") do
      {:ok,
       %{
         client_id_ref: client_id_ref,
         client_secret_ref: client_secret_ref,
         account_email: safe_string(Map.get(config, "account_email")),
         connection_id: safe_string(Map.get(config, "connection_id"))
       }}
    else
      _ -> {:error, :invalid_session}
    end
  end

  defp upsert_refresh_token(scope, refresh_token) do
    key = "GMAIL_REFRESH_TOKEN_" <> scope_key_suffix(scope)

    case SecretBank.upsert_secret(scope, key, refresh_token) do
      {:ok, _metadata} -> {:ok, "$#{key}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_profile_email(scope, oauth_client, token_payload) do
    with {:ok, access_token} <- fetch_nonempty_map(token_payload, "access_token"),
         {:ok, email} <- fetch_profile_email(oauth_client, access_token),
         {:ok, safe_email} <- normalize_email(email) do
      safe_email
    else
      {:error, reason} ->
        maybe_record_profile_lookup_failure(scope, reason)
        nil

      _ ->
        maybe_record_profile_lookup_failure(scope, :profile_lookup_failed)
        nil
    end
  end

  defp fetch_profile_email(oauth_client, access_token) do
    if function_exported?(oauth_client, :fetch_profile, 1) do
      oauth_client.fetch_profile(access_token)
    else
      {:error, :profile_lookup_failed}
    end
  end

  defp normalize_email(email) when is_binary(email) do
    case safe_string(email) do
      nil -> {:error, :profile_lookup_failed}
      "" -> {:error, :profile_lookup_failed}
      value -> {:ok, value}
    end
  end

  defp normalize_email(_email), do: {:error, :profile_lookup_failed}

  defp maybe_record_profile_lookup_failure(scope, reason) do
    _ =
      Events.record_event(
        "connection.gmail.oauth_profile_lookup_failed",
        event_scope_data(scope),
        "Gmail OAuth profile lookup failed",
        payload: Map.put(event_scope_data(scope), :reason, safe_reason(reason))
      )

    :ok
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(_reason), do: "profile_lookup_failed"

  defp upsert_gmail_connection(scope, config, refresh_ref, profile_email) do
    existing =
      scoped_connection(scope, config.connection_id) ||
        Connections.get_connection_by_type(scope, "gmail")

    existing_email = existing && existing.config && existing.config["account_email"]

    account_email =
      profile_email ||
        config.account_email ||
        safe_string(existing_email) ||
        ""

    attrs = %{
      type: "gmail",
      status: "enabled",
      config: %{
        "provider" => "gmail",
        "scopes" => [GmailCaller.compose_scope()],
        "client_id" => config.client_id_ref,
        "client_secret" => config.client_secret_ref,
        "refresh_token" => refresh_ref,
        "account_email" => account_email
      }
    }

    case existing do
      nil -> Connections.create_connection(scope, attrs)
      connection -> Connections.update_connection(scope, connection, attrs)
    end
  end

  defp scoped_connection(_scope, nil), do: nil
  defp scoped_connection(_scope, ""), do: nil

  defp scoped_connection(scope, connection_id) do
    case Connections.get_connection(scope, connection_id) do
      %Connection{type: "gmail"} = connection -> connection
      _ -> nil
    end
  end

  defp event_scope_data(%World{id: world_id}),
    do: %{world_id: world_id, city_id: nil, department_id: nil}

  defp event_scope_data(%City{id: city_id, world_id: world_id}),
    do: %{world_id: world_id, city_id: city_id, department_id: nil}

  defp event_scope_data(%Department{id: department_id, city_id: city_id, world_id: world_id}),
    do: %{world_id: world_id, city_id: city_id, department_id: department_id}

  defp scope_key_suffix(%World{id: world_id}), do: "WORLD_" <> sanitize_uuid(world_id)
  defp scope_key_suffix(%City{id: city_id}), do: "CITY_" <> sanitize_uuid(city_id)

  defp scope_key_suffix(%Department{id: department_id}),
    do: "DEPARTMENT_" <> sanitize_uuid(department_id)

  defp sanitize_uuid(id), do: id |> String.replace("-", "_") |> String.upcase()

  defp scope_data(%World{id: world_id}) when is_binary(world_id) do
    {:ok, %{"kind" => "world", "world_id" => world_id}}
  end

  defp scope_data(%City{id: city_id, world_id: world_id})
       when is_binary(city_id) and is_binary(world_id) do
    {:ok, %{"kind" => "city", "world_id" => world_id, "city_id" => city_id}}
  end

  defp scope_data(%Department{id: department_id, city_id: city_id, world_id: world_id})
       when is_binary(department_id) and is_binary(city_id) and is_binary(world_id) do
    {:ok,
     %{
       "kind" => "department",
       "world_id" => world_id,
       "city_id" => city_id,
       "department_id" => department_id
     }}
  end

  defp scope_data(_scope), do: {:error, :invalid_scope}

  defp fetch_secret_ref(map, key) do
    with {:ok, value} <- fetch_nonempty_map(map, key),
         "$" <> rest <- value,
         true <- rest != "" do
      {:ok, value}
    else
      _ -> {:error, :invalid_config}
    end
  end

  defp fetch_nonempty(list, key) do
    case Keyword.get(list, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_config}
    end
  end

  defp fetch_nonempty_map(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_config}
    end
  end

  defp fetch_integer_map(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_config}
    end
  end

  defp safe_string(nil), do: nil
  defp safe_string(value) when is_binary(value), do: String.trim(value)
  defp safe_string(_value), do: nil
end
