<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Commands, effects and targets

Select a command on **F Prime** to load valid example arguments. **Use example** restores them. Operator edits survive telemetry updates. The console explains purpose, dictionary types, argument order, units and operating conditions.

| Command | Example | Effect to verify |
| --- | --- | --- |
| `MANEUVER` | `[3,45]` | A physical 45° relative slew. Automatic observations resume with `[0,0]`. |
| `DEPLOY` | `[0]` | Hinges stow and solar generation changes. `[1]` deploys the panels. |
| `SET_BEACON` | `[1,4]` | Four-second simulated pulse period. Use 1× in 3D. `[0,4]` disables it. |
| `SET_PAYLOAD` | `[0]` | Suspend optical acquisitions. `[1]` permits acquisition when mission conditions allow. |
| `SET_DOWNLINK` | `[1]` | Permit transfer when onboard data, ground contact, link and energy are available. |
| `CMD_NO_OP` | `[]` | Verify the dispatcher response. |
| `CMD_NO_OP_STRING` | `["OrbitLab test"]` | Verify echoed text in `NoOpStringReceived`. |
| `CMD_TEST_CMD_1` | `[-10,1.5,3]` | Verify I32/F32/U8 encoding and `TestCmd1Args`. |
| `ORBIT_BURN` | `[0,2,0]` | Align +X, apply along-track thrust, measure delta-v and orbit change, debit propellant. |
| `CANCEL_BURN` | `[]` | Stop thrust at the next physical step, retaining completed effects. |
| `UPDATE_TARGET` | `[2,0.710572,-1.291648]` | Update pending T2 to New York coordinates and refresh access forecasts. |
| `REPLAN` | `[]` | Predict each target's access over the next 24 simulated hours. |
| `SET_STRATEGY` | `[0]` | Switch to priority planning while retaining targets and data. |
| `CMD_CLEAR_TRACKING` | `[]` | Reset dispatcher tracking after sequences end; verify with a subsequent `CMD_NO_OP`. |

**Last sent** distinguishes native acceptance from confirmed physical state. An accepted command may take time to apply. **Resume simulation to apply physical effects** advances the clock for mission commands; disable it to inspect acceptance while paused. Telemetry determines all mechanism poses and states.

`CONFIGURE` belongs to **Mission → Start new session**, which finalizes the previous session. `SET_STRATEGY` changes policy in the active session and records the change. Comparisons replay identical targets, faults and physical commands while fixing each compared policy.

The `CS_*` commands use **F Prime sequences**: `CS_VALIDATE` validates the binary, `CS_AUTO`/`CS_MANUAL` select mode before `CS_RUN`, `CS_START`/`CS_STEP` advance manually and `CS_CANCEL` cancels. **Verify completion** sends `CS_JOIN_WAIT` and receives a native completion ACK while the service remains responsive. Sequence paths are restricted to the validated session plan. Configuration and dispatcher maintenance are excluded from operational plans.

F Prime 4.3 `CMD_CLEAR_TRACKING` clears its own response slot. OrbitLab records the reset and requires a subsequent native probe's OK response. Maintenance is rejected while a sequence or command response is pending.

The beacon caption describes its enabled state; the indicator and model show actual pulses. Energy protection displays the hold reason. A 4 s simulated period lasts 0.4 real seconds at 10×; use 1× for inspection.

## Active targets

**Targets and data → Add observation** adds a job to the current mission. **Mission** shows the target selected by flight software and others in the queue. A new target is evaluated at the next physics frame; when paused it appears as **Target queued**. An active observation can take precedence.

Images and completion indicators belong to the displayed target. New targets without products have an empty preview. The full archive remains in **Targets and data**. Repeat jobs may show the previous product for that target while waiting for another pass.

**New session · Settings** prepares a distinct initial target. **Start new session** finalizes the current recording and resets physical conditions. Add targets from **Targets and data** to retain time, energy and stored products.

Native `ADD_TARGET` and `SCHEDULE_TARGET` use **radians**. GUI coordinate fields use **degrees**, converted by the service. Examples choose a free ID; `SET_PRIORITY` and `REMOVE_TARGET` use an existing ID. Priority never bypasses visibility or energy protection. See [orbital operations](orbital-operations.md).
