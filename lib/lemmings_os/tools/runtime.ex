defmodule LemmingsOs.Tools.Runtime do
  @moduledoc """
  Tool Runtime execution boundary for the MVP catalog.
  """

  alias LemmingsOs.Tools.Adapters.Documents
  alias LemmingsOs.Tools.Adapters.Knowledge
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.Tools.Adapters.Filesystem
  alias LemmingsOs.Tools.Adapters.Web
  alias LemmingsOs.Tools.Catalog
  alias LemmingsOs.Worlds.World

  @trusted_tool_config_env :tools_runtime_trusted_config

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

  def execute(world, instance, tool_name, args) do
    execute(world, instance, tool_name, args, %{})
  end

  @spec execute(World.t(), LemmingInstance.t(), String.t(), map(), map()) ::
          {:ok, success()} | {:error, error()}
  def execute(world, instance, tool_name, args, runtime_meta)

  def execute(
        %World{id: world_id} = world,
        %LemmingInstance{world_id: world_id} = instance,
        tool_name,
        args,
        runtime_meta
      )
      when is_binary(tool_name) and is_map(args) and is_map(runtime_meta) do
    if Catalog.supported_tool?(tool_name) do
      trusted_config = trusted_tool_config(tool_name, runtime_meta)
      dispatch_tool_call(world, instance, tool_name, args, runtime_meta, trusted_config)
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

  def execute(%World{}, %LemmingInstance{}, tool_name, _args, _runtime_meta)
      when is_binary(tool_name) do
    {:error,
     %{
       tool_name: tool_name,
       code: "tool.invalid_scope",
       message: "World scope does not match instance scope",
       details: %{}
     }}
  end

  def execute(%World{}, %LemmingInstance{}, tool_name, _args, _runtime_meta) do
    {:error,
     %{
       tool_name: nil,
       code: "tool.validation.invalid_call",
       message: "Invalid tool runtime call",
       details: %{tool_name: tool_name}
     }}
  end

  defp dispatch_tool_call(
         _world,
         instance,
         "fs.read_text_file",
         args,
         runtime_meta,
         _trusted_config
       ) do
    normalize_tool_result(
      "fs.read_text_file",
      args,
      Filesystem.read_text_file(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(
         _world,
         instance,
         "fs.write_text_file",
         args,
         runtime_meta,
         _trusted_config
       ) do
    normalize_tool_result(
      "fs.write_text_file",
      args,
      Filesystem.write_text_file(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(world, instance, "web.search", args, _runtime_meta, trusted_config) do
    normalize_tool_result("web.search", args, Web.search(world, instance, args, trusted_config))
  end

  defp dispatch_tool_call(world, instance, "web.fetch", args, _runtime_meta, trusted_config) do
    normalize_tool_result("web.fetch", args, Web.fetch(world, instance, args, trusted_config))
  end

  defp dispatch_tool_call(
         _world,
         instance,
         "knowledge.store",
         args,
         runtime_meta,
         _trusted_config
       ) do
    normalize_tool_result(
      "knowledge.store",
      args,
      Knowledge.store_memory(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(
         _world,
         instance,
         "documents.markdown_to_html",
         args,
         runtime_meta,
         _trusted_config
       ) do
    normalize_tool_result(
      "documents.markdown_to_html",
      args,
      Documents.markdown_to_html(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(
         _world,
         instance,
         "documents.print_to_pdf",
         args,
         runtime_meta,
         _trusted_config
       ) do
    normalize_tool_result(
      "documents.print_to_pdf",
      args,
      Documents.print_to_pdf(instance, args, runtime_meta)
    )
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

  defp trusted_tool_config(tool_name, runtime_meta)
       when is_binary(tool_name) and is_map(runtime_meta) do
    app_config =
      trusted_tool_config_map(Application.get_env(:lemmings_os, @trusted_tool_config_env, %{}))

    runtime_config = runtime_tool_config(runtime_meta)
    merged = Map.merge(app_config, runtime_config)
    Map.get(merged, tool_name, %{})
  end

  defp trusted_tool_config_map(config) when is_map(config) do
    Map.new(config, fn {key, value} -> {to_string(key), normalize_tool_config(value)} end)
  end

  defp trusted_tool_config_map(_config), do: %{}

  defp runtime_tool_config(%{trusted_tool_config: config}), do: trusted_tool_config_map(config)

  defp runtime_tool_config(%{"trusted_tool_config" => config}),
    do: trusted_tool_config_map(config)

  defp runtime_tool_config(_runtime_meta), do: %{}

  defp normalize_tool_config(config) when is_map(config), do: config
  defp normalize_tool_config(_config), do: %{}
end
