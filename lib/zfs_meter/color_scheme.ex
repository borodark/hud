defmodule ZfsMeter.ColorScheme do
  @moduledoc """
  Color scheme definitions for flight instruments.

  All schemes use OLED black background for true black and power efficiency.

  Available schemes:
  - :dark_bmw - Warm amber/orange/red spectrum (classic BMW instrument look)
  - :sunny_day - High contrast white/cyan/green for bright sunlight visibility

  Configure in config.exs:
      config :zfs_meter, :color_scheme, :sunny_day
  """

  @doc """
  Returns the current color scheme based on application config.
  """
  def current do
    scheme = Application.get_env(:zfs_meter, :color_scheme, :dark_bmw)
    get(scheme)
  end

  @doc """
  Returns the color scheme map for the given scheme name.
  """
  def get(scheme \\ :dark_bmw)

  def get(:dark_bmw) do
    %{
      # Base colors - warm amber/orange/red spectrum
      bg: {0, 0, 0},
      # Amber - main text/numbers
      primary: {255, 180, 0},
      # Orange - secondary elements
      secondary: {255, 140, 0},
      # Yellow - highlights
      accent: {255, 220, 0},
      # Deep orange - borders
      border: {255, 100, 0},
      # Warm red - tick marks
      tick: {255, 30, 0},
      # Orange - needles
      needle: {255, 140, 0},
      # Yellow - warnings
      warning: {255, 220, 0},
      # Red - critical
      critical: {255, 0, 0},

      # Semantic colors
      # Yellow - climb/positive
      positive: {255, 220, 0},
      # Red - descent/negative
      negative: {255, 0, 0},

      # Gauge-specific
      # Warm white for arcs
      arc_white: {255, 200, 150},
      # Yellow-green
      arc_green: {200, 180, 0},
      # Amber
      arc_yellow: {255, 180, 0},
      # Red
      arc_red: {255, 0, 0},

      # Attitude indicator (traditional for realism)
      # Dark blue
      sky: {30, 60, 130},
      # Brown
      ground: {140, 90, 50},
      # Yellow
      horizon: {255, 220, 0},

      # Heading indicator
      # Yellow for N
      cardinal: {255, 220, 0},
      # Orange
      aircraft: {255, 140, 0}
    }
  end

  def get(:sunny_day) do
    %{
      # Base colors - high contrast white/cyan for sunlight
      bg: {0, 0, 0},
      # Pure white - main text/numbers
      primary: {255, 255, 255},
      # Cyan - secondary elements
      secondary: {0, 255, 255},
      # Bright green - highlights
      accent: {0, 255, 128},
      # White - borders
      border: {255, 255, 255},
      # Cyan - tick marks
      tick: {0, 255, 255},
      # White - needles
      needle: {255, 255, 255},
      # Bright yellow - warnings
      warning: {255, 255, 0},
      # Magenta - critical (visible in sun)
      critical: {255, 0, 128},

      # Semantic colors
      # Bright green - climb/positive
      positive: {0, 255, 128},
      # Magenta - descent/negative
      negative: {255, 0, 128},

      # Gauge-specific
      # Pure white for arcs
      arc_white: {255, 255, 255},
      # Bright green
      arc_green: {0, 255, 100},
      # Bright yellow
      arc_yellow: {255, 255, 0},
      # Magenta (more visible than red)
      arc_red: {255, 0, 128},

      # Attitude indicator
      # Brighter blue
      sky: {0, 100, 200},
      # Sienna brown
      ground: {139, 90, 43},
      # White
      horizon: {255, 255, 255},

      # Heading indicator
      # Bright green for N
      cardinal: {0, 255, 128},
      # White
      aircraft: {255, 255, 255}
    }
  end

  @doc """
  Get a specific color from a scheme.
  """
  def color(scheme, key) do
    get(scheme)[key]
  end

  @doc """
  List available scheme names.
  """
  def schemes do
    [:dark_bmw, :sunny_day]
  end
end
