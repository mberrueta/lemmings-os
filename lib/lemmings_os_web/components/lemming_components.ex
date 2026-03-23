defmodule LemmingsOsWeb.LemmingComponents do
  @moduledoc """
  Components for lemming lists, detail panels, and creation flows.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.MockData

  attr :class, :string, default: nil

  def brand_wordmark(assigns) do
    ~H"""
    <span
      id="brand-wordmark"
      class={["inline-flex items-baseline gap-0 font-mono text-base font-bold tracking-tight", @class]}
    >
      <span id="brand-wordmark-main" class="text-zinc-100">Lemmings</span><span
        id="brand-wordmark-os"
        class="text-sky-400"
      >OS</span>
    </span>
    """
  end

  attr :size, :integer, default: 32
  attr :seed, :string, default: "lemming-logo"

  attr :animation, :string,
    default: "default",
    values: ~w(default random blink none)

  attr :palette, :string,
    default: "default",
    values: ~w(default random aqua lime amber violet coral slate)

  attr :class, :string, default: nil

  def lemming_logo(assigns) do
    assigns =
      assigns
      |> assign_new(:seed, fn -> "lemming-logo" end)
      |> assign_new(:animation, fn -> "default" end)
      |> assign_new(:palette, fn -> "default" end)
      |> assign_new(:class, fn -> nil end)

    resolved_animation = resolve_animation(assigns.animation, assigns.seed)
    resolved_palette = resolve_palette(assigns.palette, assigns.seed)
    palette = palette_colors(resolved_palette)

    assigns =
      assigns
      |> assign(:palette_colors, palette)
      |> assign(:animation_class, animation_class(resolved_animation))
      |> assign(:resolved_animation, resolved_animation)
      |> assign(:resolved_palette, resolved_palette)

    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 32 32"
      xmlns="http://www.w3.org/2000/svg"
      shape-rendering="crispEdges"
      aria-hidden="true"
      class={["lemming-logo size-14", @animation_class, @class]}
      style={palette_style(@palette_colors)}
    >
      <g class="lemming-logo__bubble">
        <rect x="19" y="3" width="6" height="8" fill="var(--lemming-logo-chat)" />
      </g>

      <g class="lemming-logo__head">
        <rect x="10" y="6" width="10" height="7" fill="var(--lemming-logo-head)" />

        <g class={["lemming-logo__eyes", eye_animation(@resolved_animation)]}>
          <rect x="15" y="9" width="1" height="1" fill="#111111" />
          <rect x="17" y="9" width="1" height="1" fill="#111111" />
        </g>
      </g>

      <g class="lemming-logo__body">
        <rect x="9" y="14" width="13" height="9" fill="var(--lemming-logo-shadow)" />
        <rect x="10" y="15" width="11" height="7" fill="var(--lemming-logo-body)" />
      </g>
    </svg>
    """
  end

  attr :lemmings, :list, required: true
  attr :selected_lemming, :map, default: nil

  def lemmings_page(assigns) do
    ~H"""
    <.content_container>
      <.panel id="lemmings-header-panel" tone="accent">
        <:title>{dgettext("lemmings", ".title_all_lemmings")}</:title>
        <:subtitle>{dgettext("lemmings", ".subtitle_all_lemmings")}</:subtitle>
      </.panel>

      <.content_grid id="lemmings-grid" columns="sidebar">
        <.panel id="lemmings-table-panel" class="overflow-x-auto">
          <div class="flex flex-col min-w-[40rem]">
            <div class="grid grid-cols-[1.2fr_1fr_0.8fr_1.5fr_1fr] gap-4 border-b-2 border-zinc-800 px-4 py-3 text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
              <span>{dgettext("lemmings", ".col_name")}</span>
              <span>{dgettext("lemmings", ".col_role")}</span>
              <span>{dgettext("lemmings", ".col_status")}</span>
              <span>{dgettext("lemmings", ".col_task")}</span>
              <span>{dgettext("lemmings", ".col_model")}</span>
            </div>

            <.link
              :for={lemming <- @lemmings}
              id={"lemming-link-#{lemming.id}"}
              patch={~p"/lemmings?#{%{lemming: lemming.id}}"}
              data-selected={to_string(@selected_lemming && @selected_lemming.id == lemming.id)}
              class={[
                "grid grid-cols-[1.2fr_1fr_0.8fr_1.5fr_1fr] items-center gap-4 border-b border-zinc-800/50 bg-zinc-950/40 px-4 py-3 text-sm transition-all hover:bg-zinc-900/60",
                @selected_lemming && @selected_lemming.id == lemming.id &&
                  "border-l-2 border-l-emerald-400 bg-emerald-400/5"
              ]}
            >
              <span class="font-medium text-zinc-100">{lemming.name}</span>
              <span class="text-zinc-400">{lemming.role}</span>
              <span>
                <.status kind={:lemming} value={lemming.status} />
              </span>
              <span class="truncate text-zinc-300">{lemming.current_task}</span>
              <span class="text-zinc-500 font-mono text-xs">{lemming.model}</span>
            </.link>
          </div>
        </.panel>

        <.lemming_detail_panel :if={@selected_lemming} lemming={@selected_lemming} />

        <.panel :if={!@selected_lemming} id="lemming-detail-empty">
          <:title>{dgettext("lemmings", ".title_agent_detail")}</:title>
          <.empty_state
            id="lemmings-empty-state"
            title={dgettext("lemmings", ".empty_select_lemming")}
            copy={dgettext("lemmings", ".empty_select_lemming_copy")}
          />
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  attr :lemming, :map, required: true

  def lemming_detail_panel(assigns) do
    department = MockData.department_for_lemming(assigns.lemming.id)
    city = department && MockData.city_for_department(department.id)

    assigns =
      assigns
      |> assign(:department, department)
      |> assign(:city, city)

    ~H"""
    <.panel id="lemming-detail-panel">
      <:title>{@lemming.name}</:title>
      <:subtitle>{@lemming.role}</:subtitle>
      <div class="flex flex-col gap-6">
        <div class="flex items-center gap-4">
          <div
            class="size-16 shrink-0 border-2 border-zinc-700 bg-zinc-900"
            style={accent_style(@lemming.accent)}
          >
          </div>
          <div class="flex flex-col gap-1 min-w-0">
            <.status kind={:lemming} value={@lemming.status} class="w-fit" />
            <p class="text-zinc-100 font-medium">{@lemming.current_task}</p>
            <small
              :if={@department && @city}
              class="text-zinc-500 font-mono text-[0.7rem] uppercase tracking-wider"
            >
              {@department.name} · {@city.name}
            </small>
          </div>
        </div>

        <div class="flex flex-col gap-1">
          <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_model")}
          </p>
          <p class="font-mono text-sm text-zinc-300">{@lemming.model}</p>
        </div>

        <div class="flex flex-col gap-1">
          <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_system_prompt")}
          </p>
          <p class="text-sm text-zinc-300 leading-relaxed">{@lemming.system_prompt}</p>
        </div>

        <div class="flex flex-col gap-2">
          <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_tools")}
          </p>
          <div class="flex flex-wrap gap-2">
            <.badge :for={tool <- @lemming.tools} tone="info">{tool}</.badge>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_recent_messages")}
          </p>
          <div class="flex flex-col gap-3 font-mono">
            <div :if={@lemming.recent_messages == []} class="text-sm text-zinc-500">
              <span>{dgettext("lemmings", ".empty_no_messages")}</span>
            </div>

            <div
              :for={message <- @lemming.recent_messages}
              class="flex flex-wrap items-start gap-3 text-sm"
            >
              <span class="text-xs tracking-widest text-zinc-500">[{message.time}]</span>
              <span class={[
                "font-bold",
                message.role == :assistant && "text-emerald-400"
              ]}>
                {role_label(message.role)}
              </span>
              <span class="text-zinc-300">{message.content}</span>
            </div>
          </div>
        </div>

        <div class="flex flex-col gap-2">
          <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
            {dgettext("lemmings", ".detail_activity_log")}
          </p>
          <div class="flex flex-col gap-2 font-mono">
            <div :for={item <- @lemming.activity_log} class="flex flex-wrap items-start gap-3 text-sm">
              <span class="text-xs tracking-widest text-zinc-500">[{item.time}]</span>
              <span class="text-zinc-400">{item.action}</span>
            </div>
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  attr :lemming, :map, required: true
  attr :size, :string, default: "sm", values: ~w(sm md)
  attr :path, :string, default: nil

  def lemming_sprite(assigns) do
    ~H"""
    <.link
      :if={@path}
      navigate={@path}
      class={[
        "inline-flex flex-col items-center gap-2 text-zinc-300 transition-all hover:-translate-y-px hover:text-emerald-400",
        sprite_size(@size)
      ]}
    >
      <div
        class={[
          "shrink-0 border-2 border-zinc-700 bg-zinc-900",
          if(@size == "md", do: "size-12", else: "size-10")
        ]}
        style={accent_style(@lemming.accent)}
      >
      </div>
      <span class="text-xs font-medium">{@lemming.name}</span>
    </.link>
    <div
      :if={!@path}
      class={["inline-flex flex-col items-center gap-2 text-zinc-300", sprite_size(@size)]}
    >
      <div
        class={[
          "shrink-0 border-2 border-zinc-700 bg-zinc-900",
          if(@size == "md", do: "size-12", else: "size-10")
        ]}
        style={accent_style(@lemming.accent)}
      >
      </div>
      <span class="text-xs font-medium">{@lemming.name}</span>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :selected_tools, :list, required: true
  attr :available_tools, :list, required: true

  def create_lemming_page(assigns) do
    ~H"""
    <.content_container>
      <.content_grid columns="sidebar">
        <.panel id="create-lemming-panel" tone="accent">
          <:title>{dgettext("lemmings", ".title_create_lemming")}</:title>
          <:subtitle>{dgettext("lemmings", ".subtitle_create_lemming")}</:subtitle>
          <.form for={@form} id="create-lemming-form" phx-change="validate" phx-submit="save">
            <div class="flex flex-col gap-6">
              <.input
                field={@form[:name]}
                label={dgettext("lemmings", ".label_name")}
                placeholder={dgettext("lemmings", ".placeholder_name")}
              />
              <.input
                field={@form[:role]}
                label={dgettext("lemmings", ".label_role")}
                placeholder={dgettext("lemmings", ".placeholder_role")}
              />
              <.input
                field={@form[:model]}
                type="select"
                label={dgettext("lemmings", ".label_model")}
                options={[
                  {"gpt-4o", "gpt-4o"},
                  {"gpt-4o-mini", "gpt-4o-mini"},
                  {"claude-3.5", "claude-3.5"},
                  {"claude-3-opus", "claude-3-opus"},
                  {"llama-3", "llama-3"}
                ]}
              />
              <.input
                field={@form[:system_prompt]}
                type="textarea"
                label={dgettext("lemmings", ".label_system_prompt")}
                rows="5"
              />

              <div class="flex flex-col gap-2">
                <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
                  {dgettext("lemmings", ".detail_tools_allowed")}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button
                    :for={tool <- @available_tools}
                    id={"tool-toggle-#{tool}"}
                    type="button"
                    phx-click="toggle_tool"
                    phx-value-tool={tool}
                    class={[
                      "border-2 px-3 py-1.5 text-xs font-medium transition-all duration-150",
                      tool in @selected_tools &&
                        "border-emerald-400/60 bg-emerald-400/10 text-emerald-400 shadow-md",
                      tool not in @selected_tools &&
                        "border-zinc-700 bg-zinc-950/80 text-zinc-400 hover:border-zinc-600 hover:text-zinc-200"
                    ]}
                  >
                    {tool}
                  </button>
                </div>
              </div>

              <.button type="submit" class="w-full sm:w-fit">
                {dgettext("lemmings", ".button_deploy_lemming")}
              </.button>
            </div>
          </.form>
        </.panel>

        <.panel id="create-lemming-preview">
          <:title>{dgettext("lemmings", ".title_deployment_preview")}</:title>
          <div class="flex flex-col gap-6">
            <div class="flex flex-col gap-2">
              <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_selected_tooling")}
              </p>
              <div class="flex flex-wrap gap-2">
                <.badge :for={tool <- @selected_tools} tone="accent">{tool}</.badge>
                <.badge :if={@selected_tools == []} tone="default">
                  {dgettext("lemmings", ".empty_no_tools_selected")}
                </.badge>
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <p class="text-[0.68rem] font-bold uppercase tracking-widest text-zinc-500">
                {dgettext("lemmings", ".detail_expected_outcome")}
              </p>
              <p class="text-sm text-zinc-400 leading-relaxed">
                {dgettext("lemmings", ".copy_expected_outcome")}
              </p>
            </div>
          </div>
        </.panel>
      </.content_grid>
    </.content_container>
    """
  end

  defp accent_style(color), do: "background-color: #{color};"
  defp resolve_animation("default", _seed), do: "blink"

  defp resolve_animation("random", seed),
    do: pick_variant(~w(blink none), seed)

  defp resolve_animation(animation, _seed), do: animation

  defp resolve_palette("default", _seed), do: "aqua"

  defp resolve_palette("random", seed),
    do: pick_variant(~w(aqua lime amber violet coral slate), "#{seed}-palette")

  defp resolve_palette(palette, _seed), do: palette

  defp pick_variant(options, seed) do
    index = :erlang.phash2(seed, length(options))
    Enum.at(options, index)
  end

  defp animation_class("blink"), do: "lemming-logo--blink"
  defp animation_class(_), do: nil

  defp eye_animation("blink"), do: "lemming-logo__eyes--blink"
  defp eye_animation(_), do: nil

  defp palette_style(colors) do
    Enum.map_join(colors, "; ", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp palette_colors("aqua") do
    %{
      "--lemming-logo-head" => "#10D7FF",
      "--lemming-logo-chat" => "#FFD43B",
      "--lemming-logo-shadow" => "#16576D",
      "--lemming-logo-body" => "#07AAd6"
    }
  end

  defp palette_colors("lime") do
    %{
      "--lemming-logo-head" => "#8BF55F",
      "--lemming-logo-chat" => "#D9FF66",
      "--lemming-logo-shadow" => "#2A6B32",
      "--lemming-logo-body" => "#52C05E"
    }
  end

  defp palette_colors("amber") do
    %{
      "--lemming-logo-head" => "#FFC857",
      "--lemming-logo-chat" => "#FFF2A6",
      "--lemming-logo-shadow" => "#7A4E17",
      "--lemming-logo-body" => "#F18F01"
    }
  end

  defp palette_colors("violet") do
    %{
      "--lemming-logo-head" => "#D08BFF",
      "--lemming-logo-chat" => "#73F7FF",
      "--lemming-logo-shadow" => "#4C2A73",
      "--lemming-logo-body" => "#8B5CF6"
    }
  end

  defp palette_colors("coral") do
    %{
      "--lemming-logo-head" => "#FF8A7A",
      "--lemming-logo-chat" => "#FFE27A",
      "--lemming-logo-shadow" => "#7B3440",
      "--lemming-logo-body" => "#F65D7A"
    }
  end

  defp palette_colors("slate") do
    %{
      "--lemming-logo-head" => "#B2C7D9",
      "--lemming-logo-chat" => "#7AF0FF",
      "--lemming-logo-shadow" => "#334B5F",
      "--lemming-logo-body" => "#5D7D99"
    }
  end

  defp sprite_size("sm"), do: nil
  defp sprite_size("md"), do: "sprite-card--md"
  defp role_label(:assistant), do: dgettext("lemmings", ".role_agent")
  defp role_label(:user), do: dgettext("lemmings", ".role_user")
end
