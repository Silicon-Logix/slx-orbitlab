<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Local integration protocol

The public presentation transport is UTF-8 JSON, one object per newline, over TCP loopback port 8765. Incoming requests are bounded to 64 KiB, require `op` and a 1–80 character `request_id`, and reject non-finite JSON numbers. It is a local desktop integration interface, not a deployed ground-network security protocol.

`hello` requests `operator` or `viewer` role. Only one connection owns the operator lease; disconnecting that operator pauses execution. Godot always requests viewer role. Replies carry `type: reply`, the correlated request ID, `ok`, and either `data` or `error`. Broadcasts carry `type: snapshot`, confirmed snapshot state and runtime status.

Operator operations: `start`, `pause`, `resume`, `step`, `speed`, `command`, `sequence`, `fault`, `schedule_target`, `finish`, `export`, `compare`, `campaign`, `cancel_job`, `recover`, `replay`, `seek` and `shutdown`. `status`, `runs` and `recordings` are readable by viewers. Native commands use the generated F Prime dictionary; their arguments are JSON arrays. Reusing one of the most recent 1024 native command IDs returns the original acknowledgement without execution, and a different payload with that ID is rejected.

Snapshot schema is `slx.orbitlab.snapshot/1`. Physics uses SI units: `position_eci_m`, `velocity_eci_mps`, scalar-first `quaternion_body_to_eci`, `angular_rate_body_radps`, `energy_j`, `generation_w` and `consumed_w`. Sensor validity is explicit. `truth_quaternion_body_to_eci` and `truth_pointing_error_deg` are diagnostic simulator truth, not flight-software measurements. `visual` contains confirmed mechanical angles in native degrees and separately scaled Earth-fixed display coordinates.

Recording/evidence schemas are `slx.orbitlab.scenario/1`, `slx.orbitlab.report/2` and `slx.orbitlab.evidence-manifest/2`. An unfinalized report is a current-run snapshot; replay requires a finalized recording whose manifest passes verification. Replay disables live commanding and rebuilds telemetry, event history and 3D state at the requested simulation timestamp.

The Linux process adapter carries native F Prime packets rather than exposing planning functions to the GUI. The numerical library has an independent C ABI, documented in `core/include/SiliconLogiX/OrbitLab/Core.h`.

`start` accepts `continuous: true`; in this mode snapshot `duration_s` is `null`. The Qt default is continuous; an omitted protocol flag preserves finite-scenario behavior. `schedule_target` accepts WGS84 degrees, integer priority 0–100, `repeat_s` (zero or at least 60) and absolute `deadline_s` (zero for no expiry). Omit the ID to allocate it on the server. `compare` accepts a finite `duration_s`; `campaign` accepts integer `seed_count` 1–8. `fault` accepts `kind` from `attitude_sensor`, `solar_generation`, `reaction_wheel`, `ground_link` and a simulation-second duration.

```json
{"op":"start","request_id":"start-1","scenario":"nominal","strategy":"energy-aware","continuous":true}
{"op":"schedule_target","request_id":"job-2","target":{"name":"Rome repeat","latitude_deg":41.9028,"longitude_deg":12.4964,"priority":80,"repeat_s":5400,"deadline_s":0}}
{"op":"fault","request_id":"fault-3","kind":"ground_link","duration_s":120}
{"op":"compare","request_id":"comparison-4","duration_s":6000}
```

Obtain the operator lease with `hello` before these requests. Snapshots also expose bounded `targets`/`products`, current storage, explicit `actuator_valid`/`link_available`, predicted energy/contact fields, runtime packet counters and recording health. Replayed operator inputs include their `before_frame`/`after_frame` boundary. Job acknowledgements update metadata while paused; they do not advance dynamics or transfer bytes. Reports add requirement checks and verified delivery counts; segment/checkpoint schema versions are `/1`.
