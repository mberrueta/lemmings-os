defmodule LemmingsOs.Tools.Adapters.Documents do
  @moduledoc """
  Documents adapters for Tool Runtime.
  """

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.WorkArea

  @default_max_source_bytes 10 * 1024 * 1024
  @default_max_pdf_bytes 50 * 1024 * 1024
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
      ...>     %{"source_path" => "notes/a.md", "output_path" => ""},
      ...>     %{}
      ...>   )
      iex> error.code
      "tool.validation.invalid_args"
  """
  @spec markdown_to_html(LemmingInstance.t(), map(), runtime_meta()) ::
          adapter_success() | adapter_error()
  def markdown_to_html(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with {:ok, {source_path, output_path, overwrite?}} <- validate_markdown_to_html_args(args),
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
  """
  @spec print_to_pdf(LemmingInstance.t(), map(), runtime_meta()) ::
          adapter_success() | adapter_error()
  def print_to_pdf(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with {:ok, print_args} <- validate_print_to_pdf_args(args),
         {:ok, source} <- resolve_work_area_path(instance, print_args.source_path, runtime_meta),
         {:ok, output} <- resolve_work_area_path(instance, print_args.output_path, runtime_meta),
         :ok <- validate_source_pdf_extension(source.relative_path),
         :ok <- validate_pdf_output_extension(output.relative_path),
         :ok <- ensure_source_exists(source.relative_path, source.absolute_path),
         :ok <-
           ensure_output_writable(
             output.relative_path,
             output.absolute_path,
             print_args.overwrite
           ),
         {:ok, source_content} <- read_source_binary(source.relative_path, source.absolute_path),
         :ok <- validate_source_size(source.relative_path, source_content),
         {:ok, html_body} <-
           source_to_html(source.relative_path, source_content, print_args.print_raw_file),
         {:ok, pdf_binary} <- convert_html_to_pdf(html_body, print_args),
         {:ok, bytes} <- write_pdf_atomic(output.relative_path, output.absolute_path, pdf_binary) do
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
  end

  defp validate_markdown_to_html_args(args) do
    with {:ok, source_path} <- fetch_required_path(args, "source_path"),
         {:ok, output_path} <- fetch_required_path(args, "output_path"),
         {:ok, overwrite?} <- fetch_optional_overwrite(args) do
      {:ok, {source_path, output_path, overwrite?}}
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
    case Map.get(args, "overwrite", Map.get(args, :overwrite, false)) do
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

  defp validate_source_extension(path) do
    if String.downcase(Path.extname(path)) == ".md" do
      :ok
    else
      {:error,
       %{
         code: "tool.documents.unsupported_format",
         message: "Unsupported source format",
         details: %{"source_path" => path}
       }}
    end
  end

  defp validate_output_extension(path) do
    if String.downcase(Path.extname(path)) in [".html", ".htm"] do
      :ok
    else
      {:error,
       %{
         code: "tool.documents.unsupported_format",
         message: "Unsupported output format",
         details: %{"output_path" => path}
       }}
    end
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

    if byte_size(markdown) <= max_source_bytes do
      :ok
    else
      {:error,
       %{
         code: "tool.documents.file_too_large",
         message: "Source file exceeds configured size limit",
         details: %{"source_path" => relative_path, "max_source_bytes" => max_source_bytes}
       }}
    end
  end

  defp max_source_bytes do
    documents_config = Application.get_env(:lemmings_os, :documents, [])
    configured = Keyword.get(documents_config, :max_source_bytes, @default_max_source_bytes)

    case configured do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> integer
          _ -> @default_max_source_bytes
        end

      _ ->
        @default_max_source_bytes
    end
  end

  defp render_markdown(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown) do
      {:ok, html_document, _messages} when is_binary(html_document) ->
        {:ok, html_document}

      {:error, html_document, _messages} when is_binary(html_document) ->
        {:ok, html_document}

      _ ->
        markdown_render_failed()
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
         {:ok, output_path} <- fetch_required_path(args, "output_path"),
         {:ok, overwrite} <- fetch_boolean_arg(args, "overwrite", false),
         {:ok, print_raw_file} <- fetch_boolean_arg(args, "print_raw_file", false),
         {:ok, landscape} <- fetch_boolean_arg(args, "landscape", false),
         {:ok, paper_size} <- fetch_optional_string_arg(args, "paper_size"),
         {:ok, margin_top} <- fetch_optional_string_arg(args, "margin_top"),
         {:ok, margin_bottom} <- fetch_optional_string_arg(args, "margin_bottom"),
         {:ok, margin_left} <- fetch_optional_string_arg(args, "margin_left"),
         {:ok, margin_right} <- fetch_optional_string_arg(args, "margin_right") do
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
         margin_right: margin_right
       }}
    end
  end

  defp fetch_boolean_arg(args, key, default) do
    case Map.get(args, key, Map.get(args, String.to_atom(key), default)) do
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
    case Map.get(args, key, Map.get(args, String.to_atom(key))) do
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

  defp validate_source_pdf_extension(path) do
    case String.downcase(Path.extname(path)) do
      ".html" -> :ok
      ".htm" -> :ok
      ".md" -> :ok
      ".txt" -> :ok
      ".png" -> :ok
      ".jpg" -> :ok
      ".jpeg" -> :ok
      ".webp" -> :ok
      _ -> unsupported_source_format(path)
    end
  end

  defp validate_pdf_output_extension(path) do
    if String.downcase(Path.extname(path)) == ".pdf" do
      :ok
    else
      {:error,
       %{
         code: "tool.documents.unsupported_format",
         message: "Unsupported output format",
         details: %{"output_path" => path}
       }}
    end
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

  defp convert_html_to_pdf(html_body, print_args) do
    form_fields =
      [{"files", {html_body, filename: "index.html", content_type: "text/html"}}] ++
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

    request_pdf_with_retry(request_fun, pdf_retries())
  end

  defp request_pdf_with_retry(request_fun, retries_left) when is_function(request_fun, 0) do
    case request_fun.() do
      {:ok, %Req.Response{status: status, body: body}}
      when status in 200..299 and is_binary(body) ->
        validate_pdf_size(body)

      {:ok, %Req.Response{status: status}}
      when status in @retryable_statuses and retries_left > 0 ->
        request_pdf_with_retry(request_fun, retries_left - 1)

      {:ok, %Req.Response{status: status}} ->
        {:error,
         %{
           code: "tool.documents.pdf_conversion_failed",
           message: "PDF backend conversion failed",
           details: %{"status" => status}
         }}

      {:error, %Req.TransportError{reason: reason}}
      when retries_left > 0 and reason in [:timeout, :econnrefused, :closed] ->
        request_pdf_with_retry(request_fun, retries_left - 1)

      {:error, %Req.TransportError{reason: _reason}} ->
        {:error,
         %{
           code: "tool.documents.pdf_backend_unavailable",
           message: "PDF backend is unavailable",
           details: %{}
         }}

      {:error, _} ->
        {:error,
         %{
           code: "tool.documents.pdf_backend_unavailable",
           message: "PDF backend is unavailable",
           details: %{}
         }}
    end
  end

  defp validate_pdf_size(pdf_binary) do
    max_pdf_bytes = max_pdf_bytes()

    if byte_size(pdf_binary) <= max_pdf_bytes do
      {:ok, pdf_binary}
    else
      {:error,
       %{
         code: "tool.documents.pdf_too_large",
         message: "Generated PDF exceeds configured size limit",
         details: %{"max_pdf_bytes" => max_pdf_bytes}
       }}
    end
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
    integer_config_value(:pdf_retries, @default_pdf_retries)
  end

  defp max_pdf_bytes do
    integer_config_value(:max_pdf_bytes, @default_max_pdf_bytes)
  end

  defp config_value(key, default) do
    Application.get_env(:lemmings_os, :documents, [])
    |> Keyword.get(key, default)
  end

  defp integer_config_value(key, default) do
    value = config_value(key, default)

    case value do
      integer when is_integer(integer) and integer > 0 ->
        integer

      binary when is_binary(binary) ->
        case Integer.parse(binary) do
          {integer, ""} when integer > 0 -> integer
          _ -> default
        end

      _ ->
        default
    end
  end
end
