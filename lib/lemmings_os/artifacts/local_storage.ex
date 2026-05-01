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

  @storage_scheme "local"
  @storage_host "artifacts"

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
    with :ok <- validate_world_id(world_id),
         :ok <- validate_artifact_id(artifact_id),
         :ok <- validate_filename(filename),
         {:ok, source_absolute_path} <- validate_source_path(source_path),
         {:ok, storage_ref} <- build_storage_ref(world_id, artifact_id, filename),
         :ok <- ensure_storage_root(root_path()),
         {:ok, destination_path} <- resolve_storage_ref(storage_ref),
         :ok <- File.mkdir_p(Path.dirname(destination_path)),
         :ok <- copy_file(source_absolute_path, destination_path),
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

  def store_copy(_world_id, _artifact_id, _source_path, _filename), do: {:error, :invalid_input}

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
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, _stat} -> {:error, :storage_unavailable}
      {:error, :enoent} -> File.mkdir_p(root_path)
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

  defp copy_file(source, destination) do
    case File.cp(source, destination) do
      :ok -> :ok
      {:error, reason} -> {:error, {:copy_failed, reason}}
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
