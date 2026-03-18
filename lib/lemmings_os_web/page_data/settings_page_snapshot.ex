defmodule LemmingsOsWeb.PageData.SettingsPageSnapshot do
  @moduledoc """
  Read-only runtime and world/bootstrap summary for the Settings page.
  """

  alias LemmingsOs.Worlds.World
  alias LemmingsOsWeb.PageData.WorldPageSnapshot

  @type t :: %{
          instance: %{
            app_version: String.t() | nil,
            elixir_version: String.t(),
            otp_release: String.t(),
            node_name: String.t(),
            host_name: String.t() | nil
          },
          world: %{
            name: String.t() | nil,
            slug: String.t() | nil,
            status: String.t(),
            available?: boolean()
          },
          bootstrap: %{
            path: String.t() | nil,
            status: String.t(),
            issue_count: non_neg_integer()
          },
          sync: %{
            status: String.t(),
            imported_at: DateTime.t() | nil
          },
          help_links: [%{id: String.t(), label: String.t(), to: String.t()}]
        }

  @spec build() :: t()
  def build do
    snapshot =
      case WorldPageSnapshot.build() do
        {:ok, world_snapshot} -> world_snapshot
        {:error, :not_found} -> nil
      end

    %{
      instance: %{
        app_version: app_version(),
        elixir_version: System.version(),
        otp_release: List.to_string(:erlang.system_info(:otp_release)),
        node_name: node() |> Atom.to_string(),
        host_name: host_name()
      },
      world: world_section(snapshot),
      bootstrap: bootstrap_section(snapshot),
      sync: sync_section(snapshot),
      help_links: help_links()
    }
  end

  defp world_section(nil) do
    %{
      name: nil,
      slug: nil,
      status: "unknown",
      available?: false
    }
  end

  defp world_section(snapshot) do
    %{
      name: snapshot.world.name,
      slug: snapshot.world.slug,
      status: snapshot.world.status,
      available?: true
    }
  end

  defp bootstrap_section(nil) do
    %{
      path: nil,
      status: "unknown",
      issue_count: 0
    }
  end

  defp bootstrap_section(snapshot) do
    %{
      path: snapshot.bootstrap.path,
      status: snapshot.bootstrap.status,
      issue_count: length(snapshot.bootstrap.issues)
    }
  end

  defp sync_section(nil) do
    %{
      status: "unknown",
      imported_at: nil
    }
  end

  defp sync_section(snapshot) do
    %{
      status: snapshot.last_sync.status || World.translate_status("unknown"),
      imported_at: snapshot.last_sync.imported_at
    }
  end

  defp help_links do
    [
      %{id: "world", to: "/world"},
      %{id: "logs", to: "/logs"},
      %{id: "tools", to: "/tools"}
    ]
  end

  defp app_version do
    case Application.spec(:lemmings_os, :vsn) do
      nil -> nil
      version -> List.to_string(version)
    end
  end

  defp host_name do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      _error -> nil
    end
  end
end
