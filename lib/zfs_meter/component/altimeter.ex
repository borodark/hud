defmodule ZfsMeter.Component.Altimeter do
  @moduledoc """
  An analog aircraft-style altimeter display.

  Shows altitude with three needles:
  - Long needle: 100s of feet (full rotation = 1000 ft)
  - Medium needle: 1000s of feet (full rotation = 10,000 ft)
  - Short needle: 10,000s of feet (full rotation = 100,000 ft)
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  @radius 340
  @update_interval 50

  @impl Scenic.Component
  def validate(altitude) when is_number(altitude), do: {:ok, altitude}
  def validate(_), do: {:error, "Expected altitude in feet"}

  @impl Scenic.Scene
  def init(scene, altitude, _opts) do
    Process.send_after(self(), :tick, @update_interval)

    graph = build_graph(altitude)

    scene
    |> assign(altitude: altitude, target: altitude)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl GenServer
  def handle_info(:tick, scene) do
    # Simulate altitude changes for demo
    %{altitude: current, target: target} = scene.assigns

    # Randomly adjust target occasionally
    target =
      if :rand.uniform() < 0.02 do
        max(0, min(45000, target + (:rand.uniform() - 0.5) * 5000))
      else
        target
      end

    # Smoothly move toward target
    diff = target - current
    new_altitude = current + diff * 0.05

    graph = build_graph(new_altitude)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(altitude: new_altitude, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(altitude) do
    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face()
        |> draw_tick_marks()
        |> draw_numbers()
        |> draw_needles(altitude)
        |> draw_center_cap()
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  # Black dial face with white border
  defp draw_dial_face(graph) do
    graph
    |> circle(@radius, fill: {20, 20, 20}, stroke: {8, :white})
    |> circle(@radius - 8, fill: {30, 30, 35})
  end

  # Major ticks (at each number) and minor ticks
  defp draw_tick_marks(graph) do
    graph
    |> draw_major_ticks()
    |> draw_minor_ticks()
  end

  defp draw_major_ticks(graph) do
    Enum.reduce(0..9, graph, fn i, g ->
      angle = i * (:math.pi() * 2 / 10) - :math.pi() / 2
      inner = @radius - 60
      outer = @radius - 15

      x1 = :math.cos(angle) * inner
      y1 = :math.sin(angle) * inner
      x2 = :math.cos(angle) * outer
      y2 = :math.sin(angle) * outer

      g |> line({{x1, y1}, {x2, y2}}, stroke: {8, :white}, cap: :round)
    end)
  end

  defp draw_minor_ticks(graph) do
    Enum.reduce(0..49, graph, fn i, g ->
      # Skip positions where major ticks are
      if rem(i, 5) == 0 do
        g
      else
        angle = i * (:math.pi() * 2 / 50) - :math.pi() / 2
        inner = @radius - 40
        outer = @radius - 15

        x1 = :math.cos(angle) * inner
        y1 = :math.sin(angle) * inner
        x2 = :math.cos(angle) * outer
        y2 = :math.sin(angle) * outer

        g |> line({{x1, y1}, {x2, y2}}, stroke: {3, {:white, 180}})
      end
    end)
  end

  # Numbers 0-9 around dial
  defp draw_numbers(graph) do
    Enum.reduce(0..9, graph, fn i, g ->
      angle = i * (:math.pi() * 2 / 10) - :math.pi() / 2
      dist = @radius - 100
      x = :math.cos(angle) * dist
      y = :math.sin(angle) * dist

      g
      |> text(
        "#{i}",
        fill: :white,
        font_size: 56,
        text_align: :center,
        translate: {x, y + 20}
      )
    end)
  end

  # Three needles for 100s, 1000s, 10000s
  defp draw_needles(graph, altitude) do
    altitude = max(0.0, altitude / 1.0)

    # Calculate rotations
    # Long hand: full circle = 1000 ft
    hundreds_angle = :math.fmod(altitude, 1000) / 1000 * :math.pi() * 2
    # Medium hand: full circle = 10,000 ft
    thousands_angle = :math.fmod(altitude, 10000) / 10000 * :math.pi() * 2
    # Short hand: full circle = 100,000 ft
    ten_thousands_angle = altitude / 100_000 * :math.pi() * 2

    graph
    # Long needle (100s of feet) - thin and long
    |> draw_long_needle(hundreds_angle)
    # Medium needle (1000s) - medium length
    |> draw_medium_needle(thousands_angle)
    # Short needle (10,000s) - short with triangle tip
    |> draw_short_needle(ten_thousands_angle)
  end

  defp draw_long_needle(graph, angle) do
    rotation = angle - :math.pi() / 2
    length = @radius - 50

    graph
    |> group(
      fn g ->
        g
        |> line({{0, 25}, {0, -length}}, stroke: {6, :white}, cap: :round)
      end,
      rotate: rotation
    )
  end

  defp draw_medium_needle(graph, angle) do
    rotation = angle - :math.pi() / 2
    length = @radius - 120

    graph
    |> group(
      fn g ->
        g
        |> line({{0, 40}, {0, -length}}, stroke: {12, :white}, cap: :round)
      end,
      rotate: rotation
    )
  end

  defp draw_short_needle(graph, angle) do
    rotation = angle - :math.pi() / 2
    length = @radius - 180

    graph
    |> group(
      fn g ->
        g
        # Triangle pointer
        |> triangle({{0, -length}, {-18, -length + 60}, {18, -length + 60}}, fill: :orange)
        |> line({{0, 50}, {0, -length + 50}}, stroke: {18, :orange}, cap: :round)
      end,
      rotate: rotation
    )
  end

  # Center cap covering needle pivots
  defp draw_center_cap(graph) do
    graph
    |> circle(35, fill: {50, 50, 55}, stroke: {5, {:white, 128}})
    |> circle(15, fill: {80, 80, 85})
  end
end
