defmodule LemmingsOs.Helpers do
  @moduledoc """
  Shared formatting and presence helpers used across the application.
  """

  use Gettext, backend: LemmingsOs.Gettext

  @doc """
  Returns true when the value should be treated as blank.
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
  Formats common UI values with a translated fallback for blank values.

  Supported options:
  - `:unavailable_label` - label shown when the value is blank
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
  """
  def format_datetime(datetime, opts \\ [])

  def format_datetime(nil, opts) do
    Keyword.get(opts, :nil_label, dgettext("world", ".label_not_imported"))
  end

  def format_datetime(%DateTime{} = datetime, opts) do
    format = Keyword.get(opts, :format, "%Y-%m-%d %H:%M:%S UTC")
    Calendar.strftime(datetime, format)
  end

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
