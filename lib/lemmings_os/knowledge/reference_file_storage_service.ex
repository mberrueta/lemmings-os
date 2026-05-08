defmodule LemmingsOs.Knowledge.ReferenceFileStorageService do
  @moduledoc """
  Local managed storage boundary for Knowledge reference files.

  Reference-file bytes are stored outside the database under a Knowledge-owned
  root. The returned `storage_ref` is an opaque internal pointer for trusted
  context code only. Absolute filesystem paths, storage roots, temp-upload
  paths, and raw storage refs must not be exposed to UI, tools, events, or logs.

  Public callers should use `build_reference_ref/1` and `public_descriptor/1`.
  Those descriptors intentionally exclude `storage_ref`, checksum, file size,
  and all filesystem paths.

  ## Configuration

  The service reads `:knowledge_reference_file_storage` from the application
  environment:

  - `:root_path` - managed storage root. Defaults to
    `priv/runtime/knowledge_reference_storage` under the current working
    directory.
  - `:max_file_size_bytes` - maximum bytes accepted by `put/4`. Defaults to
    `10 * 1024 * 1024`.

  `config/runtime.exs` also supports
  `LEMMINGS_KNOWLEDGE_REFERENCE_FILE_STORAGE_ROOT` for overriding the root path
  at runtime.
  """

  alias LemmingsOs.Knowledge.ReferenceFile

  @storage_scheme "local"
  @storage_host "knowledge_reference_files"
  @reference_ref_prefix "kref"
  @default_max_file_size_bytes 10 * 1024 * 1024
  @copy_chunk_size 65_536

  @type stored_file :: %{
          storage_ref: String.t(),
          checksum: String.t(),
          size_bytes: non_neg_integer()
        }

  @type public_descriptor :: %{
          reference_ref: String.t(),
          reference_file_type: String.t(),
          original_filename: String.t(),
          content_type: String.t(),
          safe_to_read: boolean(),
          safe_to_pass_to_tools: boolean(),
          metadata: map()
        }

  @doc """
  Copies a trusted source file into Knowledge-managed reference-file storage.

  ## Parameters

  - `world_id` - UUID string for the owning world.
  - `knowledge_item_id` - UUID string for the owning reference-file
    `KnowledgeItem`.
  - `source_path` - absolute path to a trusted, regular source file. Symlinks,
    relative paths, null bytes, Windows-style drive paths, and backslash paths
    are rejected.
  - `filename` - safe basename to use in managed storage. It must not contain
    path separators, traversal, null/control bytes, URI query/fragment
    separators, absolute paths, Windows drive prefixes, or `~` prefixes.

  ## Return Value

  Returns internal storage metadata for persistence by trusted Knowledge context
  code. Do not pass the returned `storage_ref`, checksum, size, or resolved path
  to public descriptors, tool outputs, UI events, or logs.

  The max accepted size is `max_file_size_bytes/0`, configured by
  `:knowledge_reference_file_storage[:max_file_size_bytes]` and defaulting to
  10 MiB.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_put")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> source_path = Path.join(root, "upload.md")
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> :ok = File.write(source_path, "hello\\n")
      iex> {:ok, stored} = LemmingsOs.Knowledge.ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")
      iex> stored.storage_ref
      "local://knowledge_reference_files/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/template.md"
      iex> stored.size_bytes
      6
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec put(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, stored_file()} | {:error, atom()}
  def put(world_id, knowledge_item_id, source_path, filename)
      when is_binary(world_id) and is_binary(knowledge_item_id) and is_binary(source_path) and
             is_binary(filename) do
    with :ok <- validate_world_id(world_id),
         :ok <- validate_knowledge_item_id(knowledge_item_id),
         :ok <- validate_filename(filename),
         {:ok, source_absolute_path} <- validate_source_path(source_path),
         {:ok, storage_ref} <- build_storage_ref(world_id, knowledge_item_id, filename),
         :ok <- ensure_storage_root(root_path()),
         {:ok, destination_path} <- resolve_storage_ref(storage_ref),
         :ok <- ensure_storage_directory(Path.dirname(destination_path)),
         :ok <- copy_file_atomic(source_absolute_path, destination_path, max_file_size_bytes()),
         {:ok, size_bytes} <- size_bytes(destination_path),
         {:ok, checksum} <- checksum(destination_path) do
      {:ok, %{storage_ref: storage_ref, checksum: checksum, size_bytes: size_bytes}}
    end
  end

  def put(_world_id, _knowledge_item_id, _source_path, _filename), do: {:error, :invalid_input}

  @doc """
  Builds an opaque internal storage ref for a reference file.

  ## Parameters

  - `world_id` - UUID string for the owning world.
  - `knowledge_item_id` - UUID string for the owning reference-file
    `KnowledgeItem`.
  - `filename` - safe basename for the file. The same filename validation used
    by `put/4` applies.

  ## Return Value

  Returns `{:ok, storage_ref}` for trusted persistence or
  `{:error, :invalid_storage_ref | :invalid_world_id | :invalid_knowledge_item_id | :invalid_filename}`.
  The generated ref is internal-only and is not a public descriptor.

  ## Examples

      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> {:ok, ref} = LemmingsOs.Knowledge.ReferenceFileStorageService.build_storage_ref(world_id, knowledge_item_id, "template.md")
      iex> ref
      "local://knowledge_reference_files/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/template.md"

      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.build_storage_ref("bad", "22222222-2222-4222-8222-222222222222", "template.md")
      {:error, :invalid_world_id}
  """
  @spec build_storage_ref(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def build_storage_ref(world_id, knowledge_item_id, filename)
      when is_binary(world_id) and is_binary(knowledge_item_id) and is_binary(filename) do
    with :ok <- validate_world_id(world_id),
         :ok <- validate_knowledge_item_id(knowledge_item_id),
         :ok <- validate_filename(filename) do
      {:ok, "#{@storage_scheme}://#{@storage_host}/#{world_id}/#{knowledge_item_id}/#{filename}"}
    end
  end

  def build_storage_ref(_world_id, _knowledge_item_id, _filename),
    do: {:error, :invalid_storage_ref}

  @doc """
  Builds a stable public reference descriptor ref for a Knowledge item.

  ## Parameters

  - `knowledge_item_id` - UUID string for the reference-file `KnowledgeItem`.

  ## Return Value

  The returned value is safe to expose and does not encode filesystem paths,
  storage roots, or storage refs.

  ## Examples

      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.build_reference_ref(knowledge_item_id)
      {:ok, "kref:22222222-2222-4222-8222-222222222222"}

      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.build_reference_ref("../secret")
      {:error, :invalid_reference_ref}
  """
  @spec build_reference_ref(Ecto.UUID.t()) :: {:ok, String.t()} | {:error, atom()}
  def build_reference_ref(knowledge_item_id) when is_binary(knowledge_item_id) do
    case validate_knowledge_item_id(knowledge_item_id) do
      :ok -> {:ok, "#{@reference_ref_prefix}:#{knowledge_item_id}"}
      {:error, _reason} -> {:error, :invalid_reference_ref}
    end
  end

  def build_reference_ref(_knowledge_item_id), do: {:error, :invalid_reference_ref}

  @doc """
  Returns a safe public descriptor for a reference file.

  ## Parameters

  - `reference_file` - a `%LemmingsOs.Knowledge.ReferenceFile{}` struct.

  ## Return Value

  This descriptor deliberately excludes `storage_ref`, checksum, size, absolute
  paths, temp-upload paths, storage roots, and workspace paths.

  ## Examples

      iex> reference_file = %LemmingsOs.Knowledge.ReferenceFile{
      ...>   reference_ref: "kref:quote_template",
      ...>   reference_file_type: "quote_template",
      ...>   original_filename: "template.md",
      ...>   content_type: "text/markdown",
      ...>   size_bytes: 123,
      ...>   checksum: String.duplicate("a", 64),
      ...>   storage_ref: "local://knowledge_reference_files/internal/path/template.md",
      ...>   metadata: %{"origin" => "upload"},
      ...>   safe_to_read: true,
      ...>   safe_to_pass_to_tools: false
      ...> }
      iex> descriptor = LemmingsOs.Knowledge.ReferenceFileStorageService.public_descriptor(reference_file)
      iex> descriptor.reference_ref
      "kref:quote_template"
      iex> Map.has_key?(descriptor, :storage_ref)
      false
      iex> Map.has_key?(descriptor, :checksum)
      false
      iex> Map.has_key?(descriptor, :size_bytes)
      false
  """
  @spec public_descriptor(ReferenceFile.t()) :: public_descriptor()
  def public_descriptor(%ReferenceFile{} = reference_file) do
    %{
      reference_ref: reference_file.reference_ref,
      reference_file_type: reference_file.reference_file_type,
      original_filename: reference_file.original_filename,
      content_type: reference_file.content_type,
      safe_to_read: reference_file.safe_to_read,
      safe_to_pass_to_tools: reference_file.safe_to_pass_to_tools,
      metadata: reference_file.metadata || %{}
    }
  end

  @doc """
  Resolves a trusted storage ref to an absolute internal path.

  ## Parameters

  - `storage_ref` - an internal ref previously produced by
    `build_storage_ref/3` or `put/4`.

  ## Return Value

  Returns `{:ok, absolute_path}` only for trusted internal use. Rejects malformed
  refs, refs that escape the configured root, and refs with symlink traversal.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_resolve")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> ref = "local://knowledge_reference_files/\#{world_id}/\#{knowledge_item_id}/template.md"
      iex> {:ok, resolved} = LemmingsOs.Knowledge.ReferenceFileStorageService.resolve_storage_ref(ref)
      iex> resolved == Path.join([Path.expand(root), world_id, knowledge_item_id, "template.md"])
      true
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec resolve_storage_ref(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def resolve_storage_ref(storage_ref) when is_binary(storage_ref) do
    with {:ok, world_id, knowledge_item_id, filename} <- parse_storage_ref(storage_ref),
         root <- root_path(),
         :ok <- validate_storage_root_available(root),
         relative_path <- Path.join([world_id, knowledge_item_id, filename]),
         absolute_path <- Path.expand(relative_path, root),
         :ok <- validate_within_root(absolute_path, root),
         :ok <- validate_no_symlink_components(root, relative_path) do
      {:ok, absolute_path}
    end
  end

  def resolve_storage_ref(_storage_ref), do: {:error, :invalid_storage_ref}

  @doc """
  Returns the World ID encoded in a Knowledge reference-file storage ref.

  ## Parameters

  - `storage_ref` - an internal reference-file storage ref.

  ## Examples

      iex> storage_ref = "local://knowledge_reference_files/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/template.md"
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.storage_ref_world_id(storage_ref)
      {:ok, "11111111-1111-4111-8111-111111111111"}

      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.storage_ref_world_id("local://wrong/ref")
      {:error, :invalid_storage_ref}
  """
  @spec storage_ref_world_id(String.t()) :: {:ok, Ecto.UUID.t()} | {:error, atom()}
  def storage_ref_world_id(storage_ref) when is_binary(storage_ref) do
    with {:ok, world_id, _knowledge_item_id, _filename} <- parse_storage_ref(storage_ref) do
      {:ok, world_id}
    end
  end

  def storage_ref_world_id(_storage_ref), do: {:error, :invalid_storage_ref}

  @doc """
  Reads private reference-file bytes from managed storage.

  ## Parameters

  - `storage_ref` - an internal ref previously produced by `put/4`.

  ## Return Value

  Returns `{:ok, binary}` for trusted internal callers. This function is not a
  public download boundary.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_read")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> source_path = Path.join(root, "upload.md")
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> :ok = File.write(source_path, "read me")
      iex> {:ok, stored} = LemmingsOs.Knowledge.ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.read_private(stored.storage_ref)
      {:ok, "read me"}
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec read_private(String.t()) :: {:ok, binary()} | {:error, atom()}
  def read_private(storage_ref) when is_binary(storage_ref) do
    with {:ok, path} <- resolve_storage_ref(storage_ref),
         true <- File.regular?(path) or {:error, :not_found},
         {:ok, content} <- File.read(path) do
      {:ok, content}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
    end
  end

  def read_private(_storage_ref), do: {:error, :invalid_storage_ref}

  @doc """
  Opens a private managed file as a binary stream and yields it to a callback.

  ## Parameters

  - `storage_ref` - an internal ref previously produced by `put/4`.
  - `fun` - one-argument callback that receives a binary stream.

  ## Return Value

  Returns `{:ok, callback_result}` or `{:error, reason}`. The stream chunk size
  is internal and currently 64 KiB.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_stream")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> source_path = Path.join(root, "upload.md")
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> :ok = File.write(source_path, "stream me")
      iex> {:ok, stored} = LemmingsOs.Knowledge.ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.open_stream(stored.storage_ref, fn stream ->
      ...>   stream |> Enum.to_list() |> IO.iodata_to_binary()
      ...> end)
      {:ok, "stream me"}
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec open_stream(String.t(), (Enumerable.t() -> term())) :: {:ok, term()} | {:error, atom()}
  def open_stream(storage_ref, fun) when is_binary(storage_ref) and is_function(fun, 1) do
    with {:ok, path} <- resolve_storage_ref(storage_ref),
         true <- File.regular?(path) or {:error, :not_found},
         {:ok, device} <- File.open(path, [:read, :binary]) do
      try do
        {:ok, fun.(IO.binstream(device, @copy_chunk_size))}
      after
        File.close(device)
      end
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
    end
  end

  def open_stream(_storage_ref, _fun), do: {:error, :invalid_input}

  @doc """
  Yields the private absolute path of a managed file to a callback.

  Intended for internal extraction or promotion flows only.

  ## Parameters

  - `storage_ref` - an internal ref previously produced by `put/4`.
  - `fun` - one-argument callback that receives the private absolute path while
    the file exists in managed storage.

  ## Return Value

  Returns `{:ok, callback_result}` or `{:error, reason}`. The yielded path must
  not be returned to public callers or logged.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_temp")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> knowledge_item_id = "22222222-2222-4222-8222-222222222222"
      iex> source_path = Path.join(root, "upload.md")
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> :ok = File.write(source_path, "private path")
      iex> {:ok, stored} = LemmingsOs.Knowledge.ReferenceFileStorageService.put(world_id, knowledge_item_id, source_path, "template.md")
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.with_temp_file(stored.storage_ref, fn path ->
      ...>   Path.type(path) == :absolute and String.contains?(path, Path.expand(root))
      ...> end)
      {:ok, true}
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec with_temp_file(String.t(), (String.t() -> term())) :: {:ok, term()} | {:error, atom()}
  def with_temp_file(storage_ref, fun) when is_binary(storage_ref) and is_function(fun, 1) do
    with {:ok, path} <- resolve_storage_ref(storage_ref),
         true <- File.regular?(path) or {:error, :not_found} do
      {:ok, fun.(path)}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
    end
  end

  def with_temp_file(_storage_ref, _fun), do: {:error, :invalid_input}

  @doc """
  Returns the configured root path for reference-file storage.

  ## Options and Defaults

  Reads `:knowledge_reference_file_storage[:root_path]`. If omitted, the
  default is `priv/runtime/knowledge_reference_storage` under `File.cwd!/0`.
  The returned path is expanded.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_reference_file_storage_doctest_root")
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: root, max_file_size_bytes: 10 * 1024 * 1024)
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.root_path()
      Path.expand(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec root_path() :: String.t()
  def root_path do
    :lemmings_os
    |> Application.get_env(:knowledge_reference_file_storage, [])
    |> Keyword.get(
      :root_path,
      Path.expand("priv/runtime/knowledge_reference_storage", File.cwd!())
    )
    |> Path.expand()
  end

  @doc """
  Returns the configured max reference-file size in bytes.

  ## Options and Defaults

  Reads `:knowledge_reference_file_storage[:max_file_size_bytes]`. If omitted,
  the default is 10 MiB.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :knowledge_reference_file_storage)
      iex> Application.put_env(:lemmings_os, :knowledge_reference_file_storage, backend: :local, root_path: "/tmp/reference-files", max_file_size_bytes: 1234)
      iex> LemmingsOs.Knowledge.ReferenceFileStorageService.max_file_size_bytes()
      1234
      iex> if old_storage, do: Application.put_env(:lemmings_os, :knowledge_reference_file_storage, old_storage), else: Application.delete_env(:lemmings_os, :knowledge_reference_file_storage)
      :ok
  """
  @spec max_file_size_bytes() :: pos_integer()
  def max_file_size_bytes do
    :lemmings_os
    |> Application.get_env(:knowledge_reference_file_storage, [])
    |> Keyword.get(:max_file_size_bytes, @default_max_file_size_bytes)
  end

  defp parse_storage_ref(storage_ref) do
    uri = URI.parse(storage_ref)

    with :ok <- validate_uri_shape(uri),
         {:ok, [world_id, knowledge_item_id, filename]} <- path_segments(uri.path),
         :ok <- validate_world_id(world_id),
         :ok <- validate_knowledge_item_id(knowledge_item_id),
         :ok <- validate_filename(filename) do
      {:ok, world_id, knowledge_item_id, filename}
    else
      _error -> {:error, :invalid_storage_ref}
    end
  end

  defp path_segments(nil), do: {:error, :invalid_storage_ref}

  defp path_segments(path) do
    segments =
      path
      |> String.trim_leading("/")
      |> String.split("/", trim: false)

    if Enum.any?(segments, &(&1 == "")) do
      {:error, :invalid_storage_ref}
    else
      {:ok, segments}
    end
  end

  defp validate_uri_shape(%URI{
         scheme: @storage_scheme,
         host: @storage_host,
         query: nil,
         fragment: nil
       }),
       do: :ok

  defp validate_uri_shape(_uri), do: {:error, :invalid_storage_ref}

  defp validate_world_id(world_id) do
    case Ecto.UUID.cast(world_id) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_world_id}
    end
  end

  defp validate_knowledge_item_id(knowledge_item_id) do
    case Ecto.UUID.cast(knowledge_item_id) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_knowledge_item_id}
    end
  end

  defp validate_filename(""), do: {:error, :invalid_filename}
  defp validate_filename("."), do: {:error, :invalid_filename}
  defp validate_filename(".."), do: {:error, :invalid_filename}

  defp validate_filename(filename) do
    with :ok <- validate_filename_bytes(filename),
         :ok <- validate_filename_uri_safety(filename) do
      validate_filename_shape(filename)
    end
  end

  defp validate_filename_bytes(filename) do
    cond do
      String.contains?(filename, <<0>>) -> {:error, :invalid_filename}
      filename =~ ~r/[\x00-\x1F\x7F]/ -> {:error, :invalid_filename}
      String.starts_with?(filename, "~") -> {:error, :invalid_filename}
      String.contains?(filename, "\\") -> {:error, :invalid_filename}
      true -> :ok
    end
  end

  defp validate_filename_uri_safety(filename) do
    if String.contains?(filename, ["?", "#"]) do
      {:error, :invalid_filename}
    else
      :ok
    end
  end

  defp validate_filename_shape(filename) do
    cond do
      Regex.match?(~r/^[A-Za-z]:/, filename) -> {:error, :invalid_filename}
      Path.type(filename) == :absolute -> {:error, :invalid_filename}
      Path.basename(filename) != filename -> {:error, :invalid_filename}
      ".." in Path.split(filename) -> {:error, :invalid_filename}
      true -> :ok
    end
  end

  defp validate_source_path(source_path) do
    cond do
      source_path == "" ->
        {:error, :invalid_source_path}

      String.contains?(source_path, <<0>>) ->
        {:error, :invalid_source_path}

      String.contains?(source_path, "\\") ->
        {:error, :invalid_source_path}

      Regex.match?(~r/^[A-Za-z]:/, source_path) ->
        {:error, :invalid_source_path}

      Path.type(source_path) != :absolute ->
        {:error, :invalid_source_path}

      true ->
        source_path
        |> Path.expand()
        |> validate_source_file()
    end
  end

  defp validate_source_file(source_path) do
    case File.lstat(source_path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, source_path}
      {:ok, %File.Stat{type: :symlink}} -> {:error, :invalid_source_path}
      {:ok, _stat} -> {:error, :source_not_regular_file}
      {:error, :enoent} -> {:error, :source_not_found}
      {:error, _reason} -> {:error, :invalid_source_path}
    end
  end

  defp ensure_storage_root(root_path) do
    case File.lstat(root_path) do
      {:ok, %File.Stat{type: :directory}} -> set_directory_permissions(root_path)
      {:ok, %File.Stat{type: :symlink}} -> {:error, :storage_unavailable}
      {:ok, _stat} -> {:error, :storage_unavailable}
      {:error, :enoent} -> ensure_storage_directory(root_path)
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp validate_storage_root_available(root_path) do
    case File.lstat(root_path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, %File.Stat{type: :symlink}} -> {:error, :storage_unavailable}
      {:ok, _stat} -> {:error, :storage_unavailable}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp ensure_storage_directory(path) do
    case File.mkdir_p(path) do
      :ok -> set_directory_permissions(path)
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp validate_within_root(absolute_path, root_path) do
    normalized_absolute = Path.expand(absolute_path)
    normalized_root = Path.expand(root_path)

    if normalized_absolute == normalized_root or
         String.starts_with?(normalized_absolute, normalized_root <> "/") do
      :ok
    else
      {:error, :invalid_storage_ref}
    end
  end

  defp validate_no_symlink_components(root_path, relative_path) do
    walk_symlink_components(Path.expand(root_path), Path.split(relative_path))
  end

  defp walk_symlink_components(_current_path, []), do: :ok

  defp walk_symlink_components(current_path, [segment | rest]) do
    next_path = Path.join(current_path, segment)

    case File.lstat(next_path) do
      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :invalid_storage_ref}

      {:ok, _stat} ->
        walk_symlink_components(next_path, rest)

      {:error, :enoent} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp copy_file_atomic(source, destination, max_file_size_bytes) do
    temp_path = temp_path_for(destination)

    result =
      case File.open(source, [:read, :binary]) do
        {:ok, source_device} ->
          try do
            copy_to_temp_and_rename(source_device, temp_path, destination, max_file_size_bytes)
          after
            File.close(source_device)
          end

        {:error, _reason} ->
          {:error, :copy_failed}
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        _ = File.rm(temp_path)
        {:error, reason}
    end
  end

  defp copy_to_temp_and_rename(source_device, temp_path, destination, max_file_size_bytes) do
    case File.open(temp_path, [:write, :binary, :exclusive]) do
      {:ok, temp_device} ->
        try do
          with {:ok, _size_bytes} <-
                 stream_copy_limited(source_device, temp_device, max_file_size_bytes),
               :ok <- set_file_permissions(temp_path),
               :ok <- rename_temp_file(temp_path, destination) do
            set_file_permissions(destination)
          end
        after
          File.close(temp_device)
        end

      {:error, _reason} ->
        {:error, :copy_failed}
    end
  end

  defp stream_copy_limited(source_device, temp_device, max_file_size_bytes) do
    do_stream_copy_limited(source_device, temp_device, max_file_size_bytes, 0)
  end

  defp do_stream_copy_limited(source_device, temp_device, max_file_size_bytes, bytes_written) do
    case IO.binread(source_device, @copy_chunk_size) do
      :eof ->
        {:ok, bytes_written}

      {:error, _reason} ->
        {:error, :copy_failed}

      chunk when is_binary(chunk) ->
        next_bytes_written = bytes_written + byte_size(chunk)

        if next_bytes_written > max_file_size_bytes do
          {:error, :file_too_large}
        else
          :ok = IO.binwrite(temp_device, chunk)

          do_stream_copy_limited(
            source_device,
            temp_device,
            max_file_size_bytes,
            next_bytes_written
          )
        end
    end
  end

  defp rename_temp_file(temp_path, destination) do
    case File.rename(temp_path, destination) do
      :ok -> :ok
      {:error, _reason} -> {:error, :copy_failed}
    end
  end

  defp temp_path_for(destination) do
    directory = Path.dirname(destination)
    base_name = Path.basename(destination)
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(directory, ".#{base_name}.tmp-#{suffix}")
  end

  defp set_directory_permissions(path) do
    case File.chmod(path, 0o700) do
      :ok -> :ok
      {:error, :enotsup} -> :ok
      {:error, :eperm} -> :ok
      {:error, :einval} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp set_file_permissions(path) do
    case File.chmod(path, 0o600) do
      :ok -> :ok
      {:error, :enotsup} -> :ok
      {:error, :eperm} -> :ok
      {:error, :einval} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp size_bytes(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when is_integer(size) and size >= 0 -> {:ok, size}
      {:ok, _stat} -> {:error, :invalid_file_size}
      {:error, _reason} -> {:error, :size_failed}
    end
  end

  defp checksum(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} ->
        digest =
          Enum.reduce(
            IO.binstream(device, @copy_chunk_size),
            :crypto.hash_init(:sha256),
            fn chunk, acc ->
              :crypto.hash_update(acc, chunk)
            end
          )
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        :ok = File.close(device)
        {:ok, digest}

      {:error, _reason} ->
        {:error, :checksum_failed}
    end
  end
end
