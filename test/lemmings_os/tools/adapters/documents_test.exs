defmodule LemmingsOs.Tools.Adapters.DocumentsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  @moduletag capture_log: true

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

  test "derives markdown output_path from source_path when omitted", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    source_path = Path.join(work_area, "notes/derived.md")
    output_path = Path.join(work_area, "notes/derived.html")
    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, "# Derived")

    assert {:ok, result} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "notes/derived.md"},
               runtime_meta
             )

    assert result.summary == "Converted notes/derived.md to notes/derived.html"
    assert result.result["output_path"] == "notes/derived.html"
    assert File.read!(output_path) =~ ~r/<h1>\s*Derived<\/h1>/
  end

  test "accepts markdown_path alias for markdown_to_html source", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    source_path = Path.join(work_area, "notes/alias.md")
    output_path = Path.join(work_area, "notes/alias.html")
    File.mkdir_p!(Path.dirname(source_path))
    File.write!(source_path, "# Alias")

    assert {:ok, result} =
             Documents.markdown_to_html(
               instance,
               %{"markdown_path" => "notes/alias.md"},
               runtime_meta
             )

    assert result.result["source_path"] == "notes/alias.md"
    assert result.result["output_path"] == "notes/alias.html"
    assert File.read!(output_path) =~ ~r/<h1>\s*Alias<\/h1>/
  end

  test "returns invalid_configuration when documents numeric config is invalid for markdown", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    Application.put_env(:lemmings_os, :documents, pdf_timeout_ms: "30s")
    File.write!(Path.join(work_area, "doc.md"), "# Title")

    assert {:error,
            %{
              code: "tool.documents.invalid_configuration",
              details: %{"field" => "pdf_timeout_ms"}
            }} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "doc.md", "output_path" => "doc.html"},
               runtime_meta
             )
  end

  test "returns invalid_configuration when documents numeric config is invalid for print", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    Application.put_env(:lemmings_os, :documents, max_pdf_bytes: "many")
    File.write!(Path.join(work_area, "doc.html"), "<html><body>Hello</body></html>")

    assert {:error,
            %{
              code: "tool.documents.invalid_configuration",
              details: %{"field" => "max_pdf_bytes"}
            }} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
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
               %{
                 "source_path" => "draft.md",
                 "output_path" => "draft.html",
                 "overwrite" => false
               },
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

  test "overwrites existing markdown output by default when overwrite is omitted", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "draft.md"), "# Default Overwrite")
    output_path = Path.join(work_area, "draft.html")
    File.write!(output_path, "existing")

    assert {:ok, _result} =
             Documents.markdown_to_html(
               instance,
               %{"source_path" => "draft.md", "output_path" => "draft.html"},
               runtime_meta
             )

    assert File.read!(output_path) =~ ~r/<h1>\s*Default Overwrite<\/h1>/
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
    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)

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

    log =
      capture_log([level: :info], fn ->
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
      end)

    assert log =~ "documents print to pdf started"
    assert log =~ "event=documents.print_to_pdf.started"
    assert log =~ "documents print to pdf completed"
    assert log =~ "event=documents.print_to_pdf.completed"
    refute log =~ "<h1>Hello</h1>"
    refute log =~ work_area
  end

  test "derives pdf output_path from source_path when omitted", %{
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

    File.mkdir_p!(Path.join(work_area, "notes"))

    File.write!(
      Path.join(work_area, "notes/source.html"),
      "<html><body>Derived PDF</body></html>"
    )

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "Derived PDF"
      Plug.Conn.resp(conn, 200, "%PDF derived")
    end)

    assert {:ok, result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "notes/source.html"},
               runtime_meta
             )

    assert result.summary == "Printed notes/source.html to notes/source.pdf"
    assert result.result["output_path"] == "notes/source.pdf"
    assert File.read!(Path.join(work_area, "notes/source.pdf")) == "%PDF derived"
  end

  test "prints .htm source to pdf", %{
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

    File.write!(Path.join(work_area, "doc.htm"), "<html><body><h1>Hello HTM</h1></body></html>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "filename=\"index.html\""
      assert body =~ "Hello HTM"
      Plug.Conn.resp(conn, 200, "%PDF htm")
    end)

    assert {:ok, result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.htm", "output_path" => "doc-htm.pdf"},
               runtime_meta
             )

    assert result.result["source_path"] == "doc.htm"
    assert File.read!(Path.join(work_area, "doc-htm.pdf")) == "%PDF htm"
  end

  test "prints markdown source to pdf with rendered markdown by default and raw text when print_raw_file is true",
       %{
         instance: instance,
         runtime_meta: runtime_meta,
         work_area: work_area
       } do
    bypass = Bypass.open()
    request_counter = :counters.new(1, [])

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

    File.write!(Path.join(work_area, "doc.md"), "# Heading\n\nParagraph")

    Bypass.expect(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      :counters.add(request_counter, 1, 1)
      attempt = :counters.get(request_counter, 1)
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case attempt do
        1 ->
          assert body =~ ~r/<h1>\s*Heading\s*<\/h1>/
          refute body =~ "<pre># Heading"

        2 ->
          assert body =~ "<pre># Heading"
      end

      Plug.Conn.resp(conn, 200, "%PDF markdown")
    end)

    assert {:ok, rendered_result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.md", "output_path" => "rendered.pdf"},
               runtime_meta
             )

    assert rendered_result.result["output_path"] == "rendered.pdf"

    assert {:ok, raw_result} =
             Documents.print_to_pdf(
               instance,
               %{
                 "source_path" => "doc.md",
                 "output_path" => "raw.pdf",
                 "print_raw_file" => true
               },
               runtime_meta
             )

    assert raw_result.result["output_path"] == "raw.pdf"
    assert File.read!(Path.join(work_area, "rendered.pdf")) == "%PDF markdown"
    assert File.read!(Path.join(work_area, "raw.pdf")) == "%PDF markdown"
  end

  test "prints txt and image source types through printable wrappers", %{
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

    File.write!(Path.join(work_area, "note.txt"), "Hello <b>team</b>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "<pre>Hello &lt;b&gt;team&lt;/b&gt;</pre>"
      Plug.Conn.resp(conn, 200, "%PDF txt")
    end)

    assert {:ok, txt_result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "note.txt", "output_path" => "note.pdf"},
               runtime_meta
             )

    assert txt_result.result["source_path"] == "note.txt"

    image_types = [
      {"png", "image/png"},
      {"jpg", "image/jpeg"},
      {"jpeg", "image/jpeg"},
      {"webp", "image/webp"}
    ]

    Enum.each(image_types, fn {ext, media_type} ->
      source_path = "image.#{ext}"
      output_path = "image-#{ext}.pdf"
      image_binary = "image-binary-#{ext}"
      File.write!(Path.join(work_area, source_path), image_binary)

      Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "data:#{media_type};base64,#{Base.encode64(image_binary)}"
        Plug.Conn.resp(conn, 200, "%PDF image #{ext}")
      end)

      assert {:ok, image_result} =
               Documents.print_to_pdf(
                 instance,
                 %{"source_path" => source_path, "output_path" => output_path},
                 runtime_meta
               )

      assert image_result.result["source_path"] == source_path
      assert File.read!(Path.join(work_area, output_path)) == "%PDF image #{ext}"
    end)
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

    log =
      capture_log(fn ->
        assert {:error,
                %{code: "tool.documents.pdf_conversion_failed", details: %{"status" => 500}}} =
                 Documents.print_to_pdf(
                   instance,
                   %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
                   runtime_meta
                 )
      end)

    assert log =~ "event=documents.print_to_pdf.backend_failed"
    assert log =~ "status=500"
    refute log =~ "boom"
    refute log =~ work_area
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
               %{
                 "source_path" => "doc.html",
                 "output_path" => "doc.pdf",
                 "overwrite" => false
               },
               runtime_meta
             )
  end

  test "overwrites existing pdf output by default when overwrite is omitted", %{
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

    File.write!(Path.join(work_area, "doc.html"), "<html>ok</html>")
    existing_pdf = Path.join(work_area, "doc.pdf")
    File.write!(existing_pdf, "existing")

    Bypass.expect_once(
      bypass,
      "POST",
      "/forms/chromium/convert/html",
      &Plug.Conn.resp(&1, 200, "%PDF replaced")
    )

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    assert File.read!(existing_pdf) == "%PDF replaced"
  end

  test "enforces source size limit for print_to_pdf before backend call", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()
    parent = self()

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 5,
      max_pdf_bytes: 1024 * 1024
    )

    File.write!(Path.join(work_area, "doc.html"), "123456")

    Bypass.stub(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      send(parent, :backend_called)
      Plug.Conn.resp(conn, 200, "%PDF should not happen")
    end)

    assert {:error,
            %{code: "tool.documents.file_too_large", details: %{"source_path" => "doc.html"}}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    refute_received :backend_called
  end

  test "returns unsupported_format for unsupported print source extension", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "doc.csv"), "a,b")

    assert {:error,
            %{code: "tool.documents.unsupported_format", details: %{"source_path" => "doc.csv"}}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.csv", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "explicit header/footer/style assets override conventional and fallback assets", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    {fallback_header_rel, fallback_header_abs} =
      write_priv_documents_file("documents_test_explicit_fallback_header.html", "FALLBACK_HEADER")

    {fallback_footer_rel, fallback_footer_abs} =
      write_priv_documents_file("documents_test_explicit_fallback_footer.html", "FALLBACK_FOOTER")

    {fallback_css_rel, fallback_css_abs} =
      write_priv_documents_file("documents_test_explicit_fallback.css", "FALLBACK_CSS")

    on_exit(fn ->
      File.rm(fallback_header_abs)
      File.rm(fallback_footer_abs)
      File.rm(fallback_css_abs)
    end)

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024,
      max_fallback_bytes: 1024 * 1024,
      default_header_path: fallback_header_rel,
      default_footer_path: fallback_footer_rel,
      default_css_path: fallback_css_rel
    )

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")
    File.write!(Path.join(work_area, "doc_pdf_header.html"), "CONVENTIONAL_HEADER")
    File.write!(Path.join(work_area, "doc_pdf_footer.html"), "CONVENTIONAL_FOOTER")
    File.write!(Path.join(work_area, "doc_pdf.css"), "CONVENTIONAL_CSS")
    File.write!(Path.join(work_area, "explicit_header.html"), "EXPLICIT_HEADER")
    File.write!(Path.join(work_area, "explicit_footer.html"), "EXPLICIT_FOOTER")
    File.write!(Path.join(work_area, "explicit_style.css"), "EXPLICIT_STYLE")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "filename=\"header.html\""
      assert body =~ "filename=\"footer.html\""
      assert body =~ "filename=\"style-1.css\""
      assert body =~ "EXPLICIT_HEADER"
      assert body =~ "EXPLICIT_FOOTER"
      assert body =~ "EXPLICIT_STYLE"
      refute body =~ "CONVENTIONAL_HEADER"
      refute body =~ "FALLBACK_HEADER"
      Plug.Conn.resp(conn, 200, "%PDF explicit")
    end)

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{
                 "source_path" => "doc.html",
                 "output_path" => "doc.pdf",
                 "header_path" => "explicit_header.html",
                 "footer_path" => "explicit_footer.html",
                 "style_paths" => ["explicit_style.css"]
               },
               runtime_meta
             )
  end

  test "conventional sibling assets are used when explicit assets are absent", %{
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

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")
    File.write!(Path.join(work_area, "doc_pdf_header.html"), "CONVENTIONAL_HEADER")
    File.write!(Path.join(work_area, "doc_pdf_footer.html"), "CONVENTIONAL_FOOTER")
    File.write!(Path.join(work_area, "doc_pdf.css"), "CONVENTIONAL_CSS")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "CONVENTIONAL_HEADER"
      assert body =~ "CONVENTIONAL_FOOTER"
      assert body =~ "CONVENTIONAL_CSS"
      Plug.Conn.resp(conn, 200, "%PDF conventional")
    end)

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "fallback assets are used when explicit and conventional assets are absent", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    {fallback_header_rel, fallback_header_abs} =
      write_priv_documents_file("documents_test_fallback_header.html", "FALLBACK_HEADER")

    {fallback_footer_rel, fallback_footer_abs} =
      write_priv_documents_file("documents_test_fallback_footer.html", "FALLBACK_FOOTER")

    {fallback_css_rel, fallback_css_abs} =
      write_priv_documents_file("documents_test_fallback.css", "FALLBACK_CSS")

    on_exit(fn ->
      File.rm(fallback_header_abs)
      File.rm(fallback_footer_abs)
      File.rm(fallback_css_abs)
    end)

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024,
      max_fallback_bytes: 1024 * 1024,
      default_header_path: fallback_header_rel,
      default_footer_path: fallback_footer_rel,
      default_css_path: fallback_css_rel
    )

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "FALLBACK_HEADER"
      assert body =~ "FALLBACK_FOOTER"
      assert body =~ "FALLBACK_CSS"
      Plug.Conn.resp(conn, 200, "%PDF fallback")
    end)

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "missing explicit assets fail with asset_not_found", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    File.write!(Path.join(work_area, "doc.html"), "<html><body>Hello</body></html>")

    assert {:error,
            %{
              code: "tool.documents.asset_not_found",
              details: %{"header_path" => "missing-header.html"}
            }} =
             Documents.print_to_pdf(
               instance,
               %{
                 "source_path" => "doc.html",
                 "output_path" => "doc.pdf",
                 "header_path" => "missing-header.html"
               },
               runtime_meta
             )
  end

  test "invalid or unsafe fallback assets are ignored safely", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    {_symlink_target_rel, symlink_target_abs} =
      write_priv_documents_file("documents_test_symlink_target.html", "TARGET")

    symlink_rel = Path.join("priv/documents", "documents_test_symlink_header.html")
    symlink_abs = Path.join(priv_documents_root(), "documents_test_symlink_header.html")
    File.rm(symlink_abs)
    assert :ok = File.ln_s(symlink_target_abs, symlink_abs)

    {oversized_css_rel, oversized_css_abs} =
      write_priv_documents_file("documents_test_oversized.css", String.duplicate("a", 50))

    on_exit(fn ->
      File.rm(symlink_abs)
      File.rm(symlink_target_abs)
      File.rm(oversized_css_abs)
    end)

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024,
      max_fallback_bytes: 10,
      default_header_path: symlink_rel,
      default_footer_path: "priv/documents/not_html.txt",
      default_css_path: oversized_css_rel
    )

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      refute body =~ "filename=\"header.html\""
      refute body =~ "filename=\"footer.html\""
      refute body =~ "filename=\"style-1.css\""
      Plug.Conn.resp(conn, 200, "%PDF no-fallback")
    end)

    _log =
      capture_log(fn ->
        assert {:ok, _result} =
                 Documents.print_to_pdf(
                   instance,
                   %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
                   runtime_meta
                 )
      end)
  end

  test "fallback asset under symlinked parent directory is rejected as outside_root", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()

    unique = System.unique_integer([:positive])
    outside_dir = Path.join(System.tmp_dir!(), "documents_fallback_outside_#{unique}")
    linked_dir_name = "documents_test_linked_dir_#{unique}"
    linked_dir_abs = Path.join(priv_documents_root(), linked_dir_name)
    linked_header_rel = Path.join("priv/documents", "#{linked_dir_name}/header.html")

    File.mkdir_p!(outside_dir)
    File.write!(Path.join(outside_dir, "header.html"), "OUTSIDE_HEADER")
    File.rm_rf(linked_dir_abs)
    assert :ok = File.ln_s(outside_dir, linked_dir_abs)

    on_exit(fn ->
      File.rm_rf(linked_dir_abs)
      File.rm_rf(outside_dir)
    end)

    Application.put_env(
      :lemmings_os,
      :documents,
      gotenberg_url: "http://localhost:#{bypass.port}",
      pdf_timeout_ms: 2_000,
      pdf_connect_timeout_ms: 2_000,
      pdf_retries: 0,
      max_source_bytes: 1024 * 1024,
      max_pdf_bytes: 1024 * 1024,
      max_fallback_bytes: 1024 * 1024,
      default_header_path: linked_header_rel
    )

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")

    Bypass.expect_once(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      refute body =~ "OUTSIDE_HEADER"
      refute body =~ "filename=\"header.html\""
      Plug.Conn.resp(conn, 200, "%PDF no-linked-fallback")
    end)

    assert {:ok, _result} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )
  end

  test "blocks remote asset references in source html before backend call", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()
    parent = self()

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

    File.write!(
      Path.join(work_area, "doc.html"),
      "<html><body><img src=\"https://example.com/logo.png\" /></body></html>"
    )

    Bypass.stub(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      send(parent, :backend_called)
      Plug.Conn.resp(conn, 200, "%PDF should not happen")
    end)

    assert {:error, %{code: "tool.documents.blocked_asset_reference"}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    refute_received :backend_called
  end

  test "blocks css @import references before backend call", %{
    instance: instance,
    runtime_meta: runtime_meta,
    work_area: work_area
  } do
    bypass = Bypass.open()
    parent = self()

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

    File.write!(Path.join(work_area, "doc.html"), "<html><head></head><body>Hello</body></html>")
    File.write!(Path.join(work_area, "doc_pdf.css"), "@import url('https://example.com/a.css');")

    Bypass.stub(bypass, "POST", "/forms/chromium/convert/html", fn conn ->
      send(parent, :backend_called)
      Plug.Conn.resp(conn, 200, "%PDF should not happen")
    end)

    assert {:error, %{code: "tool.documents.blocked_asset_reference"}} =
             Documents.print_to_pdf(
               instance,
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
               runtime_meta
             )

    refute_received :backend_called
  end

  defp write_priv_documents_file(filename, content) do
    path = Path.join(priv_documents_root(), filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    {Path.join("priv/documents", filename), path}
  end

  defp priv_documents_root do
    :lemmings_os
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("documents")
  end
end
