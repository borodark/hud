defmodule ZfsMeter.Scene.Main do
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ZfsMeter.Component.DualTachometer
  alias ZfsMeter.Component.Altimeter
  alias ZfsMeter.Component.VSI
  alias ZfsMeter.Component.AttitudeIndicator
  alias ZfsMeter.Component.AirspeedIndicator
  alias ZfsMeter.Component.HeadingIndicator
  alias ZfsMeter.ColorScheme
  alias ZfsMeter.FlightSim

  # Grid layout: 3 columns x 2 rows
  # Resolution: 2388 x 1668
  @screen_width 2388
  @screen_height 1668
  @col_width 796
  @row_height 834

  # 20 fps
  @tick_interval 50

  @impl Scenic.Scene
  def init(scene, _params, _opts) do
    # Initialize flight simulation
    flight_sim = FlightSim.new()
    c = ColorScheme.current()

    # Check config for attitude background mode
    attitude_background = Application.get_env(:zfs_meter, :attitude_background, false)

    graph =
      Graph.build(font: :roboto, font_size: 24)
      |> maybe_add_attitude_background(flight_sim, attitude_background)
      # Row 1
      |> draw_widget_frame(0, 0, "Engine RPM", c, attitude_background)
      |> draw_widget_frame(1, 0, "Altimeter", c, attitude_background)
      |> draw_widget_frame(2, 0, "Vertical Speed", c, attitude_background)
      # Row 2
      |> draw_widget_frame(0, 1, "Airspeed", c, attitude_background)
      |> maybe_draw_attitude_frame(1, 1, c, attitude_background)
      |> draw_widget_frame(2, 1, "Heading", c, attitude_background)
      # Actual widgets - with simulate: false so we control them
      # When attitude_background is true, instruments get transparent backgrounds
      |> add_tachometers(0, 0, flight_sim, c, attitude_background)
      |> add_altimeter(1, 0, flight_sim, attitude_background)
      |> add_vsi(2, 0, flight_sim, attitude_background)
      |> maybe_add_attitude_widget(1, 1, flight_sim, attitude_background)
      |> add_airspeed_indicator(0, 1, flight_sim, attitude_background)
      |> add_heading_indicator(2, 1, flight_sim, attitude_background)

    # Start simulation tick
    Process.send_after(self(), :tick, @tick_interval)

    scene
    |> assign(flight_sim: flight_sim, graph: graph, attitude_background: attitude_background)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl GenServer
  def handle_info(:tick, scene) do
    %{flight_sim: sim, attitude_background: attitude_background} = scene.assigns

    # Update simulation (50ms = 0.05 seconds)
    dt = @tick_interval / 1000
    new_sim = FlightSim.tick(sim, dt)

    # Push updated values to components
    :ok =
      put_child(
        scene,
        :engines_rpm,
        {new_sim.left_rpm, new_sim.right_rpm, new_sim.left_oil_temp, new_sim.right_oil_temp}
      )

    :ok = put_child(scene, :altimeter, new_sim.altitude)
    :ok = put_child(scene, :vsi, new_sim.vertical_speed)
    :ok = put_child(scene, :airspeed_indicator, new_sim.airspeed)
    :ok = put_child(scene, :heading_indicator, new_sim.heading)

    # Update attitude indicator (either background or widget)
    if attitude_background do
      :ok = put_child(scene, :attitude_background, {new_sim.pitch, new_sim.roll})
    else
      :ok = put_child(scene, :attitude_indicator, {new_sim.pitch, new_sim.roll})
    end

    # Schedule next tick
    Process.send_after(self(), :tick, @tick_interval)

    scene
    |> assign(flight_sim: new_sim)
    |> then(&{:noreply, &1})
  end

  # Attitude background - full screen horizon
  defp maybe_add_attitude_background(graph, flight_sim, true) do
    graph
    |> AttitudeIndicator.add_to_graph(
      {flight_sim.pitch, flight_sim.roll},
      id: :attitude_background,
      width: @screen_width,
      height: @screen_height,
      background_mode: true,
      show_border: false,
      show_bank_scale: false,
      show_aircraft: false,
      translate: {0, 0},
      simulate: false
    )
  end

  defp maybe_add_attitude_background(graph, _flight_sim, false) do
    c = ColorScheme.current()
    graph |> rect({@screen_width, @screen_height}, fill: c.bg)
  end

  # Attitude widget frame - only when not in background mode
  defp maybe_draw_attitude_frame(graph, col, row, c, false = attitude_background) do
    draw_widget_frame(graph, col, row, "Attitude", c, attitude_background)
  end

  defp maybe_draw_attitude_frame(graph, _col, _row, _c, true) do
    graph
  end

  # Attitude widget - only when not in background mode
  defp maybe_add_attitude_widget(graph, col, row, flight_sim, false) do
    add_attitude_indicator(graph, col, row, flight_sim)
  end

  defp maybe_add_attitude_widget(graph, _col, _row, _flight_sim, true) do
    graph
  end

  defp cell_origin(col, row) do
    {col * @col_width, row * @row_height}
  end

  defp draw_widget_frame(graph, col, row, title, c, transparent_bg) do
    {x, y} = cell_origin(col, row)
    padding = 15

    graph
    |> maybe_draw_frame_bg(x, y, padding, c, transparent_bg)
    |> text(title,
      fill: c.secondary,
      font_size: 28,
      translate: {x + 40, y + 55}
    )
  end

  defp maybe_draw_frame_bg(graph, x, y, padding, c, false) do
    graph
    |> rrect({@col_width - padding * 2, @row_height - padding * 2, 12},
      fill: c.bg,
      stroke: {2, c.tick},
      translate: {x + padding, y + padding}
    )
  end

  defp maybe_draw_frame_bg(graph, x, y, padding, c, true) do
    graph
    |> rrect({@col_width - padding * 2, @row_height - padding * 2, 12},
      stroke: {2, c.tick},
      translate: {x + padding, y + padding}
    )
  end

  defp add_tachometers(graph, col, row, sim, c, transparent_bg) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> DualTachometer.add_to_graph(
      {sim.left_rpm, sim.right_rpm, sim.left_oil_temp, sim.right_oil_temp},
      id: :engines_rpm,
      translate: {cx - 340, cy - 340},
      simulate: false,
      transparent_bg: transparent_bg
    )
    |> text("ENG 1",
      fill: c.primary,
      font_size: 32,
      text_align: :center,
      translate: {cx - 200, cy + 360}
    )
    |> text("ENG 2",
      fill: c.primary,
      font_size: 32,
      text_align: :center,
      translate: {cx + 200, cy + 360}
    )
  end

  defp add_altimeter(graph, col, row, sim, transparent_bg) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> Altimeter.add_to_graph(
      sim.altitude,
      id: :altimeter,
      translate: {cx - 360, cy - 360},
      simulate: false,
      transparent_bg: transparent_bg
    )
  end

  defp add_vsi(graph, col, row, sim, transparent_bg) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> VSI.add_to_graph(
      sim.vertical_speed,
      id: :vsi,
      translate: {cx - 360, cy - 360},
      simulate: false,
      transparent_bg: transparent_bg
    )
  end

  defp add_attitude_indicator(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    # Rectangular attitude indicator: 760x780, center in widget
    offset_x = (@col_width - 760) / 2
    offset_y = (@row_height - 780) / 2 + 20

    graph
    |> AttitudeIndicator.add_to_graph(
      {sim.pitch, sim.roll},
      id: :attitude_indicator,
      translate: {x + offset_x, y + offset_y},
      simulate: false
    )
  end

  defp add_airspeed_indicator(graph, col, row, sim, transparent_bg) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 30

    graph
    |> AirspeedIndicator.add_to_graph(
      sim.airspeed,
      id: :airspeed_indicator,
      translate: {cx - 330, cy - 330},
      simulate: false,
      transparent_bg: transparent_bg
    )
  end

  defp add_heading_indicator(graph, col, row, sim, transparent_bg) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 30

    graph
    |> HeadingIndicator.add_to_graph(
      sim.heading,
      id: :heading_indicator,
      translate: {cx - 330, cy - 330},
      simulate: false,
      transparent_bg: transparent_bg
    )
  end
end
