defmodule ZfsMeter.FlightSim do
  @moduledoc """
  Flight simulation that coordinates all instruments realistically.

  Flight phases:
  1. Ground idle - engines at idle, on runway
  2. Takeoff roll - throttle up, accelerating
  3. Rotation - lift off at V1
  4. Initial climb - full power climb
  5. Cruise climb - reduced power, steady climb
  6. Cruise - level flight at altitude
  7. Descent - reduced power, descending
  8. Approach - further reduced power
  9. Landing - touchdown and decelerate

  Then the cycle repeats.
  """

  defstruct [
    :phase,
    :phase_timer,
    :left_rpm,
    :right_rpm,
    :target_rpm,
    :altitude,
    :vertical_speed,
    :airspeed,
    :ground_altitude
  ]

  @idle_rpm 800
  @takeoff_rpm 2700
  @climb_rpm 2500
  @cruise_rpm 2300
  @descent_rpm 1800
  @approach_rpm 1500

  # ft/min at full power
  @max_climb_rate 2000
  @cruise_altitude 12500

  def new do
    %__MODULE__{
      phase: :ground_idle,
      phase_timer: 0,
      left_rpm: @idle_rpm,
      right_rpm: @idle_rpm,
      target_rpm: @idle_rpm,
      altitude: 0,
      vertical_speed: 0,
      airspeed: 0,
      ground_altitude: 0
    }
  end

  def tick(sim, dt_seconds) do
    sim
    |> update_phase(dt_seconds)
    |> update_rpm(dt_seconds)
    |> update_flight_dynamics(dt_seconds)
  end

  defp update_phase(sim, dt) do
    timer = sim.phase_timer + dt

    case sim.phase do
      :ground_idle when timer > 3.0 ->
        %{sim | phase: :takeoff_roll, phase_timer: 0, target_rpm: @takeoff_rpm}

      :takeoff_roll when timer > 4.0 ->
        %{sim | phase: :rotation, phase_timer: 0}

      :rotation when sim.altitude > 500 ->
        %{sim | phase: :initial_climb, phase_timer: 0}

      :initial_climb when sim.altitude > 3000 ->
        %{sim | phase: :cruise_climb, phase_timer: 0, target_rpm: @climb_rpm}

      :cruise_climb when sim.altitude > @cruise_altitude - 500 ->
        %{sim | phase: :level_off, phase_timer: 0, target_rpm: @cruise_rpm}

      :level_off when abs(sim.vertical_speed) < 50 and timer > 2.0 ->
        %{sim | phase: :cruise, phase_timer: 0}

      :cruise when timer > 8.0 ->
        %{sim | phase: :descent, phase_timer: 0, target_rpm: @descent_rpm}

      :descent when sim.altitude < 3000 ->
        %{sim | phase: :approach, phase_timer: 0, target_rpm: @approach_rpm}

      :approach when sim.altitude < 100 ->
        %{sim | phase: :landing, phase_timer: 0, target_rpm: @idle_rpm}

      :landing when sim.altitude <= 0 and timer > 3.0 ->
        %{sim | phase: :ground_idle, phase_timer: 0, altitude: 0, vertical_speed: 0, airspeed: 0}

      _ ->
        %{sim | phase_timer: timer}
    end
  end

  defp update_rpm(sim, dt) do
    # RPM changes gradually (engine spool up/down)
    # RPM per second
    rpm_change_rate = 400

    left_rpm = approach_value(sim.left_rpm, sim.target_rpm, rpm_change_rate * dt)
    # Right engine slightly different for realism
    right_target = sim.target_rpm + :rand.uniform() * 20 - 10
    right_rpm = approach_value(sim.right_rpm, right_target, rpm_change_rate * dt)

    %{sim | left_rpm: left_rpm, right_rpm: right_rpm}
  end

  defp update_flight_dynamics(sim, dt) do
    # Calculate thrust based on average RPM
    avg_rpm = (sim.left_rpm + sim.right_rpm) / 2
    thrust_fraction = (avg_rpm - @idle_rpm) / (@takeoff_rpm - @idle_rpm)
    thrust_fraction = max(0, min(1, thrust_fraction))

    # Different physics based on phase
    {target_vs, altitude} =
      case sim.phase do
        :ground_idle ->
          {0, 0}

        :takeoff_roll ->
          # Still on ground, building speed
          {0, 0}

        :rotation ->
          # Initial climb, aggressive
          target = thrust_fraction * @max_climb_rate * 0.9
          {target, sim.altitude + sim.vertical_speed * dt / 60}

        :initial_climb ->
          target = thrust_fraction * @max_climb_rate * 0.85
          {target, sim.altitude + sim.vertical_speed * dt / 60}

        :cruise_climb ->
          target = thrust_fraction * @max_climb_rate * 0.5
          {target, sim.altitude + sim.vertical_speed * dt / 60}

        :level_off ->
          # Smoothly reduce climb rate to zero
          target = max(0, sim.vertical_speed - 200 * dt)
          {target, sim.altitude + sim.vertical_speed * dt / 60}

        :cruise ->
          # Maintain altitude
          {0, sim.altitude}

        :descent ->
          # Descending
          target = -800 - thrust_fraction * 200
          {target, max(0, sim.altitude + sim.vertical_speed * dt / 60)}

        :approach ->
          # Steeper descent for approach
          target = -600
          {target, max(0, sim.altitude + sim.vertical_speed * dt / 60)}

        :landing ->
          target = -400
          new_alt = max(0, sim.altitude + sim.vertical_speed * dt / 60)

          if new_alt <= 0 do
            {0, 0}
          else
            {target, new_alt}
          end
      end

    # Vertical speed changes gradually
    # ft/min per second
    vs_change_rate = 300
    new_vs = approach_value(sim.vertical_speed, target_vs, vs_change_rate * dt)

    %{sim | vertical_speed: new_vs, altitude: altitude}
  end

  defp approach_value(current, target, max_change) do
    diff = target - current
    change = max(-max_change, min(max_change, diff))
    current + change
  end
end
