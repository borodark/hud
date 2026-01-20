defmodule ZfsMeter.Component.DiskGauge do
  @moduledoc """
  A gauge component showing disk activity rate in MB/s.

  Displays a semicircular gauge with color-coded fill based on activity level.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  @radius 160
  @max_angle :math.pi()
  @max_rate 500.0  # Maximum MB/s for full scale
  @update_interval 500  # ms
  @stroke_width 32

  # Colors for different activity levels
  @color_low {80, 200, 120}      # Green
  @color_medium {255, 200, 50}   # Yellow
  @color_high {255, 80, 80}      # Red
  @color_bg {60, 60, 70}         # Dark gray background

  @impl Scenic.Component
  def validate(rate) when is_number(rate) and rate >= 0, do: {:ok, rate}
  def validate(_), do: {:error, "Expected a non-negative number (MB/s)"}

  @impl Scenic.Scene
  def init(scene, rate, _opts) do
    # Start update timer
    Process.send_after(self(), :tick, @update_interval)

    graph = build_graph(rate)

    scene =
      scene
      |> assign(rate: rate, graph: graph)
      |> push_graph(graph)

    {:ok, scene}
  end

  @impl GenServer
  def handle_info(:tick, scene) do
    # For now, simulate with random data
    # TODO: Replace with real ZFS stats
    rate = :rand.uniform() * 200

    graph = build_graph(rate)

    Process.send_after(self(), :tick, @update_interval)

    scene =
      scene
      |> assign(rate: rate, graph: graph)
      |> push_graph(graph)

    {:noreply, scene}
  end

  defp build_graph(rate) do
    normalized = min(1.0, rate / @max_rate)
    angle = normalized * @max_angle
    color = rate_color(rate)

    Graph.build()
    |> group(
      fn g ->
        g
        # Background arc
        |> arc({@radius, @max_angle}, stroke: {@stroke_width, @color_bg}, cap: :round)
        # Active indicator (only if there's activity)
        |> maybe_draw_indicator(angle, color)
        # Center value text
        |> text(format_rate(rate),
          font_size: 36,
          fill: :white,
          text_align: :center,
          translate: {0, 30}
        )
      end,
      rotate: -@max_angle / 2
    )
  end

  defp maybe_draw_indicator(graph, angle, _color) when angle < 0.01, do: graph

  defp maybe_draw_indicator(graph, angle, color) do
    graph
    |> arc({@radius, angle}, stroke: {@stroke_width - 4, color}, cap: :round)
  end

  defp format_rate(rate) when rate < 1, do: "#{trunc(rate * 1024)} KB/s"
  defp format_rate(rate), do: "#{Float.round(rate, 1)} MB/s"

  defp rate_color(rate) when rate < 50, do: @color_low
  defp rate_color(rate) when rate < 200, do: @color_medium
  defp rate_color(_), do: @color_high
end
