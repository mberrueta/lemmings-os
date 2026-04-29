defmodule LemmingsOsWeb.SecretBankComponents do
  @moduledoc """
  Shared Secret Bank write-only UI surfaces.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.Helpers

  attr :id_prefix, :string, required: true
  attr :form, :any, required: true
  attr :metadata, :list, default: []
  attr :activity, :list, default: []
  attr :env_fallback_policy, :list, default: []
  attr :save_event, :string, required: true
  attr :edit_event, :string, required: true
  attr :delete_event, :string, required: true
  attr :title, :string, default: "Secrets"
  attr :subtitle, :string, default: "Write-only Secret Bank values for this scope."

  def secret_surface(assigns) do
    ~H"""
    <.panel id={"#{@id_prefix}-secrets-panel"} tone="info">
      <:title>{@title}</:title>
      <:subtitle>{@subtitle}</:subtitle>

      <div id={"#{@id_prefix}-secrets-layout"} class="grid gap-4 xl:grid-cols-2">
        <.panel id={"#{@id_prefix}-secrets-write-panel"} tone="accent">
          <:title>{dgettext("world", "Create or replace local secret")}</:title>
          <:subtitle>
            {dgettext("world", "Values are write-only. Saved secrets are never shown again.")}
          </:subtitle>

          <.form
            for={@form}
            id={"#{@id_prefix}-secret-form"}
            phx-submit={@save_event}
            class="space-y-4"
          >
            <.input
              id={"#{@id_prefix}-secret-bank-key"}
              field={@form[:bank_key]}
              type="text"
              label={dgettext("world", "Secret key")}
              placeholder="GITHUB_TOKEN"
              autocomplete="off"
            />
            <.input
              id={"#{@id_prefix}-secret-value"}
              field={@form[:value]}
              type="password"
              label={dgettext("world", "Secret value")}
              placeholder="********"
              autocomplete="new-password"
            />

            <div class="flex pt-10 justify-end">
              <.button id={"#{@id_prefix}-secret-save"} type="submit" variant="secondary">
                {dgettext("world", "Save secret")}
              </.button>
            </div>
          </.form>
        </.panel>

        <.panel id={"#{@id_prefix}-secrets-activity-panel"}>
          <:title>{dgettext("world", "Recent secret activity")}</:title>
          <:subtitle>{dgettext("world", "Durable safe audit activity for this scope.")}</:subtitle>

          <div :if={@activity == []} id={"#{@id_prefix}-secrets-activity-empty"}>
            <.empty_state
              id={"#{@id_prefix}-secrets-activity-empty-state"}
              title={dgettext("world", "No recent secret activity")}
              copy={dgettext("world", "Secret audit events will appear here.")}
            />
          </div>

          <div
            :if={@activity != []}
            id={"#{@id_prefix}-secrets-activity-scroll"}
            class="max-h-72 overflow-y-auto pr-1"
          >
            <ul id={"#{@id_prefix}-secrets-activity-list"} class="space-y-2 text-sm">
              <li
                :for={item <- Enum.take(@activity, 10)}
                id={"#{@id_prefix}-secret-activity-#{item.id}"}
                class="border-2 border-zinc-700 bg-zinc-950/70 p-3"
              >
                <p class="flex items-center justify-between gap-4">
                  <span class="text-zinc-100">{item.message}</span>
                  <span class="font-mono text-xs uppercase tracking-wider text-zinc-500">
                    {Helpers.format_datetime(item.occurred_at)}
                  </span>
                </p>
              </li>
            </ul>
          </div>
        </.panel>
      </div>

      <.panel id={"#{@id_prefix}-secrets-effective-panel"} class="mt-4">
        <:title>{dgettext("world", "Effective secret keys")}</:title>
        <:subtitle>
          {dgettext("world", "Inherited sources are visible, but only local values can be deleted.")}
        </:subtitle>

        <div :if={@metadata == []} id={"#{@id_prefix}-secrets-empty"}>
          <.empty_state
            id={"#{@id_prefix}-secrets-empty-state"}
            title={dgettext("world", "No secret keys available")}
            copy={
              dgettext("world", "Create a local secret or rely on inherited configured metadata.")
            }
          />
        </div>

        <div :if={@metadata != []} id={"#{@id_prefix}-secrets-list"} class="space-y-3">
          <div
            :for={entry <- @metadata}
            id={"#{@id_prefix}-secret-row-#{dom_fragment(entry.bank_key)}"}
            class="flex flex-col gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 lg:flex-row lg:items-center lg:justify-between"
          >
            <div class="space-y-1">
              <p class="font-mono text-sm text-zinc-100">
                {entry.bank_key}
                <span class="text-xs uppercase tracking-wider text-zinc-500">
                  ({entry.scope}) {configured_label(entry.configured)}
                </span>
              </p>
              <p class="text-xs text-zinc-400">
                {dgettext("world", "updated")}: {timestamp_label(
                  entry.updated_at || entry.inserted_at
                )}
              </p>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2">
              <button
                :if={editable?(entry)}
                id={"#{@id_prefix}-secret-edit-#{dom_fragment(entry.bank_key)}"}
                type="button"
                phx-click={@edit_event}
                phx-value-bank-key={entry.bank_key}
                title={dgettext("world", "Edit secret")}
                aria-label={dgettext("world", "Edit secret")}
                class="inline-flex h-9 w-9 items-center justify-center border-2 border-zinc-600 bg-zinc-900/80 text-zinc-200 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>

              <button
                :if={deletable?(entry)}
                id={"#{@id_prefix}-secret-delete-#{dom_fragment(entry.bank_key)}"}
                type="button"
                phx-click={@delete_event}
                phx-value-bank-key={entry.bank_key}
                data-confirm={dgettext("world", "Delete this local secret value?")}
                title={dgettext("world", "Delete local value")}
                aria-label={dgettext("world", "Delete local value")}
                class="inline-flex h-9 w-9 items-center justify-center border-2 border-red-400 bg-red-500/10 text-red-300 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        </div>
      </.panel>

      <.panel id={"#{@id_prefix}-secrets-env-fallback-panel"} class="mt-4">
        <:title>{dgettext("world", "Environment fallback policy")}</:title>
        <:subtitle>
          {dgettext("world", "Read-only mappings configured in application config.")}
        </:subtitle>

        <p
          id={"#{@id_prefix}-secrets-env-fallback-explainer"}
          class="text-xs uppercase tracking-wider text-zinc-500"
        >
          {dgettext(
            "world",
            "Reference example: $GITHUB_TOKEN. Explicit override example: $OPENROUTER_API_KEY -> $OPENROUTER_API_KEY."
          )}
        </p>

        <div :if={@env_fallback_policy == []} id={"#{@id_prefix}-secrets-env-fallback-empty"}>
          <.empty_state
            id={"#{@id_prefix}-secrets-env-fallback-empty-state"}
            title={dgettext("world", "No env fallback mappings configured")}
            copy={
              dgettext(
                "world",
                "Configure env fallbacks in application config. This UI does not edit mappings."
              )
            }
          />
        </div>

        <div
          :if={@env_fallback_policy != []}
          id={"#{@id_prefix}-secrets-env-fallback-list"}
          class="mt-3 space-y-3"
        >
          <div
            :for={entry <- @env_fallback_policy}
            id={"#{@id_prefix}-secrets-env-fallback-row-#{dom_fragment(entry.bank_key)}"}
            class="flex flex-col gap-3 border-2 border-zinc-700 bg-zinc-950/70 p-4 lg:flex-row lg:items-center lg:justify-between"
          >
            <div class="space-y-1">
              <p
                id={"#{@id_prefix}-secrets-env-fallback-bank-key-#{dom_fragment(entry.bank_key)}"}
                class="font-mono text-sm text-zinc-100"
              >
                {entry.bank_key}
              </p>
              <p class="text-xs text-zinc-400">
                {secret_ref_example(entry.bank_key)} -> {env_var_label(entry.env_var)}
              </p>
              <p
                :if={!entry.allowlisted}
                id={"#{@id_prefix}-secrets-env-fallback-warning-#{dom_fragment(entry.bank_key)}"}
                class="text-xs text-amber-300"
              >
                {dgettext(
                  "world",
                  "Blocked by allowlist. Add this env var to allowed_env_vars to enable fallback."
                )}
              </p>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2">
              <.badge
                id={"#{@id_prefix}-secrets-env-fallback-type-#{dom_fragment(entry.bank_key)}"}
                tone="info"
              >
                {mapping_kind_label(entry.mapping_kind)}
              </.badge>
              <.badge
                id={"#{@id_prefix}-secrets-env-fallback-status-#{dom_fragment(entry.bank_key)}"}
                tone={allowlist_badge_tone(entry.allowlisted)}
              >
                {allowlist_label(entry.allowlisted)}
              </.badge>
            </div>
          </div>
        </div>
      </.panel>
    </.panel>
    """
  end

  defp editable?(%{allowed_actions: actions}) when is_list(actions) do
    Enum.member?(actions, "upsert")
  end

  defp editable?(_entry), do: false

  defp deletable?(%{allowed_actions: actions}) when is_list(actions) do
    Enum.member?(actions, "delete")
  end

  defp deletable?(_entry), do: false

  defp configured_label(true), do: "[configured]"
  defp configured_label(false), do: "[not configured]"

  defp timestamp_label(%DateTime{} = value), do: Helpers.format_datetime(value)
  defp timestamp_label(_value), do: "-"

  defp mapping_kind_label("convention"), do: dgettext("world", "convention")
  defp mapping_kind_label("explicit_override"), do: dgettext("world", "explicit override")
  defp mapping_kind_label(_value), do: dgettext("world", "unknown")

  defp allowlist_badge_tone(true), do: "success"
  defp allowlist_badge_tone(false), do: "warning"

  defp allowlist_label(true), do: dgettext("world", "allowlisted")
  defp allowlist_label(false), do: dgettext("world", "blocked by allowlist")

  defp env_var_label(env_var) when is_binary(env_var) and env_var != "" do
    "$" <> String.trim_leading(env_var, "$")
  end

  defp env_var_label(_env_var), do: "$UNKNOWN_ENV_VAR"

  defp secret_ref_example(bank_key) when is_binary(bank_key) do
    "$" <> bank_key
  end

  defp secret_ref_example(_bank_key), do: "$EXAMPLE_KEY"

  defp dom_fragment(nil), do: "unknown"

  defp dom_fragment(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "key"
      fragment -> fragment
    end
  end
end
