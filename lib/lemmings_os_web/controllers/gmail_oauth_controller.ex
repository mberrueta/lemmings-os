defmodule LemmingsOsWeb.GmailOAuthController do
  @moduledoc """
  Browser OAuth controller for Gmail connection onboarding.

  Responsibilities:

  - `start/2` validates the requested target scope (`world`, `city`, or
    `department`) and initializes a session-bound OAuth flow through
    `LemmingsOs.Connections.GmailOAuth`.
  - `callback/2` consumes and clears session OAuth state, validates callback
    state/scope through the backend boundary, and creates or updates the
    scope-local `gmail` connection.

  Security and safety behavior:

  - Target scope for callback completion is resolved from session state, not
    from callback params.
  - OAuth session state is deleted before completion handling (fail-closed for
    replay/re-entry).
  - The controller emits safe lifecycle events
    (`connection.gmail.oauth_started|succeeded|failed`) and never logs tokens.
  - User-facing failures remain generic (`"Gmail OAuth failed."`) to avoid
    leaking provider details.
  """
  use LemmingsOsWeb, :controller

  alias LemmingsOs.Cities
  alias LemmingsOs.Connections.GmailOAuth
  alias LemmingsOs.Departments
  alias LemmingsOs.Events
  alias LemmingsOs.Worlds
  alias LemmingsOs.Worlds.World

  @oauth_session_key "gmail_oauth_state"

  def start(conn, params) do
    case scope_from_params(params) do
      {:ok, scope} ->
        case GmailOAuth.start(scope, params, redirect_uri: callback_url(conn)) do
          {:ok, %{authorize_url: url, session_state: session_state}} ->
            _ = record_event(scope, "connection.gmail.oauth_started", "Gmail OAuth started")

            return_to = safe_return_to(params, connections_redirect_path(scope))

            conn
            |> put_session(
              @oauth_session_key,
              Map.put(session_state, "return_to", return_to)
            )
            |> redirect(external: url)

          _ ->
            conn
            |> put_flash(:error, "Unable to start Gmail OAuth.")
            |> redirect(to: connections_redirect_path(scope))
        end

      _ ->
        conn
        |> put_flash(:error, "Unable to start Gmail OAuth.")
        |> redirect(to: ~p"/settings")
    end
  end

  def callback(conn, params) do
    session_state = get_session(conn, @oauth_session_key) || %{}
    conn = delete_session(conn, @oauth_session_key)

    case scope_from_session(session_state) do
      {:ok, scope} ->
        return_to = safe_return_to(session_state, connections_redirect_path(scope))

        case GmailOAuth.complete(scope, params, session_state,
               redirect_uri: callback_url(conn),
               oauth_client: oauth_client()
             ) do
          {:ok, connection} ->
            _ =
              record_event(scope, "connection.gmail.oauth_succeeded", "Gmail OAuth succeeded", %{
                connection_id: connection.id
              })

            conn
            |> put_flash(:info, "Gmail connected.")
            |> redirect(to: return_to)

          {:error, reason} ->
            _ = record_safe_failure(session_state, reason)

            conn
            |> put_flash(:error, "Gmail OAuth failed.")
            |> redirect(to: return_to)
        end

      _ ->
        conn
        |> put_flash(:error, "Gmail OAuth failed.")
        |> redirect(to: safe_return_to(session_state, ~p"/settings"))
    end
  end

  defp oauth_client do
    Application.get_env(
      :lemmings_os,
      :gmail_oauth_client,
      LemmingsOs.Connections.GmailOAuth.Client
    )
  end

  defp callback_url(conn), do: url(conn, ~p"/connections/gmail/oauth/callback")

  defp record_safe_failure(session_state, reason) do
    with {:ok, scope} <- scope_from_session(session_state) do
      record_event(scope, "connection.gmail.oauth_failed", "Gmail OAuth failed", %{
        reason: safe_reason(reason)
      })
    end
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(_reason), do: "oauth_failed"

  defp record_event(scope, event_type, message, payload \\ %{}) do
    Events.record_event(
      event_type,
      scope_data(scope),
      message,
      payload: Map.merge(scope_data(scope), payload)
    )
  end

  defp scope_data(%World{id: world_id}),
    do: %{world_id: world_id, city_id: nil, department_id: nil}

  defp scope_data(%LemmingsOs.Cities.City{id: city_id, world_id: world_id}),
    do: %{world_id: world_id, city_id: city_id, department_id: nil}

  defp scope_data(%LemmingsOs.Departments.Department{
         id: department_id,
         city_id: city_id,
         world_id: world_id
       }),
       do: %{world_id: world_id, city_id: city_id, department_id: department_id}

  defp scope_from_session(%{"scope" => %{"kind" => "world", "world_id" => world_id}})
       when is_binary(world_id) do
    case Worlds.get_world(world_id) do
      nil -> {:error, :invalid_scope}
      world -> {:ok, world}
    end
  end

  defp scope_from_session(%{
         "scope" => %{"kind" => "city", "world_id" => world_id, "city_id" => city_id}
       })
       when is_binary(world_id) and is_binary(city_id) do
    with %World{} = world <- Worlds.get_world(world_id),
         %LemmingsOs.Cities.City{} = city <- Cities.get_city(world, city_id) do
      {:ok, city}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_from_session(%{
         "scope" => %{
           "kind" => "department",
           "world_id" => world_id,
           "city_id" => city_id,
           "department_id" => department_id
         }
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    with %World{} = world <- Worlds.get_world(world_id),
         %LemmingsOs.Cities.City{} = city <- Cities.get_city(world, city_id),
         %LemmingsOs.Departments.Department{} = department <-
           Departments.get_department(department_id, world_id: world.id, city_id: city.id) do
      {:ok, department}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_from_session(_session_state), do: {:error, :invalid_scope}

  defp scope_from_params(%{
         "world_id" => world_id,
         "city_id" => city_id,
         "department_id" => department_id
       })
       when is_binary(world_id) and is_binary(city_id) and is_binary(department_id) do
    with %World{} = world <- Worlds.get_world(world_id),
         %LemmingsOs.Cities.City{} = city <- Cities.get_city(world, city_id),
         %LemmingsOs.Departments.Department{} = department <-
           Departments.get_department(department_id, world_id: world.id, city_id: city.id) do
      {:ok, department}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_from_params(%{"world_id" => world_id, "city_id" => city_id})
       when is_binary(world_id) and is_binary(city_id) do
    with %World{} = world <- Worlds.get_world(world_id),
         %LemmingsOs.Cities.City{} = city <- Cities.get_city(world, city_id) do
      {:ok, city}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_from_params(%{"world_id" => world_id}) when is_binary(world_id) do
    case Worlds.get_world(world_id) do
      %World{} = world -> {:ok, world}
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_from_params(_params), do: {:error, :invalid_scope}

  defp connections_redirect_path(%World{}),
    do: ~p"/world?#{%{tab: "connections"}}"

  defp connections_redirect_path(%LemmingsOs.Cities.City{id: city_id}),
    do: ~p"/cities?#{%{city: city_id, tab: "connections"}}"

  defp connections_redirect_path(%LemmingsOs.Departments.Department{
         id: department_id,
         city_id: city_id
       }),
       do: ~p"/departments?#{%{city: city_id, dept: department_id, tab: "connections"}}"

  defp safe_return_to(%{"return_to" => return_to}, fallback) when is_binary(return_to) do
    return_to
    |> URI.parse()
    |> safe_return_to_uri(return_to, fallback)
  end

  defp safe_return_to(_session_state, fallback), do: fallback

  defp safe_return_to_uri(%URI{scheme: nil, host: nil, path: path}, return_to, _fallback)
       when path in ["/world", "/cities", "/departments"],
       do: return_to

  defp safe_return_to_uri(_uri, _return_to, fallback), do: fallback
end
