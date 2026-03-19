defmodule LemmingsOsWeb.PageData.SettingsPageSnapshot do
  @moduledoc """
  Read-only runtime and world/bootstrap summary for the Settings page.

  The `city` section exposes the local runtime node identity and the matching
  persisted City row (if any). It does not invent or infer city data.
  """

  alias LemmingsOs.Cities
  alias LemmingsOs.Cities.City
  alias LemmingsOs.Helpers
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
          city: %{
            available?: boolean(),
            id: String.t() | nil,
            name: String.t() | nil,
            slug: String.t() | nil,
            node_name: String.t() | nil,
            status: String.t() | nil,
            status_label: String.t() | nil,
            last_seen_at: DateTime.t() | nil,
            last_seen_at_label: String.t()
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

    local_node_name = node() |> Atom.to_string()

    %{
      instance: %{
        app_version: app_version(),
        elixir_version: System.version(),
        otp_release: List.to_string(:erlang.system_info(:otp_release)),
        node_name: local_node_name,
        host_name: host_name()
      },
      world: world_section(snapshot),
      city: city_section(snapshot, local_node_name),
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

  defp city_section(nil, _local_node_name), do: unavailable_city_section()

  defp city_section(snapshot, local_node_name) do
    city = Cities.list_cities(snapshot.world.id, node_name: local_node_name) |> List.first()
    city_section_from_row(city)
  end

  defp city_section_from_row(nil), do: unavailable_city_section()

  defp city_section_from_row(%City{} = city) do
    %{
      available?: true,
      id: city.id,
      name: city.name,
      slug: city.slug,
      node_name: city.node_name,
      status: city.status,
      status_label: City.translate_status(city),
      last_seen_at: city.last_seen_at,
      last_seen_at_label: Helpers.format_datetime(city.last_seen_at)
    }
  end

  defp unavailable_city_section do
    %{
      available?: false,
      id: nil,
      name: nil,
      slug: nil,
      node_name: nil,
      status: nil,
      status_label: nil,
      last_seen_at: nil,
      last_seen_at_label: Helpers.format_datetime(nil)
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
