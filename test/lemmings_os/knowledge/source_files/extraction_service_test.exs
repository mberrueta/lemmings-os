defmodule LemmingsOs.Knowledge.SourceFiles.ExtractionServiceTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.Knowledge.SourceFiles.ExtractionService

  defmodule StubExecutor do
    def run(_command, args, _timeout_ms) do
      payload = List.first(args) || ""

      cond do
        payload == "timeout" -> {:error, :timeout}
        payload == "empty" -> {:ok, %{stdout: "   ", exit_status: 0}}
        payload == "bad_exit" -> {:ok, %{stdout: "error", exit_status: 2}}
        true -> {:ok, %{stdout: "content from #{payload}", exit_status: 0}}
      end
    end
  end

  setup do
    old_runner = Application.get_env(:lemmings_os, :knowledge_tools_runner, [])

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

    on_exit(fn -> Application.put_env(:lemmings_os, :knowledge_tools_runner, old_runner) end)
    :ok
  end

  test "extract_url/1 uses trafilatura capability and returns extracted text" do
    assert {:ok, %{method: "trafilatura", text: text}} =
             ExtractionService.extract_url("https://example.com/post")

    assert text =~ "https://example.com/post"
  end

  test "extract_url/1 handles empty output safely" do
    assert {:error, :empty} = ExtractionService.extract_url("empty")
  end

  test "extract_url/1 handles timeout safely" do
    assert {:error, :timeout} = ExtractionService.extract_url("timeout")
  end
end
