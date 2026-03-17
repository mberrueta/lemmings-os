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
end
