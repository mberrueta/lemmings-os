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
  def search(args) when is_map(args) do
    with {:ok, query} <- validate_search_args(args),
         {:ok, payload} <- request_search(query),
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
  def fetch(args) when is_map(args) do
    with {:ok, url} <- validate_fetch_args(args),
         {:ok, response} <- request_fetch(url) do
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
      %URI{scheme: scheme, host: host} = _uri
      when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, url}

      _uri ->
        {:error,
         %{
           code: "tool.web.invalid_url",
           message: "Invalid URL",
           details: %{url: url}
         }}
    end
  end

  defp request_search(query) when is_binary(query) do
    req_options = [url: search_endpoint(), params: [q: query, format: "json", no_html: 1]]

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
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp request_fetch(url) when is_binary(url) do
    case Req.get(url: url) do
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
           details: %{reason: inspect(reason)}
         }}
    end
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

  defp search_endpoint do
    Application.get_env(:lemmings_os, :tools_web_search_endpoint, "https://api.duckduckgo.com/")
  end
end
