defmodule LemmingsOs.Tools.WorkArea do
  @moduledoc """
  Runtime-only shared WorkArea path handling for filesystem tools.
  """

  require Logger

  @type resolved_path :: %{
          absolute_path: String.t(),
          relative_path: String.t(),
          root_path: String.t()
        }

  @doc """
  Best-effort creation of the shared WorkArea directory.

  ## Examples

      iex> old_path = Application.get_env(:lemmings_os, :work_areas_path)
      iex> path = Path.join(System.tmp_dir!(), "lemmings_work_area_doctest_ensure")
      iex> Application.put_env(:lemmings_os, :work_areas_path, path)
      iex> :ok = LemmingsOs.Tools.WorkArea.ensure("instance-1")
      iex> File.rm_rf!(path)
      iex> if old_path, do: Application.put_env(:lemmings_os, :work_areas_path, old_path), else: Application.delete_env(:lemmings_os, :work_areas_path)
      :ok
  """
  @spec ensure(String.t()) :: :ok | {:error, term()}
  def ensure(work_area_ref) when is_binary(work_area_ref) and work_area_ref != "" do
    root = root_path(work_area_ref)

    File.mkdir_p(root)
  end

  def ensure(_work_area_ref), do: {:error, :invalid_work_area_ref}

  @doc """
  Resolves a safe WorkArea-relative path.

  ## Examples

      iex> old_path = Application.get_env(:lemmings_os, :work_areas_path)
      iex> path = Path.join(System.tmp_dir!(), "lemmings_work_area_doctest_resolve")
      iex> Application.put_env(:lemmings_os, :work_areas_path, path)
      iex> :ok = LemmingsOs.Tools.WorkArea.ensure("instance-1")
      iex> {:ok, resolved} = LemmingsOs.Tools.WorkArea.resolve("instance-1", "scratch/notes.txt")
      iex> resolved.relative_path
      "scratch/notes.txt"
      iex> File.rm_rf!(path)
      iex> if old_path, do: Application.put_env(:lemmings_os, :work_areas_path, old_path), else: Application.delete_env(:lemmings_os, :work_areas_path)
      :ok

      iex> LemmingsOs.Tools.WorkArea.resolve("instance-1", "../secret")
      {:error, :invalid_path}
  """
  @spec resolve(String.t(), String.t()) :: {:ok, resolved_path()} | {:error, atom()}
  def resolve(work_area_ref, relative_path)
      when is_binary(work_area_ref) and is_binary(relative_path) do
    with :ok <- validate_relative_path(relative_path),
         root <- root_path(work_area_ref),
         :ok <- validate_work_area_available(root),
         resolved <- Path.expand(relative_path, root),
         :ok <- validate_within_root(resolved, root),
         normalized_relative_path <- Path.relative_to(resolved, root),
         :ok <- validate_no_symlink_components(root, normalized_relative_path) do
      {:ok,
       %{
         absolute_path: resolved,
         relative_path: normalized_relative_path,
         root_path: root
       }}
    end
  end

  def resolve(_work_area_ref, _relative_path), do: {:error, :invalid_path}

  @doc """
  Returns the absolute WorkArea root for internal runtime use.

  ## Examples

      iex> old_path = Application.get_env(:lemmings_os, :work_areas_path)
      iex> path = Path.join(System.tmp_dir!(), "lemmings_work_area_doctest_root")
      iex> Application.put_env(:lemmings_os, :work_areas_path, path)
      iex> LemmingsOs.Tools.WorkArea.root_path("instance-1") == Path.expand(Path.join(path, "instance-1"))
      true
      iex> if old_path, do: Application.put_env(:lemmings_os, :work_areas_path, old_path), else: Application.delete_env(:lemmings_os, :work_areas_path)
      :ok
  """
  @spec root_path(String.t()) :: String.t()
  def root_path(work_area_ref) when is_binary(work_area_ref) do
    work_areas_path()
    |> Path.expand()
    |> Path.join(work_area_ref)
    |> Path.expand()
  end

  @spec work_areas_path() :: String.t()
  @doc """
  Returns the configured WorkArea storage root.

  ## Examples

      iex> old_path = Application.get_env(:lemmings_os, :work_areas_path)
      iex> path = Path.join(System.tmp_dir!(), "lemmings_work_area_doctest_config")
      iex> Application.put_env(:lemmings_os, :work_areas_path, path)
      iex> LemmingsOs.Tools.WorkArea.work_areas_path()
      Path.join(System.tmp_dir!(), "lemmings_work_area_doctest_config")
      iex> if old_path, do: Application.put_env(:lemmings_os, :work_areas_path, old_path), else: Application.delete_env(:lemmings_os, :work_areas_path)
      :ok
  """
  def work_areas_path do
    Application.get_env(
      :lemmings_os,
      :work_areas_path,
      Path.expand("var/work_areas", File.cwd!())
    )
  end

  @spec log_creation_failure(String.t(), term(), map()) :: :ok
  @doc """
  Emits a warning for best-effort WorkArea creation failures.

  ## Examples

      iex> ExUnit.CaptureLog.capture_log(fn ->
      ...>   LemmingsOs.Tools.WorkArea.log_creation_failure("instance-1", :eacces, %{instance_id: "instance-1"})
      ...> end) =~ "runtime WorkArea could not be created"
      true
  """
  def log_creation_failure(work_area_ref, reason, metadata \\ %{}) do
    Logger.warning(
      "runtime WorkArea could not be created",
      Map.merge(metadata, %{
        event: "instance.work_area.create_failed",
        work_area_ref: work_area_ref,
        reason: inspect(reason)
      })
    )

    :ok
  end

  defp validate_relative_path(path) do
    cond do
      path == "" ->
        {:error, :invalid_path}

      String.contains?(path, <<0>>) ->
        {:error, :invalid_path}

      String.starts_with?(path, "~") ->
        {:error, :invalid_path}

      String.contains?(path, "\\") ->
        {:error, :invalid_path}

      Regex.match?(~r/^[A-Za-z]:/, path) ->
        {:error, :invalid_path}

      Path.type(path) == :absolute ->
        {:error, :invalid_path}

      ".." in Path.split(path) ->
        {:error, :invalid_path}

      true ->
        :ok
    end
  end

  defp validate_work_area_available(root) do
    case File.stat(root) do
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:ok, _stat} -> {:error, :work_area_unavailable}
      {:error, _reason} -> {:error, :work_area_unavailable}
    end
  end

  defp validate_within_root(absolute_path, root_path) do
    normalized_absolute = Path.expand(absolute_path)
    normalized_root = Path.expand(root_path)

    if normalized_absolute == normalized_root or
         String.starts_with?(normalized_absolute, normalized_root <> "/") do
      :ok
    else
      {:error, :invalid_path}
    end
  end

  defp validate_no_symlink_components(root_path, relative_path) do
    validate_no_symlink_components(
      Path.expand(root_path),
      Path.split(relative_path),
      relative_path
    )
  end

  defp validate_no_symlink_components(_current_path, [], _relative_path), do: :ok

  defp validate_no_symlink_components(current_path, [segment | rest], relative_path) do
    next_path = Path.join(current_path, segment)

    case File.lstat(next_path) do
      {:ok, %File.Stat{type: :symlink}} -> {:error, :invalid_path}
      {:ok, _stat} -> validate_no_symlink_components(next_path, rest, relative_path)
      {:error, :enoent} -> :ok
      {:error, _reason} -> :ok
    end
  end
end
