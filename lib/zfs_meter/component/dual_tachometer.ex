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

  # OLED color palette (red to green spectrum)
  # Pure black
  @color_bg {0, 0, 0}
  # Very dark amber
  @color_dial {15, 10, 0}
  # Amber border
  @color_border {100, 70, 0}
  # Amber text
  @color_text {255, 180, 0}
  # Orange needle
  @color_needle {255, 140, 0}
  # Darker amber ticks
  @color_tick {180, 120, 0}
  # Green arc
  @color_green {0, 255, 0}
  # Yellow arc
  @color_yellow {255, 255, 0}
  # Red arc
  @color_red {255, 0, 0}

  @impl Scenic.Component
  def validate({left_rpm, right_rpm}) when is_number(left_rpm) and is_number(right_rpm) do
    {:ok, {left_rpm, right_rpm}}
  end

  def validate(_), do: {:error, "Expected {left_rpm, right_rpm}"}

  @impl Scenic.Scene
  def init(scene, {left_rpm, right_rpm}, opts) do
    simulate = Keyword.get(opts, :simulate, true)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(left_rpm, right_rpm)

    scene
    |> assign(
      left_rpm: left_rpm,
      right_rpm: right_rpm,
      left_target: left_rpm,
      right_target: right_rpm,
      simulate: simulate
    )
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  # Handle external updates from parent scene
  @impl Scenic.Scene
  def handle_put({left_rpm, right_rpm}, scene) do
    graph = build_graph(left_rpm, right_rpm)

    scene
    |> assign(left_rpm: left_rpm, right_rpm: right_rpm)
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

    graph = build_graph(left_rpm, right_rpm)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(
      left_rpm: left_rpm,
      right_rpm: right_rpm,
      left_target: left_target,
      right_target: right_target
    )
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(left_rpm, right_rpm) do
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
    |> draw_range_arc(arc_radius, arc_width, @green_min, @green_max, @color_green, side)
    |> draw_range_arc(arc_radius, arc_width, @green_max, @yellow_max, @color_yellow, side)
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
    |> circle(28, fill: {40, 30, 0}, stroke: {4, @color_border})
    |> circle(12, fill: {60, 45, 0})
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
