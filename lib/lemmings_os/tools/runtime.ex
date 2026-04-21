defmodule LemmingsOs.Tools.Runtime do
  @moduledoc """
  Tool Runtime execution boundary for the MVP catalog.
  """

  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Filesystem
  alias LemmingsOs.Tools.Adapters.Web
  alias LemmingsOs.Tools.Catalog
  alias LemmingsOs.Worlds.World

  @type success :: %{
          tool_name: String.t(),
          args: map(),
          summary: String.t(),
          preview: String.t() | nil,
          result: map()
        }

  @type error :: %{
          tool_name: String.t() | nil,
          code: String.t(),
          message: String.t(),
          details: map()
        }

  @doc """
  Executes one tool call for a World-scoped runtime instance.

  ## Examples

      iex> world = %LemmingsOs.Worlds.World{id: "world-1"}
      iex> instance = %LemmingsOs.LemmingInstances.LemmingInstance{
      ...>   world_id: "world-1",
      ...>   department_id: "department-1",
      ...>   lemming_id: "lemming-1"
      ...> }
      iex> LemmingsOs.Tools.Runtime.execute(world, instance, "exec.run", %{})
      {:error, %{tool_name: "exec.run", code: "tool.unsupported",
  details: %{tool_name: "exec.run"}, message: "Tool is not supported"}}
  """
  @spec execute(World.t(), LemmingInstance.t(), String.t(), map()) ::
          {:ok, success()} | {:error, error()}
  def execute(world, instance, tool_name, args)

  def execute(
        %World{id: world_id},
        %LemmingInstance{world_id: world_id} = instance,
        tool_name,
        args
      )
      when is_binary(tool_name) and is_map(args) do
    if Catalog.supported_tool?(tool_name) do
      dispatch_tool_call(instance, tool_name, args)
    else
      {:error,
       %{
         tool_name: tool_name,
         code: "tool.unsupported",
         message: "Tool is not supported",
         details: %{tool_name: tool_name}
       }}
    end
  end

  def execute(%World{}, %LemmingInstance{}, tool_name, _args) when is_binary(tool_name) do
    {:error,
     %{
       tool_name: tool_name,
       code: "tool.invalid_scope",
       message: "World scope does not match instance scope",
       details: %{}
     }}
  end

  def execute(%World{}, %LemmingInstance{}, tool_name, _args) do
    {:error,
     %{
       tool_name: nil,
       code: "tool.validation.invalid_call",
       message: "Invalid tool runtime call",
       details: %{tool_name: tool_name}
     }}
  end

  defp dispatch_tool_call(instance, "fs.read_text_file", args) do
    normalize_tool_result("fs.read_text_file", args, Filesystem.read_text_file(instance, args))
  end

  defp dispatch_tool_call(instance, "fs.write_text_file", args) do
    normalize_tool_result("fs.write_text_file", args, Filesystem.write_text_file(instance, args))
  end

  defp dispatch_tool_call(_instance, "web.search", args) do
    normalize_tool_result("web.search", args, Web.search(args))
  end

  defp dispatch_tool_call(_instance, "web.fetch", args) do
    normalize_tool_result("web.fetch", args, Web.fetch(args))
  end

  defp normalize_tool_result(
         tool_name,
         args,
         {:ok, %{summary: summary, preview: preview, result: result}}
       )
       when is_map(args) and is_binary(summary) and is_map(result) do
    {:ok,
     %{
       tool_name: tool_name,
       args: args,
       summary: summary,
       preview: preview,
       result: result
     }}
  end

  defp normalize_tool_result(tool_name, _args, {:error, %{code: code, message: message} = error})
       when is_binary(code) and is_binary(message) do
    {:error,
     %{
       tool_name: tool_name,
       code: code,
       message: message,
       details: Map.get(error, :details, %{})
     }}
  end
end
