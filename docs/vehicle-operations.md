<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Components and commands in 3D

Start a mission and open **3D view**. The left panel explains the selected component and shows its confirmed telemetry. Click a component on the model or select it from the menu. **Focus** centers the camera; **Isolate component** works in interior/exploded views. F Prime actions control the simulated satellite and resume physical time if paused.

| Action | Native command | Verifiable effect |
| --- | --- | --- |
| Deploy panels / Stow | `OrbitLab.mission.DEPLOY [1/0]` | Hinges and solar generation change in Basilisk. |
| Toward the Sun | `OrbitLab.mission.MANEUVER [1,0]` | Wheels align the panel normal with the Sun. |
| Toward the Earth | `OrbitLab.mission.MANEUVER [2,0]` | Point the optical axis toward nadir. |
| Rotate [degrees] | `OrbitLab.mission.MANEUVER [3,angle]` | Relative optical-reference rotation about body Z, −180° to +180°. |
| Resume automatic mission | `OrbitLab.mission.MANEUVER [0,0]` | Resume observation planning. |
| Enable / Disable optical instrument | `OrbitLab.mission.SET_PAYLOAD [1/0]` | Permit or suspend acquisitions. |
| Enable / Disable downlink | `OrbitLab.mission.SET_DOWNLINK [1/0]` | Permit or suspend transfer; retain stored data. |
| Enable flashing / Disable beacon | `OrbitLab.mission.SET_BEACON [1/0,4]` | Four-second simulated period; 2 W load during pulses. |

Use **Satellite close-up → Time 1×** to see flashing. Use 10× or 60× for attitude maneuvers. Telemetry shows commanded-reference pointing error. Observations wait during manual control; **Resume automatic mission** restores them.

Energy reserve, sensor validity and actuator availability govern activity. The beacon is inhibited below its reserve threshold; actuator faults trigger protection. **Inject sensor fault · 10 s** creates an unavailable measurement in the simulator and F Prime responds to it.

The orbit view shows trajectory and target. Green indicates observation pointing and purple indicates active transfer. The ground view shows antenna tracking and the contact link. Interior/exploded views support subsystem inspection. The amber vector shows actual applied thrust during [orbital maneuvers](orbital-operations.md).

Commands, native responses and physical states are recorded together. Replay presents the same states without sending commands. Graphics retain the original asset hierarchies and axes.
