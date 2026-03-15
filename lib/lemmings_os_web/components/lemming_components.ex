defmodule LemmingsOsWeb.LemmingComponents do
  @moduledoc """
  Components for lemming lists, detail panels, and creation flows.
  """

  use LemmingsOsWeb, :html

  alias LemmingsOs.MockData

  attr :class, :string, default: nil

  def brand_wordmark(assigns) do
    ~H"""
    <span class={["brand-wordmark", @class]}>
      <span class="brand-wordmark__main">Lemmings</span><span class="brand-wordmark__os">OS</span>
    </span>
    """
  end

  attr :size, :integer, default: 32
  attr :seed, :string, default: "lemming-logo"

  # TODO: add CSS @keyframes for jump / head-turn / eyes-scan / walk
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
        <:title>All Lemmings</:title>
        <:subtitle>Mock agent registry for future real LiveView behavior.</:subtitle>
      </.panel>

      <.content_grid id="lemmings-grid" columns="sidebar">
        <.panel id="lemmings-table-panel">
          <:title>Agent Registry</:title>
          <div class="data-table">
            <div class="data-table__header">
              <span>Name</span>
              <span>Role</span>
              <span>Status</span>
              <span>Task</span>
              <span>Model</span>
            </div>

            <.link
              :for={lemming <- @lemmings}
              id={"lemming-link-#{lemming.id}"}
              patch={~p"/lemmings?#{%{lemming: lemming.id}}"}
              class={[
                "data-table__row",
                @selected_lemming && @selected_lemming.id == lemming.id && "data-table__row--active"
              ]}
            >
              <span>{lemming.name}</span>
              <span>{lemming.role}</span>
              <span>
                <.badge tone={status_tone(lemming.status)}>{status_label(lemming.status)}</.badge>
              </span>
              <span class="truncate">{lemming.current_task}</span>
              <span>{lemming.model}</span>
            </.link>
          </div>
        </.panel>

        <.lemming_detail_panel :if={@selected_lemming} lemming={@selected_lemming} />

        <.panel :if={!@selected_lemming} id="lemming-detail-empty">
          <:title>Agent Detail</:title>
          <.empty_state
            id="lemmings-empty-state"
            title="Select a lemming"
            copy="Choose an agent from the registry to inspect its task, model, tools, and activity."
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
      <div class="page-stack">
        <div class="detail-hero">
          <div class="detail-hero__avatar" style={accent_style(@lemming.accent)}></div>
          <div class="detail-hero__copy">
            <.badge tone={status_tone(@lemming.status)}>{status_label(@lemming.status)}</.badge>
            <p>{@lemming.current_task}</p>
            <small :if={@department && @city}>{@department.name} · {@city.name}</small>
          </div>
        </div>

        <div class="detail-section">
          <p class="detail-section__title">Model</p>
          <p>{@lemming.model}</p>
        </div>

        <div class="detail-section">
          <p class="detail-section__title">System Prompt</p>
          <p>{@lemming.system_prompt}</p>
        </div>

        <div class="detail-section">
          <p class="detail-section__title">Tools</p>
          <div class="tool-badges">
            <.badge :for={tool <- @lemming.tools} tone="info">{tool}</.badge>
          </div>
        </div>

        <div class="detail-section">
          <p class="detail-section__title">Recent Messages</p>
          <div class="activity-feed">
            <div :if={@lemming.recent_messages == []} class="activity-feed__row">
              <span>No messages yet.</span>
            </div>

            <div :for={message <- @lemming.recent_messages} class="activity-feed__row">
              <span class="activity-feed__time">[{message.time}]</span>
              <span class={[
                "activity-feed__agent",
                message.role == :assistant && "activity-feed__agent--accent"
              ]}>
                {role_label(message.role)}
              </span>
              <span>{message.content}</span>
            </div>
          </div>
        </div>

        <div class="detail-section">
          <p class="detail-section__title">Activity Log</p>
          <div class="activity-feed">
            <div :for={item <- @lemming.activity_log} class="activity-feed__row">
              <span class="activity-feed__time">[{item.time}]</span>
              <span>{item.action}</span>
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
    <.link :if={@path} navigate={@path} class={["sprite-card", sprite_size(@size)]}>
      <div class="sprite-card__figure" style={accent_style(@lemming.accent)}></div>
      <span>{@lemming.name}</span>
    </.link>
    <div :if={!@path} class={["sprite-card", sprite_size(@size)]}>
      <div class="sprite-card__figure" style={accent_style(@lemming.accent)}></div>
      <span>{@lemming.name}</span>
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
          <:title>Create New Lemming</:title>
          <:subtitle>Mock form now, real workflow later.</:subtitle>
          <.form for={@form} id="create-lemming-form" phx-change="validate" phx-submit="save">
            <div class="page-stack">
              <.input field={@form[:name]} label="Name" placeholder="e.g. Turing" />
              <.input field={@form[:role]} label="Role" placeholder="e.g. Reliability Engineer" />
              <.input
                field={@form[:model]}
                type="select"
                label="Model"
                options={[
                  {"gpt-4o", "gpt-4o"},
                  {"gpt-4o-mini", "gpt-4o-mini"},
                  {"claude-3.5", "claude-3.5"},
                  {"claude-3-opus", "claude-3-opus"},
                  {"llama-3", "llama-3"}
                ]}
              />
              <.input field={@form[:system_prompt]} type="textarea" label="System Prompt" rows="5" />

              <div class="detail-section">
                <p class="detail-section__title">Tools Allowed</p>
                <div class="tool-toggle-grid">
                  <button
                    :for={tool <- @available_tools}
                    id={"tool-toggle-#{tool}"}
                    type="button"
                    phx-click="toggle_tool"
                    phx-value-tool={tool}
                    class={[
                      "tool-toggle",
                      tool in @selected_tools && "tool-toggle--active"
                    ]}
                  >
                    {tool}
                  </button>
                </div>
              </div>

              <.button type="submit">Deploy Lemming</.button>
            </div>
          </.form>
        </.panel>

        <.panel id="create-lemming-preview">
          <:title>Deployment Preview</:title>
          <div class="page-stack">
            <div class="detail-section">
              <p class="detail-section__title">Selected Tooling</p>
              <div class="tool-badges">
                <.badge :for={tool <- @selected_tools} tone="accent">{tool}</.badge>
                <.badge :if={@selected_tools == []} tone="default">No tools selected</.badge>
              </div>
            </div>

            <div class="detail-section">
              <p class="detail-section__title">Expected Outcome</p>
              <p>
                This submit path is intentionally mocked. It exercises the LiveView form flow, keeps the shell
                interactive, and provides the shape we will connect to real persistence in the next tickets.
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
  defp role_label(:assistant), do: "AGENT"
  defp role_label(:user), do: "USER"
  defp status_tone(:running), do: "success"
  defp status_tone(:thinking), do: "warning"
  defp status_tone(:error), do: "danger"
  defp status_tone(_), do: "default"
  defp status_label(:running), do: "RUNNING"
  defp status_label(:thinking), do: "THINKING"
  defp status_label(:error), do: "ERROR"
  defp status_label(:idle), do: "IDLE"
  defp status_label(status), do: status |> Atom.to_string() |> String.upcase()
end
