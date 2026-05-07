defmodule LemmingsOs.Knowledge.SourceFiles.ExtractionServiceTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Knowledge.SourceFile
  alias LemmingsOs.Knowledge.SourceFileStorageService
  alias LemmingsOs.Knowledge.SourceFiles.ExtractionService

  defmodule StubExecutor do
    def run(command, args, _timeout_ms) do
      mode = Application.get_env(:lemmings_os, :knowledge_extraction_test_mode)
      payload = List.first(args) || ""

      case stubbed_response(mode, command) do
        nil -> payload_response(payload)
        response -> response
      end
    end

    defp stubbed_response(:pdf_fallback_success, "markitdown"),
      do: {:ok, %{stdout: " ", exit_status: 0}}

    defp stubbed_response(:pdf_fallback_success, "pdftotext"),
      do: {:ok, %{stdout: "Fallback PDF text with enough chars for indexing", exit_status: 0}}

    defp stubbed_response(:pdf_needs_ocr, "markitdown"),
      do: {:ok, %{stdout: " ", exit_status: 0}}

    defp stubbed_response(:pdf_needs_ocr, "pdftotext"),
      do: {:ok, %{stdout: "tiny", exit_status: 0}}

    defp stubbed_response(:markitdown_long, "markitdown"),
      do: {:ok, %{stdout: String.duplicate("x", 100), exit_status: 0}}

    defp stubbed_response(:url_empty, "trafilatura"),
      do: {:ok, %{stdout: "   ", exit_status: 0}}

    defp stubbed_response(:url_timeout, "trafilatura"),
      do: {:error, :timeout}

    defp stubbed_response(_mode, _command), do: nil

    defp payload_response("timeout"), do: {:error, :timeout}
    defp payload_response("empty"), do: {:ok, %{stdout: "   ", exit_status: 0}}
    defp payload_response("bad_exit"), do: {:ok, %{stdout: "error", exit_status: 2}}

    defp payload_response(payload),
      do: {:ok, %{stdout: "content from #{payload}", exit_status: 0}}
  end

  setup do
    old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
    old_storage = Application.get_env(:lemmings_os, :knowledge_source_file_storage)

    Application.put_env(:lemmings_os, :knowledge_tools_runner,
      timeout_ms: 30_000,
      max_extracted_chars: 500_000,
      executor_module: StubExecutor,
      capabilities: %{
        trafilatura_extract_url: "trafilatura",
        markitdown_extract_file: "markitdown",
        pdftotext_extract_file: "pdftotext"
      }
    )

    root_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_extraction_service_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :knowledge_source_file_storage,
      backend: :local,
      root_path: root_path,
      max_file_size_bytes: 10 * 1024 * 1024
    )

    on_exit(fn ->
      Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner)
      Application.delete_env(:lemmings_os, :knowledge_extraction_test_mode)

      if old_storage do
        Application.put_env(:lemmings_os, :knowledge_source_file_storage, old_storage)
      else
        Application.delete_env(:lemmings_os, :knowledge_source_file_storage)
      end

      File.rm_rf(root_path)
    end)

    {:ok, root_path: root_path}
  end

  test "extract_url/1 uses trafilatura capability and returns extracted text" do
    assert {:ok, %{method: "trafilatura", text: text}} =
             ExtractionService.extract_url("https://example.com/post")

    assert text =~ "https://example.com/post"
  end

  test "extract_url/1 handles empty output safely" do
    Application.put_env(:lemmings_os, :knowledge_extraction_test_mode, :url_empty)
    assert {:error, :empty} = ExtractionService.extract_url("https://example.com/empty")
  end

  test "extract_url/1 handles timeout safely" do
    Application.put_env(:lemmings_os, :knowledge_extraction_test_mode, :url_timeout)
    assert {:error, :timeout} = ExtractionService.extract_url("https://example.com/timeout")
  end

  test "extract_url/1 rejects non-http(s) schemes" do
    assert {:error, :unsupported} = ExtractionService.extract_url("file:///etc/passwd")
  end

  test "extract_url/1 rejects hostless URLs" do
    assert {:error, :unsupported} = ExtractionService.extract_url("https:///no-host")
  end

  test "extract/1 uses pdftotext fallback for PDFs when markitdown is insufficient", %{
    root_path: root_path
  } do
    Application.put_env(:lemmings_os, :knowledge_extraction_test_mode, :pdf_fallback_success)
    source_file = build_source_file(root_path, "file.pdf", "application/pdf")

    assert {:ok, %{method: "pdftotext", text: text}} = ExtractionService.extract(source_file)
    assert text =~ "Fallback PDF text with enough chars"
  end

  test "extract/1 marks PDF as needs_ocr when markitdown and pdftotext are insufficient", %{
    root_path: root_path
  } do
    Application.put_env(:lemmings_os, :knowledge_extraction_test_mode, :pdf_needs_ocr)
    source_file = build_source_file(root_path, "scan.pdf", "application/pdf")

    assert {:error, :needs_ocr} = ExtractionService.extract(source_file)
  end

  test "extract/1 clamps extracted text to configured max_extracted_chars", %{
    root_path: root_path
  } do
    Application.put_env(:lemmings_os, :knowledge_extraction_test_mode, :markitdown_long)

    Application.put_env(:lemmings_os, :knowledge_tools_runner,
      timeout_ms: 30_000,
      max_extracted_chars: 12,
      executor_module: StubExecutor,
      capabilities: %{
        trafilatura_extract_url: "trafilatura",
        markitdown_extract_file: "markitdown",
        pdftotext_extract_file: "pdftotext"
      }
    )

    source_file = build_source_file(root_path, "file.md", "text/markdown")

    assert {:ok, %{method: "markitdown", text: text}} = ExtractionService.extract(source_file)
    assert text == String.duplicate("x", 12)
  end

  defp build_source_file(root_path, filename, content_type) do
    world_id = Ecto.UUID.generate()
    knowledge_item_id = Ecto.UUID.generate()
    source_path = Path.join(root_path, "source-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root_path)
    File.write!(source_path, "source")

    {:ok, stored} =
      SourceFileStorageService.put(world_id, knowledge_item_id, source_path, filename)

    %SourceFile{
      storage_ref: stored.storage_ref,
      content_type: content_type
    }
  end
end
