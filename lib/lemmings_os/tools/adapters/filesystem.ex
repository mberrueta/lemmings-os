defmodule LemmingsOs.Tools.Adapters.Filesystem do
  @moduledoc """
  Filesystem adapters for Tool Runtime MVP.
  """

  alias LemmingsOs.LemmingInstances.LemmingInstance

  @type success_result :: %{
          summary: String.t(),
          preview: String.t() | nil,
          result: map()
        }

  @type error_result :: %{
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @doc """
  Executes the `fs.read_text_file` adapter.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   department_id: "department-1",
      ...>   lemming_id: "lemming-1"
      ...> }
      iex> LemmingsOs.Tools.Adapters.Filesystem.read_text_file(instance, %{"path" => "notes.txt"})
      {:error, %{code: "tool.fs.not_found", details: %{path: "notes.txt"}, message: "File not found"}}
  """
  @spec read_text_file(LemmingInstance.t(), map()) ::
          {:ok, success_result()} | {:error, error_result()}
  def read_text_file(%LemmingInstance{} = instance, args) when is_map(args) do
    with {:ok, relative_path} <- validate_read_args(args),
         {:ok, %{absolute_path: absolute_path, workspace_path: workspace_path}} <-
           resolve_workspace_path(instance, relative_path),
         {:ok, content} <- read_utf8_file(absolute_path) do
      {:ok,
       %{
         summary: "Read file #{workspace_path}",
         preview: String.slice(content, 0, 280),
         result: %{
           path: workspace_path,
           content: content,
           bytes: byte_size(content)
         }
       }}
    end
  end

  @doc """
  Executes the `fs.write_text_file` adapter.

  ## Examples

      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   department_id: "department-1",
      ...>   lemming_id: "lemming-1"
      ...> }
      iex> LemmingsOs.Tools.Adapters.Filesystem.write_text_file(instance, %{"path" => "notes.txt", "content" => "hello"})
      {:ok,
      %{result: %{bytes: 5,
  path: "/workspace/department-1/lemming-1/notes.txt"},
  summary: "Wrote file /workspace/department-1/lemming-1/notes.txt", preview: "hello"}}
  """
  @spec write_text_file(LemmingInstance.t(), map()) ::
          {:ok, success_result()} | {:error, error_result()}
  def write_text_file(%LemmingInstance{} = instance, args) when is_map(args) do
    with {:ok, {relative_path, content}} <- validate_write_args(args),
         {:ok, %{absolute_path: absolute_path, workspace_path: workspace_path}} <-
           resolve_workspace_path(instance, relative_path),
         :ok <- ensure_parent_directory(absolute_path),
         :ok <- write_utf8_file(absolute_path, content) do
      {:ok,
       %{
         summary: "Wrote file #{workspace_path}",
         preview: String.slice(content, 0, 280),
         result: %{
           path: workspace_path,
           bytes: byte_size(content)
         }
       }}
    end
  end

  defp validate_read_args(%{"path" => path}) when is_binary(path), do: {:ok, path}
  defp validate_read_args(%{path: path}) when is_binary(path), do: {:ok, path}

  defp validate_read_args(_args) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{required: ["path"]}
     }}
  end

  defp validate_write_args(%{"path" => path, "content" => content})
       when is_binary(path) and is_binary(content),
       do: {:ok, {path, content}}

  defp validate_write_args(%{path: path, content: content})
       when is_binary(path) and is_binary(content),
       do: {:ok, {path, content}}

  defp validate_write_args(_args) do
    {:error,
     %{
       code: "tool.validation.invalid_args",
       message: "Invalid tool arguments",
       details: %{required: ["path", "content"]}
     }}
  end

  defp resolve_workspace_path(
         %LemmingInstance{department_id: department_id, lemming_id: lemming_id},
         relative_path
       )
       when is_binary(department_id) and is_binary(lemming_id) and is_binary(relative_path) do
    with :ok <- validate_relative_path(relative_path) do
      workspace_root = workspace_root()
      work_area_root = Path.join([workspace_root, department_id, lemming_id])
      absolute_path = Path.expand(relative_path, work_area_root)

      if path_within_root?(absolute_path, work_area_root) do
        workspace_path =
          Path.join([
            "/workspace",
            department_id,
            lemming_id,
            Path.relative_to(absolute_path, work_area_root)
          ])

        {:ok, %{absolute_path: absolute_path, workspace_path: workspace_path}}
      else
        {:error,
         %{
           code: "tool.fs.path_outside_workspace",
           message: "Path escapes workspace boundary",
           details: %{path: relative_path}
         }}
      end
    end
  end

  defp resolve_workspace_path(_instance, _relative_path) do
    {:error,
     %{
       code: "tool.fs.invalid_instance_scope",
       message: "Instance scope is incomplete",
       details: %{}
     }}
  end

  defp validate_relative_path(path) when is_binary(path) do
    cond do
      path == "" ->
        {:error,
         %{
           code: "tool.validation.invalid_args",
           message: "Invalid tool arguments",
           details: %{field: "path"}
         }}

      Path.type(path) == :absolute ->
        {:error,
         %{
           code: "tool.fs.path_must_be_relative",
           message: "Path must be workspace-relative",
           details: %{path: path}
         }}

      true ->
        :ok
    end
  end

  defp path_within_root?(absolute_path, root_path)
       when is_binary(absolute_path) and is_binary(root_path) do
    normalized_absolute = Path.expand(absolute_path)
    normalized_root = Path.expand(root_path)

    normalized_absolute == normalized_root or
      String.starts_with?(normalized_absolute, normalized_root <> "/")
  end

  defp read_utf8_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} when is_binary(content) ->
        {:ok, content}

      {:error, :enoent} ->
        {:error,
         %{
           code: "tool.fs.not_found",
           message: "File not found",
           details: %{path: Path.basename(path)}
         }}

      {:error, reason} ->
        {:error,
         %{
           code: "tool.fs.read_failed",
           message: "Could not read file",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp ensure_parent_directory(path) when is_binary(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.fs.write_failed",
           message: "Could not prepare target directory",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp write_utf8_file(path, content) when is_binary(path) and is_binary(content) do
    case File.write(path, content) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           code: "tool.fs.write_failed",
           message: "Could not write file",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp workspace_root do
    Application.get_env(
      :lemmings_os,
      :runtime_workspace_root,
      Path.expand("../../../priv/runtime/workspace", __DIR__)
    )
  end
end
