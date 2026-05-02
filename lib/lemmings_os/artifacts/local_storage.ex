defmodule LemmingsOs.Artifacts.LocalStorage do
  @moduledoc """
  Local managed storage boundary for promoted Artifact files.

  An Artifact is not just a plain file path in a workspace. It is a promoted
  runtime output that must be stored under an app-managed root with a stable,
  opaque storage reference (`local://artifacts/...`), plus integrity metadata.

  This module is responsible for the filesystem side of that contract:
  safe reference generation, trusted resolution, root-bound copying, and
  checksum/size calculation.
  """

  @behaviour LemmingsOs.Artifacts.Storage.Adapter

  require Logger

  @storage_scheme "local"
  @storage_host "artifacts"
  @default_max_file_size_bytes 100 * 1024 * 1024
  @copy_chunk_size 65_536

  @typedoc """
  Metadata returned after storing a file in managed artifact storage.
  """
  @type stored_file :: %{
          storage_ref: String.t(),
          checksum: String.t(),
          size_bytes: non_neg_integer()
        }

  @doc """
  Copies a trusted source file into managed storage.

  Returns an opaque `storage_ref` suitable for persistence plus checksum and size.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :artifact_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_local_storage_doctest_store_copy")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> artifact_id = "22222222-2222-4222-8222-222222222222"
      iex> source_path = Path.join(root, "source.txt")
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(root)
      iex> Application.put_env(:lemmings_os, :artifact_storage, backend: :local, root_path: root)
      iex> :ok = File.write(source_path, "hello\\n")
      iex> {:ok, stored} =
      ...>   LemmingsOs.Artifacts.LocalStorage.store_copy(world_id, artifact_id, source_path, "artifact.txt")
      iex> stored.storage_ref
      "local://artifacts/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/artifact.txt"
      iex> stored.size_bytes
      6
      iex> expected_checksum = :sha256 |> :crypto.hash("hello\\n") |> Base.encode16(case: :lower)
      iex> stored.checksum == expected_checksum
      true
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :artifact_storage, old_storage), else: Application.delete_env(:lemmings_os, :artifact_storage)
      :ok
  """
  @spec store_copy(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, stored_file()} | {:error, atom() | {atom(), term()}}
  def store_copy(world_id, artifact_id, source_path, filename)
      when is_binary(world_id) and is_binary(artifact_id) and is_binary(source_path) and
             is_binary(filename) do
    metadata = storage_metadata(world_id, artifact_id, filename, %{operation: :write})

    instrument_write(metadata, fn ->
      do_store_copy(world_id, artifact_id, source_path, filename)
    end)
  end

  def store_copy(_world_id, _artifact_id, _source_path, _filename), do: {:error, :invalid_input}

  defp do_store_copy(world_id, artifact_id, source_path, filename) do
    with :ok <- validate_world_id(world_id),
         :ok <- validate_artifact_id(artifact_id),
         :ok <- validate_filename(filename),
         {:ok, source_absolute_path} <- validate_source_path(source_path),
         {:ok, storage_ref} <- build_storage_ref(world_id, artifact_id, filename),
         :ok <- ensure_storage_root(root_path()),
         {:ok, destination_path} <- resolve_storage_ref(storage_ref),
         :ok <- ensure_storage_directory(Path.dirname(destination_path)),
         :ok <- copy_file_atomic(source_absolute_path, destination_path, max_file_size_bytes()),
         {:ok, size_bytes} <- size_bytes(destination_path),
         {:ok, checksum} <- checksum(destination_path) do
      {:ok,
       %{
         storage_ref: storage_ref,
         checksum: checksum,
         size_bytes: size_bytes
       }}
    end
  end

  @impl true
  @doc """
  Behaviour callback wrapper for storing a trusted source file.
  """
  @spec put(Ecto.UUID.t(), Ecto.UUID.t(), String.t(), String.t()) ::
          {:ok, stored_file()} | {:error, atom() | {atom(), term()}}
  def put(world_id, artifact_id, source_path, filename),
    do: store_copy(world_id, artifact_id, source_path, filename)

  @doc """
  Builds an opaque local artifact storage reference.

  ## Examples

      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> artifact_id = "22222222-2222-4222-8222-222222222222"
      iex> {:ok, ref} = LemmingsOs.Artifacts.LocalStorage.build_storage_ref(world_id, artifact_id, "summary.md")
      iex> ref
      "local://artifacts/11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/summary.md"
  """
  @spec build_storage_ref(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def build_storage_ref(world_id, artifact_id, filename)
      when is_binary(world_id) and is_binary(artifact_id) and is_binary(filename) do
    with :ok <- validate_world_id(world_id),
         :ok <- validate_artifact_id(artifact_id),
         :ok <- validate_filename(filename) do
      {:ok, "#{@storage_scheme}://#{@storage_host}/#{world_id}/#{artifact_id}/#{filename}"}
    end
  end

  def build_storage_ref(_world_id, _artifact_id, _filename), do: {:error, :invalid_storage_ref}

  @doc """
  Resolves a trusted storage reference into an absolute filesystem path.

  This function is for internal runtime use only.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :artifact_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_local_storage_doctest_resolve")
      iex> world_id = "11111111-1111-4111-8111-111111111111"
      iex> artifact_id = "22222222-2222-4222-8222-222222222222"
      iex> File.rm_rf!(root)
      iex> File.mkdir_p!(Path.join([root, world_id, artifact_id]))
      iex> Application.put_env(:lemmings_os, :artifact_storage, backend: :local, root_path: root)
      iex> ref = "local://artifacts/\#{world_id}/\#{artifact_id}/summary.md"
      iex> {:ok, path} = LemmingsOs.Artifacts.LocalStorage.resolve_storage_ref(ref)
      iex> path == Path.join([Path.expand(root), world_id, artifact_id, "summary.md"])
      true
      iex> File.rm_rf!(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :artifact_storage, old_storage), else: Application.delete_env(:lemmings_os, :artifact_storage)
      :ok
  """
  @spec resolve_storage_ref(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def resolve_storage_ref(storage_ref) when is_binary(storage_ref) do
    with {:ok, world_id, artifact_id, filename} <- parse_storage_ref(storage_ref),
         root <- root_path(),
         :ok <- validate_storage_root_available(root),
         relative_path <- Path.join([world_id, artifact_id, filename]),
         absolute_path <- Path.expand(relative_path, root),
         :ok <- validate_within_root(absolute_path, root),
         :ok <- validate_no_symlink_components(root, relative_path) do
      {:ok, absolute_path}
    end
  end

  def resolve_storage_ref(_storage_ref), do: {:error, :invalid_storage_ref}

  @impl true
  @doc """
  Behaviour callback for resolving a trusted storage reference into an internal path.
  """
  @spec path_for(String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def path_for(storage_ref, _opts \\ []), do: resolve_storage_ref(storage_ref)

  @impl true
  @doc """
  Behaviour callback for checking whether the managed file exists for a trusted ref.
  """
  @spec exists?(String.t(), keyword()) :: {:ok, boolean()} | {:error, atom()}
  def exists?(storage_ref, _opts \\ []) do
    with {:ok, path} <- resolve_storage_ref(storage_ref) do
      {:ok, File.regular?(path)}
    end
  end

  @impl true
  @doc """
  Behaviour callback for opening a managed file after scope/status checks.
  """
  @spec open(String.t(), keyword()) ::
          {:ok,
           %{
             path: String.t(),
             filename: String.t(),
             content_type: String.t(),
             size_bytes: non_neg_integer()
           }}
          | {:error, atom() | {atom(), term()}}
  def open(storage_ref, opts \\ []) do
    filename = Keyword.get(opts, :filename, "artifact.bin")
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    metadata = storage_ref_metadata(storage_ref, %{operation: :open, filename: filename})

    instrument_open(metadata, fn ->
      with {:ok, path} <- resolve_storage_ref(storage_ref),
           true <- File.regular?(path) or {:error, :not_found},
           {:ok, size_bytes} <- size_bytes(path) do
        {:ok,
         %{path: path, filename: filename, content_type: content_type, size_bytes: size_bytes}}
      end
    end)
  end

  @doc """
  Returns the configured artifact storage root path.

  ## Examples

      iex> old_storage = Application.get_env(:lemmings_os, :artifact_storage)
      iex> root = Path.join(System.tmp_dir!(), "lemmings_local_storage_doctest_root")
      iex> Application.put_env(:lemmings_os, :artifact_storage, backend: :local, root_path: root)
      iex> LemmingsOs.Artifacts.LocalStorage.root_path()
      Path.expand(root)
      iex> if old_storage, do: Application.put_env(:lemmings_os, :artifact_storage, old_storage), else: Application.delete_env(:lemmings_os, :artifact_storage)
      :ok
  """
  @spec root_path() :: String.t()
  def root_path do
    :lemmings_os
    |> Application.get_env(:artifact_storage, [])
    |> Keyword.get(:root_path, Path.expand("priv/runtime/storage", File.cwd!()))
    |> Path.expand()
  end

  @doc """
  Returns the configured max artifact file size in bytes.
  """
  @spec max_file_size_bytes() :: pos_integer()
  def max_file_size_bytes do
    :lemmings_os
    |> Application.get_env(:artifact_storage, [])
    |> Keyword.get(:max_file_size_bytes, @default_max_file_size_bytes)
  end

  @impl true
  @doc """
  Behaviour callback that verifies the storage root is available.
  """
  @spec health_check(keyword()) :: :ok | {:error, atom()}
  def health_check(_opts \\ []) do
    root = root_path()

    instrument_health_check(%{operation: :health_check}, fn ->
      with :ok <- ensure_storage_root(root),
           {:ok, temp_file_path} <- create_health_check_file(root) do
        delete_health_check_file(temp_file_path)
      end
    end)
  end

  defp instrument_write(metadata, fun) do
    start_time = System.monotonic_time()
    emit_telemetry([:lemmings_os, :artifact_storage, :write, :start], %{count: 1}, metadata)

    case fun.() do
      {:ok, stored} ->
        duration_ms = duration_ms(start_time)

        success_metadata =
          Map.merge(metadata, %{
            checksum: stored.checksum,
            size_bytes: stored.size_bytes,
            status: :ok
          })

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :write, :stop],
          %{count: 1, duration_ms: duration_ms, size_bytes: stored.size_bytes},
          success_metadata
        )

        Logger.info("artifact storage write succeeded",
          event: "artifact.storage.write.succeeded",
          operation: Map.get(metadata, :operation),
          world_id: Map.get(metadata, :world_id),
          artifact_id: Map.get(metadata, :artifact_id),
          filename: Map.get(metadata, :filename),
          size_bytes: stored.size_bytes,
          checksum: stored.checksum
        )

        {:ok, stored}

      {:error, reason} ->
        duration_ms = duration_ms(start_time)
        failure_metadata = Map.merge(metadata, %{reason: reason_token(reason), status: :error})

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :write, :exception],
          %{count: 1, duration_ms: duration_ms},
          failure_metadata
        )

        Logger.warning("artifact storage write failed",
          event: "artifact.storage.write.failed",
          operation: Map.get(metadata, :operation),
          world_id: Map.get(metadata, :world_id),
          artifact_id: Map.get(metadata, :artifact_id),
          filename: Map.get(metadata, :filename),
          reason: reason_token(reason)
        )

        {:error, reason}
    end
  end

  defp instrument_open(metadata, fun) do
    start_time = System.monotonic_time()

    case fun.() do
      {:ok, opened} ->
        duration_ms = duration_ms(start_time)
        success_metadata = Map.merge(metadata, %{size_bytes: opened.size_bytes, status: :ok})

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :open, :stop],
          %{count: 1, duration_ms: duration_ms, size_bytes: opened.size_bytes},
          success_metadata
        )

        Logger.info("artifact storage open succeeded",
          event: "artifact.storage.open.succeeded",
          operation: Map.get(metadata, :operation),
          world_id: Map.get(metadata, :world_id),
          artifact_id: Map.get(metadata, :artifact_id),
          filename: Map.get(metadata, :filename),
          size_bytes: opened.size_bytes
        )

        {:ok, opened}

      {:error, reason} ->
        duration_ms = duration_ms(start_time)
        failure_metadata = Map.merge(metadata, %{reason: reason_token(reason), status: :error})

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :open, :exception],
          %{count: 1, duration_ms: duration_ms},
          failure_metadata
        )

        Logger.warning("artifact storage open failed",
          event: "artifact.storage.open.failed",
          operation: Map.get(metadata, :operation),
          world_id: Map.get(metadata, :world_id),
          artifact_id: Map.get(metadata, :artifact_id),
          filename: Map.get(metadata, :filename),
          reason: reason_token(reason)
        )

        {:error, reason}
    end
  end

  defp instrument_health_check(metadata, fun) do
    start_time = System.monotonic_time()

    case fun.() do
      :ok ->
        duration_ms = duration_ms(start_time)
        success_metadata = Map.put(metadata, :status, :ok)

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :health_check, :stop],
          %{count: 1, duration_ms: duration_ms},
          success_metadata
        )

        Logger.info("artifact storage health check succeeded",
          event: "artifact.storage.health_check.succeeded",
          operation: :health_check
        )

        :ok

      {:error, reason} ->
        duration_ms = duration_ms(start_time)
        failure_metadata = Map.merge(metadata, %{reason: reason_token(reason), status: :error})

        emit_telemetry(
          [:lemmings_os, :artifact_storage, :health_check, :exception],
          %{count: 1, duration_ms: duration_ms},
          failure_metadata
        )

        Logger.warning("artifact storage health check failed",
          event: "artifact.storage.health_check.failed",
          operation: :health_check,
          reason: reason_token(reason)
        )

        {:error, reason}
    end
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp duration_ms(start_time) do
    (System.monotonic_time() - start_time)
    |> System.convert_time_unit(:native, :millisecond)
  end

  defp storage_metadata(world_id, artifact_id, filename, extra) do
    %{
      world_id: world_id,
      artifact_id: artifact_id,
      filename: filename
    }
    |> Map.merge(extra)
    |> Map.update(:filename, nil, &safe_metadata_string/1)
  end

  defp storage_ref_metadata(storage_ref, extra) when is_binary(storage_ref) do
    case parse_storage_ref(storage_ref) do
      {:ok, world_id, artifact_id, filename} ->
        storage_metadata(world_id, artifact_id, filename, extra)

      {:error, _reason} ->
        %{
          world_id: nil,
          artifact_id: nil,
          filename: safe_metadata_string(Map.get(extra, :filename)),
          operation: Map.get(extra, :operation)
        }
    end
  end

  defp storage_ref_metadata(_storage_ref, extra) do
    %{
      world_id: nil,
      artifact_id: nil,
      filename: safe_metadata_string(Map.get(extra, :filename)),
      operation: Map.get(extra, :operation)
    }
  end

  defp reason_token(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_token({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_token(_reason), do: "storage_error"

  defp safe_metadata_string(value) when is_binary(value) do
    value
    |> String.replace(~r/[\x00-\x1F\x7F]/, "")
    |> String.replace("/", "")
    |> String.replace("\\", "")
    |> String.slice(0, 255)
  end

  defp safe_metadata_string(_value), do: nil

  defp parse_storage_ref(storage_ref) do
    uri = URI.parse(storage_ref)

    with :ok <- validate_uri_shape(uri),
         [world_id, artifact_id, filename] <- path_segments(uri.path),
         :ok <- validate_world_id(world_id),
         :ok <- validate_artifact_id(artifact_id),
         :ok <- validate_filename(filename) do
      {:ok, world_id, artifact_id, filename}
    else
      _error -> {:error, :invalid_storage_ref}
    end
  end

  defp path_segments(nil), do: []

  defp path_segments(path) do
    path
    |> String.trim_leading("/")
    |> Path.split()
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

  defp validate_artifact_id(artifact_id) do
    case Ecto.UUID.cast(artifact_id) do
      {:ok, _uuid} -> :ok
      :error -> {:error, :invalid_artifact_id}
    end
  end

  defp validate_filename(""), do: {:error, :invalid_filename}
  defp validate_filename("."), do: {:error, :invalid_filename}
  defp validate_filename(".."), do: {:error, :invalid_filename}

  defp validate_filename(filename) do
    with :ok <- validate_filename_bytes(filename) do
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
    case File.stat(root_path) do
      {:ok, %File.Stat{type: :directory}} -> set_directory_permissions(root_path)
      {:ok, _stat} -> {:error, :storage_unavailable}
      {:error, :enoent} -> ensure_storage_directory(root_path)
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp validate_storage_root_available(root_path) do
    case File.stat(root_path) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, _stat} -> {:error, :storage_unavailable}
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
    walk_symlink_components(
      Path.expand(root_path),
      Path.split(relative_path)
    )
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

  defp ensure_storage_directory(path) do
    case File.mkdir_p(path) do
      :ok -> set_directory_permissions(path)
      {:error, _reason} -> {:error, :storage_unavailable}
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
            _ = File.close(source_device)
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
          _ = File.close(temp_device)
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

  defp create_health_check_file(root_path) do
    temp_file_path =
      Path.join(
        root_path,
        ".storage-healthcheck-#{System.unique_integer([:positive, :monotonic])}"
      )

    with :ok <- File.write(temp_file_path, "ok", [:write, :exclusive]),
         :ok <- set_file_permissions(temp_file_path) do
      {:ok, temp_file_path}
    else
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp delete_health_check_file(temp_file_path) do
    case File.rm(temp_file_path) do
      :ok -> :ok
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp size_bytes(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when is_integer(size) and size >= 0 -> {:ok, size}
      {:ok, _stat} -> {:error, :invalid_file_size}
      {:error, reason} -> {:error, {:size_failed, reason}}
    end
  end

  defp checksum(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} ->
        digest =
          Enum.reduce(IO.binstream(device, 65_536), :crypto.hash_init(:sha256), fn chunk, acc ->
            :crypto.hash_update(acc, chunk)
          end)
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)

        :ok = File.close(device)
        {:ok, digest}

      {:error, reason} ->
        {:error, {:checksum_failed, reason}}
    end
  end
end
