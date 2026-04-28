defmodule LemmingsOs.Tools.Runtime do
  @moduledoc """
  Tool Runtime execution boundary for the MVP catalog.
  """

  alias LemmingsOs.Lemmings.Lemming
  alias LemmingsOs.LemmingInstances.LemmingInstance
  alias LemmingsOs.SecretBank
  alias LemmingsOs.Tools.Adapters.Filesystem
  alias LemmingsOs.Tools.Adapters.Web
  alias LemmingsOs.Tools.Catalog
  alias LemmingsOs.Worlds.World

  @secret_prefix "$secrets."
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
      with {:ok, trusted_config} <-
             resolve_trusted_tool_config(world, instance, tool_name, runtime_meta) do
        dispatch_tool_call(instance, tool_name, args, runtime_meta, trusted_config)
      end
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

  defp dispatch_tool_call(instance, "fs.read_text_file", args, runtime_meta, _trusted_config) do
    normalize_tool_result(
      "fs.read_text_file",
      args,
      Filesystem.read_text_file(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(instance, "fs.write_text_file", args, runtime_meta, _trusted_config) do
    normalize_tool_result(
      "fs.write_text_file",
      args,
      Filesystem.write_text_file(instance, args, runtime_meta)
    )
  end

  defp dispatch_tool_call(_instance, "web.search", args, _runtime_meta, trusted_config) do
    normalize_tool_result("web.search", args, Web.search(args, trusted_config))
  end

  defp dispatch_tool_call(_instance, "web.fetch", args, _runtime_meta, trusted_config) do
    normalize_tool_result("web.fetch", args, Web.fetch(args, trusted_config))
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

  defp resolve_trusted_tool_config(world, instance, tool_name, runtime_meta) do
    trusted_config = trusted_tool_config(tool_name, runtime_meta)

    case trusted_tool_config_contains_secret_ref?(trusted_config) do
      true ->
        with {:ok, scope} <- runtime_scope(world, instance) do
          resolve_secret_refs(tool_name, scope, trusted_config)
        end

      false ->
        {:ok, trusted_config}
    end
  end

  defp runtime_scope(
         %World{id: world_id},
         %LemmingInstance{
           lemming_id: lemming_id,
           city_id: city_id,
           department_id: department_id
         }
       )
       when is_binary(world_id) and is_binary(lemming_id) and is_binary(city_id) and
              is_binary(department_id) do
    {:ok,
     %Lemming{
       id: lemming_id,
       world_id: world_id,
       city_id: city_id,
       department_id: department_id
     }}
  end

  defp runtime_scope(_world, _instance), do: {:error, :invalid_scope}

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

  defp trusted_tool_config_contains_secret_ref?(value) when is_map(value) do
    Enum.any?(value, fn {_key, nested_value} ->
      trusted_tool_config_contains_secret_ref?(nested_value)
    end)
  end

  defp trusted_tool_config_contains_secret_ref?(values) when is_list(values) do
    Enum.any?(values, &trusted_tool_config_contains_secret_ref?/1)
  end

  defp trusted_tool_config_contains_secret_ref?(value) when is_binary(value),
    do: String.starts_with?(value, @secret_prefix)

  defp trusted_tool_config_contains_secret_ref?(_value), do: false

  defp resolve_secret_refs(tool_name, scope, value) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, nested_value}, {:ok, acc} ->
      case resolve_secret_refs(tool_name, scope, nested_value) do
        {:ok, resolved_value} -> {:cont, {:ok, Map.put(acc, key, resolved_value)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp resolve_secret_refs(tool_name, scope, values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case resolve_secret_refs(tool_name, scope, value) do
        {:ok, resolved_value} -> {:cont, {:ok, acc ++ [resolved_value]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp resolve_secret_refs(tool_name, scope, value) when is_binary(value) do
    case String.starts_with?(value, @secret_prefix) do
      true ->
        case SecretBank.resolve_runtime_secret(scope, value, tool_name: tool_name) do
          {:ok, %{value: secret_value}} when is_binary(secret_value) ->
            {:ok, secret_value}

          {:error, reason} ->
            {:error, secret_resolution_error(tool_name, scope, value, reason)}
        end

      false ->
        {:ok, value}
    end
  end

  defp resolve_secret_refs(_tool_name, _scope, value), do: {:ok, value}

  defp secret_resolution_error(tool_name, scope, secret_ref, reason) do
    {code, message} = secret_resolution_error_code(reason)

    %{
      tool_name: tool_name,
      code: code,
      message: message,
      details: %{
        secret_ref: secret_ref,
        bank_key: normalize_secret_ref(secret_ref),
        requested_scope: requested_scope(scope),
        reason: secret_resolution_reason(reason)
      }
    }
  end

  defp secret_resolution_error_code(:missing_secret),
    do: {"tool.secret.missing", "Tool secret is not configured"}

  defp secret_resolution_error_code(:invalid_key),
    do: {"tool.secret.invalid_reference", "Tool secret reference is invalid"}

  defp secret_resolution_error_code(:invalid_scope),
    do: {"tool.secret.invalid_scope", "Tool secret scope is invalid"}

  defp secret_resolution_error_code(:decrypt_failed),
    do: {"tool.secret.decrypt_failed", "Tool secret could not be decrypted"}

  defp secret_resolution_reason(reason), do: Atom.to_string(reason)

  defp requested_scope(%Lemming{} = scope) do
    %{
      world_id: scope.world_id,
      city_id: scope.city_id,
      department_id: scope.department_id,
      lemming_id: scope.id
    }
  end

  defp normalize_secret_ref(secret_ref) when is_binary(secret_ref) do
    String.replace_prefix(secret_ref, @secret_prefix, "")
  end
end
