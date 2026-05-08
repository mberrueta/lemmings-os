defmodule LemmingsOs.Knowledge.SourceFiles.ExtractionService do
  @moduledoc """
  Source-file extraction boundary for indexing flows.
  """

  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileStorageService
  alias LemmingsOs.Knowledge.SourceFiles.ToolsRunner

  @default_max_extracted_chars 500_000
  @pdf_min_chars 20

  @type extraction_success :: {:ok, %{text: String.t(), method: String.t()}}
  @type extraction_error ::
          {:error, :needs_ocr | :source_not_found | :timeout | :unsupported | :empty | :failed}

  @spec extract(SourceFile.t()) :: extraction_success() | extraction_error()
  def extract(%SourceFile{} = source_file) do
    SourceFileStorageService.with_temp_file(source_file.storage_ref, fn path ->
      run_extraction(source_file, path)
    end)
    |> normalize_storage_result()
  end

  @doc """
  Extracts bounded preview text from a trusted local managed file path.

  This is intended for read-time previews that reuse the same safe conversion
  tools as source-file indexing without creating chunks or embeddings.
  """
  @spec extract_path(String.t(), String.t()) :: extraction_success() | extraction_error()
  def extract_path(content_type, path) when is_binary(content_type) and is_binary(path) do
    run_extraction(%{content_type: content_type}, path)
  end

  def extract_path(_content_type, _path), do: {:error, :failed}

  @doc """
  Extracts URL/HTML source content through the registered Trafilatura capability.
  """
  @spec extract_url(String.t()) :: extraction_success() | extraction_error()
  def extract_url(url) when is_binary(url) do
    with {:ok, validated_url} <- validate_extract_url(url) do
      :trafilatura_extract_url
      |> ToolsRunner.run_capability([validated_url])
      |> normalize_url_extraction_result()
    end
  end

  def extract_url(_url), do: {:error, :failed}

  defp validate_extract_url(url) do
    trimmed = String.trim(url)
    uri = URI.parse(trimmed)

    cond do
      trimmed == "" -> {:error, :unsupported}
      uri.scheme not in ["http", "https"] -> {:error, :unsupported}
      not is_binary(uri.host) or uri.host == "" -> {:error, :unsupported}
      true -> {:ok, trimmed}
    end
  end

  defp normalize_url_extraction_result({:ok, %{exit_status: 0, stdout: text}})
       when is_binary(text) do
    text
    |> String.trim()
    |> url_text_result()
  end

  defp normalize_url_extraction_result({:ok, _result}), do: {:error, :failed}
  defp normalize_url_extraction_result({:error, :timeout}), do: {:error, :timeout}

  defp normalize_url_extraction_result({:error, :unsupported_capability}),
    do: {:error, :unsupported}

  defp normalize_url_extraction_result({:error, _reason}), do: {:error, :failed}

  defp url_text_result(""), do: {:error, :empty}
  defp url_text_result(text), do: {:ok, %{text: clamp_text(text), method: "trafilatura"}}

  defp normalize_storage_result({:ok, result}), do: result
  defp normalize_storage_result({:error, :not_found}), do: {:error, :source_not_found}
  defp normalize_storage_result({:error, _reason}), do: {:error, :failed}

  defp run_extraction(%{content_type: "application/pdf"}, path) do
    with {:ok, primary} <- run_markitdown(path),
         true <- sufficient_text?(primary) do
      {:ok, %{text: clamp_text(primary), method: "markitdown"}}
    else
      false -> run_pdf_fallback(path)
      {:error, :timeout} -> {:error, :timeout}
      {:error, :unsupported} -> run_pdf_fallback(path)
      {:error, :empty} -> run_pdf_fallback(path)
      {:error, _reason} -> run_pdf_fallback(path)
    end
  end

  defp run_extraction(_source_file, path) do
    with {:ok, primary} <- run_markitdown(path),
         true <- sufficient_text?(primary) do
      {:ok, %{text: clamp_text(primary), method: "markitdown"}}
    else
      false -> {:error, :empty}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_pdf_fallback(path) do
    case ToolsRunner.run_capability(:pdftotext_extract_file, [path]) do
      {:ok, %{exit_status: 0, stdout: text}} when is_binary(text) ->
        trimmed = String.trim(text)

        cond do
          byte_size(trimmed) == 0 -> {:error, :needs_ocr}
          byte_size(trimmed) < @pdf_min_chars -> {:error, :needs_ocr}
          true -> {:ok, %{text: clamp_text(trimmed), method: "pdftotext"}}
        end

      {:ok, _result} ->
        {:error, :failed}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, :unsupported_capability} ->
        {:error, :unsupported}

      {:error, _reason} ->
        {:error, :failed}
    end
  end

  defp run_markitdown(path) do
    case ToolsRunner.run_capability(:markitdown_extract_file, [path]) do
      {:ok, %{exit_status: 0, stdout: text}} when is_binary(text) ->
        trimmed = String.trim(text)
        if trimmed == "", do: {:error, :empty}, else: {:ok, trimmed}

      {:ok, _result} ->
        {:error, :failed}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, :unsupported_capability} ->
        {:error, :unsupported}

      {:error, _reason} ->
        {:error, :failed}
    end
  end

  defp sufficient_text?(text) when is_binary(text),
    do: byte_size(String.trim(text)) >= @pdf_min_chars

  defp clamp_text(text) do
    max_chars =
      Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      |> Keyword.get(:max_extracted_chars, @default_max_extracted_chars)

    case max_chars do
      value when is_integer(value) and value > 0 -> String.slice(text, 0, value)
      _other -> String.slice(text, 0, @default_max_extracted_chars)
    end
  end
end
