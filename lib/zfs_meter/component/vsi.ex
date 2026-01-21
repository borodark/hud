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
  alias ZfsMeter.ColorScheme
  import Scenic.Primitives

  @radius 340
  @update_interval 50

  # Scale configuration
  @max_rate 2000
  @sweep_angle :math.pi() * 5 / 6

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

    target =
      if :rand.uniform() < 0.03 do
        (:rand.uniform() - 0.5) * 3000
      else
        target
      end

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
    c = ColorScheme.current()

    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face(c)
        |> draw_tick_marks(c)
        |> draw_numbers(c)
        |> draw_labels(c)
        |> draw_readout(rate, c)
        |> draw_needle(rate, c)
        |> draw_center_cap(c)
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  defp draw_dial_face(graph, c) do
    graph
    |> circle(@radius, fill: c.bg, stroke: {8, c.border})
    |> circle(@radius - 8, fill: c.bg)
  end

  defp draw_tick_marks(graph, c) do
    graph
    |> draw_major_ticks(c)
    |> draw_minor_ticks(c)
  end

  defp draw_major_ticks(graph, c) do
    values = [0, 500, 1000, 1500, 2000]

    graph
    |> draw_ticks_for_values(values, :up, 8, 55, c)
    |> draw_ticks_for_values(values, :down, 8, 55, c)
  end

  defp draw_minor_ticks(graph, c) do
    values = [250, 750, 1250, 1750]

    graph
    |> draw_ticks_for_values(values, :up, 3, 35, c)
    |> draw_ticks_for_values(values, :down, 3, 35, c)
  end

  defp draw_ticks_for_values(graph, values, direction, width, length, c) do
    Enum.reduce(values, graph, fn value, g ->
      if value == 0 and direction == :down do
        g
      else
        angle = value_to_angle(value, direction)
        draw_tick(g, angle, width, length, c)
      end
    end)
  end

  defp draw_tick(graph, angle, width, length, c) do
    inner = @radius - 15 - length
    outer = @radius - 15

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {width, c.tick}, cap: :round)
  end

  defp draw_numbers(graph, c) do
    graph
    |> draw_number(0, :up, "0", c)
    |> draw_number(500, :up, "5", c)
    |> draw_number(1000, :up, "10", c)
    |> draw_number(1500, :up, "15", c)
    |> draw_number(2000, :up, "20", c)
    |> draw_number(500, :down, "5", c)
    |> draw_number(1000, :down, "10", c)
    |> draw_number(1500, :down, "15", c)
    |> draw_number(2000, :down, "20", c)
  end

  defp draw_number(graph, value, direction, label, c) do
    angle = value_to_angle(value, direction)
    dist = @radius - 100

    x = :math.cos(angle) * dist
    y = :math.sin(angle) * dist

    graph
    |> text(label,
      fill: c.primary,
      font_size: 48,
      text_align: :center,
      translate: {x, y + 16}
    )
  end

  defp draw_labels(graph, c) do
    graph
    |> text("UP",
      fill: c.positive,
      font_size: 36,
      text_align: :center,
      translate: {-100, -120}
    )
    |> text("DN",
      fill: c.negative,
      font_size: 36,
      text_align: :center,
      translate: {-100, 120}
    )
  end

  defp draw_readout(graph, rate, c) do
    value = round(rate / 50) * 50
    display = if value >= 0, do: "+#{value}", else: "#{value}"

    color =
      cond do
        value > 50 -> c.positive
        value < -50 -> c.negative
        true -> c.primary
      end

    graph
    |> text(display,
      fill: color,
      font_size: 42,
      text_align: :center,
      translate: {160, 12}
    )
  end

  defp draw_needle(graph, rate, c) do
    clamped = max(-@max_rate, min(@max_rate, rate))

    direction = if clamped >= 0, do: :up, else: :down
    angle = value_to_angle(abs(clamped), direction)

    needle_length = @radius - 70
    tail_length = 55

    graph
    |> group(fn g ->
      g
      |> line({{0, 0}, {:math.cos(angle) * needle_length, :math.sin(angle) * needle_length}},
        stroke: {8, c.needle},
        cap: :round
      )
      |> line(
        {{0, 0},
         {:math.cos(angle + :math.pi()) * tail_length,
          :math.sin(angle + :math.pi()) * tail_length}},
        stroke: {8, c.needle},
        cap: :round
      )
    end)
  end

  defp draw_center_cap(graph, c) do
    graph
    |> circle(35, fill: c.bg, stroke: {5, c.border})
    |> circle(15, fill: c.border)
  end

  defp value_to_angle(value, :up) do
    fraction = value / @max_rate
    :math.pi() + fraction * @sweep_angle
  end

  defp value_to_angle(value, :down) do
    fraction = value / @max_rate
    :math.pi() - fraction * @sweep_angle
  end
end
