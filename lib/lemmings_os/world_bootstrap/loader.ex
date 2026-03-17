defmodule LemmingsOs.WorldBootstrap.Loader do
  @moduledoc """
  Loads bootstrap YAML from disk and normalizes bootstrap-file errors.

  YAML is treated as ingestion input only. This loader resolves a source path,
  parses YAML, and returns normalized bootstrap-layer errors instead of leaking
  parser-specific exceptions.
  """

  alias LemmingsOs.WorldBootstrap.PathResolver
  alias LemmingsOs.Gettext, as: AppGettext

  @type issue :: %{
          severity: String.t(),
          code: String.t(),
          summary: String.t(),
          detail: String.t(),
          source: String.t(),
          path: String.t(),
          action_hint: String.t()
        }

  @type load_success :: %{source: String.t(), path: String.t(), config: map()}
  @type load_error :: %{source: String.t(), path: String.t(), issues: [issue()]}

  @doc """
  Resolves and loads the bootstrap YAML file.

  ## Examples

      iex> path = LemmingsOs.WorldBootstrapTestHelpers.write_temp_file!("world: {}\\n")
      iex> {:ok, result} = LemmingsOs.WorldBootstrap.Loader.load(path: path, source: "direct")
      iex> result.path == path
      true
  """
  def load(input \\ [])

  @spec load(keyword()) :: {:ok, load_success()} | {:error, load_error()}
  def load(opts) when is_list(opts) do
    opts
    |> resolved_path()
    |> load()
  end

  @spec load(PathResolver.resolved_path()) :: {:ok, load_success()} | {:error, load_error()}
  def load(%{path: path, source: source} = resolved_path)
      when is_binary(path) and is_binary(source) do
    case YamlElixir.read_from_file(path) do
      {:ok, config} ->
        {:ok, %{source: source, path: path, config: config}}

      {:error, %YamlElixir.FileNotFoundError{} = error} ->
        {:error, normalized_error(resolved_path, file_not_found_issue(path, error))}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, normalized_error(resolved_path, parsing_issue(path, error))}

      {:error, error} ->
        {:error, normalized_error(resolved_path, malformed_yaml_issue(path, error))}
    end
  end

  defp resolved_path(opts) when is_list(opts),
    do: resolved_path(Keyword.get(opts, :path), Keyword.get(opts, :source), opts)

  defp resolved_path(path, source, _opts) when is_binary(path) and is_binary(source),
    do: %{path: path, source: source}

  defp resolved_path(_path, _source, opts), do: PathResolver.resolve(opts)

  defp normalized_error(%{path: path, source: source}, issue),
    do: %{source: source, path: path, issues: [issue]}

  defp file_not_found_issue(path, error) do
    normalized_issue(
      "bootstrap_file_not_found",
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_file_not_found_summary"),
      Exception.message(error),
      "bootstrap_file",
      path,
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_file_not_found_action_hint")
    )
  end

  defp parsing_issue(path, error) do
    normalized_issue(
      "bootstrap_yaml_parse_error",
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_yaml_parse_error_summary"),
      Exception.message(error),
      "bootstrap_file",
      path,
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_yaml_parse_error_action_hint")
    )
  end

  defp malformed_yaml_issue(path, error) do
    normalized_issue(
      "bootstrap_yaml_parse_error",
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_yaml_parse_error_summary"),
      Exception.message(error),
      "bootstrap_file",
      path,
      Gettext.dgettext(AppGettext, "errors", ".bootstrap_yaml_parse_error_action_hint")
    )
  end

  defp normalized_issue(code, summary, detail, source, path, action_hint) do
    %{
      severity: "error",
      code: code,
      summary: summary,
      detail: detail,
      source: source,
      path: path,
      action_hint: action_hint
    }
  end
end
