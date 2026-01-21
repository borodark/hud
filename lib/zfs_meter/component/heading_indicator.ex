defmodule ZfsMeter.Component.HeadingIndicator do
  @moduledoc """
  Heading Indicator (Directional Gyro) - shows aircraft magnetic heading.

  - Rotating compass card (0-360°)
  - Cardinal directions (N, E, S, W)
  - Fixed lubber line at top
  - Current heading shown at 12 o'clock position
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  alias ZfsMeter.ColorScheme
  import Scenic.Primitives

  @radius 310
  @update_interval 50

  @impl Scenic.Component
  def validate(heading) when is_number(heading), do: {:ok, heading}
  def validate(_), do: {:error, "Expected heading in degrees (0-360)"}

  @impl Scenic.Scene
  def init(scene, heading, opts) do
    simulate = Keyword.get(opts, :simulate, true)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(heading)

    scene
    |> assign(heading: heading, target: heading, simulate: simulate)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl Scenic.Scene
  def handle_put(heading, scene) when is_number(heading) do
    graph = build_graph(heading)

    scene
    |> assign(heading: heading)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{heading: current, target: target} = scene.assigns

    # Randomly adjust target occasionally
    target =
      if :rand.uniform() < 0.02 do
        :rand.uniform() * 360
      else
        target
      end

    # Smoothly turn toward target (shortest path)
    diff = target - current
    diff = cond do
      diff > 180 -> diff - 360
      diff < -180 -> diff + 360
      true -> diff
    end

    new_heading = current + diff * 0.05

    # Normalize
    new_heading = cond do
      new_heading >= 360 -> new_heading - 360
      new_heading < 0 -> new_heading + 360
      true -> new_heading
    end

    graph = build_graph(new_heading)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(heading: new_heading, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(heading) do
    c = ColorScheme.current()

    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face(c)
        |> draw_compass_card(heading, c)
        |> draw_lubber_line(c)
        |> draw_aircraft_symbol(c)
        |> draw_readout(heading, c)
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  defp draw_dial_face(graph, c) do
    graph
    |> circle(@radius, fill: c.bg, stroke: {8, c.border})
    |> circle(@radius - 8, fill: c.bg)
  end

  defp draw_compass_card(graph, heading, c) do
    # Rotate the entire compass card so current heading is at top
    rotation = -heading * :math.pi() / 180

    graph
    |> group(
      fn g ->
        g
        |> draw_degree_ticks(c)
        |> draw_degree_numbers(c)
        |> draw_cardinal_directions(c)
      end,
      rotate: rotation
    )
  end

  defp draw_degree_ticks(graph, c) do
    # Draw tick marks every 5 degrees, longer every 10
    Enum.reduce(0..35, graph, fn i, g ->
      angle_deg = i * 10
      angle_rad = angle_deg * :math.pi() / 180

      # Every 30° gets longest tick, every 10° medium, every 5° short
      {length, width} = cond do
        rem(angle_deg, 30) == 0 -> {40, 4}
        true -> {25, 2}
      end

      inner = @radius - 20 - length
      outer = @radius - 20

      x1 = :math.sin(angle_rad) * inner
      y1 = -:math.cos(angle_rad) * inner
      x2 = :math.sin(angle_rad) * outer
      y2 = -:math.cos(angle_rad) * outer

      g |> line({{x1, y1}, {x2, y2}}, stroke: {width, c.tick}, cap: :round)
    end)
  end

  defp draw_degree_numbers(graph, c) do
    # Draw numbers every 30 degrees (showing as 3, 6, 9, etc. or N, E, S, W)
    numbers = [
      {0, "N"}, {30, "3"}, {60, "6"}, {90, "E"},
      {120, "12"}, {150, "15"}, {180, "S"}, {210, "21"},
      {240, "24"}, {270, "W"}, {300, "30"}, {330, "33"}
    ]

    Enum.reduce(numbers, graph, fn {angle_deg, label}, g ->
      # Skip cardinals, they're drawn separately
      if label in ["N", "E", "S", "W"] do
        g
      else
        draw_rotated_number(g, angle_deg, label, c)
      end
    end)
  end

  defp draw_rotated_number(graph, angle_deg, label, c) do
    angle_rad = angle_deg * :math.pi() / 180
    dist = @radius - 80

    x = :math.sin(angle_rad) * dist
    y = -:math.cos(angle_rad) * dist

    # Rotate text to be readable (counter-rotate by same angle)
    graph
    |> group(
      fn g ->
        g
        |> text(label,
          fill: c.primary,
          font_size: 36,
          text_align: :center,
          translate: {0, 12}
        )
      end,
      translate: {x, y},
      rotate: angle_rad
    )
  end

  defp draw_cardinal_directions(graph, c) do
    cardinals = [
      {0, "N", c.cardinal},
      {90, "E", c.primary},
      {180, "S", c.primary},
      {270, "W", c.primary}
    ]

    Enum.reduce(cardinals, graph, fn {angle_deg, label, color}, g ->
      angle_rad = angle_deg * :math.pi() / 180
      dist = @radius - 80

      x = :math.sin(angle_rad) * dist
      y = -:math.cos(angle_rad) * dist

      g
      |> group(
        fn gr ->
          gr
          |> text(label,
            fill: color,
            font_size: 44,
            text_align: :center,
            translate: {0, 14}
          )
        end,
        translate: {x, y},
        rotate: angle_rad
      )
    end)
  end

  defp draw_lubber_line(graph, c) do
    # Fixed triangle at top pointing down (lubber line)
    graph
    |> triangle({{0, -@radius + 15}, {-12, -@radius + 40}, {12, -@radius + 40}},
      fill: c.needle
    )
    # Side reference marks
    |> line({{-@radius + 20, 0}, {-@radius + 50, 0}},
      stroke: {4, c.tick}
    )
    |> line({{@radius - 20, 0}, {@radius - 50, 0}},
      stroke: {4, c.tick}
    )
  end

  defp draw_aircraft_symbol(graph, c) do
    # Small fixed aircraft symbol in center
    graph
    # Fuselage
    |> line({{0, -40}, {0, 40}}, stroke: {4, c.aircraft}, cap: :round)
    # Wings
    |> line({{-35, 5}, {35, 5}}, stroke: {4, c.aircraft}, cap: :round)
    # Tail
    |> line({{-15, 35}, {15, 35}}, stroke: {3, c.aircraft}, cap: :round)
    # Center dot
    |> circle(6, fill: c.aircraft)
  end

  defp draw_readout(graph, heading, c) do
    # Round to nearest degree for display
    value = round(heading)
    value = if value == 0, do: 360, else: value

    # Format with leading zeros
    padded = value |> Integer.to_string() |> String.pad_leading(3, "0")
    display = padded <> "°"

    graph
    |> text(display,
      fill: c.primary,
      font_size: 42,
      text_align: :center,
      translate: {0, @radius - 60}
    )
  end
end
