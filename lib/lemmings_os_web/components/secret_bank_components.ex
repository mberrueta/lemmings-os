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
  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil

  def secret_surface(assigns) do
    assigns =
      assigns
      |> assign(:title, assigns[:title] || dgettext("world", ".tab_secrets"))
      |> assign(:subtitle, assigns[:subtitle] || dgettext("world", ".secret_default_subtitle"))

    ~H"""
    <.panel id={"#{@id_prefix}-secrets-panel"} tone="info">
      <:title>{@title}</:title>
      <:subtitle>{@subtitle}</:subtitle>

      <div id={"#{@id_prefix}-secrets-layout"} class="grid gap-4 xl:grid-cols-2">
        <.panel id={"#{@id_prefix}-secrets-write-panel"} tone="accent">
          <:title>{dgettext("world", ".secret_form_title")}</:title>
          <:subtitle>
            {dgettext("world", ".secret_form_subtitle")}
          </:subtitle>

          <.form
            for={@form}
            id={"#{@id_prefix}-secret-form"}
            phx-submit={@save_event}
            aria-describedby={"#{@id_prefix}-secret-form-help"}
            class="space-y-4"
          >
            <p id={"#{@id_prefix}-secret-form-help"} class="text-sm text-zinc-300">
              {dgettext("world", ".secret_form_help")}
            </p>
            <.input
              id={"#{@id_prefix}-secret-bank-key"}
              field={@form[:bank_key]}
              type="text"
              label={dgettext("world", ".secret_key_label")}
              placeholder="GITHUB_TOKEN"
              autocomplete="off"
              required
              aria-describedby={"#{@id_prefix}-secret-bank-key-help"}
            />
            <p id={"#{@id_prefix}-secret-bank-key-help"} class="-mt-2 text-xs text-zinc-400">
              {dgettext("world", ".secret_key_help")}
            </p>
            <.input
              id={"#{@id_prefix}-secret-value"}
              field={@form[:value]}
              type="password"
              label={dgettext("world", ".secret_value_label")}
              placeholder="********"
              autocomplete="new-password"
              required
              aria-describedby={"#{@id_prefix}-secret-value-help"}
            />
            <p id={"#{@id_prefix}-secret-value-help"} class="-mt-2 text-xs text-zinc-400">
              {dgettext("world", ".secret_value_help")}
            </p>

            <div class="flex pt-10 justify-end">
              <.button
                id={"#{@id_prefix}-secret-save"}
                type="submit"
                variant="secondary"
                phx-disable-with={dgettext("world", ".secret_save_pending")}
              >
                {dgettext("world", ".secret_save_button")}
              </.button>
            </div>
          </.form>
        </.panel>

        <.panel id={"#{@id_prefix}-secrets-activity-panel"}>
          <:title>{dgettext("world", ".secret_activity_title")}</:title>
          <:subtitle>{dgettext("world", ".secret_activity_subtitle")}</:subtitle>

          <div
            :if={@activity == []}
            id={"#{@id_prefix}-secrets-activity-empty"}
            role="status"
            aria-live="polite"
          >
            <.empty_state
              id={"#{@id_prefix}-secrets-activity-empty-state"}
              title={dgettext("world", ".secret_activity_empty_title")}
              copy={dgettext("world", ".secret_activity_empty_copy")}
            />
          </div>

          <div
            :if={@activity != []}
            id={"#{@id_prefix}-secrets-activity-scroll"}
            class="max-h-72 overflow-y-auto pr-1"
            role="region"
            aria-labelledby={"#{@id_prefix}-secrets-activity-heading"}
            aria-live="polite"
          >
            <h3 id={"#{@id_prefix}-secrets-activity-heading"} class="sr-only">
              {dgettext("world", ".secret_activity_title")}
            </h3>
            <ul id={"#{@id_prefix}-secrets-activity-list"} class="space-y-2 text-sm">
              <li
                :for={item <- Enum.take(@activity, 10)}
                id={"#{@id_prefix}-secret-activity-#{item.id}"}
                class="border-2 border-zinc-700 bg-zinc-950/70 p-3"
              >
                <p class="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
                  <span class="text-zinc-100">{item.message}</span>
                  <time
                    datetime={datetime_iso8601(item.occurred_at)}
                    class="font-mono text-xs uppercase tracking-wider text-zinc-500"
                  >
                    {Helpers.format_datetime(item.occurred_at)}
                  </time>
                </p>
              </li>
            </ul>
          </div>
        </.panel>
      </div>

      <.panel id={"#{@id_prefix}-secrets-effective-panel"} class="mt-4">
        <:title>{dgettext("world", ".secret_effective_title")}</:title>
        <:subtitle>
          {dgettext("world", ".secret_effective_subtitle")}
        </:subtitle>

        <div :if={@metadata == []} id={"#{@id_prefix}-secrets-empty"}>
          <.empty_state
            id={"#{@id_prefix}-secrets-empty-state"}
            title={dgettext("world", ".secret_empty_title")}
            copy={dgettext("world", ".secret_empty_copy")}
          />
        </div>

        <ul :if={@metadata != []} id={"#{@id_prefix}-secrets-list"} class="space-y-3">
          <li
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
                {dgettext("world", ".label_updated")}: {timestamp_label(
                  entry.updated_at || entry.inserted_at
                )}
              </p>
              <p
                id={"#{@id_prefix}-secret-action-state-#{dom_fragment(entry.bank_key)}"}
                class="text-xs text-zinc-300"
              >
                {action_state_label(entry)}
              </p>
            </div>

            <div class="flex flex-wrap items-center justify-end gap-2">
              <button
                :if={editable?(entry)}
                id={"#{@id_prefix}-secret-edit-#{dom_fragment(entry.bank_key)}"}
                type="button"
                phx-click={@edit_event}
                phx-value-bank-key={entry.bank_key}
                title={edit_label(entry.bank_key)}
                aria-label={edit_label(entry.bank_key)}
                aria-describedby={"#{@id_prefix}-secret-action-state-#{dom_fragment(entry.bank_key)}"}
                class="inline-flex h-9 w-9 items-center justify-center border-2 border-zinc-600 bg-zinc-900/80 text-zinc-200 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400 focus-visible:ring-offset-2 focus-visible:ring-offset-zinc-950"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </button>

              <button
                :if={deletable?(entry)}
                id={"#{@id_prefix}-secret-delete-#{dom_fragment(entry.bank_key)}"}
                type="button"
                phx-click={@delete_event}
                phx-value-bank-key={entry.bank_key}
                data-confirm={dgettext("world", ".secret_delete_confirm")}
                title={delete_label(entry.bank_key)}
                aria-label={delete_label(entry.bank_key)}
                aria-describedby={"#{@id_prefix}-secret-action-state-#{dom_fragment(entry.bank_key)}"}
                class="inline-flex h-9 w-9 items-center justify-center border-2 border-red-400 bg-red-500/10 text-red-300 shadow-lg transition duration-200 ease-out hover:-translate-y-px hover:brightness-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-300 focus-visible:ring-offset-2 focus-visible:ring-offset-zinc-950"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </li>
        </ul>
      </.panel>

      <.panel id={"#{@id_prefix}-secrets-env-fallback-panel"} class="mt-4">
        <:title>{dgettext("world", ".secret_env_policy_title")}</:title>
        <:subtitle>
          {dgettext("world", ".secret_env_policy_subtitle")}
        </:subtitle>

        <p
          id={"#{@id_prefix}-secrets-env-fallback-explainer"}
          class="text-xs uppercase tracking-wider text-zinc-500"
        >
          {dgettext("world", ".secret_env_policy_explainer")}
        </p>

        <div :if={@env_fallback_policy == []} id={"#{@id_prefix}-secrets-env-fallback-empty"}>
          <.empty_state
            id={"#{@id_prefix}-secrets-env-fallback-empty-state"}
            title={dgettext("world", ".secret_env_policy_empty_title")}
            copy={dgettext("world", ".secret_env_policy_empty_copy")}
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
                {dgettext("world", ".secret_env_policy_blocked_warning")}
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

  defp mapping_kind_label("convention"), do: dgettext("world", ".secret_mapping_convention")

  defp mapping_kind_label("explicit_override"),
    do: dgettext("world", ".secret_mapping_explicit_override")

  defp mapping_kind_label(_value), do: dgettext("world", ".label_unknown")

  defp allowlist_badge_tone(true), do: "success"
  defp allowlist_badge_tone(false), do: "warning"

  defp allowlist_label(true), do: dgettext("world", ".secret_allowlisted")
  defp allowlist_label(false), do: dgettext("world", ".secret_blocked_by_allowlist")

  defp action_state_label(entry) do
    cond do
      editable?(entry) && deletable?(entry) ->
        dgettext("world", ".secret_action_local_replace_delete")

      editable?(entry) ->
        dgettext("world", ".secret_action_inherited_replace")

      deletable?(entry) ->
        dgettext("world", ".secret_action_local_delete")

      true ->
        dgettext("world", ".secret_action_inherited_read_only")
    end
  end

  defp edit_label(bank_key), do: dgettext("world", ".secret_edit_label", key: bank_key)

  defp delete_label(bank_key),
    do: dgettext("world", ".secret_delete_label", key: bank_key)

  defp env_var_label(env_var) when is_binary(env_var) and env_var != "" do
    "$" <> String.trim_leading(env_var, "$")
  end

  defp env_var_label(_env_var), do: "$UNKNOWN_ENV_VAR"

  defp secret_ref_example(bank_key) when is_binary(bank_key) do
    "$" <> bank_key
  end

  defp secret_ref_example(_bank_key), do: "$EXAMPLE_KEY"

  defp datetime_iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp datetime_iso8601(_value), do: nil

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
