defmodule ZfsMeter.Component.AirspeedIndicator do
  @moduledoc """
  Airspeed Indicator (ASI) - shows indicated airspeed in knots.

  - Scale: 0 to 200 knots
  - Color arcs:
    - White: Vs0 (45) to Vfe (100) - flap operating range
    - Green: Vs1 (55) to Vno (140) - normal operating range
    - Yellow: Vno (140) to Vne (180) - caution range
    - Red line: Vne (180) - never exceed speed
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  alias ZfsMeter.ColorScheme
  import Scenic.Primitives

  @radius 310
  @update_interval 50

  # Speed limits (knots)
  @vs0 45
  @vs1 55
  @vfe 100
  @vno 140
  @vne 180
  @max_speed 200

  @start_angle :math.pi() * 5 / 4
  @sweep_angle :math.pi() * 3 / 2

  @impl Scenic.Component
  def validate(airspeed) when is_number(airspeed), do: {:ok, airspeed}
  def validate(_), do: {:error, "Expected airspeed in knots"}

  @impl Scenic.Scene
  def init(scene, airspeed, opts) do
    simulate = Keyword.get(opts, :simulate, true)
    transparent_bg = Keyword.get(opts, :transparent_bg, false)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(airspeed, transparent_bg)

    scene
    |> assign(
      airspeed: airspeed,
      target: airspeed,
      simulate: simulate,
      transparent_bg: transparent_bg
    )
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl Scenic.Scene
  def handle_put(airspeed, scene) when is_number(airspeed) do
    %{transparent_bg: transparent_bg} = scene.assigns
    graph = build_graph(airspeed, transparent_bg)

    scene
    |> assign(airspeed: airspeed)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{airspeed: current, target: target, transparent_bg: transparent_bg} = scene.assigns

    target =
      if :rand.uniform() < 0.03 do
        60 + :rand.uniform() * 100
      else
        target
      end

    diff = target - current
    new_airspeed = current + diff * 0.08

    graph = build_graph(new_airspeed, transparent_bg)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(airspeed: new_airspeed, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(airspeed, transparent_bg) do
    c = ColorScheme.current()

    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face(c, transparent_bg)
        |> draw_speed_arcs(c)
        |> draw_tick_marks(c)
        |> draw_numbers(c)
        |> draw_label(c)
        |> draw_readout(airspeed, c)
        |> draw_needle(airspeed, c)
        |> draw_center_cap(c, transparent_bg)
      end,
      translate: {@radius + 20, @radius + 20}
    )
  end

  defp draw_dial_face(graph, c, transparent_bg) do
    if transparent_bg do
      graph
      |> circle(@radius, stroke: {8, c.border})
    else
      graph
      |> circle(@radius, fill: c.bg, stroke: {8, c.border})
      |> circle(@radius - 8, fill: c.bg)
    end
  end

  defp draw_speed_arcs(graph, c) do
    arc_radius = @radius - 25
    arc_width = 18

    graph
    |> draw_arc(@vs0, @vfe, arc_radius, arc_width, c.arc_white)
    |> draw_arc(@vs1, @vno, arc_radius - arc_width - 2, arc_width, c.arc_green)
    |> draw_arc(@vno, @vne, arc_radius, arc_width, c.arc_yellow)
    |> draw_vne_line(arc_radius, c)
  end

  defp draw_arc(graph, start_speed, end_speed, radius, width, color) do
    start_angle = speed_to_angle(start_speed)
    end_angle = speed_to_angle(end_speed)

    segments = 24
    angle_step = (end_angle - start_angle) / segments

    points =
      for i <- 0..segments do
        angle = start_angle + angle_step * i
        x = :math.cos(angle) * radius
        y = :math.sin(angle) * radius
        {x, y}
      end

    Enum.chunk_every(points, 2, 1, :discard)
    |> Enum.reduce(graph, fn [{x1, y1}, {x2, y2}], g ->
      g |> line({{x1, y1}, {x2, y2}}, stroke: {width, color}, cap: :round)
    end)
  end

  defp draw_vne_line(graph, radius, c) do
    angle = speed_to_angle(@vne)
    inner = radius - 30
    outer = radius + 5

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {6, c.arc_red}, cap: :butt)
  end

  defp draw_tick_marks(graph, c) do
    graph
    |> draw_major_ticks(c)
    |> draw_minor_ticks(c)
  end

  defp draw_major_ticks(graph, c) do
    speeds = [0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200]

    Enum.reduce(speeds, graph, fn speed, g ->
      draw_tick(g, speed, 8, 45, c)
    end)
  end

  defp draw_minor_ticks(graph, c) do
    speeds = [10, 30, 50, 70, 90, 110, 130, 150, 170, 190]

    Enum.reduce(speeds, graph, fn speed, g ->
      draw_tick(g, speed, 3, 25, c)
    end)
  end

  defp draw_tick(graph, speed, width, length, c) do
    angle = speed_to_angle(speed)
    inner = @radius - 15 - length
    outer = @radius - 15

    x1 = :math.cos(angle) * inner
    y1 = :math.sin(angle) * inner
    x2 = :math.cos(angle) * outer
    y2 = :math.sin(angle) * outer

    graph |> line({{x1, y1}, {x2, y2}}, stroke: {width, c.tick}, cap: :round)
  end

  defp draw_numbers(graph, c) do
    speeds = [0, 40, 80, 120, 160, 200]

    Enum.reduce(speeds, graph, fn speed, g ->
      draw_number(g, speed, c)
    end)
  end

  defp draw_number(graph, speed, c) do
    angle = speed_to_angle(speed)
    dist = @radius - 85

    x = :math.cos(angle) * dist
    y = :math.sin(angle) * dist

    label = Integer.to_string(speed)

    graph
    |> text(label,
      fill: c.primary,
      font_size: 42,
      text_align: :center,
      translate: {x, y + 14}
    )
  end

  defp draw_label(graph, c) do
    graph
    |> text("AIRSPEED",
      fill: c.primary,
      font_size: 28,
      text_align: :center,
      translate: {0, -80}
    )
    |> text("KNOTS",
      fill: c.primary,
      font_size: 24,
      text_align: :center,
      translate: {0, -50}
    )
  end

  defp draw_readout(graph, airspeed, c) do
    value = trunc(max(0, airspeed))
    display = Integer.to_string(value)

    color =
      cond do
        airspeed >= @vne -> c.critical
        airspeed >= @vno -> c.warning
        airspeed < @vs1 and airspeed > 0 -> c.critical
        true -> c.primary
      end

    graph
    |> text(display,
      fill: color,
      font_size: 48,
      text_align: :center,
      translate: {0, 100}
    )
  end

  defp draw_needle(graph, airspeed, c) do
    clamped = max(0, min(@max_speed, airspeed))
    angle = speed_to_angle(clamped)

    needle_length = @radius - 60
    tail_length = 50

    graph
    |> line({{0, 0}, {:math.cos(angle) * needle_length, :math.sin(angle) * needle_length}},
      stroke: {8, c.needle},
      cap: :round
    )
    |> line(
      {{0, 0},
       {:math.cos(angle + :math.pi()) * tail_length, :math.sin(angle + :math.pi()) * tail_length}},
      stroke: {8, c.needle},
      cap: :round
    )
  end

  defp draw_center_cap(graph, c, transparent_bg) do
    if transparent_bg do
      graph
      |> circle(30, stroke: {5, c.border})
      |> circle(12, fill: c.border)
    else
      graph
      |> circle(30, fill: c.bg, stroke: {5, c.border})
      |> circle(12, fill: c.border)
    end
  end

  defp speed_to_angle(speed) do
    fraction = speed / @max_speed
    @start_angle + fraction * @sweep_angle
  end
end
