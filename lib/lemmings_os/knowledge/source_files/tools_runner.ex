defmodule LemmingsOs.Knowledge.SourceFiles.ToolsRunner do
  @moduledoc """
  Controlled CLI capability runner for source-file extraction.

  Commands are invoked only through configured named capabilities.
  Raw shell strings are never executed.
  """

  @type run_result :: {:ok, %{stdout: String.t(), exit_status: integer()}} | {:error, atom()}

  @default_timeout_ms 30_000

  @spec run_capability(atom(), [String.t()], keyword()) :: run_result()
  def run_capability(capability, args, opts \\ [])

  def run_capability(capability, args, opts) when is_atom(capability) and is_list(args) do
    with :ok <- validate_args(args),
         {:ok, command} <- capability_command(capability),
         timeout_ms <- timeout_ms(opts),
         executor <- executor_module(),
         {:ok, result} <- executor.run(command, args, timeout_ms) do
      {:ok, %{stdout: result.stdout || "", exit_status: result.exit_status}}
    else
      {:error, :unsupported_capability} -> {:error, :unsupported_capability}
      {:error, :invalid_args} -> {:error, :invalid_args}
      {:error, :timeout} -> {:error, :timeout}
      {:error, :command_not_found} -> {:error, :command_not_found}
      {:error, _reason} -> {:error, :runner_failed}
    end
  end

  def run_capability(_capability, _args, _opts), do: {:error, :invalid_args}

  defp validate_args(args) do
    if Enum.all?(args, &(is_binary(&1) and byte_size(&1) > 0)),
      do: :ok,
      else: {:error, :invalid_args}
  end

  defp capability_command(capability) do
    capabilities =
      Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      |> Keyword.get(:capabilities, %{})

    case Map.get(capabilities, capability) do
      command when is_binary(command) and byte_size(command) > 0 -> {:ok, command}
      _other -> {:error, :unsupported_capability}
    end
  end

  defp timeout_ms(opts) do
    configured =
      Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
      |> Keyword.get(:timeout_ms, @default_timeout_ms)

    case Keyword.get(opts, :timeout_ms, configured) do
      value when is_integer(value) and value > 0 -> value
      _other -> @default_timeout_ms
    end
  end

  defp executor_module do
    Application.get_env(:lemmings_os, :knowledge_tools_runner, [])
    |> Keyword.get(:executor_module, LemmingsOs.Knowledge.SourceFiles.ToolsRunner.SystemExecutor)
  end
end
