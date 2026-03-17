defmodule LemmingsOsWeb.PageData.SettingsPageSnapshotTest do
  use LemmingsOs.DataCase, async: false

  alias LemmingsOs.World
  alias LemmingsOs.WorldBootstrapTestHelpers
  alias LemmingsOs.WorldCache
  alias LemmingsOsWeb.PageData.SettingsPageSnapshot

  setup do
    Repo.delete_all(World)
    WorldCache.invalidate_all()
    :ok
  end

  describe "build/0" do
    test "builds a read-only snapshot from the resolved world" do
      path =
        WorldBootstrapTestHelpers.write_temp_file!(
          WorldBootstrapTestHelpers.valid_bootstrap_yaml()
        )

      imported_at = DateTime.utc_now() |> DateTime.truncate(:second)

      insert(:world,
        slug: "local",
        name: "Local World",
        status: "ok",
        bootstrap_path: path,
        bootstrap_source: "direct",
        last_import_status: "ok",
        last_imported_at: imported_at
      )

      snapshot = SettingsPageSnapshot.build()

      assert snapshot.instance.app_version == app_version()
      assert snapshot.instance.elixir_version == System.version()
      assert snapshot.instance.otp_release == otp_release()
      assert snapshot.instance.node_name == Atom.to_string(node())
      assert snapshot.instance.host_name == host_name()

      assert snapshot.world == %{
               name: "Local World",
               slug: "local",
               status: "ok",
               available?: true
             }

      assert snapshot.bootstrap == %{
               path: path,
               status: "ok",
               issue_count: 0
             }

      assert snapshot.sync == %{
               status: "ok",
               imported_at: imported_at
             }

      assert snapshot.help_links == [
               %{id: "world", to: "/world"},
               %{id: "logs", to: "/logs"},
               %{id: "tools", to: "/tools"}
             ]
    end

    test "returns honest unknown values when no world can be resolved" do
      snapshot = SettingsPageSnapshot.build()

      assert snapshot.world == %{
               name: nil,
               slug: nil,
               status: "unknown",
               available?: false
             }

      assert snapshot.bootstrap == %{
               path: nil,
               status: "unknown",
               issue_count: 0
             }

      assert snapshot.sync == %{
               status: "unknown",
               imported_at: nil
             }

      assert snapshot.instance.app_version == app_version()
      assert snapshot.instance.elixir_version == System.version()
      assert snapshot.instance.otp_release == otp_release()
      assert snapshot.instance.node_name == Atom.to_string(node())
      assert snapshot.instance.host_name == host_name()

      assert snapshot.help_links == [
               %{id: "world", to: "/world"},
               %{id: "logs", to: "/logs"},
               %{id: "tools", to: "/tools"}
             ]
    end
  end

  defp app_version do
    case Application.spec(:lemmings_os, :vsn) do
      nil -> nil
      version -> List.to_string(version)
    end
  end

  defp otp_release do
    :erlang.system_info(:otp_release) |> List.to_string()
  end

  defp host_name do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      _error -> nil
    end
  end
end
