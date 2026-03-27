defmodule LemmingsOs.ModelRuntime.Providers.Ollama do
  @moduledoc """
  Ollama provider implementation for model runtime execution.
  """

  @behaviour LemmingsOs.ModelRuntime.Provider

  require Logger

  alias LemmingsOs.ModelRuntime.Provider

  @provider_name "ollama"
  @default_base_url "http://localhost:11434"
  @default_timeout 120_000

  @doc """
  Executes a chat request against Ollama's `/api/chat` endpoint.

  ## Examples

      iex> request = %{model: "llama3.2", messages: [%{role: "user", content: "Hi"}], format: "json"}
      iex> match?({:error, :network_error}, LemmingsOs.ModelRuntime.Providers.Ollama.chat(request, base_url: "http://127.0.0.1:1", timeout: 1))
      true
  """
  @spec chat(Provider.request(), keyword()) ::
          {:ok, Provider.provider_response()}
          | {:error, :network_error | :provider_error | :timeout}
  def chat(request, opts \\ [])

  def chat(%{model: model, messages: messages} = request, opts)
      when is_binary(model) and is_list(messages) and is_list(opts) do
    req =
      Req.new(
        base_url: Keyword.get(opts, :base_url, default_base_url()),
        receive_timeout: Keyword.get(opts, :timeout, default_timeout()),
        http_errors: :return,
        retry: false
      )

    case Req.post(req, url: "/api/chat", json: request_body(request)) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        with {:ok, response_body} <- normalize_body(body),
             {:ok, content} <- response_content(response_body) do
          {:ok, build_provider_response(content, response_body, model)}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        log_provider_error(status, body)
        {:error, :provider_error}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{} = error} ->
        log_network_error(error)
        {:error, :network_error}

      {:error, error} ->
        log_network_error(error)
        {:error, :network_error}
    end
  end

  def chat(_request, _opts), do: {:error, :provider_error}

  defp request_body(request) do
    model = Map.get(request, :model) || Map.get(request, "model")
    messages = Map.get(request, :messages) || Map.get(request, "messages") || []

    %{
      "model" => model,
      "messages" => messages,
      "format" => request_format(request),
      "stream" => false
    }
  end

  defp request_format(request) do
    Map.get(request, :format) || Map.get(request, "format") || "json"
  end

  defp normalize_body(body) when is_map(body), do: {:ok, body}

  defp normalize_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
      {:ok, _parsed} -> {:error, :provider_error}
      {:error, _reason} -> {:error, :provider_error}
    end
  end

  defp normalize_body(_body), do: {:error, :provider_error}

  defp response_content(%{"message" => %{"content" => content}}) when is_binary(content),
    do: {:ok, content}

  defp response_content(%{"message" => %{"content" => content}}) when is_list(content),
    do: {:ok, IO.iodata_to_binary(content)}

  defp response_content(%{"message" => %{} = message}) do
    case Map.get(message, :content) || Map.get(message, "content") do
      content when is_binary(content) -> {:ok, content}
      content when is_list(content) -> {:ok, IO.iodata_to_binary(content)}
      _ -> {:error, :provider_error}
    end
  end

  defp response_content(_body), do: {:error, :provider_error}

  defp build_provider_response(content, body, model) do
    input_tokens = fetch_integer(body, "prompt_eval_count")
    output_tokens = fetch_integer(body, "eval_count")
    total_tokens = resolve_total_tokens(body, input_tokens, output_tokens)

    %{
      content: content,
      provider: @provider_name,
      model: fetch_string(body, "model") || model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      usage: usage_map(body),
      raw: body
    }
  end

  defp usage_map(body) do
    %{
      prompt_eval_count: fetch_integer(body, "prompt_eval_count"),
      eval_count: fetch_integer(body, "eval_count"),
      total_duration: fetch_integer(body, "total_duration"),
      load_duration: fetch_integer(body, "load_duration"),
      prompt_eval_duration: fetch_integer(body, "prompt_eval_duration"),
      eval_duration: fetch_integer(body, "eval_duration"),
      done: fetch_bool(body, "done"),
      done_reason: fetch_string(body, "done_reason")
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp resolve_total_tokens(body, input_tokens, output_tokens) do
    cond do
      is_integer(input_tokens) and is_integer(output_tokens) ->
        input_tokens + output_tokens

      is_integer(fetch_integer(body, "total_tokens")) ->
        fetch_integer(body, "total_tokens")

      true ->
        nil
    end
  end

  defp fetch_integer(body, key) do
    case Map.get(body, key) || Map.get(body, String.to_atom(key)) do
      value when is_integer(value) -> value
      _ -> nil
    end
  end

  defp fetch_string(body, key) do
    case Map.get(body, key) || Map.get(body, String.to_atom(key)) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp fetch_bool(body, key) do
    case Map.get(body, key) || Map.get(body, String.to_atom(key)) do
      value when is_boolean(value) -> value
      _ -> nil
    end
  end

  defp log_provider_error(status, body) do
    Logger.error("ollama provider returned a non-success response",
      event: "model_runtime.provider.ollama.error",
      status: status,
      reason: inspect(body)
    )
  end

  defp log_network_error(reason) do
    Logger.error("ollama provider request failed",
      event: "model_runtime.provider.ollama.network_error",
      reason: inspect(reason)
    )
  end

  defp default_base_url do
    model_runtime_config()
    |> Keyword.get(:ollama, [])
    |> Keyword.get(:base_url, @default_base_url)
  end

  defp default_timeout do
    Keyword.get(model_runtime_config(), :timeout, @default_timeout)
  end

  defp model_runtime_config do
    Application.get_env(:lemmings_os, :model_runtime, [])
  end
end
