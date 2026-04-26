defmodule LemmingsOs.LemmingInstances.Executor.Redaction do
  @moduledoc """
  Redaction helpers for runtime payloads that can be serialized into context.
  """

  @redacted "[REDACTED]"
  @sensitive_key_patterns [
    "api_key",
    "apikey",
    "password",
    "passwd",
    "passphrase",
    "token",
    "secret",
    "authorization",
    "auth"
  ]

  @doc """
  Recursively redacts sensitive values by key name.
  """
  @spec redact(term()) :: term()
  def redact(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      if sensitive_key?(key) do
        {key, @redacted}
      else
        {key, redact(nested_value)}
      end
    end)
  end

  def redact(value) when is_list(value), do: Enum.map(value, &redact/1)

  def redact(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&redact/1) |> List.to_tuple()

  def redact(value), do: value

  @doc """
  Encodes a redacted value to JSON.
  """
  @spec encode_redacted(term()) :: binary()
  def encode_redacted(value), do: value |> redact() |> Jason.encode!()

  defp sensitive_key?(key) do
    key
    |> to_string()
    |> String.downcase()
    |> then(&Enum.any?(@sensitive_key_patterns, fn pattern -> String.contains?(&1, pattern) end))
  end
end
