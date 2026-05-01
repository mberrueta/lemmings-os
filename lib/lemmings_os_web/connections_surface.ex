defmodule LemmingsOsWeb.ConnectionsSurface do
  @moduledoc """
  Shared form parsing/building for scope-local Connections surfaces.
  """

  use Gettext, backend: LemmingsOs.Gettext

  alias LemmingsOs.Connections

  def create_form(types, params \\ %{}) do
    default_type =
      case Map.get(params, "type") do
        type when is_binary(type) and type != "" -> type
        _ -> default_type(types)
      end

    default_config = default_config_text(types, default_type)

    form_params = %{
      "type" => default_type,
      "status" => "enabled",
      "config" => Map.get(params, "config", default_config)
    }

    form_params
    |> connection_form_changeset()
    |> Phoenix.Component.to_form(as: :connection_create)
  end

  def edit_form(connection_or_params) do
    params =
      case connection_or_params do
        %{"type" => type} = params when is_binary(type) ->
          params

        connection ->
          %{
            "connection_id" => connection.id,
            "type" => connection.type,
            "status" => connection.status,
            "config" => encode_config(connection.config || %{})
          }
      end

    params
    |> connection_form_changeset()
    |> Phoenix.Component.to_form(as: :connection_edit)
  end

  def parse_connection_form_params(params) when is_map(params) do
    with type when is_binary(type) and type != "" <- String.trim(Map.get(params, "type", "")),
         status when is_binary(status) and status != "" <-
           String.trim(Map.get(params, "status", "enabled")),
         {:ok, config} <- parse_config_payload(Map.get(params, "config", "{}")) do
      {:ok, %{type: type, status: status, config: config}}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  def parse_connection_form_params(_params), do: {:error, :invalid_payload}

  def default_config_text(types, type) do
    config =
      types
      |> Enum.find_value(%{}, fn entry -> if entry.id == type, do: entry.default_config end)

    encode_config(config)
  end

  def encode_config(config) when is_map(config), do: Jason.encode!(config, pretty: true)

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

  def run_connection_lifecycle(scope, connection, "enable"),
    do: Connections.enable_connection(scope, connection)

  def run_connection_lifecycle(scope, connection, "disable"),
    do: Connections.disable_connection(scope, connection)

  def run_connection_lifecycle(_scope, _connection, _action), do: {:error, :invalid_action}

  def test_failure_message(reason) do
    "#{dgettext("layout", ".connections_flash_test_failed")} (#{test_failure_reason_label(reason)})"
  end

  defp connection_form_changeset(params) do
    types = %{type: :string, status: :string, config: :string, connection_id: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:type, :status, :config])
  end

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
