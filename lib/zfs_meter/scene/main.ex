defmodule ZfsMeter.Scene.Main do
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ZfsMeter.Component.DualTachometer
  alias ZfsMeter.Component.Altimeter
  alias ZfsMeter.Component.VSI
  alias ZfsMeter.Component.AttitudeIndicator
  alias ZfsMeter.Component.AirspeedIndicator
  alias ZfsMeter.FlightSim

  # Grid layout: 3 columns x 2 rows
  # Resolution: 2388 x 1668
  @col_width 796
  @row_height 834

  # 20 fps
  @tick_interval 50

  # OLED color palette (yellow -> red spectrum + black)
  @color_black {0, 0, 0}
  @color_yellow {255, 220, 0}
  @color_amber {255, 180, 0}
  @color_orange {255, 140, 0}
  @color_deep_orange {255, 100, 0}
  @color_red_orange {255, 60, 0}
  @color_warm_red {255, 30, 0}
  @color_red {255, 0, 0}

  # Semantic aliases
  @color_bg @color_black
  @color_frame @color_black
  @color_border @color_warm_red
  @color_text @color_amber
  @color_title @color_orange
  @color_status @color_yellow

  @impl Scenic.Scene
  def init(scene, _params, _opts) do
    # Initialize flight simulation
    flight_sim = FlightSim.new()

    graph =
      Graph.build(font: :roboto, font_size: 24)
      |> rect({2388, 1668}, fill: @color_bg)
      # Row 1
      |> draw_widget_frame(0, 0, "Engine RPM")
      |> draw_widget_frame(1, 0, "Altimeter")
      |> draw_widget_frame(2, 0, "Vertical Speed")
      # Row 2
      |> draw_widget_frame(0, 1, "Airspeed")
      |> draw_widget_frame(1, 1, "Attitude")
      |> draw_widget_frame(2, 1, "Widget 6")
      # Flight status display
      |> add_flight_status()
      # Actual widgets - with simulate: false so we control them
      |> add_tachometers(0, 0, flight_sim)
      |> add_altimeter(1, 0, flight_sim)
      |> add_vsi(2, 0, flight_sim)
      |> add_attitude_indicator(1, 1, flight_sim)
      |> add_airspeed_indicator(0, 1, flight_sim)

    # Start simulation tick
    Process.send_after(self(), :tick, @tick_interval)

    scene
    |> assign(flight_sim: flight_sim, graph: graph)
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  @impl GenServer
  def handle_info(:tick, scene) do
    %{flight_sim: sim} = scene.assigns

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
    :ok = put_child(scene, :attitude_indicator, {new_sim.pitch, new_sim.roll})
    :ok = put_child(scene, :airspeed_indicator, new_sim.airspeed)

    # Update flight status display
    graph =
      scene.assigns.graph
      |> Graph.modify(:phase_text, &text(&1, format_phase(new_sim.phase)))
      |> Graph.modify(:altitude_text, &text(&1, "ALT: #{trunc(new_sim.altitude)} ft"))
      |> Graph.modify(:vs_text, &text(&1, "VS: #{trunc(new_sim.vertical_speed)} ft/min"))

    # Schedule next tick
    Process.send_after(self(), :tick, @tick_interval)

    scene
    |> assign(flight_sim: new_sim, graph: graph)
    |> push_graph(graph)
    |> then(&{:noreply, &1})
  end

  defp cell_origin(col, row) do
    {col * @col_width, row * @row_height}
  end

  defp draw_widget_frame(graph, col, row, title) do
    {x, y} = cell_origin(col, row)
    padding = 15

    graph
    |> rrect({@col_width - padding * 2, @row_height - padding * 2, 12},
      fill: @color_frame,
      stroke: {2, @color_border},
      translate: {x + padding, y + padding}
    )
    |> text(title,
      fill: @color_title,
      font_size: 28,
      translate: {x + 40, y + 55}
    )
  end

  defp add_flight_status(graph) do
    # Add flight status in Widget 6 area (bottom-right)
    {x, y} = cell_origin(2, 1)
    cx = x + @col_width / 2

    graph
    |> text("GROUND IDLE",
      id: :phase_text,
      fill: @color_status,
      font_size: 48,
      text_align: :center,
      translate: {cx, y + 300}
    )
    |> text("ALT: 0 ft",
      id: :altitude_text,
      fill: @color_orange,
      font_size: 36,
      text_align: :center,
      translate: {cx, y + 380}
    )
    |> text("VS: 0 ft/min",
      id: :vs_text,
      fill: @color_amber,
      font_size: 36,
      text_align: :center,
      translate: {cx, y + 440}
    )
  end

  defp add_tachometers(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> DualTachometer.add_to_graph(
      {sim.left_rpm, sim.right_rpm, sim.left_oil_temp, sim.right_oil_temp},
      id: :engines_rpm,
      translate: {cx - 340, cy - 340},
      simulate: false
    )
    |> text("ENG 1",
      fill: @color_text,
      font_size: 32,
      text_align: :center,
      translate: {cx - 200, cy + 360}
    )
    |> text("ENG 2",
      fill: @color_text,
      font_size: 32,
      text_align: :center,
      translate: {cx + 200, cy + 360}
    )
  end

  defp add_altimeter(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> Altimeter.add_to_graph(
      sim.altitude,
      id: :altimeter,
      translate: {cx - 360, cy - 360},
      simulate: false
    )
  end

  defp add_vsi(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    graph
    |> VSI.add_to_graph(
      sim.vertical_speed,
      id: :vsi,
      translate: {cx - 360, cy - 360},
      simulate: false
    )
  end

  defp add_attitude_indicator(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 30

    graph
    |> AttitudeIndicator.add_to_graph(
      {sim.pitch, sim.roll},
      id: :attitude_indicator,
      translate: {cx - 330, cy - 330},
      simulate: false
    )
  end

  defp add_airspeed_indicator(graph, col, row, sim) do
    {x, y} = cell_origin(col, row)
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 30

    graph
    |> AirspeedIndicator.add_to_graph(
      sim.airspeed,
      id: :airspeed_indicator,
      translate: {cx - 330, cy - 330},
      simulate: false
    )
  end

  defp format_phase(phase) do
    case phase do
      :ground_idle -> "GROUND IDLE"
      :takeoff_roll -> "TAKEOFF ROLL"
      :rotation -> "ROTATION"
      :initial_climb -> "INITIAL CLIMB"
      :cruise_climb -> "CRUISE CLIMB"
      :level_off -> "LEVEL OFF"
      :cruise -> "CRUISE"
      :descent -> "DESCENT"
      :approach -> "APPROACH"
      :landing -> "LANDING"
    end
  end
end
