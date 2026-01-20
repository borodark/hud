defmodule ZfsMeter.Component.Tachometer do
  @moduledoc """
  Aircraft engine tachometer (RPM gauge) - semicircular design.

  Both engines share a common center point, creating "( )" layout.
  - Left engine: "(" shape curving left
  - Right engine: ")" shape curving right
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

  @impl Scenic.Component
  def validate({rpm, side}) when is_number(rpm) and side in [:left, :right],
    do: {:ok, {rpm, side}}

  def validate(rpm) when is_number(rpm), do: {:ok, {rpm, :left}}
  def validate(_), do: {:error, "Expected {rpm, :left | :right} or just rpm"}

  @impl Scenic.Scene
  def init(scene, {rpm, side}, opts) do
    Process.send_after(self(), :tick, @update_interval)

    graph = build_graph(rpm, side)

    scene
    |> assign(rpm: rpm, target: rpm, side: side, id: opts[:id])
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl GenServer
  def handle_info(:tick, scene) do
    %{rpm: current, target: target, side: side} = scene.assigns

    target =
      if :rand.uniform() < 0.03 do
        1800 + :rand.uniform() * 1000
      else
        target
      end

    diff = target - current
    new_rpm = current + diff * 0.1

    graph = build_graph(new_rpm, side)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(rpm: new_rpm, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(rpm, side) do
    # Center point is at origin - both dials mount here
    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face(side)
        |> draw_colored_arcs(side)
        |> draw_tick_marks(side)
        |> draw_numbers(side)
        |> draw_labels(side)
        |> draw_needle(rpm, side)
        |> draw_center_cap()
      end,
      translate: {20, @radius + 20}
    )
  end

  defp draw_dial_face(graph, side) do
    # Left "(": sector from π/2 to -π/2 (right half, curving left)
    # Right ")": sector from π/2 to 3π/2 (left half, curving right)
    {start, sweep} =
      case side do
        # Top to bottom, curving left
        :left -> {-:math.pi() / 2, @sweep_angle}
        # Bottom to top, curving right
        :right -> {:math.pi() / 2, @sweep_angle}
      end

    graph
    |> sector({@radius, sweep},
      fill: {20, 20, 20},
      stroke: {6, :white},
      rotate: start
    )
    |> sector({@radius - 6, sweep},
      fill: {30, 30, 35},
      rotate: start
    )
  end

  defp draw_colored_arcs(graph, side) do
    arc_radius = @radius - 35
    arc_width = 22

    graph
    |> draw_range_arc(arc_radius, arc_width, @green_min, @green_max, {80, 200, 80}, side)
    |> draw_range_arc(arc_radius, arc_width, @green_max, @yellow_max, {220, 200, 50}, side)
    |> draw_range_arc(arc_radius, arc_width, @yellow_max, @max_rpm, {220, 60, 60}, side)
    |> draw_redline(side)
  end

  defp draw_range_arc(graph, arc_radius, arc_width, rpm_start, rpm_end, color, side) do
    start_angle = rpm_to_angle(rpm_start, side)
    end_angle = rpm_to_angle(rpm_end, side)

    # Calculate sweep - direction depends on side
    sweep =
      case side do
        # Counter-clockwise (negative)
        :left -> start_angle - end_angle
        # Clockwise (positive)
        :right -> end_angle - start_angle
      end

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
    |> line({{x1, y1}, {x2, y2}}, stroke: {5, {255, 0, 0}}, cap: :round)
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

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {width, :white}, cap: :round)
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
        fill: :white,
        font_size: 38,
        text_align: :center,
        translate: {x, y + 14}
      )
    end)
  end

  defp draw_labels(graph, side) do
    # Labels in the outer corner area
    {label_x, align} =
      case side do
        :left -> {-@radius + 80, :left}
        :right -> {@radius - 80, :right}
      end

    graph
    |> text("RPM",
      fill: {:white, 220},
      font_size: 32,
      text_align: align,
      translate: {label_x, -@radius + 100}
    )
    |> text("×100",
      fill: {:white, 180},
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
        stroke: {6, :white},
        cap: :round
      )
      |> line(
        {{0, 0},
         {:math.cos(angle + :math.pi()) * tail_length,
          :math.sin(angle + :math.pi()) * tail_length}},
        stroke: {6, :white},
        cap: :round
      )
    end)
  end

  defp draw_center_cap(graph) do
    graph
    |> circle(28, fill: {50, 50, 55}, stroke: {4, {:white, 128}})
    |> circle(12, fill: {80, 80, 85})
  end

  # Convert RPM to angle
  # Left "(": 0 RPM at bottom (π/2), max at top (-π/2), needle sweeps on LEFT side
  # Right ")": 0 RPM at bottom (π/2), max at top (-π/2), needle sweeps on RIGHT side
  defp rpm_to_angle(rpm, side) do
    fraction = (rpm - @min_rpm) / (@max_rpm - @min_rpm)

    case side do
      :left ->
        # Bottom (π/2) to top (-π/2), going counter-clockwise through LEFT side (π)
        :math.pi() / 2 + fraction * @sweep_angle

      :right ->
        # Bottom (π/2) to top (-π/2), going clockwise through RIGHT side (0)
        :math.pi() / 2 - fraction * @sweep_angle
    end
  end
end
