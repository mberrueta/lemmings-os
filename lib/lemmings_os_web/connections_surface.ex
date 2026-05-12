defmodule LemmingsOsWeb.ConnectionsSurface do
  @moduledoc """
  Shared form parsing/building for scope-local Connections surfaces.
  """

  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.Connections
  alias LemmingsOs.Connections.Connection
  alias LemmingsOs.Connections.Providers.GmailCaller
  alias LemmingsOs.SecretBank

  @gmail_client_id_refs [
    "$GMAIL_CLIENT_ID",
    "$GOOGLE_OAUTH_CLIENT_ID",
    "$GMAIL_OAUTH_CLIENT_ID"
  ]
  @gmail_client_secret_refs [
    "$GMAIL_CLIENT_SECRET",
    "$GOOGLE_OAUTH_CLIENT_SECRET",
    "$GMAIL_OAUTH_CLIENT_SECRET"
  ]
  @gmail_default_client_id_ref "$GMAIL_CLIENT_ID"
  @gmail_default_client_secret_ref "$GMAIL_CLIENT_SECRET"

  def create_form(types, params \\ %{}) do
    default_type =
      case Map.get(params, "type") do
        type when is_binary(type) and type != "" -> type
        _ -> default_type(types)
      end

    form_params =
      params
      |> Map.put_new("type", default_type)
      |> Map.put_new("status", "enabled")
      |> Map.put_new("config", default_config_text(types, default_type))
      |> normalize_gmail_form_params()

    form_params
    |> connection_form_changeset()
    |> Phoenix.Component.to_form(as: :connection_create)
  end

  def create_form_for_type(types, type, rows) when is_list(rows) do
    params =
      case find_local_connection_by_type(rows, type) do
        {:ok, connection} -> params_from_connection(connection)
        :error -> %{"type" => type}
      end

    create_form(types, params)
  end

  def edit_form(connection_or_params) do
    params =
      case connection_or_params do
        %{"type" => type} = params when is_binary(type) ->
          params

        connection ->
          params_from_connection(connection)
      end

    params
    |> normalize_gmail_form_params()
    |> connection_form_changeset()
    |> Phoenix.Component.to_form(as: :connection_edit)
  end

  def parse_connection_form_params(params) when is_map(params) do
    with type when is_binary(type) and type != "" <- String.trim(Map.get(params, "type", "")),
         {:ok, status} <- fetch_status(params) do
      parse_connection_config(type, status, params)
    else
      _ -> {:error, :invalid_payload}
    end
  end

  def parse_connection_form_params(_params), do: {:error, :invalid_payload}

  def connection_form_action(%{"action" => "connect_gmail"}), do: :connect_gmail
  def connection_form_action(_params), do: :save

  def upsert_gmail_connection(scope, attrs, "") when is_map(attrs),
    do: upsert_gmail_connection(scope, attrs, nil)

  def upsert_gmail_connection(scope, attrs, connection_id)
      when is_map(attrs) and is_binary(connection_id) do
    existing = Connections.get_connection(scope, connection_id)

    cond do
      match?(%Connection{type: "gmail"}, existing) ->
        Connections.update_connection(scope, existing, attrs)

      is_nil(existing) ->
        upsert_gmail_connection(scope, attrs, nil)

      true ->
        {:error, :invalid_type}
    end
  end

  def upsert_gmail_connection(scope, attrs, _connection_id) when is_map(attrs) do
    case Connections.get_connection_by_type(scope, "gmail") do
      %Connection{} = connection -> Connections.update_connection(scope, connection, attrs)
      nil -> Connections.create_connection(scope, attrs)
    end
  end

  def gmail_oauth_state(scope) do
    client_id_ref = first_available_ref(scope, @gmail_client_id_refs)
    client_secret_ref = first_available_ref(scope, @gmail_client_secret_refs)

    missing_refs =
      []
      |> maybe_add_missing_ref(client_id_ref, List.first(@gmail_client_id_refs))
      |> maybe_add_missing_ref(client_secret_ref, List.first(@gmail_client_secret_refs))

    %{
      enabled?: missing_refs == [],
      client_id_ref: client_id_ref || List.first(@gmail_client_id_refs),
      client_secret_ref: client_secret_ref || List.first(@gmail_client_secret_refs),
      missing_refs: missing_refs
    }
  end

  def default_config_text(types, type) do
    config =
      types
      |> Enum.find_value(%{}, fn entry -> if entry.id == type, do: entry.default_config end)

    encode_config(config)
  end

  def encode_config(config) when is_map(config), do: Jason.encode!(config, pretty: true)

  def gmail_form?(form), do: form_value(form, :type) == "gmail"

  def gmail_connected?(form) do
    form
    |> gmail_refresh_token_ref()
    |> present?()
  end

  def gmail_account_label(form) do
    case form_value(form, :account_email) do
      value when is_binary(value) and value != "" -> value
      _ -> dgettext("layout", "Not available")
    end
  end

  def gmail_refresh_token_ref(form) do
    case form_value(form, :refresh_token) do
      "$" <> _rest = ref -> ref
      _ -> nil
    end
  end

  def gmail_status_label(form) do
    if gmail_connected?(form) do
      dgettext("layout", "Connected")
    else
      dgettext("layout", "Not connected")
    end
  end

  def gmail_action_label(form) do
    if gmail_connected?(form) do
      dgettext("layout", "Reconnect Gmail")
    else
      dgettext("layout", "Connect Gmail")
    end
  end

  def connection_label(%{connection: connection, source_scope: source_scope}) do
    "#{String.capitalize(source_scope)} / #{connection.type}"
  end

  def source_scope_tone(%{local?: true}), do: "ok"
  def source_scope_tone(_row), do: "warn"

  def source_scope_copy(%{local?: true}), do: dgettext("layout", ".connections_source_local")

  def source_scope_copy(%{inherited?: true}),
    do: dgettext("layout", ".connections_source_inherited")

  def source_scope_copy(_row), do: dgettext("layout", ".connections_source_unknown")

  def source_scope_label("world"), do: dgettext("layout", ".connections_source_world")
  def source_scope_label("city"), do: dgettext("layout", ".connections_source_city")
  def source_scope_label("department"), do: dgettext("layout", ".connections_source_department")
  def source_scope_label(_source_scope), do: dgettext("layout", ".connections_source_unknown")

  def find_local_connection_row(rows, connection_id) do
    case Enum.find(rows, &(&1.local? and &1.connection.id == connection_id)) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  def find_local_connection_by_type(rows, type) when is_list(rows) and is_binary(type) do
    case Enum.find(rows, &(&1.local? and &1.connection.type == type)) do
      nil -> :error
      row -> {:ok, row.connection}
    end
  end

  def run_connection_lifecycle(scope, connection, "enable"),
    do: Connections.enable_connection(scope, connection)

  def run_connection_lifecycle(scope, connection, "disable"),
    do: Connections.disable_connection(scope, connection)

  def run_connection_lifecycle(_scope, _connection, _action), do: {:error, :invalid_action}

  def test_failure_message(reason) do
    "#{dgettext("layout", ".connections_flash_test_failed")} (#{test_failure_reason_label(reason)})"
  end

  defp connection_form_changeset(params) do
    types = %{
      type: :string,
      status: :string,
      config: :string,
      connection_id: :string,
      client_id: :string,
      client_secret: :string,
      account_email: :string,
      refresh_token: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:type, :status, :config])
  end

  defp params_from_connection(%Connection{} = connection) do
    %{
      "connection_id" => connection.id,
      "type" => connection.type,
      "status" => connection.status,
      "config" => encode_config(connection.config || %{})
    }
  end

  defp normalize_gmail_form_params(%{"type" => "gmail"} = params) do
    config = parse_config_payload(Map.get(params, "config", "{}")) |> parsed_config_or_empty()

    client_id =
      first_present([
        Map.get(params, "client_id"),
        Map.get(config, "client_id"),
        @gmail_default_client_id_ref
      ])

    client_secret =
      first_present([
        Map.get(params, "client_secret"),
        Map.get(config, "client_secret"),
        @gmail_default_client_secret_ref
      ])

    account_email =
      first_present([Map.get(params, "account_email"), Map.get(config, "account_email"), ""])

    refresh_token =
      first_present([Map.get(params, "refresh_token"), Map.get(config, "refresh_token"), ""])

    gmail_config =
      gmail_config(client_id, client_secret, account_email, refresh_token)

    params
    |> Map.put("client_id", client_id)
    |> Map.put("client_secret", client_secret)
    |> Map.put("account_email", account_email)
    |> Map.put("refresh_token", refresh_token)
    |> Map.put("config", Map.get(params, "config") || encode_config(gmail_config))
  end

  defp normalize_gmail_form_params(params), do: params

  defp parsed_config_or_empty({:ok, config}), do: config
  defp parsed_config_or_empty(_result), do: %{}

  defp first_present(values) do
    Enum.find_value(values, "", fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end)
  end

  defp fetch_status(params) do
    case String.trim(Map.get(params, "status", "enabled")) do
      "" -> {:error, :invalid_payload}
      status -> {:ok, status}
    end
  end

  defp parse_connection_config("gmail", status, params) do
    with {:ok, client_id_ref} <- fetch_secret_ref(params, "client_id"),
         {:ok, client_secret_ref} <- fetch_secret_ref(params, "client_secret") do
      account_email = params |> Map.get("account_email", "") |> safe_string()
      refresh_token = params |> Map.get("refresh_token", "") |> safe_string()

      {:ok,
       %{
         type: "gmail",
         status: status,
         config: gmail_config(client_id_ref, client_secret_ref, account_email, refresh_token)
       }}
    end
  end

  defp parse_connection_config(type, status, params) do
    with {:ok, config} <- parse_config_payload(Map.get(params, "config", "{}")) do
      {:ok, %{type: type, status: status, config: config}}
    end
  end

  defp gmail_config(client_id_ref, client_secret_ref, account_email, refresh_token) do
    %{
      "provider" => "gmail",
      "scopes" => [GmailCaller.compose_scope()],
      "client_id" => client_id_ref,
      "client_secret" => client_secret_ref,
      "account_email" => account_email || ""
    }
    |> maybe_put_refresh_token(refresh_token)
  end

  defp maybe_put_refresh_token(config, "$" <> _rest = refresh_token),
    do: Map.put(config, "refresh_token", refresh_token)

  defp maybe_put_refresh_token(config, _refresh_token), do: config

  defp fetch_secret_ref(map, key) do
    with value when is_binary(value) <- Map.get(map, key),
         "$" <> rest = ref <- String.trim(value),
         true <- rest != "" do
      {:ok, ref}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp safe_string(value) when is_binary(value), do: String.trim(value)
  defp safe_string(_value), do: ""

  defp form_value(form, field) do
    value = form[field].value

    case value do
      value when is_binary(value) -> String.trim(value)
      _ -> value
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp parse_config_payload(payload) when is_binary(payload) do
    case YamlElixir.read_from_string(payload) do
      {:ok, parsed} when is_map(parsed) -> {:ok, stringify_keys(parsed)}
      _ -> decode_json_payload(payload)
    end
  end

  defp parse_config_payload(_payload), do: {:error, :invalid_payload}

  defp decode_json_payload(payload) do
    case Jason.decode(payload) do
      {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
      _ -> {:error, :invalid_payload}
    end
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
      {key, stringify_value(v)}
    end)
    |> Map.new()
  end

  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value), do: value

  defp default_type([%{id: id} | _rest]), do: id
  defp default_type(_types), do: ""

  defp first_available_ref(scope, refs) when is_list(refs) do
    Enum.find(refs, &secret_configured?(scope, &1))
  end

  defp secret_configured?(scope, ref) when is_binary(ref) do
    case SecretBank.list_effective_metadata(scope, bank_key: ref) do
      [%{configured: true} | _rest] -> true
      _ -> false
    end
  end

  defp maybe_add_missing_ref(missing_refs, nil, required_ref), do: missing_refs ++ [required_ref]
  defp maybe_add_missing_ref(missing_refs, _present_ref, _required_ref), do: missing_refs

  defp test_failure_reason_label(%Ecto.Changeset{}), do: "invalid changeset"
  defp test_failure_reason_label(:missing_secret), do: "missing_secret"
  defp test_failure_reason_label(:secret_resolution_failed), do: "secret_resolution_failed"
  defp test_failure_reason_label(:invalid_config), do: "invalid_config"
  defp test_failure_reason_label(:disabled), do: "disabled"
  defp test_failure_reason_label(:invalid), do: "invalid"
  defp test_failure_reason_label(:missing), do: "missing"
  defp test_failure_reason_label(:unsupported_type), do: "unsupported_type"
  defp test_failure_reason_label(:invalid_scope), do: "invalid_scope"
  defp test_failure_reason_label(:invalid_type), do: "invalid_type"
  defp test_failure_reason_label(:provider_test_failed), do: "provider_test_failed"
  defp test_failure_reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp test_failure_reason_label(_reason), do: "unknown"
end
