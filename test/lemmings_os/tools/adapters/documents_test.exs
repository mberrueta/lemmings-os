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
               %{"source_path" => "doc.html", "output_path" => "doc.pdf"},
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

    symlink_rel = "priv/documents/documents_test_symlink_header.html"
    symlink_abs = Path.expand(symlink_rel)
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
    path = Path.expand(Path.join("priv/documents", filename))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    {Path.join("priv/documents", filename), path}
  end
end
