defmodule LemmingsOs.Knowledge.SourceFiles.ToolsRunner.SystemExecutor do
  @moduledoc false

  @spec run(String.t(), [String.t()], pos_integer()) ::
          {:ok, %{stdout: String.t(), exit_status: integer()}} | {:error, atom()}
  # sobelow_skip ["CI.System"]
  def run(command, args, timeout_ms)
      when is_binary(command) and is_list(args) and is_integer(timeout_ms) and timeout_ms > 0 do
    task =
      Task.async(fn ->
        System.cmd(command, args, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {stdout, exit_status}} ->
        {:ok, %{stdout: stdout || "", exit_status: exit_status}}

      nil ->
        {:error, :timeout}
    end
  rescue
    ErlangError -> {:error, :command_not_found}
  end
end
