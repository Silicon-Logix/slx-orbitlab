<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Orbit, access windows and propulsion

**Orbit and passes** connects a command to measured physical effects. `ORBIT_BURN` passes through the F Prime dictionary and dispatcher. The C++ core checks propellant, perigee, energy, sensors and alignment. Basilisk integrates thrust and returns position, velocity and attitude. Telemetry, 3D, recording and reports follow these measurements.

## Initial targets and later observations

The demonstration's initial circular orbit passes the first selected target at approximately 300 simulated seconds. Choosing **New York** before **Start observation** therefore prepares an early pass over New York. Ground delivery still depends on contact with the configured station.

Adding New York during a Rome mission retains the current physical orbit. F Prime schedules its next suitable pass based on visibility, priority and energy. The page shows the predicted window or absence of access in the next 24 hours. Geographic presets fill valid coordinates; **Correct selected target coordinates** sends `UPDATE_TARGET`. A small burn changes access gradually and does not move the satellite instantly to another city.

## Demonstrating a burn

1. Start the nominal mission and wait for the first image delivery.
2. Open **Orbit and passes → Raise orbit · +2 m/s**.
3. Click **Send maneuver to F Prime**. Watch +X alignment, measured thrust, delivered delta-v, remaining propellant and apogee.
4. In 3D, the amber arrow shows applied thrust. Original geometries, component names and pivots are retained.
5. On **Delta-v achieved**, the previous attitude mode resumes. **Stop thrust** cancels future thrust and retains delivered velocity and consumed propellant.

ACK confirms acceptance; telemetry confirms execution. The clock must advance. Low energy holds thrust and permits Sun pointing/recharge. Invalid sensors or actuators inhibit force. Manual attitude maneuvers are rejected during an active orbital burn; cancel the burn first.

## Units and physical assumptions

| Quantity | Definition |
| --- | --- |
| Command | RTN delta-v [m/s]: R radially outward, T perpendicular to R in the orbital plane, N along `r × v`. Frame refreshed during thrust. |
| Limits | Magnitude 0.01–10 m/s, sufficient propellant, impulsive predicted perigee ≥200 km, eccentricity <0.1. One active burn. |
| Thruster | Ideal center-of-mass body +X force, maximum 5 N. Alignment within 1° and angular-rate error <0.003 rad/s before thrust. |
| Accounting | `delta-v = ∫F/65 dt`; propellant debit `∫F/(220·9.80665) dt`. Initially 1 kg, optionally less. Final impulse limited to remaining delta-v. |
| Dynamics | Basilisk C++ `extForceTorque`. Constant dynamic mass 65 kg; velocity results from integration. |
| Prediction | Elliptical two-body propagation over 24 h; 10 s grid for the first 12000 s, then 30 s. Refresh every 60 s, after burns or via `REPLAN`. |
| Frames | Mathematical ECI and ECEF with constant Earth rotation; no precise J2000/IERS transformation. Graphics follow the 3D coordinate contract. |

Delivered delta-v is the scalar thrust integral. Velocity differences also include gravity and RTN-frame rotation. Predictions exclude future burns. The perigee guard is a demonstration safeguard. Variable mass, tank dynamics, valves, plume, drag, J2, thermal budgets and automatic transfers between cities are excluded. Reports disclose these limits.

## Verification

`tests/test_orbit.py` checks a complete burn against a no-thrust baseline, propellant balance, sensor and energy holds, cancellation, command bounds, New York access, target correction, extended sequences, native completion wait and maintenance. `tools/check-desktop-runtime.py --orbits` exercises actual QML controls and verifies thrust, orbit change and the New York preset. Recording and replay preserve orbital and propellant state.

References: [Basilisk extForceTorque](https://avslab.github.io/basilisk/Documentation/simulation/dynamics/extForceTorque/extForceTorque.html) and [F Prime 4.3 CmdSequencer API](https://fprime.jpl.nasa.gov/v4.3.0/docs/reference/api/cpp/html/class_svc_1_1_cmd_sequencer_component_base.html). This integration uses the pinned project versions.
