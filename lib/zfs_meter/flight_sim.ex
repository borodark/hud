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
    :ground_altitude,
    :left_oil_temp,
    :right_oil_temp,
    :pitch,
    :roll,
    :roll_phase,
    :heading,
    :target_heading
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

  # Oil temperature ranges (°C)
  @oil_temp_ambient 20
  @oil_temp_max 110

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
      ground_altitude: 0,
      left_oil_temp: @oil_temp_ambient,
      right_oil_temp: @oil_temp_ambient,
      pitch: 0.0,
      roll: 0.0,
      roll_phase: :rand.uniform() * 2 * :math.pi(),
      heading: 270.0,
      target_heading: 270.0
    }
  end

  def tick(sim, dt_seconds) do
    sim
    |> update_phase(dt_seconds)
    |> update_rpm(dt_seconds)
    |> update_flight_dynamics(dt_seconds)
    |> update_airspeed(dt_seconds)
    |> update_oil_temps(dt_seconds)
    |> update_attitude(dt_seconds)
    |> update_heading(dt_seconds)
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

  defp update_airspeed(sim, dt) do
    # Target airspeed based on flight phase (knots)
    # Typical light twin aircraft speeds
    target_airspeed =
      case sim.phase do
        :ground_idle -> 0
        :takeoff_roll -> 70 * min(1.0, sim.phase_timer / 4.0)
        :rotation -> 75
        :initial_climb -> 95
        :cruise_climb -> 120
        :level_off -> 140
        :cruise -> 145
        :descent -> 130
        :approach -> 90
        :landing -> max(0, 70 - sim.phase_timer * 25)
      end

    # Airspeed changes gradually
    # knots per second
    airspeed_rate = 15
    new_airspeed = approach_value(sim.airspeed, target_airspeed, airspeed_rate * dt)

    %{sim | airspeed: max(0, new_airspeed)}
  end

  defp update_oil_temps(sim, dt) do
    # Oil temp correlates with RPM - higher RPM = more heat
    # Target temp based on RPM fraction
    left_rpm_fraction = (sim.left_rpm - @idle_rpm) / (@takeoff_rpm - @idle_rpm)
    right_rpm_fraction = (sim.right_rpm - @idle_rpm) / (@takeoff_rpm - @idle_rpm)

    # Target temperature ranges from ambient (at idle) to max (at full power)
    left_target = @oil_temp_ambient + left_rpm_fraction * (@oil_temp_max - @oil_temp_ambient)
    right_target = @oil_temp_ambient + right_rpm_fraction * (@oil_temp_max - @oil_temp_ambient)

    # Add slight random variation
    left_target = left_target + (:rand.uniform() - 0.5) * 2
    right_target = right_target + (:rand.uniform() - 0.5) * 2

    # Oil temp changes slowly (thermal inertia)
    # °C per second
    temp_change_rate = 5
    left_temp = approach_value(sim.left_oil_temp, left_target, temp_change_rate * dt)
    right_temp = approach_value(sim.right_oil_temp, right_target, temp_change_rate * dt)

    %{sim | left_oil_temp: left_temp, right_oil_temp: right_temp}
  end

  defp approach_value(current, target, max_change) do
    diff = target - current
    change = max(-max_change, min(max_change, diff))
    current + change
  end

  defp update_attitude(sim, dt) do
    # Target pitch based on flight phase
    target_pitch =
      case sim.phase do
        :ground_idle -> 0.0
        :takeoff_roll -> 0.0
        :rotation -> 12.0
        :initial_climb -> 10.0
        :cruise_climb -> 6.0
        :level_off -> 2.0
        :cruise -> 1.0
        :descent -> -5.0
        :approach -> -3.0
        :landing -> -2.0
      end

    # Smoothly approach target pitch
    # degrees per second
    pitch_rate = 3.0
    new_pitch = approach_value(sim.pitch, target_pitch, pitch_rate * dt)

    # Roll oscillates gently during flight (simulates minor corrections)
    # Use sine wave with slow frequency for natural feel
    # slow oscillation
    roll_phase = sim.roll_phase + dt * 0.3

    # Roll amplitude depends on phase (more stable on ground)
    roll_amplitude =
      case sim.phase do
        :ground_idle -> 0.0
        :takeoff_roll -> 0.0
        :rotation -> 2.0
        :initial_climb -> 4.0
        :cruise_climb -> 3.0
        :level_off -> 2.0
        :cruise -> 3.0
        :descent -> 4.0
        :approach -> 2.0
        :landing -> 1.0
      end

    target_roll = :math.sin(roll_phase) * roll_amplitude
    # degrees per second
    roll_rate = 5.0
    new_roll = approach_value(sim.roll, target_roll, roll_rate * dt)

    %{sim | pitch: new_pitch, roll: new_roll, roll_phase: roll_phase}
  end

  defp update_heading(sim, dt) do
    # Heading changes based on flight phase
    # Simulate a flight pattern: takeoff heading 270, turn to 360 for cruise,
    # then turn to 090 for approach back to runway

    target_heading =
      case sim.phase do
        :ground_idle -> 270.0
        :takeoff_roll -> 270.0
        :rotation -> 270.0
        :initial_climb -> 270.0
        :cruise_climb -> 360.0
        :level_off -> 360.0
        :cruise -> 360.0
        :descent -> 090.0
        :approach -> 090.0
        :landing -> 090.0
      end

    # Calculate shortest turn direction
    diff = target_heading - sim.heading

    diff =
      cond do
        diff > 180 -> diff - 360
        diff < -180 -> diff + 360
        true -> diff
      end

    # Turn rate depends on phase (degrees per second)
    turn_rate =
      case sim.phase do
        :ground_idle -> 0.0
        :takeoff_roll -> 0.0
        :rotation -> 0.0
        _ -> 3.0
      end

    # Apply turn
    heading_change = max(-turn_rate * dt, min(turn_rate * dt, diff))
    new_heading = sim.heading + heading_change

    # Normalize to 0-360
    new_heading =
      cond do
        new_heading >= 360 -> new_heading - 360
        new_heading < 0 -> new_heading + 360
        true -> new_heading
      end

    %{sim | heading: new_heading, target_heading: target_heading}
  end
end
