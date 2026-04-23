defmodule LemmingsOsWeb.LemmingImageComponents do
  @moduledoc """
  Visual primitives for lemming branding and deterministic type avatars.
  """

  use LemmingsOsWeb, :html

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
  attr :animation, :string, default: "default", values: ~w(default random blink none)

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

  attr :slug, :string, required: true
  attr :size, :integer, default: 48
  attr :id, :string, default: "lemming-type-avatar"
  attr :class, :string, default: nil

  def lemming_type_avatar(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "inline-flex shrink-0 items-center justify-center border-2 border-zinc-800 bg-zinc-950/80 p-2",
        @class
      ]}
    >
      <.lemming_logo size={@size} seed={@slug} palette="random" animation="none" />
    </div>
    """
  end

  defp resolve_animation("default", _seed), do: "blink"
  defp resolve_animation("random", seed), do: pick_variant(~w(blink none), seed)
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
end
