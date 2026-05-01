defmodule LemmingsOsWeb.ConnectionsComponents do
  @moduledoc """
  Shared Connections UI surface for world/city/department pages.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers
  alias LemmingsOsWeb.ConnectionsSurface

  attr :id_prefix, :string, required: true
  attr :scope_kind, :string, required: true
  attr :scope_available?, :boolean, default: true
  attr :types, :list, default: []
  attr :create_form, :any, required: true
  attr :create_open?, :boolean, default: false
  attr :rows, :list, default: []
  attr :editing_connection_id, :string, default: nil
  attr :edit_form, :any, default: nil
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :create_submit_event, :string, required: true
  attr :create_type_change_event, :string, required: true
  attr :open_create_event, :string, required: true
  attr :close_create_event, :string, required: true
  attr :start_edit_event, :string, required: true
  attr :cancel_edit_event, :string, required: true
  attr :save_edit_event, :string, required: true
  attr :edit_type_change_event, :string, required: true
  attr :delete_event, :string, required: true
  attr :lifecycle_event, :string, required: true
  attr :test_event, :string, required: true

  def connection_surface(assigns) do
    assigns =
      assigns
      |> assign(:title, assigns[:title] || dgettext("layout", ".title_connections"))
      |> assign(:subtitle, assigns[:subtitle] || dgettext("layout", ".subtitle_connections"))

    ~H"""
    <.panel id={"#{@id_prefix}-connections-panel"} tone="accent">
      <:title>{@title}</:title>
      <:subtitle>{@subtitle}</:subtitle>

      <div
        :if={!@scope_available?}
        id={"#{@id_prefix}-connections-unavailable"}
        class="text-sm text-zinc-400"
      >
        {dgettext("layout", ".connections_scope_unavailable")}
      </div>

      <div :if={@scope_available?} class="space-y-4">
        <.panel id={"#{@id_prefix}-connections-effective-panel"}>
          <:title>{dgettext("layout", ".title_connections")}</:title>
          <:subtitle>{scope_title(@scope_kind)}</:subtitle>
          <:actions>
            <.button
              :if={!@create_open?}
              id={"#{@id_prefix}-connections-open-create"}
              type="button"
              phx-click={@open_create_event}
              variant="secondary"
              class="ml-auto"
            >
              + {dgettext("layout", ".connections_action_create")}
            </.button>
          </:actions>

          <.form
            :if={@create_open?}
            for={@create_form}
            id={"#{@id_prefix}-connections-create-form"}
            phx-submit={@create_submit_event}
            class="mb-4 rounded-md border border-zinc-700 bg-zinc-900/40 p-3"
          >
            <div class="grid gap-3 md:grid-cols-2">
              <label
                for={"#{@id_prefix}-connections-create-type"}
                class="text-sm font-medium text-zinc-200"
              >
                {dgettext("layout", ".connections_label_type")}
              </label>
              <select
                id={"#{@id_prefix}-connections-create-type"}
                name="connection_create[type]"
                phx-change={@create_type_change_event}
                class="rounded border border-zinc-600 bg-zinc-950 px-3 py-2 text-zinc-100"
              >
                <option
                  :for={type <- @types}
                  value={type.id}
                  selected={@create_form[:type].value == type.id}
                >
                  {type.label} ({type.id})
                </option>
              </select>
            </div>

            <input type="hidden" name="connection_create[status]" value="enabled" />

            <.input
              field={@create_form[:config]}
              id={"#{@id_prefix}-connections-create-config"}
              type="textarea"
              label={dgettext("layout", ".connections_label_config_json")}
            />

            <div class="mt-3 flex justify-end gap-2">
              <button
                id={"#{@id_prefix}-connections-create-cancel"}
                type="button"
                phx-click={@close_create_event}
                class="rounded border border-zinc-600 px-3 py-2 text-sm text-zinc-300"
              >
                {dgettext("layout", ".connections_action_cancel")}
              </button>
              <.button
                id={"#{@id_prefix}-connections-create-submit"}
                type="submit"
                variant="secondary"
              >
                {dgettext("layout", ".connections_action_save")}
              </.button>
            </div>
          </.form>

          <div :if={@rows == []} id={"#{@id_prefix}-connections-empty"} class="text-sm text-zinc-400">
            {dgettext("layout", ".connections_empty")}
          </div>

          <div :if={@rows != []} class="overflow-x-auto">
            <table class="min-w-full border-separate border-spacing-y-2 text-sm">
              <caption class="sr-only">
                {dgettext("layout", ".title_connections")}
              </caption>
              <thead>
                <tr class="text-left text-xs uppercase tracking-widest text-zinc-400">
                  <th class="px-2 py-1">{dgettext("layout", ".connections_column_name")}</th>
                  <th class="px-2 py-1">{dgettext("layout", ".connections_label_type")}</th>
                  <th class="px-2 py-1">{dgettext("layout", ".connections_column_last_test")}</th>
                  <th class="px-2 py-1">{dgettext("layout", ".connections_column_actions")}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @rows}
                  id={"#{@id_prefix}-connections-row-#{row.connection.id}"}
                  class="rounded-md border border-zinc-700 bg-zinc-900/30"
                >
                  <th scope="row" class="px-2 py-2 text-zinc-100">
                    <div class="font-medium">{ConnectionsSurface.connection_label(row)}</div>
                    <span
                      id={"#{@id_prefix}-connections-source-#{row.connection.id}"}
                      class={[
                        "mt-1 inline-flex rounded-full border px-2 py-0.5 text-xs font-medium",
                        ConnectionsSurface.source_scope_tone(row) == "ok" &&
                          "border-emerald-500/50 text-emerald-300",
                        ConnectionsSurface.source_scope_tone(row) == "warn" &&
                          "border-amber-500/50 text-amber-300"
                      ]}
                    >
                      {ConnectionsSurface.source_scope_label(row.source_scope)} · {ConnectionsSurface.source_scope_copy(
                        row
                      )}
                    </span>
                  </th>
                  <td class="px-2 py-2 text-zinc-300">{row.connection.type}</td>
                  <td class="px-2 py-2">
                    <span
                      id={"#{@id_prefix}-connections-status-#{row.connection.id}"}
                      data-status={row.connection.status}
                      class={[
                        "inline-flex rounded-full border px-2 py-0.5 text-xs font-medium uppercase tracking-wide",
                        row.connection.status == "enabled" &&
                          "border-emerald-500/50 text-emerald-300",
                        row.connection.status == "disabled" && "border-zinc-500/50 text-zinc-300",
                        row.connection.status == "invalid" && "border-rose-500/50 text-rose-300"
                      ]}
                    >
                      {row.connection.status}
                    </span>
                    <div
                      id={"#{@id_prefix}-connections-last-test-#{row.connection.id}"}
                      class="text-xs text-zinc-400"
                      role="status"
                      aria-live="polite"
                    >
                      <span class="sr-only">
                        {dgettext("layout", ".connections_column_last_test")}:
                      </span>
                      {Helpers.display_value(row.connection.last_test)}
                    </div>
                  </td>
                  <td class="px-2 py-2">
                    <div class="flex flex-wrap items-center gap-2">
                      <button
                        id={"#{@id_prefix}-connections-test-#{row.connection.id}"}
                        type="button"
                        phx-click={@test_event}
                        phx-value-type={row.connection.type}
                        class="rounded border border-emerald-500/50 p-1 text-emerald-300"
                        title={dgettext("layout", ".connections_action_test")}
                        aria-label={dgettext("layout", ".connections_action_test")}
                      >
                        <.icon name="hero-beaker" class="size-4" />
                      </button>
                      <button
                        :if={row.local? and row.connection.status != "enabled"}
                        id={"#{@id_prefix}-connections-enable-#{row.connection.id}"}
                        type="button"
                        phx-click={@lifecycle_event}
                        phx-value-connection_id={row.connection.id}
                        phx-value-action="enable"
                        class="rounded border border-zinc-500/50 p-1 text-zinc-300"
                        title={dgettext("layout", ".connections_action_enable")}
                        aria-label={dgettext("layout", ".connections_action_enable")}
                      >
                        <.icon name="hero-play" class="size-4" />
                      </button>
                      <button
                        :if={row.local? and row.connection.status != "disabled"}
                        id={"#{@id_prefix}-connections-disable-#{row.connection.id}"}
                        type="button"
                        phx-click={@lifecycle_event}
                        phx-value-connection_id={row.connection.id}
                        phx-value-action="disable"
                        class="rounded border border-zinc-500/50 p-1 text-zinc-300"
                        title={dgettext("layout", ".connections_action_disable")}
                        aria-label={dgettext("layout", ".connections_action_disable")}
                      >
                        <.icon name="hero-pause" class="size-4" />
                      </button>
                      <button
                        :if={row.local?}
                        id={"#{@id_prefix}-connections-edit-#{row.connection.id}"}
                        type="button"
                        phx-click={@start_edit_event}
                        phx-value-connection_id={row.connection.id}
                        class="rounded border border-zinc-500/50 p-1 text-zinc-300"
                        title={dgettext("layout", ".connections_action_edit")}
                        aria-label={dgettext("layout", ".connections_action_edit")}
                      >
                        <.icon name="hero-pencil-square" class="size-4" />
                      </button>
                      <button
                        :if={row.local?}
                        id={"#{@id_prefix}-connections-delete-#{row.connection.id}"}
                        type="button"
                        phx-click={@delete_event}
                        phx-value-connection_id={row.connection.id}
                        class="rounded border border-rose-500/50 p-1 text-rose-300"
                        title={dgettext("layout", ".connections_action_delete")}
                        aria-label={dgettext("layout", ".connections_action_delete")}
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>

            <.form
              :for={row <- @rows}
              :if={
                not is_nil(@editing_connection_id) and
                  not is_nil(@edit_form) and
                  @editing_connection_id == row.connection.id
              }
              for={@edit_form}
              id={"#{@id_prefix}-connections-edit-form-#{row.connection.id}"}
              phx-change={@edit_type_change_event}
              phx-submit={@save_edit_event}
              class="mt-3 grid gap-2 rounded-md border border-zinc-700 bg-zinc-900/40 p-3"
            >
              <input type="hidden" name="connection_edit[connection_id]" value={row.connection.id} />
              <input type="hidden" name="connection_edit[status]" value={row.connection.status} />

              <label
                for={"#{@id_prefix}-connections-edit-type-#{row.connection.id}"}
                class="text-sm font-medium text-zinc-200"
              >
                {dgettext("layout", ".connections_label_type")}
              </label>
              <select
                id={"#{@id_prefix}-connections-edit-type-#{row.connection.id}"}
                name="connection_edit[type]"
                class="rounded border border-zinc-600 bg-zinc-950 px-3 py-2 text-zinc-100"
              >
                <option
                  :for={type <- @types}
                  value={type.id}
                  selected={@edit_form[:type].value == type.id}
                >
                  {type.label} ({type.id})
                </option>
              </select>

              <.input
                field={@edit_form[:config]}
                type="textarea"
                id={"#{@id_prefix}-connections-edit-config-#{row.connection.id}"}
                label={dgettext("layout", ".connections_label_config_json")}
              />

              <div class="mt-2 flex gap-2">
                <.button
                  id={"#{@id_prefix}-connections-edit-save-#{row.connection.id}"}
                  type="submit"
                  variant="secondary"
                >
                  {dgettext("layout", ".connections_action_save")}
                </.button>
                <button
                  id={"#{@id_prefix}-connections-edit-cancel-#{row.connection.id}"}
                  type="button"
                  phx-click={@cancel_edit_event}
                  class="rounded border border-zinc-600 px-3 py-2 text-sm text-zinc-300"
                >
                  {dgettext("layout", ".connections_action_cancel")}
                </button>
              </div>
            </.form>
          </div>
        </.panel>
      </div>
    </.panel>
    """
  end

  defp scope_title("world"), do: dgettext("layout", ".connections_scope_world")
  defp scope_title("city"), do: dgettext("layout", ".connections_scope_city")
  defp scope_title("department"), do: dgettext("layout", ".connections_scope_department")
  defp scope_title(_scope), do: dgettext("layout", ".connections_scope_unavailable")
end
