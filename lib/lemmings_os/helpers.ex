defmodule LemmingsOs.Helpers do
  @moduledoc """
  Shared formatting and presence helpers used across the application.
  """

  use Gettext, backend: LemmingsOs.Gettext

  @doc """
  Returns true when the value should be treated as blank.

  ## Examples

      iex> LemmingsOs.Helpers.blank?(nil)
      true

      iex> LemmingsOs.Helpers.blank?("   ")
      true

      iex> LemmingsOs.Helpers.blank?("value")
      false
  """
  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_value), do: false

  @doc """
  Converts a string into a slug-friendly format.

  ## Examples

      iex> LemmingsOs.Helpers.slugify("This is an example")
      "this-is-an-example"

      iex> LemmingsOs.Helpers.slugify("Another Example with Special Characters!@#$%")
      "another-example-with-special-characters"
  """
  @spec slugify(nil | String.t()) :: nil | String.t()
  def slugify(nil), do: nil
  def slugify(""), do: ""

  def slugify(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.trim()
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.join("-")
  end

  @doc """
  Normalizes a list of tags into canonical hyphenated values.

  The normalization rules are:

  - trim surrounding whitespace
  - downcase values
  - collapse repeated separators into `-`
  - strip leading/trailing `-`
  - reject blank results
  - deduplicate while preserving first-seen order

  ## Examples

      iex> LemmingsOs.Helpers.normalize_tags([" Customer Support ", "High-Priority"])
      ["customer-support", "high-priority"]

      iex> LemmingsOs.Helpers.normalize_tags(["---", "Ops__Desk", "ops desk", "QA", "qa"])
      ["ops-desk", "qa"]
  """
  @spec normalize_tags(nil | [term()]) :: [String.t()]
  def normalize_tags(nil), do: []

  def normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.reduce([], &normalize_tag_into/2)
    |> Enum.reverse()
  end

  def normalize_tags(_tags), do: []

  @doc """
  Takes allowed keys from a map while accepting atom-keyed and string-keyed input.

  Output keys are always the atom keys from `allowed_keys`. Missing and nil
  values are omitted, and unknown input keys are ignored.

  ## Examples

      iex> LemmingsOs.Helpers.take_existing(%{"name" => "Ada", ignored: true}, [:name])
      %{name: "Ada"}

      iex> LemmingsOs.Helpers.take_existing(%{name: "Ada", age: nil}, [:name, :age])
      %{name: "Ada"}
  """
  @spec take_existing(map(), [atom()]) :: map()
  def take_existing(attrs, allowed_keys) when is_map(attrs) and is_list(allowed_keys) do
    allowed_keys
    |> Map.new(fn key -> {key, Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def take_existing(_attrs, _allowed_keys), do: %{}

  @doc """
  Formats common UI values with a translated fallback for blank values.

  Supported options:
  - `:unavailable_label` - label shown when the value is blank

  ## Examples

      iex> LemmingsOs.Helpers.display_value(nil, unavailable_label: "N/A")
      "N/A"

      iex> LemmingsOs.Helpers.display_value(true)
      "true"

      iex> LemmingsOs.Helpers.display_value("local")
      "local"
  """
  def display_value(value, opts \\ [])

  def display_value(value, _opts) when is_boolean(value) do
    if value, do: "true", else: "false"
  end

  def display_value(value, opts) do
    unavailable_label =
      Keyword.get(opts, :unavailable_label, dgettext("world", ".label_not_available"))

    if blank?(value), do: unavailable_label, else: to_string(value)
  end

  @doc """
  Truncates a value for compact UI display.

  Supported options:
  - `:max_length` - max binary size before truncating. Defaults to `24`
  - `:unavailable_label` - label shown when the value is blank

  ## Examples

      iex> LemmingsOs.Helpers.truncate_value(nil, unavailable_label: "N/A")
      "N/A"

      iex> LemmingsOs.Helpers.truncate_value("abcdefghijklmnopqrstuvwxyz", max_length: 10)
      "abcdefghij..."

      iex> LemmingsOs.Helpers.truncate_value("local", max_length: 10)
      "local"
  """
  def truncate_value(value, opts \\ []) do
    unavailable_label =
      Keyword.get(opts, :unavailable_label, dgettext("world", ".label_not_available"))

    max_length = Keyword.get(opts, :max_length, 24)

    cond do
      blank?(value) ->
        unavailable_label

      is_binary(value) and byte_size(value) > max_length ->
        "#{String.slice(value, 0, max_length)}..."

      true ->
        display_value(value, unavailable_label: unavailable_label)
    end
  end

  @doc """
  Formats datetimes for operator-facing UI.

  Supported options:
  - `:nil_label` - label shown when the value is `nil`
  - `:format` - `Calendar.strftime/2` format string

  ## Examples

      iex> LemmingsOs.Helpers.format_datetime(nil, nil_label: "N/A")
      "N/A"

      iex> LemmingsOs.Helpers.format_datetime(~U[2026-03-17 11:03:00Z])
      "2026-03-17 11:03:00 UTC"

      iex> LemmingsOs.Helpers.format_datetime(~U[2026-03-17 11:03:00Z], format: "%Y-%m-%d")
      "2026-03-17"
  """
  def format_datetime(datetime, opts \\ [])

  def format_datetime(nil, opts) do
    Keyword.get(opts, :nil_label, dgettext("world", ".label_not_imported"))
  end

  def format_datetime(%DateTime{} = datetime, opts) do
    format = Keyword.get(opts, :format, "%Y-%m-%d %H:%M:%S UTC")
    Calendar.strftime(datetime, format)
  end

  @doc """
  Returns env value when present, otherwise fallback.

  ## Examples

      iex> LemmingsOs.Helpers.env_or_default("__LEMMINGS_OS_HELPERS_NOT_SET_0E6D80__", "fallback")
      "fallback"
  """
  @spec env_or_default(String.t(), term()) :: term()
  def env_or_default(env_key, fallback) when is_binary(env_key) do
    case System.get_env(env_key) do
      nil -> fallback
      value -> value
    end
  end

  @doc """
  Returns env value when present, maps `\"\"` to nil, otherwise fallback.

  ## Examples

      iex> LemmingsOs.Helpers.env_optional_path_or_default("__LEMMINGS_OS_HELPERS_NOT_SET_9758E0__", "fallback")
      "fallback"
  """
  @spec env_optional_path_or_default(String.t(), term()) :: term()
  def env_optional_path_or_default(env_key, fallback) when is_binary(env_key) do
    case System.get_env(env_key) do
      nil -> fallback
      "" -> nil
      value -> value
    end
  end

  @doc """
  Parses positive integers from integer or string values.

  ## Examples

      iex> LemmingsOs.Helpers.parse_positive_integer(5)
      {:ok, 5}

      iex> LemmingsOs.Helpers.parse_positive_integer("42")
      {:ok, 42}

      iex> LemmingsOs.Helpers.parse_positive_integer("0")
      :error
  """
  @spec parse_positive_integer(term()) :: {:ok, pos_integer()} | :error
  def parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  def parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> :error
    end
  end

  def parse_positive_integer(_value), do: :error

  @doc """
  Parses non-negative integers from integer or string values.

  ## Examples

      iex> LemmingsOs.Helpers.parse_non_negative_integer(0)
      {:ok, 0}

      iex> LemmingsOs.Helpers.parse_non_negative_integer("7")
      {:ok, 7}

      iex> LemmingsOs.Helpers.parse_non_negative_integer("-1")
      :error
  """
  @spec parse_non_negative_integer(term()) :: {:ok, non_neg_integer()} | :error
  def parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  def parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> :error
    end
  end

  def parse_non_negative_integer(_value), do: :error

  defp normalize_tag_into(tag, normalized_tags) do
    case normalize_tag(tag) do
      nil ->
        normalized_tags

      normalized_tag ->
        if normalized_tag in normalized_tags do
          normalized_tags
        else
          [normalized_tag | normalized_tags]
        end
    end
  end

  defp normalize_tag(tag) when is_binary(tag) do
    tag
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[\s\-_]+/u, "-")
    |> String.trim("-")
    |> normalize_tag_result()
  end

  defp normalize_tag(_tag), do: nil

  defp normalize_tag_result(""), do: nil
  defp normalize_tag_result(tag), do: tag
end
