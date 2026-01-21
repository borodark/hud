defmodule ZfsMeter.Component.AttitudeIndicator do
  @moduledoc """
  Attitude Indicator (Artificial Horizon) - G1000-style rectangular display.

  - Blue sky above horizon, brown ground below
  - Horizon line shifts vertically with pitch
  - Entire horizon rotates with roll
  - Bank angle scale at top
  - Fixed aircraft symbol in center
  - Full rectangular display for future data overlays

  Options:
  - width: display width (default: 760)
  - height: display height (default: 780)
  - show_border: whether to show border (default: true)
  - show_bank_scale: whether to show bank scale (default: true)
  - show_aircraft: whether to show aircraft symbol (default: true)
  - background_mode: when true, only draws sky/ground/horizon (default: false)
  """
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  alias ZfsMeter.ColorScheme
  import Scenic.Primitives

  # Default dimensions (fits widget space)
  @default_width 760
  @default_height 780

  @update_interval 50

  # Pixels per degree of pitch
  @pixels_per_degree 12

  @impl Scenic.Component
  def validate({pitch, roll}) when is_number(pitch) and is_number(roll), do: {:ok, {pitch, roll}}
  def validate(_), do: {:error, "Expected {pitch, roll} tuple with numeric values"}

  @impl Scenic.Scene
  def init(scene, {pitch, roll}, opts) do
    simulate = Keyword.get(opts, :simulate, true)
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)
    show_border = Keyword.get(opts, :show_border, true)
    show_bank_scale = Keyword.get(opts, :show_bank_scale, true)
    show_aircraft = Keyword.get(opts, :show_aircraft, true)
    background_mode = Keyword.get(opts, :background_mode, false)

    if simulate do
      Process.send_after(self(), :tick, @update_interval)
    end

    config = %{
      width: width,
      height: height,
      center_x: width / 2,
      center_y: height / 2 + 20,
      show_border: show_border,
      show_bank_scale: show_bank_scale,
      show_aircraft: show_aircraft,
      background_mode: background_mode
    }

    graph = build_graph(pitch, roll, config)

    scene
    |> assign(pitch: pitch, roll: roll, simulate: simulate, config: config)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl Scenic.Scene
  def handle_put({pitch, roll}, scene) when is_number(pitch) and is_number(roll) do
    %{config: config} = scene.assigns
    graph = build_graph(pitch, roll, config)

    scene
    |> assign(pitch: pitch, roll: roll)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info(:tick, %{assigns: %{simulate: false}} = scene) do
    {:noreply, scene}
  end

  def handle_info(:tick, scene) do
    %{pitch: pitch, roll: roll, config: config} = scene.assigns

    # Random gentle movement for simulation
    new_pitch = pitch + (:rand.uniform() - 0.5) * 0.5
    new_roll = roll + (:rand.uniform() - 0.5) * 0.5

    graph = build_graph(new_pitch, new_roll, config)

    Process.send_after(self(), :tick, @update_interval)

    scene
    |> assign(pitch: new_pitch, roll: new_roll)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp build_graph(pitch, roll, config) do
    c = ColorScheme.current()

    Graph.build()
    |> group(
      fn g ->
        g
        |> draw_horizon(pitch, roll, c, config)
        |> maybe_draw_pitch_ladder(pitch, c, config)
        |> maybe_draw_bank_scale(c, config)
        |> maybe_draw_bank_pointer(roll, c, config)
        |> maybe_draw_aircraft_symbol(c, config)
        |> maybe_draw_border(c, config)
      end,
      translate: {0, 0}
    )
  end

  defp draw_horizon(graph, pitch, roll, c, config) do
    roll_rad = roll * :math.pi() / 180
    y_offset = pitch * @pixels_per_degree

    # The horizon group rotates around center
    graph
    |> group(
      fn g ->
        g
        |> draw_sky_ground(y_offset, c, config)
        |> draw_horizon_line(y_offset, c, config)
      end,
      translate: {config.center_x, config.center_y},
      rotate: roll_rad
    )
  end

  defp draw_sky_ground(graph, y_offset, c, config) do
    # Large rectangles for sky and ground that extend beyond visible area
    # This ensures full coverage when rotated
    size = config.width + config.height  # Diagonal coverage

    graph
    # Sky - extends upward from horizon
    |> rect({size * 2, size},
      fill: c.sky,
      translate: {-size, y_offset - size}
    )
    # Ground - extends downward from horizon
    |> rect({size * 2, size},
      fill: c.ground,
      translate: {-size, y_offset}
    )
  end

  defp draw_horizon_line(graph, y_offset, c, config) do
    # Main horizon line
    graph
    |> line({{-config.width, y_offset}, {config.width, y_offset}},
      stroke: {3, c.horizon}
    )
  end

  defp maybe_draw_pitch_ladder(graph, pitch, c, config) do
    if config.background_mode do
      graph
    else
      draw_pitch_ladder(graph, pitch, c, config)
    end
  end

  defp draw_pitch_ladder(graph, pitch, c, config) do
    y_offset = pitch * @pixels_per_degree
    roll_rad = 0  # Pitch ladder rotates with horizon in actual use
    pitch_marks = [-30, -25, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30]

    # Draw pitch ladder centered and rotated
    graph
    |> group(
      fn g ->
        Enum.reduce(pitch_marks, g, fn mark, gr ->
          mark_y = y_offset - mark * @pixels_per_degree

          # Line width varies: longer for 10-degree marks
          {half_width, show_label} = cond do
            rem(abs(mark), 10) == 0 -> {80, true}
            rem(abs(mark), 5) == 0 -> {40, false}
            true -> {25, false}
          end

          # Draw pitch line
          gr
          |> line({{-half_width, mark_y}, {-20, mark_y}},
            stroke: {2, c.primary}
          )
          |> line({{20, mark_y}, {half_width, mark_y}},
            stroke: {2, c.primary}
          )
          # Add small vertical ticks at ends for negative pitch (below horizon)
          |> then(fn g2 ->
            if mark < 0 do
              g2
              |> line({{-half_width, mark_y}, {-half_width, mark_y - 10}},
                stroke: {2, c.primary}
              )
              |> line({{half_width, mark_y}, {half_width, mark_y - 10}},
                stroke: {2, c.primary}
              )
            else
              g2
            end
          end)
          # Label the 10-degree marks
          |> then(fn g2 ->
            if show_label do
              label = Integer.to_string(abs(mark))

              g2
              |> text(label,
                fill: c.primary,
                font_size: 24,
                text_align: :right,
                translate: {-half_width - 10, mark_y + 8}
              )
              |> text(label,
                fill: c.primary,
                font_size: 24,
                text_align: :left,
                translate: {half_width + 10, mark_y + 8}
              )
            else
              g2
            end
          end)
        end)
      end,
      translate: {config.center_x, config.center_y},
      rotate: roll_rad
    )
  end

  defp maybe_draw_bank_scale(graph, c, config) do
    if config.show_bank_scale and not config.background_mode do
      draw_bank_scale(graph, c, config)
    else
      graph
    end
  end

  defp draw_bank_scale(graph, c, config) do
    # Bank marks at top of display, centered
    bank_radius = min(config.width, config.height) / 2 - 100
    bank_marks = [
      {0, :major},
      {10, :minor},
      {-10, :minor},
      {20, :minor},
      {-20, :minor},
      {30, :major},
      {-30, :major},
      {45, :minor},
      {-45, :minor},
      {60, :major},
      {-60, :major}
    ]

    Enum.reduce(bank_marks, graph, fn {angle_deg, type}, g ->
      angle_rad = (angle_deg - 90) * :math.pi() / 180

      {length, width} =
        case type do
          :major -> {25, 4}
          :minor -> {15, 2}
        end

      inner_r = bank_radius - length
      outer_r = bank_radius

      x1 = config.center_x + :math.cos(angle_rad) * inner_r
      y1 = config.center_y + :math.sin(angle_rad) * inner_r
      x2 = config.center_x + :math.cos(angle_rad) * outer_r
      y2 = config.center_y + :math.sin(angle_rad) * outer_r

      g
      |> line({{x1, y1}, {x2, y2}}, stroke: {width, c.tick})
    end)
  end

  defp maybe_draw_bank_pointer(graph, roll, c, config) do
    if config.show_bank_scale and not config.background_mode do
      draw_bank_pointer(graph, roll, c, config)
    else
      graph
    end
  end

  defp draw_bank_pointer(graph, roll, c, config) do
    # Triangle pointer at top that moves with roll
    roll_rad = roll * :math.pi() / 180
    pointer_dist = min(config.width, config.height) / 2 - 130

    # Rotate the pointer position around center
    tip_angle = -:math.pi() / 2 + roll_rad
    tip_x = config.center_x + :math.cos(tip_angle) * pointer_dist
    tip_y = config.center_y + :math.sin(tip_angle) * pointer_dist

    # Triangle pointing inward
    size = 18
    base_dist = pointer_dist + size

    left_angle = tip_angle - 0.12
    right_angle = tip_angle + 0.12

    left_x = config.center_x + :math.cos(left_angle) * base_dist
    left_y = config.center_y + :math.sin(left_angle) * base_dist
    right_x = config.center_x + :math.cos(right_angle) * base_dist
    right_y = config.center_y + :math.sin(right_angle) * base_dist

    graph
    |> triangle({{tip_x, tip_y}, {left_x, left_y}, {right_x, right_y}},
      fill: c.aircraft,
      stroke: {1, c.tick}
    )
  end

  defp maybe_draw_aircraft_symbol(graph, c, config) do
    if config.show_aircraft and not config.background_mode do
      draw_aircraft_symbol(graph, c, config)
    else
      graph
    end
  end

  defp draw_aircraft_symbol(graph, c, config) do
    # Fixed aircraft symbol in center - G1000 style
    # Yellow/orange wings with center dot
    wing_span = 180
    wing_height = 8
    center_gap = 30
    cx = config.center_x
    cy = config.center_y

    graph
    # Left wing
    |> line({{cx - center_gap, cy}, {cx - wing_span / 2, cy}},
      stroke: {wing_height, c.aircraft},
      cap: :round
    )
    # Left wing tip (down)
    |> line({{cx - wing_span / 2, cy}, {cx - wing_span / 2, cy + 25}},
      stroke: {wing_height, c.aircraft},
      cap: :round
    )
    # Right wing
    |> line({{cx + center_gap, cy}, {cx + wing_span / 2, cy}},
      stroke: {wing_height, c.aircraft},
      cap: :round
    )
    # Right wing tip (down)
    |> line({{cx + wing_span / 2, cy}, {cx + wing_span / 2, cy + 25}},
      stroke: {wing_height, c.aircraft},
      cap: :round
    )
    # Center dot
    |> circle(8, fill: c.aircraft, translate: {cx, cy})
  end

  defp maybe_draw_border(graph, c, config) do
    if config.show_border and not config.background_mode do
      draw_border(graph, c, config)
    else
      graph
    end
  end

  defp draw_border(graph, c, config) do
    # Thin border around the display
    graph
    |> rect({config.width, config.height},
      stroke: {3, c.border},
      translate: {0, 0}
    )
  end
end
