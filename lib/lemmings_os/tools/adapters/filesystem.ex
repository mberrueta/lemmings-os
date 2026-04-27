defmodule LemmingsOs.Tools.Adapters.Filesystem do
  @moduledoc """
  Filesystem adapters for Tool Runtime MVP.
  """

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.WorkArea

  @type runtime_meta :: %{
          optional(:actor_instance_id) => String.t(),
          optional(:work_area_ref) => String.t(),
          optional(:world_id) => String.t(),
          optional(:city_id) => String.t(),
          optional(:department_id) => String.t()
        }

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
  """
  @spec read_text_file(LemmingInstance.t(), map(), runtime_meta()) ::
          {:ok, success_result()} | {:error, error_result()}
  def read_text_file(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with {:ok, relative_path} <- validate_read_args(args),
         {:ok, %{absolute_path: absolute_path, relative_path: normalized_relative_path}} <-
           resolve_workspace_path(instance, relative_path, runtime_meta),
         {:ok, content} <- read_utf8_file(absolute_path, normalized_relative_path) do
      {:ok,
       %{
         summary: "Read file #{normalized_relative_path}",
         preview: String.slice(content, 0, 280),
         result: %{
           path: normalized_relative_path,
           content: content,
           bytes: byte_size(content)
         }
       }}
    end
  end

  @doc """
  Executes the `fs.write_text_file` adapter.
  """
  @spec write_text_file(LemmingInstance.t(), map(), runtime_meta()) ::
          {:ok, success_result()} | {:error, error_result()}
  def write_text_file(%LemmingInstance{} = instance, args, runtime_meta \\ %{})
      when is_map(args) and is_map(runtime_meta) do
    with {:ok, {relative_path, content}} <- validate_write_args(args),
         {:ok, %{absolute_path: absolute_path, relative_path: normalized_relative_path}} <-
           resolve_workspace_path(instance, relative_path, runtime_meta),
         :ok <- ensure_parent_directory(absolute_path),
         :ok <- write_utf8_file(absolute_path, content) do
      {:ok,
       %{
         summary: "Wrote file #{normalized_relative_path}",
         preview: String.slice(content, 0, 280),
         result: %{
           path: normalized_relative_path,
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

  defp resolve_workspace_path(%LemmingInstance{} = instance, relative_path, runtime_meta) do
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

  defp read_utf8_file(path, relative_path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} when is_binary(content) ->
        {:ok, content}

      {:error, :enoent} ->
        {:error,
         %{
           code: "tool.fs.not_found",
           message: "File not found",
           details: %{path: relative_path}
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
end
