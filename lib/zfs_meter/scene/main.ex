defmodule ZfsMeter.Scene.Main do
  use Scenic.Scene

  alias Scenic.Graph
  import Scenic.Primitives

  alias ZfsMeter.Component.Tachometer
  alias ZfsMeter.Component.Altimeter
  alias ZfsMeter.Component.VSI

  # Grid layout: 3 columns x 2 rows
  # Resolution: 2388 x 1668
  @col_width 796
  @row_height 834

  @impl Scenic.Scene
  def init(scene, _params, _opts) do
    graph =
      Graph.build(font: :roboto, font_size: 24)
      |> rect({2388, 1668}, fill: {25, 25, 30})
      # Row 1
      |> draw_widget_frame(0, 0, "Engine RPM")
      |> draw_widget_frame(1, 0, "Altimeter")
      |> draw_widget_frame(2, 0, "Vertical Speed")
      # Row 2 - placeholders
      |> draw_widget_frame(0, 1, "Widget 4")
      |> draw_widget_frame(1, 1, "Widget 5")
      |> draw_widget_frame(2, 1, "Widget 6")
      # Actual widgets
      |> add_tachometers(0, 0)
      |> add_altimeter(1, 0)
      |> add_vsi(2, 0)

    scene
    |> push_graph(graph)
    |> then(&{:ok, &1})
  end

  defp cell_origin(col, row) do
    {col * @col_width, row * @row_height}
  end

  defp draw_widget_frame(graph, col, row, title) do
    {x, y} = cell_origin(col, row)
    padding = 15

    graph
    |> rrect({@col_width - padding * 2, @row_height - padding * 2, 12},
      fill: {35, 35, 40},
      stroke: {2, {60, 60, 70}},
      translate: {x + padding, y + padding}
    )
    |> text(title,
      fill: {:white, 200},
      font_size: 28,
      translate: {x + 40, y + 55}
    )
  end

  defp add_tachometers(graph, col, row) do
    {x, y} = cell_origin(col, row)
    # Both tachometers share the same center point, creating "( )" layout
    # Internal offset is {20, radius+20} = {20, 340}
    # Position so the shared center is at cell center
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40

    # Both dials mount at the same point - center of the cell
    # The internal offset {20, 340} means we subtract that to center
    mount_x = cx - 20
    mount_y = cy - 340

    graph
    |> Tachometer.add_to_graph({2400.0, :left}, id: :engine1_rpm, translate: {mount_x, mount_y})
    |> Tachometer.add_to_graph({2400.0, :right}, id: :engine2_rpm, translate: {mount_x, mount_y})
    |> text("ENG 1", fill: :white, font_size: 32, text_align: :center, translate: {cx - 200, cy + 360})
    |> text("ENG 2", fill: :white, font_size: 32, text_align: :center, translate: {cx + 200, cy + 360})
  end

  defp add_altimeter(graph, col, row) do
    {x, y} = cell_origin(col, row)
    # Altimeter has internal translate of {radius+20, radius+20} = {360, 360}
    # To center it, offset by that amount from cell center
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40  # Shift down for title

    graph
    |> Altimeter.add_to_graph(12500.0, id: :altimeter, translate: {cx - 360, cy - 360})
  end

  defp add_vsi(graph, col, row) do
    {x, y} = cell_origin(col, row)
    # VSI has internal translate of {radius+20, radius+20} = {360, 360}
    cx = x + @col_width / 2
    cy = y + @row_height / 2 + 40  # Shift down for title

    graph
    |> VSI.add_to_graph(0.0, id: :vsi, translate: {cx - 360, cy - 360})
  end
end
