if Mix.env() == :dev do
  defmodule LemmingsOs.LiveDebuggerSettingsStorage do
    @moduledoc false

    @behaviour LiveDebugger.API.SettingsStorage

    require Logger

    alias LiveDebugger.API.SettingsStorage

    @default_settings %{
      dead_view_mode: true,
      garbage_collection: true,
      debug_button: true,
      tracing_enabled_on_start: true,
      dead_liveviews: false,
      highlight_in_browser: true
    }

    @table_name :lvdbg_settings
    @filename "live_debugger_saved_settings"

    @impl true
    def init() do
      ensure_dets_open()

      SettingsStorage.available_settings()
      |> Enum.each(fn setting ->
        value = Application.get_env(:live_debugger, setting, fetch_setting(setting))
        save(setting, value)
      end)

      :ok
    end

    @impl true
    def save(setting, value) do
      :dets.insert(@table_name, {setting, value})
    end

    @impl true
    def get(setting) do
      fetch_setting(setting)
    end

    @impl true
    def get_all() do
      SettingsStorage.available_settings()
      |> Enum.map(fn setting ->
        {setting, fetch_setting(setting)}
      end)
      |> Enum.into(%{})
    end

    defp ensure_dets_open() do
      case :dets.open_file(@table_name, auto_save: :timer.seconds(1), file: file_path()) do
        {:ok, _table} ->
          :ok

        {:error, {:needs_repair, file}} ->
          repair_and_reopen(file)

        {:error, reason} ->
          Logger.warning("live_debugger settings storage failed to open, recreating file",
            reason: inspect(reason)
          )

          delete_storage_file()
          reopen_storage!()
      end
    end

    defp repair_and_reopen(file) do
      Logger.warning(
        "live_debugger settings storage needs repair, recreating file at #{List.to_string(file)}"
      )

      delete_storage_file()
      reopen_storage!()
    end

    defp reopen_storage!() do
      case :dets.open_file(@table_name, auto_save: :timer.seconds(1), file: file_path()) do
        {:ok, _table} ->
          :ok

        {:error, reason} ->
          raise "failed to open live_debugger settings storage: #{inspect(reason)}"
      end
    end

    defp delete_storage_file() do
      file_path()
      |> List.to_string()
      |> File.rm()

      :ok
    end

    defp fetch_setting(setting) do
      with {:error, :not_saved} <- get_from_dets(setting) do
        @default_settings[setting]
      end
    end

    defp get_from_dets(setting) do
      case :dets.lookup(@table_name, setting) do
        [{^setting, value}] ->
          value

        _ ->
          {:error, :not_saved}
      end
    end

    defp file_path() do
      :live_debugger
      |> Application.app_dir(@filename)
      |> String.to_charlist()
    end
  end
end
