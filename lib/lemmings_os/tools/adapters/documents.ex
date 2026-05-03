defmodule LemmingsOs.Tools.Adapters.Documents do
  @moduledoc """
  Documents adapters for Tool Runtime.
  """

  require Logger

  alias LemmingsOs.Helpers
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.WorkArea

  @default_max_source_bytes 10 * 1024 * 1024
  @default_max_pdf_bytes 50 * 1024 * 1024
  @default_max_fallback_bytes 1 * 1024 * 1024
  @default_pdf_timeout_ms 30_000
  @default_pdf_connect_timeout_ms 5_000
  @default_pdf_retries 1
  @default_gotenberg_url "http://gotenberg:3000"
  @retryable_statuses [429, 502, 503, 504]

  @type runtime_meta :: %{
          optional(:actor_instance_id) => String.t(),
          optional(:work_area_ref) => String.t(),
          optional(:world_id) => String.t(),
          optional(:city_id) => String.t(),
          optional(:department_id) => String.t()
        }

  @type adapter_success :: {:ok, %{summary: String.t(), preview: String.t() | nil, result: map()}}
  @type adapter_error :: {:error, %{code: String.t(), message: String.t(), details: map()}}

  @doc """
  Converts a markdown file from the WorkArea into a printable HTML document.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{id: "instance-1"}
      iex> {:error, error} =
      ...>   LemmingsOs.Tools.Adapters.Documents.markdown_to_html(
      ...>     instance,
      ...>     %{"source_path" => "", "output_path" => "notes/a.html"},
      ...>     %{}
      ...>   )
      iex> error.code
      "tool.validation.invalid_args"
  """
  @spec markdown_to_html(LemmingInstance.t(), map(), runtime_meta()) ::
          adapter_success() | adapter_error()
  def markdown_to_html(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with :ok <- validate_documents_config(),
         {:ok, {source_path, output_path, overwrite?}} <- validate_markdown_to_html_args(args),
         {:ok, source} <- resolve_work_area_path(instance, source_path, runtime_meta),
         {:ok, output} <- resolve_work_area_path(instance, output_path, runtime_meta),
         :ok <- validate_source_extension(source.relative_path),
         :ok <- validate_output_extension(output.relative_path),
         :ok <- ensure_source_exists(source.relative_path, source.absolute_path),
         :ok <- ensure_output_writable(output.relative_path, output.absolute_path, overwrite?),
         {:ok, markdown} <- read_markdown_source(source.relative_path, source.absolute_path),
         :ok <- validate_source_size(source.relative_path, markdown),
         {:ok, body_html} <- render_markdown(markdown),
         html_document <- wrap_html_document(body_html),
         {:ok, bytes} <-
           write_html_atomic(output.relative_path, output.absolute_path, html_document) do
      {:ok,
       %{
         summary: "Converted #{source.relative_path} to #{output.relative_path}",
         preview: String.slice(html_document, 0, 280),
         result: %{
           "source_path" => source.relative_path,
           "output_path" => output.relative_path,
           "content_type" => "text/html",
           "bytes" => bytes
         }
       }}
    end
  end

  @doc """
  Prints a supported WorkArea source file into a PDF via Gotenberg.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{id: "instance-1"}
      iex> {:error, error} =
      ...>   LemmingsOs.Tools.Adapters.Documents.print_to_pdf(
      ...>     instance,
      ...>     %{"source_path" => "", "output_path" => "notes/a.pdf"},
      ...>     %{}
      ...>   )
      iex> error.code
      "tool.validation.invalid_args"
  """
  @spec print_to_pdf(LemmingInstance.t(), map(), runtime_meta()) ::
          adapter_success() | adapter_error()
  def print_to_pdf(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    started_at = System.monotonic_time()

    result =
      with :ok <- validate_documents_config(),
           {:ok, print_args} <- validate_print_to_pdf_args(args),
           {:ok, source} <-
             resolve_work_area_path(instance, print_args.source_path, runtime_meta),
           {:ok, output} <-
             resolve_work_area_path(instance, print_args.output_path, runtime_meta),
           :ok <- validate_source_pdf_extension(source.relative_path),
           :ok <- validate_pdf_output_extension(output.relative_path),
           :ok <- ensure_source_exists(source.relative_path, source.absolute_path),
           :ok <-
             ensure_output_writable(
               output.relative_path,
               output.absolute_path,
               print_args.overwrite
             ),
           {:ok, source_content} <-
             read_source_binary(source.relative_path, source.absolute_path),
           :ok <- validate_source_size(source.relative_path, source_content),
           :ok <-
             log_print_started(instance, runtime_meta, source.relative_path, output.relative_path),
           {:ok, html_body} <-
             source_to_html(source.relative_path, source_content, print_args.print_raw_file),
           {:ok, resolved_assets} <-
             resolve_print_assets(instance, source, print_args, runtime_meta),
           :ok <- enforce_asset_policy(source.relative_path, html_body, resolved_assets),
           {:ok, pdf_binary} <-
             convert_html_to_pdf(
               html_body,
               print_args,
               resolved_assets,
               print_log_metadata(instance, runtime_meta,
                 source_path: source.relative_path,
                 output_path: output.relative_path
               )
             ),
           {:ok, bytes} <-
             write_pdf_atomic(output.relative_path, output.absolute_path, pdf_binary) do
        {:ok,
         %{
           summary: "Printed #{source.relative_path} to #{output.relative_path}",
           preview: nil,
           result: %{
             "source_path" => source.relative_path,
             "output_path" => output.relative_path,
             "content_type" => "application/pdf",
             "bytes" => bytes
           }
         }}
      end

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    case result do
      {:ok, output} ->
        Logger.info(
          "documents print to pdf completed",
          [event: "documents.print_to_pdf.completed"] ++
            print_log_metadata(instance, runtime_meta,
              source_path: nil,
              output_path: output.result["output_path"]
            ) ++
            [
              duration_ms: duration_ms,
              size_bytes: output.result["bytes"],
              reason: "ok",
              status: "ok"
            ]
        )

      {:error, %{code: code} = error} ->
        log_print_failure(
          error,
          code,
          duration_ms,
          print_log_metadata(instance, runtime_meta,
            source_path: failure_source_path(error),
            output_path: failure_output_path(error)
          )
        )
    end

    result
  end

  defp validate_markdown_to_html_args(args) do
    with {:ok, source_path} <- fetch_markdown_source_path(args),
         {:ok, output_path} <- fetch_optional_output_path(args, source_path, ".html"),
         {:ok, overwrite?} <- fetch_optional_overwrite(args) do
      {:ok, {source_path, output_path, overwrite?}}
    end
  end

  defp fetch_markdown_source_path(args) do
    case fetch_arg(args, "source_path", :missing) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      :missing ->
        fetch_markdown_source_path_alias(args)

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "source_path"}
         }}
    end
  end

  defp fetch_markdown_source_path_alias(args) do
    case fetch_arg(args, "markdown_path", :missing) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "source_path"}
         }}
    end
  end

  defp fetch_required_path(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: key}
         }}
    end
  end

  defp fetch_optional_overwrite(args) do
    case Map.get(args, "overwrite", Map.get(args, :overwrite, true)) do
      value when value in [true, false] ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "overwrite"}
         }}
    end
  end

  defp resolve_work_area_path(%LemmingInstance{} = instance, relative_path, runtime_meta) do
    case work_area_ref(instance, runtime_meta) do
      work_area_ref when is_binary(work_area_ref) and work_area_ref != "" ->
        relative_path
        |> then(&WorkArea.resolve(work_area_ref, &1))
        |> normalize_resolve_result(relative_path)

      _other ->
        {:error,
         %{
           code: "tool.fs.invalid_instance_scope",
           message: "Instance scope is incomplete",
           details: %{}
         }}
    end
  end

  defp work_area_ref(_instance, %{work_area_ref: work_area_ref}) when is_binary(work_area_ref),
    do: work_area_ref

  defp work_area_ref(_instance, %{"work_area_ref" => work_area_ref})
       when is_binary(work_area_ref),
       do: work_area_ref

  defp work_area_ref(%LemmingInstance{id: instance_id}, _runtime_meta)
       when is_binary(instance_id),
       do: instance_id

  defp work_area_ref(_instance, _runtime_meta), do: nil

  defp normalize_resolve_result({:ok, resolved}, _relative_path), do: {:ok, resolved}

  defp normalize_resolve_result({:error, :work_area_unavailable}, relative_path) do
    {:error,
     %{
       code: "tool.fs.work_area_unavailable",
       message: "WorkArea is unavailable",
       details: %{path: relative_path}
     }}
  end

  defp normalize_resolve_result({:error, _reason}, relative_path) do
    {:error,
     %{
       code: "tool.validation.invalid_path",
       message: "Invalid workspace-relative path",
       details: %{path: relative_path}
     }}
  end

  defp validate_source_extension(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> validate_source_extension_from_ext(path)
  end

  defp validate_source_extension_from_ext(".md", _path), do: :ok

  defp validate_source_extension_from_ext(_ext, path) do
    {:error,
     %{
       code: "tool.documents.unsupported_format",
       message: "Unsupported source format",
       details: %{"source_path" => path}
     }}
  end

  defp validate_output_extension(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> validate_output_extension_from_ext(path)
  end

  defp validate_output_extension_from_ext(ext, _path) when ext in [".html", ".htm"], do: :ok

  defp validate_output_extension_from_ext(_ext, path) do
    {:error,
     %{
       code: "tool.documents.unsupported_format",
       message: "Unsupported output format",
       details: %{"output_path" => path}
     }}
  end

  defp ensure_source_exists(relative_path, absolute_path) do
    case File.stat(absolute_path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok

      {:ok, _} ->
        source_not_found(relative_path)

      {:error, :enoent} ->
        source_not_found(relative_path)

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.source_not_found",
           message: "Source file not found",
           details: %{"source_path" => relative_path, "reason" => inspect(reason)}
         }}
    end
  end

  defp source_not_found(relative_path) do
    {:error,
     %{
       code: "tool.documents.source_not_found",
       message: "Source file not found",
       details: %{"source_path" => relative_path}
     }}
  end

  defp ensure_output_writable(_relative_path, absolute_path, true) do
    ensure_output_parent_directory(absolute_path)
  end

  defp ensure_output_writable(relative_path, absolute_path, false) do
    case File.lstat(absolute_path) do
      {:ok, _stat} ->
        {:error,
         %{
           code: "tool.documents.output_exists",
           message: "Output file already exists",
           details: %{"output_path" => relative_path}
         }}

      {:error, :enoent} ->
        ensure_output_parent_directory(absolute_path)

      {:error, _reason} ->
        ensure_output_parent_directory(absolute_path)
    end
  end

  defp ensure_output_parent_directory(absolute_path) do
    absolute_path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.write_failed",
           message: "Could not prepare output directory",
           details: %{"reason" => inspect(reason)}
         }}
    end
  end

  defp read_markdown_source(relative_path, absolute_path) do
    case File.read(absolute_path) do
      {:ok, content} when is_binary(content) ->
        {:ok, content}

      {:error, :enoent} ->
        source_not_found(relative_path)

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.source_not_found",
           message: "Source file not found",
           details: %{"source_path" => relative_path, "reason" => inspect(reason)}
         }}
    end
  end

  defp validate_source_size(relative_path, markdown) do
    max_source_bytes = max_source_bytes()
    validate_source_size(relative_path, markdown, max_source_bytes)
  end

  defp validate_source_size(_relative_path, markdown, max_source_bytes)
       when byte_size(markdown) <= max_source_bytes,
       do: :ok

  defp validate_source_size(relative_path, _markdown, max_source_bytes) do
    {:error,
     %{
       code: "tool.documents.file_too_large",
       message: "Source file exceeds configured size limit",
       details: %{"source_path" => relative_path, "max_source_bytes" => max_source_bytes}
     }}
  end

  defp max_source_bytes do
    integer_config_value(:max_source_bytes, @default_max_source_bytes)
  end

  defp render_markdown(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html_document, _messages} when is_binary(html_document) ->
        {:ok, html_document}

      {:error, html_document, _messages} when is_binary(html_document) ->
        {:ok, html_document}
    end
  rescue
    _ ->
      markdown_render_failed()
  end

  defp markdown_render_failed do
    {:error,
     %{
       code: "tool.documents.write_failed",
       message: "Could not render markdown",
       details: %{}
     }}
  end

  defp wrap_html_document(body_html) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Document</title>
        <style>
          :root { color-scheme: light; }
          body {
            font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            margin: 2rem;
            color: #111827;
          }
          pre, code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
          }
          img {
            max-width: 100%;
            height: auto;
          }
          table {
            border-collapse: collapse;
            width: 100%;
          }
          th, td {
            border: 1px solid #d1d5db;
            padding: 0.4rem 0.5rem;
            text-align: left;
          }
        </style>
      </head>
      <body>
    #{body_html}
      </body>
    </html>
    """
  end

  defp write_html_atomic(relative_path, destination_path, html_document) do
    target_dir = Path.dirname(destination_path)

    temp_path =
      Path.join(target_dir, ".documents-markdown-#{System.unique_integer([:positive])}.tmp")

    with :ok <- write_temp_html(temp_path, html_document),
         :ok <- rename_into_place(temp_path, destination_path, relative_path) do
      {:ok, byte_size(html_document)}
    else
      {:error, error} ->
        _ = File.rm(temp_path)
        {:error, error}
    end
  end

  defp write_temp_html(temp_path, html_document) do
    case File.write(temp_path, html_document, [:binary]) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.write_failed",
           message: "Could not write output file",
           details: %{"reason" => inspect(reason)}
         }}
    end
  end

  defp rename_into_place(temp_path, destination_path, relative_path) do
    case File.rename(temp_path, destination_path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.write_failed",
           message: "Could not finalize output file",
           details: %{"output_path" => relative_path, "reason" => inspect(reason)}
         }}
    end
  end

  defp validate_print_to_pdf_args(args) do
    with {:ok, source_path} <- fetch_required_path(args, "source_path"),
         {:ok, output_path} <- fetch_optional_output_path(args, source_path, ".pdf"),
         {:ok, overwrite} <- fetch_boolean_arg(args, "overwrite", true),
         {:ok, print_raw_file} <- fetch_boolean_arg(args, "print_raw_file", false),
         {:ok, landscape} <- fetch_boolean_arg(args, "landscape", false),
         {:ok, paper_size} <- fetch_optional_string_arg(args, "paper_size"),
         {:ok, margin_top} <- fetch_optional_string_arg(args, "margin_top"),
         {:ok, margin_bottom} <- fetch_optional_string_arg(args, "margin_bottom"),
         {:ok, margin_left} <- fetch_optional_string_arg(args, "margin_left"),
         {:ok, margin_right} <- fetch_optional_string_arg(args, "margin_right"),
         {:ok, header_path} <- fetch_optional_string_arg(args, "header_path"),
         {:ok, footer_path} <- fetch_optional_string_arg(args, "footer_path"),
         {:ok, style_paths} <- fetch_optional_style_paths(args) do
      {:ok,
       %{
         source_path: source_path,
         output_path: output_path,
         overwrite: overwrite,
         print_raw_file: print_raw_file,
         landscape: landscape,
         paper_size: paper_size,
         margin_top: margin_top,
         margin_bottom: margin_bottom,
         margin_left: margin_left,
         margin_right: margin_right,
         header_path: header_path,
         footer_path: footer_path,
         style_paths: style_paths
       }}
    end
  end

  defp fetch_optional_output_path(args, source_path, extension)
       when is_map(args) and is_binary(source_path) and is_binary(extension) do
    case fetch_arg(args, "output_path", :missing) do
      :missing ->
        {:ok, replace_extension(source_path, extension)}

      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "output_path"}
         }}
    end
  end

  defp fetch_boolean_arg(args, key, default) do
    case fetch_arg(args, key, default) do
      value when value in [true, false] ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: key}
         }}
    end
  end

  defp fetch_optional_string_arg(args, key) do
    case fetch_arg(args, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) and value != "" ->
        {:ok, value}

      _ ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: key}
         }}
    end
  end

  defp fetch_optional_style_paths(args) do
    args
    |> fetch_arg("style_paths")
    |> normalize_style_paths_arg()
  end

  defp normalize_style_paths_arg(nil), do: {:ok, nil}

  defp normalize_style_paths_arg(paths) when is_list(paths) do
    if Enum.all?(paths, &(is_binary(&1) and &1 != "")) do
      {:ok, paths}
    else
      invalid_style_paths_error()
    end
  end

  defp normalize_style_paths_arg(_value), do: invalid_style_paths_error()

  defp fetch_arg(args, key, default \\ nil) do
    case Map.fetch(args, key) do
      {:ok, value} ->
        value

      :error ->
        case arg_atom_key(key) do
          nil -> default
          atom_key -> Map.get(args, atom_key, default)
        end
    end
  end

  defp arg_atom_key("source_path"), do: :source_path
  defp arg_atom_key("markdown_path"), do: :markdown_path
  defp arg_atom_key("output_path"), do: :output_path
  defp arg_atom_key("overwrite"), do: :overwrite
  defp arg_atom_key("print_raw_file"), do: :print_raw_file
  defp arg_atom_key("landscape"), do: :landscape
  defp arg_atom_key("paper_size"), do: :paper_size
  defp arg_atom_key("margin_top"), do: :margin_top
  defp arg_atom_key("margin_bottom"), do: :margin_bottom
  defp arg_atom_key("margin_left"), do: :margin_left
  defp arg_atom_key("margin_right"), do: :margin_right
  defp arg_atom_key("header_path"), do: :header_path
  defp arg_atom_key("footer_path"), do: :footer_path
  defp arg_atom_key("style_paths"), do: :style_paths
  defp arg_atom_key(_key), do: nil

  defp invalid_style_paths_error do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{field: "style_paths"}
     }}
  end

  defp validate_source_pdf_extension(path) do
    if String.downcase(Path.extname(path)) in [
         ".html",
         ".htm",
         ".md",
         ".txt",
         ".png",
         ".jpg",
         ".jpeg",
         ".webp"
       ] do
      :ok
    else
      unsupported_source_format(path)
    end
  end

  defp validate_pdf_output_extension(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> validate_pdf_output_extension_from_ext(path)
  end

  defp validate_pdf_output_extension_from_ext(".pdf", _path), do: :ok

  defp validate_pdf_output_extension_from_ext(_ext, path) do
    {:error,
     %{
       code: "tool.documents.unsupported_format",
       message: "Unsupported output format",
       details: %{"output_path" => path}
     }}
  end

  defp unsupported_source_format(path) do
    {:error,
     %{
       code: "tool.documents.unsupported_format",
       message: "Unsupported source format",
       details: %{"source_path" => path}
     }}
  end

  defp read_source_binary(relative_path, absolute_path) do
    case File.read(absolute_path) do
      {:ok, content} when is_binary(content) ->
        {:ok, content}

      {:error, :enoent} ->
        source_not_found(relative_path)

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.source_not_found",
           message: "Source file not found",
           details: %{"source_path" => relative_path, "reason" => inspect(reason)}
         }}
    end
  end

  defp source_to_html(relative_path, content, print_raw_file) do
    case String.downcase(Path.extname(relative_path)) do
      ext when ext in [".html", ".htm"] ->
        {:ok, content}

      ".md" ->
        markdown_to_pdf_html(content, print_raw_file)

      ".txt" ->
        {:ok, wrap_text_document(content)}

      ext when ext in [".png", ".jpg", ".jpeg", ".webp"] ->
        {:ok, wrap_image_document(content, ext)}

      _ ->
        unsupported_source_format(relative_path)
    end
  end

  defp markdown_to_pdf_html(markdown, true), do: {:ok, wrap_text_document(markdown)}

  defp markdown_to_pdf_html(markdown, false) do
    with {:ok, html} <- render_markdown(markdown) do
      {:ok, wrap_html_document(html)}
    end
  end

  defp wrap_text_document(content) do
    escaped =
      content
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Document</title>
        <style>
          body {
            font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
            margin: 2rem;
            color: #111827;
          }
          pre {
            white-space: pre-wrap;
            word-break: break-word;
          }
        </style>
      </head>
      <body><pre>#{escaped}</pre></body>
    </html>
    """
  end

  defp wrap_image_document(binary, ext) do
    media_type =
      case ext do
        ".png" -> "image/png"
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".webp" -> "image/webp"
      end

    encoded = Base.encode64(binary)

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Document</title>
        <style>
          body { margin: 1rem; }
          img { max-width: 100%; height: auto; display: block; }
        </style>
      </head>
      <body><img src="data:#{media_type};base64,#{encoded}" alt="document image" /></body>
    </html>
    """
  end

  defp convert_html_to_pdf(html_body, print_args, resolved_assets, log_metadata) do
    html_with_styles =
      inject_css_into_html(html_body, Enum.map(resolved_assets.styles, & &1.content))

    form_fields =
      [
        {"files", {html_with_styles, filename: "index.html", content_type: "text/html"}}
      ] ++
        maybe_header_field(resolved_assets.header) ++
        maybe_footer_field(resolved_assets.footer) ++
        style_file_fields(resolved_assets.styles) ++
        print_options_fields(print_args)

    request_fun = fn ->
      req =
        Req.new(
          base_url: gotenberg_url(),
          receive_timeout: pdf_timeout_ms(),
          connect_options: [timeout: pdf_connect_timeout_ms()],
          retry: false,
          redirect: false,
          http_errors: :return
        )

      Req.post(req, url: "/forms/chromium/convert/html", form_multipart: form_fields)
    end

    request_pdf_with_retry(request_fun, pdf_retries(), log_metadata)
  end

  defp maybe_header_field(nil), do: []

  defp maybe_header_field(%{content: content}) do
    [{"files", {content, filename: "header.html", content_type: "text/html"}}]
  end

  defp maybe_footer_field(nil), do: []

  defp maybe_footer_field(%{content: content}) do
    [{"files", {content, filename: "footer.html", content_type: "text/html"}}]
  end

  defp style_file_fields(styles) when is_list(styles) do
    styles
    |> Enum.with_index(1)
    |> Enum.map(fn {%{content: content}, index} ->
      {"files", {content, filename: "style-#{index}.css", content_type: "text/css"}}
    end)
  end

  defp inject_css_into_html(html_body, []), do: html_body

  defp inject_css_into_html(html_body, css_contents) do
    style_block =
      css_contents
      |> Enum.map_join("\n", & &1)
      |> then(fn css -> "<style>\n#{css}\n</style>" end)

    inject_css_into_html_body(html_body, style_block)
  end

  defp inject_css_into_html_body(html_body, style_block) when is_binary(html_body) do
    case String.contains?(html_body, "</head>") do
      true ->
        String.replace(html_body, "</head>", "#{style_block}\n</head>")

      false ->
        """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            #{style_block}
          </head>
          <body>
        #{html_body}
          </body>
        </html>
        """
    end
  end

  defp resolve_print_assets(instance, source, print_args, runtime_meta) do
    with {:ok, header} <- resolve_header_asset(instance, source, print_args, runtime_meta),
         {:ok, footer} <- resolve_footer_asset(instance, source, print_args, runtime_meta),
         {:ok, styles} <- resolve_style_assets(instance, source, print_args, runtime_meta) do
      {:ok, %{header: header, footer: footer, styles: styles}}
    end
  end

  defp resolve_header_asset(instance, source, print_args, runtime_meta) do
    resolve_optional_html_asset(
      instance,
      source,
      runtime_meta,
      print_args.header_path,
      conventional_header_path(source.relative_path),
      :default_header_path,
      "header_path"
    )
  end

  defp resolve_footer_asset(instance, source, print_args, runtime_meta) do
    resolve_optional_html_asset(
      instance,
      source,
      runtime_meta,
      print_args.footer_path,
      conventional_footer_path(source.relative_path),
      :default_footer_path,
      "footer_path"
    )
  end

  defp resolve_optional_html_asset(
         instance,
         source,
         runtime_meta,
         explicit_path,
         conventional_path,
         fallback_key,
         field_name
       ) do
    with {:ok, explicit} <-
           resolve_explicit_asset(
             instance,
             runtime_meta,
             explicit_path,
             field_name,
             &html_extension?/1
           ),
         {:ok, conventional} <-
           resolve_conventional_asset(
             instance,
             runtime_meta,
             conventional_path,
             &html_extension?/1
           ),
         {:ok, fallback} <- resolve_fallback_asset(fallback_key, &html_extension?/1) do
      asset = explicit || conventional || fallback
      {:ok, maybe_require_full_html_document(asset, source.relative_path)}
    end
  end

  defp maybe_require_full_html_document(nil, _source_path), do: nil

  defp maybe_require_full_html_document(%{content: content} = asset, _source_path)
       when is_binary(content) do
    case String.contains?(String.downcase(content), "<html") do
      true -> asset
      false -> %{asset | content: wrap_html_document(content)}
    end
  end

  defp resolve_style_assets(instance, source, print_args, runtime_meta) do
    with {:ok, explicit_styles} <-
           resolve_explicit_style_assets(instance, runtime_meta, print_args.style_paths),
         {:ok, conventional_style} <-
           resolve_conventional_style_asset(instance, runtime_meta, source.relative_path),
         {:ok, fallback_style} <- resolve_fallback_asset(:default_css_path, &css_extension?/1) do
      styles =
        cond do
          explicit_styles != [] -> explicit_styles
          conventional_style != nil -> [conventional_style]
          fallback_style != nil -> [fallback_style]
          true -> []
        end

      {:ok, styles}
    end
  end

  defp resolve_explicit_style_assets(_instance, _runtime_meta, nil), do: {:ok, []}

  defp resolve_explicit_style_assets(instance, runtime_meta, style_paths)
       when is_list(style_paths) do
    style_paths
    |> Enum.reduce_while({:ok, []}, fn style_path, {:ok, acc} ->
      case resolve_explicit_asset(
             instance,
             runtime_meta,
             style_path,
             "style_paths",
             &css_extension?/1
           ) do
        {:ok, nil} ->
          {:halt,
           {:error,
            %{
              code: "tool.documents.asset_not_found",
              message: "Style asset not found",
              details: %{"style_path" => style_path}
            }}}

        {:ok, asset} ->
          {:cont, {:ok, [asset | acc]}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, styles} -> {:ok, Enum.reverse(styles)}
      error -> error
    end
  end

  defp resolve_conventional_style_asset(instance, runtime_meta, source_path) do
    resolve_conventional_asset(
      instance,
      runtime_meta,
      conventional_css_path(source_path),
      &css_extension?/1
    )
  end

  defp resolve_explicit_asset(_instance, _runtime_meta, nil, _field_name, _ext_check),
    do: {:ok, nil}

  defp resolve_explicit_asset(instance, runtime_meta, explicit_path, field_name, extension_check) do
    with true <-
           extension_check.(explicit_path) || invalid_asset_extension(field_name, explicit_path),
         {:ok, resolved} <- resolve_work_area_path(instance, explicit_path, runtime_meta),
         :ok <- ensure_asset_exists(resolved.relative_path, resolved.absolute_path, field_name),
         {:ok, content} <-
           read_asset_content(resolved.relative_path, resolved.absolute_path, field_name) do
      {:ok, %{source: :explicit, content: content, path: resolved.relative_path}}
    end
  end

  defp resolve_conventional_asset(instance, runtime_meta, conventional_path, extension_check) do
    with true <- extension_check.(conventional_path),
         {:ok, resolved} <- resolve_work_area_path(instance, conventional_path, runtime_meta) do
      read_conventional_asset(resolved)
    else
      {:error, %{code: "tool.validation.invalid_path"}} -> {:ok, nil}
      {:error, %{code: "tool.fs.work_area_unavailable"}} -> {:ok, nil}
      _ -> {:ok, nil}
    end
  end

  defp read_conventional_asset(%{absolute_path: absolute_path, relative_path: relative_path}) do
    case File.stat(absolute_path) do
      {:ok, %File.Stat{type: :regular}} ->
        case File.read(absolute_path) do
          {:ok, content} ->
            {:ok, %{source: :conventional, content: content, path: relative_path}}

          {:error, _} ->
            {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp resolve_fallback_asset(key, extension_check) do
    key
    |> config_value(nil)
    |> resolve_fallback_asset_path(extension_check)
  end

  defp resolve_fallback_asset_path(fallback_path, extension_check)
       when is_binary(fallback_path) and fallback_path != "",
       do: resolve_valid_fallback_asset(fallback_path, extension_check)

  defp resolve_fallback_asset_path(_fallback_path, _extension_check), do: {:ok, nil}

  defp resolve_valid_fallback_asset(fallback_path, extension_check) do
    fallback_absolute = Path.expand(fallback_path, app_root_path())
    allowed_root = allowed_fallback_root()

    with true <-
           path_within_root?(fallback_absolute, allowed_root) ||
             fallback_reject("outside_root"),
         true <- extension_check.(fallback_absolute) || fallback_reject("invalid_extension"),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(fallback_absolute),
         true <-
           path_without_symlink_components?(allowed_root, fallback_absolute) ||
             fallback_reject("symlink"),
         {:ok, content} <- File.read(fallback_absolute),
         true <- byte_size(content) <= max_fallback_bytes() || fallback_reject("too_large") do
      {:ok, %{source: :fallback, content: content, path: nil}}
    else
      {:error, :rejected_fallback} ->
        {:ok, nil}

      {:ok, %File.Stat{type: :symlink}} ->
        _ = fallback_reject("symlink")
        {:ok, nil}

      {:ok, _stat} ->
        _ = fallback_reject("not_regular")
        {:ok, nil}

      {:error, :enoent} ->
        {:ok, nil}

      {:error, _reason} ->
        _ = fallback_reject("unreadable")
        {:ok, nil}
    end
  end

  defp fallback_reject(reason) do
    Logger.warning("documents fallback asset rejected",
      event: "documents.fallback_asset.rejected",
      reason: reason
    )

    {:error, :rejected_fallback}
  end

  defp path_within_root?(candidate_path, root_path) do
    candidate_path == root_path or String.starts_with?(candidate_path, root_path <> "/")
  end

  defp path_without_symlink_components?(root_path, candidate_path) do
    {valid?, _path} =
      candidate_path
      |> Path.relative_to(root_path)
      |> String.split("/", trim: true)
      |> Enum.reduce_while({true, root_path}, fn segment, {_valid?, current_path} ->
        next_path = Path.join(current_path, segment)

        case File.lstat(next_path) do
          {:ok, %File.Stat{type: :symlink}} ->
            {:halt, {false, next_path}}

          {:ok, _} ->
            {:cont, {true, next_path}}

          {:error, _} ->
            {:halt, {true, next_path}}
        end
      end)

    valid?
  end

  defp app_root_path do
    Application.app_dir(:lemmings_os)
  end

  defp allowed_fallback_root do
    :lemmings_os
    |> :code.priv_dir()
    |> List.to_string()
    |> Path.join("documents")
    |> Path.expand()
  end

  defp ensure_asset_exists(relative_path, absolute_path, field_name) do
    case File.stat(absolute_path) do
      {:ok, %File.Stat{type: :regular}} ->
        :ok

      _ ->
        {:error,
         %{
           code: "tool.documents.asset_not_found",
           message: "Asset file not found",
           details: %{field_name => relative_path}
         }}
    end
  end

  defp read_asset_content(relative_path, absolute_path, field_name) do
    case File.read(absolute_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, _reason} ->
        {:error,
         %{
           code: "tool.documents.asset_not_found",
           message: "Asset file not found",
           details: %{field_name => relative_path}
         }}
    end
  end

  defp invalid_asset_extension(field_name, path) do
    {:error,
     %{
       code: "tool.documents.unsupported_format",
       message: "Unsupported asset format",
       details: %{field_name => path}
     }}
  end

  defp html_extension?(path), do: String.downcase(Path.extname(path)) in [".html", ".htm"]
  defp css_extension?(path), do: String.downcase(Path.extname(path)) == ".css"

  defp conventional_header_path(source_path) do
    with_ext(source_path, "_pdf_header.html")
  end

  defp conventional_footer_path(source_path) do
    with_ext(source_path, "_pdf_footer.html")
  end

  defp conventional_css_path(source_path) do
    with_ext(source_path, "_pdf.css")
  end

  defp with_ext(path, suffix) do
    directory = Path.dirname(path)
    basename = Path.rootname(Path.basename(path))
    Path.join(directory, basename <> suffix)
  end

  defp replace_extension(path, extension) do
    Path.rootname(path) <> extension
  end

  defp enforce_asset_policy(source_path, html_body, resolved_assets) do
    [{"source_path", source_path, html_body}]
    |> append_optional_policy_asset("header_path", resolved_assets.header)
    |> append_optional_policy_asset("footer_path", resolved_assets.footer)
    |> append_policy_styles(resolved_assets.styles)
    |> Enum.reduce_while(:ok, fn {field, path, content}, :ok ->
      case check_asset_content(field, path, content) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp append_optional_policy_asset(assets, _field, nil), do: assets

  defp append_optional_policy_asset(assets, field, %{content: content, path: path})
       when is_list(assets),
       do: assets ++ [{field, path, content}]

  defp append_policy_styles(assets, styles) when is_list(styles) do
    assets ++ Enum.map(styles, &{"style_paths", &1.path, &1.content})
  end

  defp append_policy_styles(assets, _styles), do: assets

  defp check_asset_content(field, path, content) when is_binary(content) do
    do_check_asset_content(field, path, content)
  end

  defp do_check_asset_content(field, path, content) do
    [
      &reject_http_https_references/3,
      &reject_file_references/3,
      &reject_protocol_relative_references/3,
      &reject_css_import_references/3
    ]
    |> Enum.reduce_while(:ok, fn validator, :ok ->
      case validator.(field, path, content) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp reject_http_https_references(field, path, content) do
    if Regex.match?(~r/https?:\/\//i, content) do
      {:error, blocked_asset_error(field, path, "remote_url")}
    else
      :ok
    end
  end

  defp reject_file_references(field, path, content) do
    if Regex.match?(~r/file:\/\//i, content) do
      {:error, blocked_asset_error(field, path, "file_url")}
    else
      :ok
    end
  end

  defp reject_protocol_relative_references(field, path, content) do
    if Regex.match?(~r/(^|[\s"'(=])\/\/[a-z0-9]/i, content) do
      {:error, blocked_asset_error(field, path, "protocol_relative_url")}
    else
      :ok
    end
  end

  defp reject_css_import_references(field, path, content) do
    if Regex.match?(~r/@import\b/i, content) do
      {:error, blocked_asset_error(field, path, "css_import")}
    else
      :ok
    end
  end

  defp blocked_asset_error(field, path, reason) do
    details =
      %{field => path || "fallback_asset", "reason" => reason}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %{
      code: "tool.documents.blocked_asset_reference",
      message: "Blocked asset reference in HTML/CSS input",
      details: details
    }
  end

  defp request_pdf_with_retry(request_fun, retries_left, log_metadata)
       when is_function(request_fun, 0) and is_list(log_metadata) do
    request_pdf_with_retry_loop(request_fun, retries_left, pdf_retries(), 1, log_metadata)
  rescue
    _ ->
      backend_unavailable("unexpected_error", log_metadata)
  end

  defp request_pdf_with_retry_loop(request_fun, retries_left, max_retries, attempt, log_metadata)
       when retries_left >= 0 do
    request_fun.()
    |> handle_pdf_request_result(request_fun, retries_left, max_retries, attempt, log_metadata)
  end

  defp handle_pdf_request_result(
         {:ok, %Req.Response{status: status, body: body}},
         _request_fun,
         _retries_left,
         _max_retries,
         _attempt,
         _log_metadata
       )
       when status in 200..299 and is_binary(body) do
    validate_pdf_size(body)
  end

  defp handle_pdf_request_result(
         {:ok, %Req.Response{status: status}},
         request_fun,
         retries_left,
         max_retries,
         attempt,
         log_metadata
       )
       when status in @retryable_statuses and retries_left > 0 do
    backend_retry("retryable_status", max_retries, attempt, status, log_metadata)

    request_pdf_with_retry_loop(
      request_fun,
      retries_left - 1,
      max_retries,
      attempt + 1,
      log_metadata
    )
  end

  defp handle_pdf_request_result(
         {:ok, %Req.Response{status: status}},
         _request_fun,
         _retries_left,
         _max_retries,
         _attempt,
         log_metadata
       ) do
    backend_failed(status, log_metadata)
  end

  defp handle_pdf_request_result(
         {:error, %Req.TransportError{reason: reason}},
         request_fun,
         retries_left,
         max_retries,
         attempt,
         log_metadata
       )
       when retries_left > 0 and reason in [:timeout, :econnrefused, :closed] do
    backend_retry(normalize_transport_reason(reason), max_retries, attempt, nil, log_metadata)

    request_pdf_with_retry_loop(
      request_fun,
      retries_left - 1,
      max_retries,
      attempt + 1,
      log_metadata
    )
  end

  defp handle_pdf_request_result(
         {:error, %Req.TransportError{}},
         _request_fun,
         _retries_left,
         _max_retries,
         _attempt,
         log_metadata
       ) do
    backend_unavailable("transport_error", log_metadata)
  end

  defp handle_pdf_request_result(
         {:error, _},
         _request_fun,
         _retries_left,
         _max_retries,
         _attempt,
         log_metadata
       ) do
    backend_unavailable("request_failed", log_metadata)
  end

  defp backend_retry(reason, max_retries, attempt, status, log_metadata) do
    Logger.warning(
      "documents print to pdf backend retry",
      log_metadata ++
        [
          event: "documents.print_to_pdf.backend_retry",
          status: if(is_integer(status), do: to_string(status), else: nil),
          reason: reason,
          retry_count: attempt,
          max_retries: max_retries
        ]
    )
  end

  defp backend_failed(status, log_metadata) do
    Logger.error(
      "documents print to pdf backend failed",
      log_metadata ++
        [
          event: "documents.print_to_pdf.backend_failed",
          status: to_string(status),
          reason: "backend_status"
        ]
    )

    {:error,
     %{
       code: "tool.documents.pdf_conversion_failed",
       message: "PDF backend conversion failed",
       details: %{"status" => status}
     }}
  end

  defp backend_unavailable(reason, log_metadata) do
    Logger.error(
      "documents print to pdf backend unavailable",
      log_metadata ++
        [
          event: "documents.print_to_pdf.backend_unavailable",
          reason: reason
        ]
    )

    {:error,
     %{
       code: "tool.documents.pdf_backend_unavailable",
       message: "PDF backend is unavailable",
       details: %{}
     }}
  end

  defp normalize_transport_reason(:timeout), do: "timeout"
  defp normalize_transport_reason(:econnrefused), do: "connection_refused"
  defp normalize_transport_reason(:closed), do: "connection_closed"

  defp log_print_started(instance, runtime_meta, source_path, output_path) do
    Logger.info(
      "documents print to pdf started",
      [event: "documents.print_to_pdf.started", reason: "start"] ++
        print_log_metadata(instance, runtime_meta,
          source_path: source_path,
          output_path: output_path
        )
    )

    :ok
  end

  defp log_print_failure(error, code, duration_ms, log_metadata) do
    level = print_failure_level(code)
    event = print_failure_event(code)
    reason = print_failure_reason(code)
    status = print_failure_status(error)
    path = print_failure_path(error)

    Logger.log(
      level,
      "documents print to pdf failed",
      log_metadata ++
        [
          event: event,
          reason: reason,
          duration_ms: duration_ms,
          status: status,
          path: path
        ]
    )
  end

  defp print_failure_level("tool.documents.pdf_conversion_failed"), do: :error
  defp print_failure_level("tool.documents.pdf_backend_unavailable"), do: :error
  defp print_failure_level(_code), do: :warning

  defp print_failure_event("tool.documents.pdf_conversion_failed"),
    do: "documents.print_to_pdf.backend_failed"

  defp print_failure_event("tool.documents.pdf_backend_unavailable"),
    do: "documents.print_to_pdf.backend_unavailable"

  defp print_failure_event(_code), do: "documents.print_to_pdf.failed"

  defp print_failure_reason(code) do
    code
    |> String.replace_prefix("tool.documents.", "")
    |> String.replace(".", "_")
  end

  defp print_failure_status(%{details: %{"status" => status}}) when is_integer(status),
    do: to_string(status)

  defp print_failure_status(_error), do: "error"

  defp print_failure_path(%{details: %{"output_path" => path}}) when is_binary(path), do: path
  defp print_failure_path(%{details: %{"source_path" => path}}) when is_binary(path), do: path
  defp print_failure_path(_error), do: nil

  defp failure_source_path(%{details: %{"source_path" => path}}) when is_binary(path), do: path
  defp failure_source_path(_error), do: nil

  defp failure_output_path(%{details: %{"output_path" => path}}) when is_binary(path), do: path
  defp failure_output_path(_error), do: nil

  defp print_log_metadata(instance, runtime_meta, opts) do
    source_path = Keyword.get(opts, :source_path)
    output_path = Keyword.get(opts, :output_path)

    [
      path: output_path || source_path,
      instance_id: Map.get(instance, :id),
      world_id: runtime_meta_value(runtime_meta, :world_id),
      city_id: runtime_meta_value(runtime_meta, :city_id),
      department_id: runtime_meta_value(runtime_meta, :department_id),
      work_area_ref: runtime_meta_value(runtime_meta, :work_area_ref)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp runtime_meta_value(runtime_meta, key) do
    Map.get(runtime_meta, key) || Map.get(runtime_meta, Atom.to_string(key))
  end

  defp validate_pdf_size(pdf_binary) do
    max_pdf_bytes = max_pdf_bytes()
    validate_pdf_size(pdf_binary, max_pdf_bytes)
  end

  defp validate_pdf_size(pdf_binary, max_pdf_bytes) when byte_size(pdf_binary) <= max_pdf_bytes,
    do: {:ok, pdf_binary}

  defp validate_pdf_size(_pdf_binary, max_pdf_bytes) do
    {:error,
     %{
       code: "tool.documents.pdf_too_large",
       message: "Generated PDF exceeds configured size limit",
       details: %{"max_pdf_bytes" => max_pdf_bytes}
     }}
  end

  defp write_pdf_atomic(relative_path, destination_path, pdf_binary) do
    target_dir = Path.dirname(destination_path)
    temp_path = Path.join(target_dir, ".documents-pdf-#{System.unique_integer([:positive])}.tmp")

    with :ok <- write_temp_pdf(temp_path, pdf_binary),
         :ok <- rename_into_place(temp_path, destination_path, relative_path) do
      {:ok, byte_size(pdf_binary)}
    else
      {:error, error} ->
        _ = File.rm(temp_path)
        {:error, error}
    end
  end

  defp write_temp_pdf(temp_path, pdf_binary) do
    case File.write(temp_path, pdf_binary, [:binary]) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.documents.write_failed",
           message: "Could not write output file",
           details: %{"reason" => inspect(reason)}
         }}
    end
  end

  defp print_options_fields(print_args) do
    paper_fields = paper_size_fields(print_args.paper_size)

    margin_fields =
      [
        {"marginTop", print_args.margin_top},
        {"marginBottom", print_args.margin_bottom},
        {"marginLeft", print_args.margin_left},
        {"marginRight", print_args.margin_right}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    paper_fields ++ margin_fields ++ [{"landscape", to_string(print_args.landscape)}]
  end

  defp paper_size_fields(nil), do: []

  defp paper_size_fields(paper_size) do
    case String.upcase(paper_size) do
      "A4" -> [{"paperWidth", "8.27"}, {"paperHeight", "11.7"}]
      "A3" -> [{"paperWidth", "11.7"}, {"paperHeight", "16.54"}]
      "A5" -> [{"paperWidth", "5.83"}, {"paperHeight", "8.27"}]
      "LETTER" -> [{"paperWidth", "8.5"}, {"paperHeight", "11"}]
      "LEGAL" -> [{"paperWidth", "8.5"}, {"paperHeight", "14"}]
      "TABLOID" -> [{"paperWidth", "11"}, {"paperHeight", "17"}]
      _ -> []
    end
  end

  defp gotenberg_url do
    config_value(:gotenberg_url, @default_gotenberg_url)
  end

  defp pdf_timeout_ms do
    integer_config_value(:pdf_timeout_ms, @default_pdf_timeout_ms)
  end

  defp pdf_connect_timeout_ms do
    integer_config_value(:pdf_connect_timeout_ms, @default_pdf_connect_timeout_ms)
  end

  defp pdf_retries do
    non_negative_integer_config_value(:pdf_retries, @default_pdf_retries)
  end

  defp max_pdf_bytes do
    integer_config_value(:max_pdf_bytes, @default_max_pdf_bytes)
  end

  defp max_fallback_bytes do
    integer_config_value(:max_fallback_bytes, @default_max_fallback_bytes)
  end

  defp config_value(key, default) do
    Application.get_env(:lemmings_os, :documents, [])
    |> Keyword.get(key, default)
  end

  defp validate_documents_config do
    [
      pdf_timeout_ms: {@default_pdf_timeout_ms, :positive},
      pdf_connect_timeout_ms: {@default_pdf_connect_timeout_ms, :positive},
      pdf_retries: {@default_pdf_retries, :non_negative},
      max_source_bytes: {@default_max_source_bytes, :positive},
      max_pdf_bytes: {@default_max_pdf_bytes, :positive},
      max_fallback_bytes: {@default_max_fallback_bytes, :positive}
    ]
    |> Enum.reduce_while(:ok, fn {key, {default, parser}}, :ok ->
      case parse_integer_config_value(config_value(key, default), parser) do
        {:ok, _value} ->
          {:cont, :ok}

        :error ->
          {:halt, invalid_documents_config_error(key)}
      end
    end)
  end

  defp invalid_documents_config_error(key) when is_atom(key) do
    {:error,
     %{
       code: "tool.documents.invalid_configuration",
       message: "Documents tool is misconfigured",
       details: %{"field" => Atom.to_string(key)}
     }}
  end

  defp integer_config_value(key, default) do
    case parse_integer_config_value(config_value(key, default), :positive) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp non_negative_integer_config_value(key, default) do
    case parse_integer_config_value(config_value(key, default), :non_negative) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp parse_integer_config_value(value, :positive), do: Helpers.parse_positive_integer(value)

  defp parse_integer_config_value(value, :non_negative),
    do: Helpers.parse_non_negative_integer(value)
end
