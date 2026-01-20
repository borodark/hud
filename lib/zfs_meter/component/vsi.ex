defmodule ZfsMeter.Component.VSI do
  @moduledoc """
  Vertical Speed Indicator (VSI) - shows rate of climb/descent.

  - Zero at 9 o'clock position
  - Climb (positive) clockwise on right side
  - Descent (negative) counter-clockwise on left side
  - Scale: -2000 to +2000 ft/min
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  import Scenic.Primitives

  @radius 340
  @update_interval 50

  # Scale configuration
  @max_rate 2000  # ft/min
  # The needle sweeps 150 degrees each direction from zero (at 9 o'clock)
  @sweep_angle :math.pi() * 5 / 6  # 150 degrees in radians

  @impl Scenic.Component
  def validate(rate) when is_number(rate), do: {:ok, rate}
  def validate(_), do: {:error, "Expected vertical speed in ft/min"}

  @impl Scenic.Scene
  def init(scene, rate, opts) do
    simulate = Keyword.get(opts, :simulate, true)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(rate)

    scene
    |> assign(rate: rate, target: rate, simulate: simulate)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  # Handle external updates from parent scene
  @impl Scenic.Scene
  def handle_put(rate, scene) when is_number(rate) do
    graph = build_graph(rate)

    scene
    |> assign(rate: rate)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{rate: current, target: target} = scene.assigns

    # Randomly adjust target occasionally
    target =
      if :rand.uniform() < 0.03 do
        # Random rate between -1500 and +1500
        (:rand.uniform() - 0.5) * 3000
      else
        target
      end

    # Smoothly move toward target
    diff = target - current
    new_rate = current + diff * 0.08

    graph = build_graph(new_rate)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(rate: new_rate, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(rate) do
    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face()
        |> draw_tick_marks()
        |> draw_numbers()
        |> draw_labels()
        |> draw_needle(rate)
        |> draw_center_cap()
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  defp draw_dial_face(graph) do
    graph
    |> circle(@radius, fill: {20, 20, 20}, stroke: {8, :white})
    |> circle(@radius - 8, fill: {30, 30, 35})
  end

  defp draw_tick_marks(graph) do
    graph
    |> draw_major_ticks()
    |> draw_minor_ticks()
  end

  # Major ticks at 0, 500, 1000, 1500, 2000 (both up and down)
  defp draw_major_ticks(graph) do
    values = [0, 500, 1000, 1500, 2000]

    graph
    |> draw_ticks_for_values(values, :up, 8, 55)
    |> draw_ticks_for_values(values, :down, 8, 55)
  end

  # Minor ticks at 250, 750, 1250, 1750
  defp draw_minor_ticks(graph) do
    values = [250, 750, 1250, 1750]

    graph
    |> draw_ticks_for_values(values, :up, 3, 35)
    |> draw_ticks_for_values(values, :down, 3, 35)
  end

  defp draw_ticks_for_values(graph, values, direction, width, length) do
    Enum.reduce(values, graph, fn value, g ->
      # Skip zero for down direction (already drawn in up)
      if value == 0 and direction == :down do
        g
      else
        angle = value_to_angle(value, direction)
        draw_tick(g, angle, width, length)
      end
    end)
  end

  defp draw_tick(graph, angle, width, length) do
    inner = @radius - 15 - length
    outer = @radius - 15

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {width, :white}, cap: :round)
  end

  defp draw_numbers(graph) do
    # Numbers for climb side (right)
    graph
    |> draw_number(0, :up, "0")
    |> draw_number(500, :up, "5")
    |> draw_number(1000, :up, "10")
    |> draw_number(1500, :up, "15")
    |> draw_number(2000, :up, "20")
    # Numbers for descent side (left) - skip 0
    |> draw_number(500, :down, "5")
    |> draw_number(1000, :down, "10")
    |> draw_number(1500, :down, "15")
    |> draw_number(2000, :down, "20")
  end

  defp draw_number(graph, value, direction, label) do
    angle = value_to_angle(value, direction)
    dist = @radius - 100

    x = :math.cos(angle) * dist
    y = :math.sin(angle) * dist

    graph
    |> text(label,
      fill: :white,
      font_size: 48,
      text_align: :center,
      translate: {x, y + 16}
    )
  end

  defp draw_labels(graph) do
    graph
    |> text("UP",
      fill: {:green, 200},
      font_size: 36,
      text_align: :center,
      translate: {120, -50}
    )
    |> text("DN",
      fill: {:red, 200},
      font_size: 36,
      text_align: :center,
      translate: {-120, -50}
    )
    |> text("VERTICAL",
      fill: {:white, 180},
      font_size: 32,
      text_align: :center,
      translate: {0, 80}
    )
    |> text("SPEED",
      fill: {:white, 180},
      font_size: 32,
      text_align: :center,
      translate: {0, 115}
    )
  end

  defp draw_needle(graph, rate) do
    # Clamp rate to scale
    clamped = max(-@max_rate, min(@max_rate, rate))

    direction = if clamped >= 0, do: :up, else: :down
    angle = value_to_angle(abs(clamped), direction)

    needle_length = @radius - 70
    tail_length = 55

    # Needle rotation (angle is already in standard position)
    graph
    |> group(
      fn g ->
        g
        |> line({{0, 0}, {:math.cos(angle) * needle_length, :math.sin(angle) * needle_length}},
          stroke: {8, :white},
          cap: :round
        )
        # Small tail in opposite direction
        |> line({{0, 0}, {:math.cos(angle + :math.pi()) * tail_length, :math.sin(angle + :math.pi()) * tail_length}},
          stroke: {8, :white},
          cap: :round
        )
      end
    )
  end

  defp draw_center_cap(graph) do
    graph
    |> circle(35, fill: {50, 50, 55}, stroke: {5, {:white, 128}})
    |> circle(15, fill: {80, 80, 85})
  end

  # Convert value to angle
  # Zero is at 9 o'clock (pointing left, angle = π)
  # Up (climb) goes clockwise from there
  # Down (descent) goes counter-clockwise from there
  defp value_to_angle(value, :up) do
    # 0 -> π (9 o'clock), 2000 -> π - sweep_angle (pointing up-right)
    fraction = value / @max_rate
    :math.pi() - fraction * @sweep_angle
  end

  defp value_to_angle(value, :down) do
    # 0 -> π (9 o'clock), 2000 -> π + sweep_angle (pointing down-left)
    fraction = value / @max_rate
    :math.pi() + fraction * @sweep_angle
  end
end
