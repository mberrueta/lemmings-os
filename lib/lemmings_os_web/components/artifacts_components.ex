defmodule LemmingsOsWeb.ArtifactsComponents do
  @moduledoc """
  Shared read-only Artifacts UI surface for world/city/department/lemming pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  attr :id_prefix, :string, required: true
  attr :rows, :list, default: []
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil

  def artifact_surface(assigns) do
    assigns =
      assigns
      |> assign(:title, assigns[:title] || dgettext("layout", "Artifacts"))
      |> assign(
        :subtitle,
        assigns[:subtitle] || dgettext("layout", "Artifacts available at this scope.")
      )

    ~H"""
    <.panel id={"#{@id_prefix}-artifacts-panel"} tone="info">
      <:title>{@title}</:title>
      <:subtitle>{@subtitle}</:subtitle>

      <div :if={@rows == []} id={"#{@id_prefix}-artifacts-empty"} class="text-sm text-zinc-400">
        {dgettext("layout", "No artifacts available for this scope.")}
      </div>

      <div :if={@rows != []} id={"#{@id_prefix}-artifacts-table-wrap"} class="overflow-x-auto">
        <table class="min-w-full border-separate border-spacing-y-2 text-sm">
          <caption class="sr-only">{dgettext("layout", "Artifacts")}</caption>
          <thead class="text-left text-xs uppercase tracking-wider text-zinc-400">
            <tr>
              <th class="px-2 py-1">{dgettext("layout", "Filename")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Scope")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Type")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Status")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Size")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Created")}</th>
              <th class="px-2 py-1">{dgettext("layout", "Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @rows}
              id={"#{@id_prefix}-artifacts-row-#{row.id}"}
              class="bg-zinc-950/70 align-top"
            >
              <td
                id={"#{@id_prefix}-artifacts-filename-#{row.id}"}
                class="px-2 py-2 font-medium text-zinc-100"
              >
                {Helpers.display_value(row.filename)}
              </td>
              <td id={"#{@id_prefix}-artifacts-scope-#{row.id}"} class="px-2 py-2">
                <div class="flex flex-wrap gap-1.5">
                  <.badge
                    :if={present_text?(row.city_slug)}
                    id={"#{@id_prefix}-artifacts-context-city-#{row.id}"}
                    tone="info"
                  >
                    {dgettext("layout", "city")}:{row.city_slug}
                  </.badge>
                  <.badge
                    :if={present_text?(row.department_slug)}
                    id={"#{@id_prefix}-artifacts-context-department-#{row.id}"}
                    tone="warning"
                  >
                    {dgettext("layout", "dept")}:{row.department_slug}
                  </.badge>
                  <.badge
                    :if={present_text?(row.lemming_slug)}
                    id={"#{@id_prefix}-artifacts-context-lemming-#{row.id}"}
                    tone="success"
                  >
                    {dgettext("layout", "lemming")}:{row.lemming_slug}
                  </.badge>
                  <.badge
                    :if={
                      !present_text?(row.city_slug) and !present_text?(row.department_slug) and
                        !present_text?(row.lemming_slug)
                    }
                    id={"#{@id_prefix}-artifacts-context-world-#{row.id}"}
                    tone="default"
                  >
                    {dgettext("layout", "world")}
                  </.badge>
                </div>
              </td>
              <td id={"#{@id_prefix}-artifacts-type-#{row.id}"} class="px-2 py-2 text-zinc-300">
                {Helpers.display_value(row.type)}
              </td>
              <td id={"#{@id_prefix}-artifacts-status-#{row.id}"} class="px-2 py-2 text-zinc-300">
                {Helpers.display_value(row.status)}
              </td>
              <td id={"#{@id_prefix}-artifacts-size-#{row.id}"} class="px-2 py-2 text-zinc-300">
                {size_label(row.size_bytes)}
              </td>
              <td id={"#{@id_prefix}-artifacts-created-#{row.id}"} class="px-2 py-2 text-zinc-300">
                {Helpers.format_datetime(row.inserted_at)}
              </td>
              <td id={"#{@id_prefix}-artifacts-actions-#{row.id}"} class="px-2 py-2 text-zinc-300">
                <.link
                  :if={download_href(row)}
                  id={"#{@id_prefix}-artifacts-download-#{row.id}"}
                  href={download_href(row)}
                  class="inline-flex h-9 items-center justify-center gap-2 border-2 border-emerald-400/50 bg-emerald-400/10 px-3 text-xs font-medium text-emerald-300 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-300 focus-visible:ring-offset-2 focus-visible:ring-offset-zinc-950"
                  aria-label={
                    dgettext("layout", "Download Artifact %{filename}", filename: row.filename)
                  }
                >
                  {dgettext("layout", "Download")}
                </.link>
                <span :if={!download_href(row)} class="text-zinc-500">-</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.panel>
    """
  end

  defp size_label(size_bytes) when is_integer(size_bytes) and size_bytes >= 0,
    do: "#{size_bytes} B"

  defp size_label(_size_bytes), do: "-"

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

  defp download_href(%{
         id: artifact_id,
         lemming_instance_id: instance_id,
         world_id: world_id,
         status: "ready"
       })
       when is_binary(artifact_id) and is_binary(instance_id) and is_binary(world_id) do
    ~p"/lemmings/instances/#{instance_id}/artifacts/#{artifact_id}/download?#{%{world: world_id}}"
  end

  defp download_href(_row), do: nil
end
