defmodule ZfsMeter.Component.DualTachometer do
  @moduledoc """
  Dual aircraft engine tachometer - both engines share a common center point.

  Creates "( )" layout with single center pivot for both needles.
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  @radius 320
  @update_interval 50

  # RPM range
  @min_rpm 0
  @max_rpm 3500

  # Operating ranges (RPM)
  @green_min 2100
  @green_max 2700
  @yellow_max 3000
  @redline 3000

  # Semicircle sweep (180 degrees)
  @sweep_angle :math.pi()

  # OLED color palette (yellow -> red spectrum + black)
  @color_black {0, 0, 0}
  @color_yellow {255, 220, 0}
  @color_amber {255, 180, 0}
  @color_orange {255, 140, 0}
  @color_deep_orange {255, 100, 0}
  @color_red_orange {255, 60, 0}
  @color_warm_red {255, 30, 0}
  @color_red {255, 0, 0}

  # Semantic aliases
  @color_bg @color_black
  @color_dial @color_black
  @color_border @color_deep_orange
  @color_text @color_amber
  @color_needle @color_orange
  @color_tick @color_warm_red

  @impl Scenic.Component
  def validate({left_rpm, right_rpm, left_oil, right_oil})
      when is_number(left_rpm) and is_number(right_rpm) and is_number(left_oil) and is_number(right_oil) do
    {:ok, {left_rpm, right_rpm, left_oil, right_oil}}
  end

  def validate(_), do: {:error, "Expected {left_rpm, right_rpm, left_oil_temp, right_oil_temp}"}

  @impl Scenic.Scene
  def init(scene, {left_rpm, right_rpm, left_oil, right_oil}, opts) do
    simulate = Keyword.get(opts, :simulate, true)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(left_rpm, right_rpm, left_oil, right_oil)

    scene
    |> assign(
      left_rpm: left_rpm,
      right_rpm: right_rpm,
      left_target: left_rpm,
      right_target: right_rpm,
      left_oil: left_oil,
      right_oil: right_oil,
      simulate: simulate
    )
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  # Handle external updates from parent scene
  @impl Scenic.Scene
  def handle_put({left_rpm, right_rpm, left_oil, right_oil}, scene) do
    graph = build_graph(left_rpm, right_rpm, left_oil, right_oil)

    scene
    |> assign(left_rpm: left_rpm, right_rpm: right_rpm, left_oil: left_oil, right_oil: right_oil)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{
      left_rpm: left_current,
      right_rpm: right_current,
      left_target: left_target,
      right_target: right_target
    } = scene.assigns

    # Simulate RPM changes for both engines
    left_target =
      if :rand.uniform() < 0.03 do
        1800 + :rand.uniform() * 1000
      else
        left_target
      end

    right_target =
      if :rand.uniform() < 0.03 do
        1800 + :rand.uniform() * 1000
      else
        right_target
      end

    # Smooth movement
    left_rpm = left_current + (left_target - left_current) * 0.1
    right_rpm = right_current + (right_target - right_current) * 0.1

    # Simulate oil temps (correlate with RPM)
    left_oil_sim = 50 + (left_rpm / @max_rpm) * 60
    right_oil_sim = 50 + (right_rpm / @max_rpm) * 60

    graph = build_graph(left_rpm, right_rpm, left_oil_sim, right_oil_sim)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(
      left_rpm: left_rpm,
      right_rpm: right_rpm,
      left_target: left_target,
      right_target: right_target,
      left_oil: left_oil_sim,
      right_oil: right_oil_sim
    )
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(left_rpm, right_rpm, left_oil, right_oil) do
    Graph.build()
    |> group(
      fn g ->
        g
        # Draw both dial faces first (backgrounds)
        |> draw_dial_face(:left)
        |> draw_dial_face(:right)
        # Then colored arcs for both
        |> draw_colored_arcs(:left)
        |> draw_colored_arcs(:right)
        # Tick marks for both
        |> draw_tick_marks(:left)
        |> draw_tick_marks(:right)
        # Numbers for both
        |> draw_numbers(:left)
        |> draw_numbers(:right)
        # Labels for both
        |> draw_labels(:left)
        |> draw_labels(:right)
        # Oil temperature displays
        |> draw_oil_temp(left_oil, :left)
        |> draw_oil_temp(right_oil, :right)
        # Both needles
        |> draw_needle(left_rpm, :left)
        |> draw_needle(right_rpm, :right)
        # Single shared center cap (drawn last, on top)
        |> draw_center_cap()
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  defp draw_dial_face(graph, side) do
    {start, sweep} =
      case side do
        # Bottom to top, curving left
        :left -> {:math.pi() / 2, @sweep_angle}
        # Top to bottom, curving right
        :right -> {-:math.pi() / 2, @sweep_angle}
      end

    graph
    |> sector({@radius, sweep},
      fill: @color_bg,
      stroke: {6, @color_border},
      rotate: start
    )
    |> sector({@radius - 6, sweep},
      fill: @color_dial,
      rotate: start
    )
  end

  defp draw_colored_arcs(graph, side) do
    arc_radius = @radius - 35
    arc_width = 22

    graph
    |> draw_range_arc(arc_radius, arc_width, @green_min, @green_max, @color_orange, side)
    |> draw_range_arc(arc_radius, arc_width, @green_max, @yellow_max, @color_deep_orange, side)
    |> draw_range_arc(arc_radius, arc_width, @yellow_max, @max_rpm, @color_red, side)
    |> draw_redline(side)
  end

  defp draw_range_arc(graph, arc_radius, arc_width, rpm_start, rpm_end, color, side) do
    start_angle = rpm_to_angle(rpm_start, side)
    end_angle = rpm_to_angle(rpm_end, side)

    sweep = end_angle - start_angle

    graph
    |> arc({arc_radius, sweep},
      stroke: {arc_width, color},
      rotate: start_angle,
      cap: :butt
    )
  end

  defp draw_redline(graph, side) do
    angle = rpm_to_angle(@redline, side)
    inner = @radius - 65
    outer = @radius - 12

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph
    |> line({{x1, y1}, {x2, y2}}, stroke: {5, @color_red}, cap: :round)
  end

  defp draw_tick_marks(graph, side) do
    graph
    |> draw_major_ticks(side)
    |> draw_minor_ticks(side)
  end

  defp draw_major_ticks(graph, side) do
    Enum.reduce(0..7, graph, fn i, g ->
      rpm = i * 500
      angle = rpm_to_angle(rpm, side)
      draw_tick(g, angle, 6, 45)
    end)
  end

  defp draw_minor_ticks(graph, side) do
    Enum.reduce(0..35, graph, fn i, g ->
      rpm = i * 100

      if rem(i, 5) == 0 do
        g
      else
        angle = rpm_to_angle(rpm, side)
        draw_tick(g, angle, 2, 28)
      end
    end)
  end

  defp draw_tick(graph, angle, width, length) do
    inner = @radius - 12 - length
    outer = @radius - 12

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {width, @color_tick}, cap: :round)
  end

  defp draw_numbers(graph, side) do
    numbers = [0, 5, 10, 15, 20, 25, 30, 35]

    Enum.reduce(numbers, graph, fn n, g ->
      rpm = n * 100
      angle = rpm_to_angle(rpm, side)
      dist = @radius - 85

      x = :math.cos(angle) * dist
      y = :math.sin(angle) * dist

      g
      |> text("#{n}",
        fill: @color_text,
        font_size: 38,
        text_align: :center,
        translate: {x, y + 14}
      )
    end)
  end

  defp draw_labels(graph, side) do
    {label_x, align} =
      case side do
        :left -> {-@radius + 80, :left}
        :right -> {@radius - 80, :right}
      end

    graph
    |> text("RPM",
      fill: @color_text,
      font_size: 32,
      text_align: align,
      translate: {label_x, -@radius + 100}
    )
    |> text("×100",
      fill: @color_tick,
      font_size: 24,
      text_align: align,
      translate: {label_x, -@radius + 135}
    )
  end

  defp draw_oil_temp(graph, temp, side) do
    # Position between center and numbers 15/20
    x = case side do
      :left -> -150
      :right -> 150
    end

    # 7 bars configuration
    bar_width = 28
    bar_height = 10
    bar_gap = 3
    total_height = 7 * bar_height + 6 * bar_gap
    start_y = total_height / 2 - bar_height / 2

    # Temperature thresholds for each bar (bottom to top)
    # Bars light up as temp increases
    thresholds = [30, 50, 65, 80, 95, 105, 115]

    # Bar colors: yellow -> orange -> red gradient
    bar_colors = [
      {255, 220, 0},   # Bar 1 - yellow (cold)
      {255, 180, 0},   # Bar 2 - amber
      {255, 140, 0},   # Bar 3 - orange (optimal)
      {255, 100, 0},   # Bar 4 - deep orange (optimal)
      {255, 60, 0},    # Bar 5 - red-orange
      {255, 30, 0},    # Bar 6 - warm red
      {255, 0, 0}      # Bar 7 - red (hot)
    ]

    # Dim versions of colors for inactive bars
    dim_factor = 0.2

    Enum.reduce(0..6, graph, fn i, g ->
      threshold = Enum.at(thresholds, i)
      color = Enum.at(bar_colors, i)
      y = start_y - i * (bar_height + bar_gap)

      # Bar is active if temp >= threshold
      active = temp >= threshold

      fill = if active do
        color
      else
        # Dim the color
        {r, g_val, b} = color
        {trunc(r * dim_factor), trunc(g_val * dim_factor), trunc(b * dim_factor)}
      end

      g
      |> rrect({bar_width, bar_height, 2},
        fill: fill,
        translate: {x - bar_width / 2, y}
      )
    end)
  end

  defp draw_needle(graph, rpm, side) do
    clamped = max(@min_rpm, min(@max_rpm, rpm))
    angle = rpm_to_angle(clamped, side)
    needle_length = @radius - 50
    tail_length = 40

    graph
    |> group(fn g ->
      g
      |> line({{0, 0}, {:math.cos(angle) * needle_length, :math.sin(angle) * needle_length}},
        stroke: {6, @color_needle},
        cap: :round
      )
      |> line(
        {{0, 0},
         {:math.cos(angle + :math.pi()) * tail_length,
          :math.sin(angle + :math.pi()) * tail_length}},
        stroke: {6, @color_needle},
        cap: :round
      )
    end)
  end

  defp draw_center_cap(graph) do
    graph
    |> circle(28, fill: @color_black, stroke: {4, @color_border})
    |> circle(12, fill: @color_deep_orange)
  end

  # Convert RPM to angle
  # Left "(": 0 RPM at bottom, max at top, needle on LEFT side
  # Right ")": 0 RPM at bottom, max at top, needle on RIGHT side
  defp rpm_to_angle(rpm, side) do
    fraction = (rpm - @min_rpm) / (@max_rpm - @min_rpm)

    case side do
      :left ->
        # Bottom (π/2) to top (3π/2), going through left side (π)
        :math.pi() / 2 + fraction * @sweep_angle

      :right ->
        # Bottom (π/2) to top (-π/2), going through right side (0)
        :math.pi() / 2 - fraction * @sweep_angle
    end
  end
end
