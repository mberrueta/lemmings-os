defmodule LemmingsOs.Tools.Adapters.DocumentsTest do
  use ExUnit.Case, async: false

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Documents
  alias LemmingsOs.Tools.WorkArea

  setup do
    old_work_areas_path = Application.get_env(:lemmings_os, :work_areas_path)
    old_documents_config = Application.get_env(:lemmings_os, :documents)

    work_areas_path =
      Path.join(
        System.tmp_dir!(),
        "lemmings_tools_documents_test_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:lemmings_os, :work_areas_path, work_areas_path)
    Application.put_env(:lemmings_os, :documents, max_source_bytes: 1024 * 1024)

    instance = %LemmingInstance{
      id: Ecto.UUID.generate(),
      world_id: Ecto.UUID.generate(),
      department_id: Ecto.UUID.generate(),
      lemming_id: Ecto.UUID.generate()
    }

    work_area_ref = Ecto.UUID.generate()
    :ok = WorkArea.ensure(work_area_ref)
    work_area = WorkArea.root_path(work_area_ref)
    runtime_meta = %{actor_instance_id: instance.id, work_area_ref: work_area_ref}

    on_exit(fn ->
      if old_work_areas_path do
        Application.put_env(:lemmings_os, :work_areas_path, old_work_areas_path)
      else
        Application.delete_env(:lemmings_os, :work_areas_path)
      end

      if old_documents_config do
        Application.put_env(:lemmings_os, :documents, old_documents_config)
      else
        Application.delete_env(:lemmings_os, :documents)
      end

      File.rm_rf(work_areas_path)
    end)

    {:ok, instance: instance, runtime_meta: runtime_meta, work_area: work_area}
  end

  test "converts markdown to html inside WorkArea", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    source_path = Path.join(work_area, "notes/spec.md")
    output_path = Path.join(work_area, "notes/spec.html")
    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, "# Title\n\nA paragraph.")

    assert {:ok, result} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "notes/spec.md", "output_path" => "notes/spec.html"},
               runtime_meta
             )

    assert result.summary == "Converted notes/spec.md to notes/spec.html"
    assert result.result["source_path"] == "notes/spec.md"
    assert result.result["output_path"] == "notes/spec.html"
    assert result.result["content_type"] == "text/html"
    assert is_integer(result.result["bytes"])
    assert result.preview =~ "<!doctype html>"
    assert result.preview =~ "<meta charset=\"utf-8\""
    refute result.preview =~ work_area

    html = File.read!(output_path)
    assert html =~ ~r/<h1>\s*Title<\/h1>/
    assert html =~ ~r/<p>\s*A paragraph\.<\/p>/
    assert byte_size(html) == result.result["bytes"]
  end

  test "rejects invalid args", %{instance: instance, runtime_meta: runtime_meta} do
    assert {:error, %{code: "tool.validation.invalid_args", details: %{field: "source_path"}}} =
             Documents.markdown_to_html(instance, %{"output_path" => "x.html"}, runtime_meta)

    assert {:error, %{code: "tool.validation.invalid_args", details: %{field: "overwrite"}}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "a.md", "output_path" => "a.html", "overwrite" => "yes"},
               runtime_meta
             )
  end

  test "rejects invalid workspace-relative paths", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    assert {:error, %{code: "tool.validation.invalid_path"}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "../secret.md", "output_path" => "x.html"},
               runtime_meta
             )
  end

  test "validates source and output extensions", %{instance: instance, runtime_meta: runtime_meta} do
    assert {:error,
            %{code: "tool.documents.unsupported_format", details: %{"source_path" => "a.txt"}}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "a.txt", "output_path" => "a.html"},
               runtime_meta
             )

    assert {:error,
            %{code: "tool.documents.unsupported_format", details: %{"output_path" => "a.pdf"}}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "a.md", "output_path" => "a.pdf"},
               runtime_meta
             )
  end

  test "returns source_not_found when source file is missing", %{
    instance: instance,
    runtime_meta: runtime_meta
  } do
    assert {:error,
            %{code: "tool.documents.source_not_found", details: %{"source_path" => "missing.md"}}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "missing.md", "output_path" => "out.html"},
               runtime_meta
             )
  end

  test "enforces source size limit", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    Application.put_env(:lemmings_os, :documents, max_source_bytes: 10)
    File.write!(Path.join(work_area, "large.md"), String.duplicate("a", 11))

    assert {:error, %{code: "tool.documents.file_too_large"}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "large.md", "output_path" => "large.html"},
               runtime_meta
             )
  end

  test "protects existing output when overwrite is false", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "draft.md"), "# Hello")
    output_path = Path.join(work_area, "draft.html")
    File.write!(output_path, "existing")

    assert {:error, %{code: "tool.documents.output_exists"}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "draft.md", "output_path" => "draft.html"},
               runtime_meta
             )

    assert File.read!(output_path) == "existing"
  end

  test "overwrites output when overwrite is true", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "draft.md"), "# New")
    output_path = Path.join(work_area, "draft.html")
    File.write!(output_path, "existing")

    assert {:ok, _result} =
             Documents.markdown_to_html(
               instance,
               %{
                 "source_path" => "draft.md",
                 "output_path" => "draft.html",
                 "overwrite" => true
               },
               runtime_meta
             )

    assert File.read!(output_path) =~ ~r/<h1>\s*New<\/h1>/
  end

  test "returns write_failed and does not leave output file on directory preparation failure", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "source.md"), "# Doc")
    File.write!(Path.join(work_area, "blocked"), "not a directory")

    output_relative = "blocked/output.html"
    output_absolute = Path.join(work_area, output_relative)

    assert {:error, %{code: "tool.documents.write_failed"}} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "source.md", "output_path" => output_relative},
               runtime_meta
             )

    refute File.exists?(output_absolute)
  end

  test "prints html source to pdf via gotenberg and writes atomically", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 1,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024
    )

    File.write!(Path.join(work_area, "doc.html"), "<html><body><h1>Hello</h1></body></html>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "filename=\"index.html\""
      Plug.Conn.resp(conn, 200, "%PDF-1.7 mock pdf")
    end)

    assert {:ok, result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    assert result.summary == "Printed doc.html to doc.pdf"
    assert result.result["content_type"] == "application/pdf"
    assert result.result["source_path"] == "doc.html"
    assert result.result["output_path"] == "doc.pdf"
    assert is_integer(result.result["bytes"])
    assert File.read!(Path.join(work_area, "doc.pdf")) == "%PDF-1.7 mock pdf"
  end

  test "returns pdf_conversion_failed on non-2xx response", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024
    )

    File.write!(Path.join(work_area, "doc.html"), "<html>bad</html>")

    Bypass.expect_once(
      bypass,
      "POST",
      "/forms/chromium/convert/html",
      &Plug.Conn.resp(&1, 500, "boom")
    )

    assert {:error, %{code: "tool.documents.pdf_conversion_failed", details: %{"status" => 500}}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "returns pdf_backend_unavailable on transport failure", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()
    port = bypass.port
    Bypass.down(bypass)

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{port}",
      pdf_timeout_ms: 10,
      pdf_connect_timeout_ms: 10,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024
    )

    File.write!(Path.join(work_area, "doc.html"), "<html>ok</html>")

    assert {:error, %{code: "tool.documents.pdf_backend_unavailable"}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "retries transient backend status according to config", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()
    counter = :counters.new(1, [])

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 1,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024
    )

    File.write!(Path.join(work_area, "doc.html"), "<html>ok</html>")

    Bypass.expect(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      :counters.add(counter, 1, 1)

      case :counters.get(counter, 1) do
        1 -> Plug.Conn.resp(conn, 503, "busy")
        _ -> Plug.Conn.resp(conn, 200, "%PDF ok")
      end
    end)

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "returns pdf_too_large and does not write output when response exceeds limit", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 5
    )

    File.write!(Path.join(work_area, "doc.html"), "<html>ok</html>")

    Bypass.expect_once(
      bypass,
      "POST",
      "/forms/chromium/convert/html",
      &Plug.Conn.resp(&1, 200, "123456")
    )

    assert {:error, %{code: "tool.documents.pdf_too_large"}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    refute File.exists?(Path.join(work_area, "doc.pdf"))
  end

  test "returns output_exists for pdf output conflict when overwrite false", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "doc.html"), "<html>ok</html>")
    File.write!(Path.join(work_area, "doc.pdf"), "existing")

    assert {:error, %{code: "tool.documents.output_exists"}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end
end
