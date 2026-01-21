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
      primary: {255, 180, 0},        # Amber - main text/numbers
      secondary: {255, 140, 0},      # Orange - secondary elements
      accent: {255, 220, 0},         # Yellow - highlights
      border: {255, 100, 0},         # Deep orange - borders
      tick: {255, 30, 0},            # Warm red - tick marks
      needle: {255, 140, 0},         # Orange - needles
      warning: {255, 220, 0},        # Yellow - warnings
      critical: {255, 0, 0},         # Red - critical

      # Semantic colors
      positive: {255, 220, 0},       # Yellow - climb/positive
      negative: {255, 0, 0},         # Red - descent/negative

      # Gauge-specific
      arc_white: {255, 200, 150},    # Warm white for arcs
      arc_green: {200, 180, 0},      # Yellow-green
      arc_yellow: {255, 180, 0},     # Amber
      arc_red: {255, 0, 0},          # Red

      # Attitude indicator (traditional for realism)
      sky: {30, 60, 130},            # Dark blue
      ground: {140, 90, 50},         # Brown
      horizon: {255, 220, 0},        # Yellow

      # Heading indicator
      cardinal: {255, 220, 0},       # Yellow for N
      aircraft: {255, 140, 0}        # Orange
    }
  end

  def get(:sunny_day) do
    %{
      # Base colors - high contrast white/cyan for sunlight
      bg: {0, 0, 0},
      primary: {255, 255, 255},      # Pure white - main text/numbers
      secondary: {0, 255, 255},      # Cyan - secondary elements
      accent: {0, 255, 128},         # Bright green - highlights
      border: {255, 255, 255},       # White - borders
      tick: {0, 255, 255},           # Cyan - tick marks
      needle: {255, 255, 255},       # White - needles
      warning: {255, 255, 0},        # Bright yellow - warnings
      critical: {255, 0, 128},       # Magenta - critical (visible in sun)

      # Semantic colors
      positive: {0, 255, 128},       # Bright green - climb/positive
      negative: {255, 0, 128},       # Magenta - descent/negative

      # Gauge-specific
      arc_white: {255, 255, 255},    # Pure white for arcs
      arc_green: {0, 255, 100},      # Bright green
      arc_yellow: {255, 255, 0},     # Bright yellow
      arc_red: {255, 0, 128},        # Magenta (more visible than red)

      # Attitude indicator
      sky: {0, 100, 200},            # Brighter blue
      ground: {139, 90, 43},         # Sienna brown
      horizon: {255, 255, 255},      # White

      # Heading indicator
      cardinal: {0, 255, 128},       # Bright green for N
      aircraft: {255, 255, 255}      # White
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
