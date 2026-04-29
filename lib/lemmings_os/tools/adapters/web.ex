defmodule LemmingsOs.Tools.Adapters.Web do
  @moduledoc """
  Web adapters for Tool Runtime MVP.
  """

  alias LemmingsOs.Events
  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Worlds.World

  @redacted "[REDACTED]"
  @secret_ref_prefix "$"

  @type success_result :: %{
          summary: String.t(),
          preview: String.t() | nil,
          result: map()
        }

  @type error_result :: %{
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @doc """
  Executes the `web.search` adapter.

  ## Examples

      iex> LemmingsOs.Tools.Adapters.Web.search(%{"query" => "phoenix framework"})
      {:error, %{code: "tool.web.request_failed", details: %{reason: _}, message: "Web search request failed"}}
  """
  @spec search(map()) :: {:ok, success_result()} | {:error, error_result()}
  def search(args) when is_map(args), do: search(args, %{})

  @spec search(World.t(), LemmingInstance.t(), map(), map()) ::
          {:ok, success_result()} | {:error, error_result()}
  def search(%World{} = world, %LemmingInstance{} = instance, args, trusted_config)
      when is_map(args) and is_map(trusted_config) do
    with {:ok, query} <- validate_search_args(args),
         {:ok, private_config, redaction_values, secret_audit} <-
           private_execution_config(world, instance, "web.search", trusted_config) do
      search_result =
        with {:ok, payload} <- request_search(query, private_config, secret_audit),
             {:ok, results} <- extract_search_results(payload) do
          {:ok,
           %{
             summary: "Search completed with #{length(results)} result(s)",
             preview: first_result_preview(results),
             result: %{query: query, results: results}
           }}
        end

      redact_adapter_result(search_result, redaction_values)
    end
  end

  @spec search(map(), map()) :: {:ok, success_result()} | {:error, error_result()}
  def search(args, trusted_config) when is_map(args) and is_map(trusted_config) do
    with {:ok, query} <- validate_search_args(args),
         {:ok, payload} <- request_search(query, trusted_config),
         {:ok, results} <- extract_search_results(payload) do
      {:ok,
       %{
         summary: "Search completed with #{length(results)} result(s)",
         preview: first_result_preview(results),
         result: %{query: query, results: results}
       }}
    end
  end

  @doc """
  Executes the `web.fetch` adapter.

  ## Examples

      iex> LemmingsOs.Tools.Adapters.Web.fetch(%{"url" => "invalid"})
      {:error, %{code: "tool.web.invalid_url", details: %{url: "invalid"}, message: "Invalid URL"}}
  """
  @spec fetch(map()) :: {:ok, success_result()} | {:error, error_result()}
  def fetch(args) when is_map(args), do: fetch(args, %{})

  @spec fetch(World.t(), LemmingInstance.t(), map(), map()) ::
          {:ok, success_result()} | {:error, error_result()}
  def fetch(%World{} = world, %LemmingInstance{} = instance, args, trusted_config)
      when is_map(args) and is_map(trusted_config) do
    with {:ok, url} <- validate_fetch_args(args),
         {:ok, private_config, redaction_values, secret_audit} <-
           private_execution_config(world, instance, "web.fetch", trusted_config) do
      fetch_result = request_fetch(url, private_config, secret_audit)

      fetch_result
      |> normalize_fetch_response(url)
      |> redact_adapter_result(redaction_values)
    end
  end

  @spec fetch(map(), map()) :: {:ok, success_result()} | {:error, error_result()}
  def fetch(args, trusted_config) when is_map(args) and is_map(trusted_config) do
    with {:ok, url} <- validate_fetch_args(args),
         {:ok, response} <- request_fetch(url, trusted_config) do
      body = to_string(response.body || "")

      {:ok,
       %{
         summary: "Fetched #{url}",
         preview: String.slice(body, 0, 280),
         result: %{
           url: url,
           status: response.status,
           body: body
         }
       }}
    end
  end

  defp validate_search_args(%{"query" => query}) when is_binary(query) and byte_size(query) > 0,
    do: {:ok, query}

  defp validate_search_args(%{query: query}) when is_binary(query) and byte_size(query) > 0,
    do: {:ok, query}

  defp validate_search_args(_args) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{required: ["query"]}
     }}
  end

  defp validate_fetch_args(%{"url" => url}) when is_binary(url), do: validate_http_url(url)
  defp validate_fetch_args(%{url: url}) when is_binary(url), do: validate_http_url(url)

  defp validate_fetch_args(_args) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{required: ["url"]}
     }}
  end

  defp validate_http_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        validate_egress_url(uri, url)

      _uri ->
        {:error,
         %{
           code: "tool.web.invalid_url",
           message: "Invalid URL",
           details: %{url: url}
         }}
    end
  end

  defp request_search(query, trusted_config),
    do: request_search(query, trusted_config, nil)

  defp request_search(query, trusted_config, secret_audit)
       when is_binary(query) and is_map(trusted_config) do
    endpoint = search_endpoint()

    with :ok <- validate_endpoint_egress(endpoint),
         :ok <- validate_secret_header_destination(endpoint, trusted_config, secret_audit) do
      headers = trusted_headers(trusted_config)

      req_options =
        [url: endpoint, params: [q: query, format: "json", no_html: 1], headers: headers]
        |> Keyword.merge(req_timeout_options())

      case Req.get(req_options) do
        {:ok, %Req.Response{} = response} when response.status in 200..299 ->
          record_used_by_tool_events(secret_audit, "succeeded")
          {:ok, response.body}

        {:ok, %Req.Response{} = response} ->
          record_used_by_tool_events(secret_audit, "failed")

          {:error,
           %{
             code: "tool.web.bad_status",
             message: "Web search returned a non-success status",
             details: %{status: response.status}
           }}

        {:error, reason} ->
          record_used_by_tool_events(secret_audit, "failed")

          {:error,
           %{
             code: "tool.web.request_failed",
             message: "Web search request failed",
             details: %{reason: request_error_reason(reason)}
           }}
      end
    end
  end

  defp request_fetch(url, trusted_config),
    do: request_fetch(url, trusted_config, nil)

  defp request_fetch(url, trusted_config, secret_audit)
       when is_binary(url) and is_map(trusted_config) do
    with :ok <- validate_secret_header_destination(url, trusted_config, secret_audit) do
      headers = trusted_headers(trusted_config)

      req_options =
        [url: url, headers: headers]
        |> Keyword.merge(req_timeout_options())

      case Req.get(req_options) do
        {:ok, %Req.Response{} = response} when response.status in 200..299 ->
          record_used_by_tool_events(secret_audit, "succeeded")
          {:ok, response}

        {:ok, %Req.Response{} = response} ->
          record_used_by_tool_events(secret_audit, "failed")

          {:error,
           %{
             code: "tool.web.bad_status",
             message: "Web fetch returned a non-success status",
             details: %{status: response.status}
           }}

        {:error, reason} ->
          record_used_by_tool_events(secret_audit, "failed")

          {:error,
           %{
             code: "tool.web.request_failed",
             message: "Web fetch request failed",
             details: %{reason: request_error_reason(reason)}
           }}
      end
    end
  end

  defp normalize_fetch_response({:ok, %Req.Response{} = response}, url) do
    body = to_string(response.body || "")

    {:ok,
     %{
       summary: "Fetched #{url}",
       preview: String.slice(body, 0, 280),
       result: %{
         url: url,
         status: response.status,
         body: body
       }
     }}
  end

  defp normalize_fetch_response({:error, error}, _url), do: {:error, error}

  defp validate_endpoint_egress(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) ->
        uri
        |> validate_egress_url(endpoint)
        |> case do
          {:ok, _url} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _uri ->
        {:error,
         %{
           code: "tool.web.invalid_url",
           message: "Invalid URL",
           details: %{url: endpoint}
         }}
    end
  end

  defp validate_egress_url(%URI{host: host}, url) when is_binary(host) and is_binary(url) do
    if private_host_allowed?() or public_host?(host) do
      {:ok, url}
    else
      {:error,
       %{
         code: "tool.web.egress_blocked",
         message: "URL host is blocked by web egress policy",
         details: %{host: host}
       }}
    end
  end

  defp public_host?(host) when is_binary(host) do
    normalized_host = host |> String.trim("[]") |> String.downcase()

    not localhost_name?(normalized_host) and
      not private_ip_literal?(normalized_host)
  end

  defp localhost_name?("localhost"), do: true
  defp localhost_name?(host), do: String.ends_with?(host, ".localhost")

  defp private_ip_literal?(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, address} -> private_ip?(address)
      {:error, :einval} -> false
    end
  end

  defp private_ip?({first, _second, _third, _fourth}) when first in [0, 10, 127], do: true
  defp private_ip?({169, 254, _third, _fourth}), do: true
  defp private_ip?({172, second, _third, _fourth}) when second in 16..31, do: true
  defp private_ip?({192, 168, _third, _fourth}), do: true

  defp private_ip?({first, _second, _third, _fourth})
       when first >= 224,
       do: true

  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp private_ip?({first, _b, _c, _d, _e, _f, _g, _h}) when first in 0xFC00..0xFDFF, do: true
  defp private_ip?({first, _b, _c, _d, _e, _f, _g, _h}) when first in 0xFE80..0xFEBF, do: true
  defp private_ip?(_address), do: false

  defp private_host_allowed? do
    Application.get_env(:lemmings_os, :tools_web_allow_private_hosts, false)
  end

  defp req_timeout_options do
    timeout = Application.get_env(:lemmings_os, :tools_web_timeout_ms, 5_000)

    [
      retry: false,
      receive_timeout: timeout,
      connect_options: [timeout: timeout]
    ]
  end

  defp extract_search_results(%{} = payload) do
    results =
      payload
      |> Map.get("RelatedTopics", [])
      |> Enum.flat_map(&normalize_topic/1)
      |> Enum.take(5)

    {:ok, results}
  end

  defp extract_search_results(_payload) do
    {:error,
     %{
       code: "tool.web.invalid_response",
       message: "Web search response has invalid format",
       details: %{}
     }}
  end

  defp normalize_topic(%{"Text" => text, "FirstURL" => url})
       when is_binary(text) and is_binary(url) do
    [%{title: text, url: url, snippet: text}]
  end

  defp normalize_topic(%{"Topics" => topics}) when is_list(topics) do
    Enum.flat_map(topics, &normalize_topic/1)
  end

  defp normalize_topic(_topic), do: []

  defp first_result_preview([%{snippet: snippet} | _rest]) when is_binary(snippet),
    do: String.slice(snippet, 0, 280)

  defp first_result_preview(_results), do: nil

  defp trusted_headers(%{headers: headers}), do: normalize_headers(headers)
  defp trusted_headers(%{"headers" => headers}), do: normalize_headers(headers)
  defp trusted_headers(_trusted_config), do: []

  defp normalize_headers(headers) when is_map(headers) do
    headers
    |> Enum.reduce([], fn
      {key, value}, acc when is_binary(value) ->
        [{to_string(key), value} | acc]

      _entry, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp normalize_headers(_headers), do: []

  defp validate_secret_header_destination(_url, _trusted_config, nil), do: :ok

  defp validate_secret_header_destination(url, trusted_config, secret_audit) do
    if secret_audit_has_header_secret?(secret_audit) do
      with {:ok, host} <- url_host(url),
           true <- host_allowed_for_secret_headers?(host, trusted_config) do
        :ok
      else
        {:error, error} ->
          {:error, error}

        false ->
          {:error,
           %{
             code: "tool.secret.destination_not_allowed",
             message: "Tool secret destination is not allowed",
             details: %{host: url_host_value(url)}
           }}
      end
    else
      :ok
    end
  end

  defp secret_audit_has_header_secret?(%{entries: entries}) when is_list(entries),
    do: Enum.any?(entries, &header_secret_entry?/1)

  defp secret_audit_has_header_secret?(_secret_audit), do: false

  defp url_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        {:ok, normalize_host(host)}

      _uri ->
        {:error,
         %{
           code: "tool.web.invalid_url",
           message: "Invalid URL",
           details: %{url: url}
         }}
    end
  end

  defp url_host_value(url) when is_binary(url) do
    case url_host(url) do
      {:ok, host} -> host
      {:error, _error} -> nil
    end
  end

  defp host_allowed_for_secret_headers?(host, trusted_config) do
    trusted_config
    |> allowed_secret_header_hosts()
    |> MapSet.member?(host)
  end

  defp allowed_secret_header_hosts(%{allowed_hosts: hosts}), do: normalize_host_set(hosts)
  defp allowed_secret_header_hosts(%{"allowed_hosts" => hosts}), do: normalize_host_set(hosts)

  defp allowed_secret_header_hosts(%{secret_header_allowed_hosts: hosts}),
    do: normalize_host_set(hosts)

  defp allowed_secret_header_hosts(%{"secret_header_allowed_hosts" => hosts}),
    do: normalize_host_set(hosts)

  defp allowed_secret_header_hosts(_trusted_config), do: MapSet.new()

  defp normalize_host_set(hosts) when is_list(hosts) do
    hosts
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_host/1)
    |> MapSet.new()
  end

  defp normalize_host_set(_hosts), do: MapSet.new()

  defp normalize_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.trim("[]")
    |> String.downcase()
  end

  defp private_execution_config(world, instance, tool_name, trusted_config) do
    case trusted_config_contains_secret_ref?(trusted_config) do
      true ->
        with {:ok, scope} <- runtime_scope(world, instance) do
          resolve_private_config(tool_name, scope, instance, trusted_config)
        end

      false ->
        {:ok, trusted_config, [], nil}
    end
  end

  defp runtime_scope(
         %World{id: world_id},
         %LemmingInstance{
           lemming_id: lemming_id,
           city_id: city_id,
           department_id: department_id
         }
       )
       when is_binary(world_id) and is_binary(lemming_id) and is_binary(city_id) and
              is_binary(department_id) do
    {:ok,
     %Lemming{
       id: lemming_id,
       world_id: world_id,
       city_id: city_id,
       department_id: department_id
     }}
  end

  defp runtime_scope(_world, _instance),
    do: {:error, private_config_error(nil, nil, :invalid_scope)}

  defp trusted_config_contains_secret_ref?(value) when is_map(value) do
    Enum.any?(value, fn {_key, nested_value} ->
      trusted_config_contains_secret_ref?(nested_value)
    end)
  end

  defp trusted_config_contains_secret_ref?(values) when is_list(values) do
    Enum.any?(values, &trusted_config_contains_secret_ref?/1)
  end

  defp trusted_config_contains_secret_ref?(value) when is_binary(value),
    do: secret_ref?(value)

  defp trusted_config_contains_secret_ref?(_value), do: false

  defp resolve_private_config(tool_name, scope, instance, trusted_config) do
    with {:ok, private_config, redaction_values, audit_entries} <-
           resolve_secret_refs(tool_name, scope, trusted_config) do
      secret_audit = %{
        tool_name: tool_name,
        scope: scope,
        instance_id: instance.id,
        entries: audit_entries
      }

      {:ok, private_config, normalize_redaction_values(redaction_values), secret_audit}
    end
  end

  defp resolve_secret_refs(tool_name, scope, value),
    do: resolve_secret_refs(tool_name, scope, value, [])

  defp resolve_secret_refs(tool_name, scope, value, path) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}, [], []}, fn {key, nested_value},
                                                    {:ok, acc, redaction_values, audit_entries} ->
      case resolve_secret_refs(tool_name, scope, nested_value, path ++ [path_key(key)]) do
        {:ok, resolved_value, nested_redaction_values, nested_audit_entries} ->
          {:cont,
           {:ok, Map.put(acc, key, resolved_value), redaction_values ++ nested_redaction_values,
            audit_entries ++ nested_audit_entries}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp resolve_secret_refs(tool_name, scope, values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], [], []}, fn {value, index},
                                               {:ok, acc, redaction_values, audit_entries} ->
      case resolve_secret_refs(tool_name, scope, value, path ++ [index]) do
        {:ok, resolved_value, nested_redaction_values, nested_audit_entries} ->
          {:cont,
           {:ok, acc ++ [resolved_value], redaction_values ++ nested_redaction_values,
            audit_entries ++ nested_audit_entries}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp resolve_secret_refs(tool_name, scope, value, path) when is_binary(value) do
    case secret_ref?(value) do
      true ->
        resolve_secret_ref(tool_name, scope, value, path)

      false ->
        {:ok, value, [], []}
    end
  end

  defp resolve_secret_refs(_tool_name, _scope, value, _path), do: {:ok, value, [], []}

  defp resolve_secret_ref(tool_name, scope, value, path) do
    case SecretBank.resolve_runtime_secret(scope, value, tool_name: tool_name) do
      {:ok, %{value: secret_value} = runtime_secret} when is_binary(secret_value) ->
        {:ok, secret_value, [secret_value], [secret_audit_entry(runtime_secret, path)]}

      {:error, reason} ->
        {:error, private_config_error(tool_name, scope, value, reason)}
    end
  end

  defp path_key(key) when is_atom(key), do: Atom.to_string(key)
  defp path_key(key) when is_binary(key), do: key
  defp path_key(key), do: to_string(key)

  defp secret_audit_entry(runtime_secret, path) do
    %{
      key: runtime_secret.bank_key,
      resolved_source: runtime_secret.scope,
      path: path
    }
  end

  defp private_config_error(tool_name, scope, secret_ref, reason) do
    {code, message} = private_config_error_code(reason)

    %{
      code: code,
      message: message,
      details: %{
        secret_ref: secret_ref,
        bank_key: normalize_secret_ref(secret_ref),
        requested_scope: requested_scope(scope),
        reason: private_config_error_reason(reason)
      }
    }
    |> maybe_put_tool_name(tool_name)
  end

  defp private_config_error(_tool_name, _scope, reason) do
    {code, message} = private_config_error_code(reason)

    %{
      code: code,
      message: message,
      details: %{reason: private_config_error_reason(reason)}
    }
  end

  defp private_config_error_code(:missing_secret),
    do: {"tool.secret.missing", "Tool secret is not configured"}

  defp private_config_error_code(:invalid_key),
    do: {"tool.secret.invalid_reference", "Tool secret reference is invalid"}

  defp private_config_error_code(:invalid_scope),
    do: {"tool.secret.invalid_scope", "Tool secret scope is invalid"}

  defp private_config_error_code(:scope_mismatch),
    do: {"tool.secret.invalid_scope", "Tool secret scope is invalid"}

  defp private_config_error_code(:decrypt_failed),
    do: {"tool.secret.decrypt_failed", "Tool secret could not be decrypted"}

  defp private_config_error_reason(reason), do: Atom.to_string(reason)

  defp maybe_put_tool_name(error, tool_name) when is_binary(tool_name),
    do: Map.put(error, :tool_name, tool_name)

  defp record_used_by_tool_events(%{entries: entries} = secret_audit, status)
       when is_list(entries) and status in ["succeeded", "failed"] do
    entries
    |> Enum.filter(&header_secret_entry?/1)
    |> Enum.uniq_by(&{&1.key, &1.resolved_source})
    |> Enum.each(fn entry ->
      _ =
        Events.record_event(
          "secret.used_by_tool",
          secret_audit.scope,
          "#{entry.key} used by #{secret_audit.tool_name}",
          payload: used_by_tool_payload(secret_audit, entry),
          event_family: "audit",
          action: "use",
          status: status,
          resource_type: "secret",
          resource_id: entry.key
        )
    end)
  end

  defp record_used_by_tool_events(_secret_audit, _status), do: :ok

  defp header_secret_entry?(%{path: ["headers", _header_name | _rest]}), do: true
  defp header_secret_entry?(_entry), do: false

  defp used_by_tool_payload(secret_audit, entry) do
    secret_audit.scope
    |> requested_scope()
    |> Map.merge(%{
      key: entry.key,
      tool_name: secret_audit.tool_name,
      adapter_name: inspect(__MODULE__),
      lemming_instance_id: secret_audit.instance_id,
      resolved_source: entry.resolved_source
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp requested_scope(%Lemming{} = scope) do
    %{
      world_id: scope.world_id,
      city_id: scope.city_id,
      department_id: scope.department_id,
      lemming_id: scope.id
    }
  end

  defp normalize_secret_ref(secret_ref) when is_binary(secret_ref) do
    secret_ref
    |> String.trim()
    |> String.trim_leading(@secret_ref_prefix)
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
  end

  defp secret_ref?(value) when is_binary(value) do
    String.starts_with?(String.trim(value), @secret_ref_prefix)
  end

  defp normalize_redaction_values(values) when is_list(values) do
    values
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort_by(&byte_size/1, :desc)
  end

  defp redact_adapter_result({:ok, result}, redaction_values) do
    {:ok, redact_value(result, redaction_values)}
  end

  defp redact_adapter_result({:error, error}, redaction_values) do
    {:error, redact_value(error, redaction_values)}
  end

  defp redact_value(value, redaction_values) when is_binary(value) do
    Enum.reduce(redaction_values, value, fn secret_value, acc ->
      String.replace(acc, secret_value, @redacted)
    end)
  end

  defp redact_value(value, redaction_values) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      {key, redact_value(nested_value, redaction_values)}
    end)
  end

  defp redact_value(values, redaction_values) when is_list(values) do
    Enum.map(values, &redact_value(&1, redaction_values))
  end

  defp redact_value(value, _redaction_values), do: value

  defp request_error_reason(%Req.TransportError{reason: reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp request_error_reason(%Req.TransportError{}), do: "transport_error"
  defp request_error_reason(_reason), do: "request_failed"

  defp search_endpoint do
    Application.get_env(:lemmings_os, :tools_web_search_endpoint, "https://api.duckduckgo.com/")
  end
end
