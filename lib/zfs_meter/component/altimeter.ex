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
  alias ZfsMeter.ColorScheme
  import Scenic.Primitives

  @radius 340
  @update_interval 50

  @impl Scenic.Component
  def validate(altitude) when is_number(altitude), do: {:ok, altitude}
  def validate(_), do: {:error, "Expected altitude in feet"}

  @impl Scenic.Scene
  def init(scene, altitude, opts) do
    simulate = Keyword.get(opts, :simulate, true)
    transparent_bg = Keyword.get(opts, :transparent_bg, false)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    graph = build_graph(altitude, transparent_bg)

    scene
    |> assign(
      altitude: altitude,
      target: altitude,
      simulate: simulate,
      transparent_bg: transparent_bg
    )
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl Scenic.Scene
  def handle_put(altitude, scene) when is_number(altitude) do
    %{transparent_bg: transparent_bg} = scene.assigns
    graph = build_graph(altitude, transparent_bg)

    scene
    |> assign(altitude: altitude)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{altitude: current, target: target, transparent_bg: transparent_bg} = scene.assigns

    target =
      if :rand.uniform() < 0.02 do
        max(0, min(45000, target + (:rand.uniform() - 0.5) * 5000))
      else
        target
      end

    diff = target - current
    new_altitude = current + diff * 0.05

    graph = build_graph(new_altitude, transparent_bg)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(altitude: new_altitude, target: target)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(altitude, transparent_bg) do
    c = ColorScheme.current()

    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_dial_face(c, transparent_bg)
        |> draw_tick_marks(c)
        |> draw_numbers(c)
        |> draw_readout(altitude, c)
        |> draw_needles(altitude, c)
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

  defp draw_tick_marks(graph, c) do
    graph
    |> draw_major_ticks(c)
    |> draw_minor_ticks(c)
  end

  defp draw_major_ticks(graph, c) do
    Enum.reduce(0..9, graph, fn i, g ->
      angle = i * (:math.pi() * 2 / 10) - :math.pi() / 2
      inner = @radius - 60
      outer = @radius - 15

      x1 = :math.cos(angle) * inner
      y1 = :math.sin(angle) * inner
      x2 = :math.cos(angle) * outer
      y2 = :math.sin(angle) * outer

      g |> line({{x1, y1}, {x2, y2}}, stroke: {8, c.tick}, cap: :round)
    end)
  end

  defp draw_minor_ticks(graph, c) do
    Enum.reduce(0..49, graph, fn i, g ->
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

        g |> line({{x1, y1}, {x2, y2}}, stroke: {3, c.secondary})
      end
    end)
  end

  defp draw_numbers(graph, c) do
    Enum.reduce(0..9, graph, fn i, g ->
      angle = i * (:math.pi() * 2 / 10) - :math.pi() / 2
      dist = @radius - 100
      x = :math.cos(angle) * dist
      y = :math.sin(angle) * dist

      g
      |> text(
        "#{i}",
        fill: c.primary,
        font_size: 56,
        text_align: :center,
        translate: {x, y + 20}
      )
    end)
  end

  defp draw_readout(graph, altitude, c) do
    meters = trunc(altitude * 0.3048)
    display = "#{meters} m"

    graph
    |> text(display,
      fill: c.primary,
      font_size: 36,
      text_align: :center,
      translate: {0, 180}
    )
  end

  defp draw_needles(graph, altitude, c) do
    altitude = max(0.0, altitude / 1.0)

    hundreds_angle = :math.fmod(altitude, 1000) / 1000 * :math.pi() * 2
    thousands_angle = :math.fmod(altitude, 10000) / 10000 * :math.pi() * 2
    ten_thousands_angle = altitude / 100_000 * :math.pi() * 2

    graph
    |> draw_long_needle(hundreds_angle, c)
    |> draw_medium_needle(thousands_angle, c)
    |> draw_short_needle(ten_thousands_angle, c)
  end

  defp draw_long_needle(graph, angle, c) do
    length = @radius - 50

    graph
    |> group(
      fn g ->
        g
        |> line({{0, 25}, {0, -length}}, stroke: {6, c.primary}, cap: :round)
      end,
      rotate: angle
    )
  end

  defp draw_medium_needle(graph, angle, c) do
    length = @radius - 120

    graph
    |> group(
      fn g ->
        g
        |> line({{0, 40}, {0, -length}}, stroke: {12, c.secondary}, cap: :round)
      end,
      rotate: angle
    )
  end

  defp draw_short_needle(graph, angle, c) do
    length = @radius - 180

    graph
    |> group(
      fn g ->
        g
        |> triangle({{0, -length}, {-18, -length + 60}, {18, -length + 60}},
          fill: c.tick
        )
        |> line({{0, 50}, {0, -length + 50}}, stroke: {18, c.tick}, cap: :round)
      end,
      rotate: angle
    )
  end

  defp draw_center_cap(graph, c, transparent_bg) do
    if transparent_bg do
      graph
      |> circle(35, stroke: {5, c.border})
      |> circle(15, fill: c.border)
    else
      graph
      |> circle(35, fill: c.bg, stroke: {5, c.border})
      |> circle(15, fill: c.border)
    end
  end
end
