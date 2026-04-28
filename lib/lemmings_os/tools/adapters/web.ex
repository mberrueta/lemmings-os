defmodule LemmingsOs.Tools.Adapters.Web do
  @moduledoc """
  Web adapters for Tool Runtime MVP.
  """

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

  defp request_search(query, trusted_config) when is_binary(query) and is_map(trusted_config) do
    endpoint = search_endpoint()

    with :ok <- validate_endpoint_egress(endpoint) do
      headers = trusted_headers(trusted_config)

      req_options =
        [url: endpoint, params: [q: query, format: "json", no_html: 1], headers: headers]
        |> Keyword.merge(req_timeout_options())

      case Req.get(req_options) do
        {:ok, %Req.Response{} = response} when response.status in 200..299 ->
          {:ok, response.body}

        {:ok, %Req.Response{} = response} ->
          {:error,
           %{
             code: "tool.web.bad_status",
             message: "Web search returned a non-success status",
             details: %{status: response.status}
           }}

        {:error, reason} ->
          {:error,
           %{
             code: "tool.web.request_failed",
             message: "Web search request failed",
             details: %{reason: request_error_reason(reason)}
           }}
      end
    end
  end

  defp request_fetch(url, trusted_config) when is_binary(url) and is_map(trusted_config) do
    req_options =
      [url: url, headers: trusted_headers(trusted_config)]
      |> Keyword.merge(req_timeout_options())

    case Req.get(req_options) do
      {:ok, %Req.Response{} = response} when response.status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{} = response} ->
        {:error,
         %{
           code: "tool.web.bad_status",
           message: "Web fetch returned a non-success status",
           details: %{status: response.status}
         }}

      {:error, reason} ->
        {:error,
         %{
           code: "tool.web.request_failed",
           message: "Web fetch request failed",
           details: %{reason: request_error_reason(reason)}
         }}
    end
  end

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

  defp request_error_reason(%Req.TransportError{reason: reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp request_error_reason(%Req.TransportError{}), do: "transport_error"
  defp request_error_reason(_reason), do: "request_failed"

  defp search_endpoint do
    Application.get_env(:lemmings_os, :tools_web_search_endpoint, "https://api.duckduckgo.com/")
  end
end
