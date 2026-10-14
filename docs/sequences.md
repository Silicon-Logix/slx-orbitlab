<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# F Prime operational sequences

**F Prime sequences** composes command plans executed by native `Svc.CmdSequencer` in F Prime 4.3. The integration uses the generated FPP dictionary, GDS encoder, native binary format and CRC validation. Plans support target management, policy changes, orbital and attitude maneuvers, instrument permissions and typed diagnostics.

## First sequence

1. Start a nominal mission. Use **1×** for beacon inspection or **10×** for a faster demonstration.
2. Open **F Prime sequences** and load **Example · attitude and beacon**. The eight-step plan deploys panels, suspends the payload, points toward the Sun, enables the beacon after 5 s, requests a 30° relative slew after another 45 s, disables the beacon after another 60 s, then restores the payload and automatic mission.
3. Click **Validate sequence**. `fprime-seqgen` compiles the plan; native `CS_VALIDATE` checks it. The panel confirms binary size and total delay.
4. Click **Run automatically**, or **Load for manual steps → Start first step**. Manual execution requires **Next step** after each completed command.
5. Follow native responses and mission times. **Check effects in the 3D view** opens the satellite. Check attitude, hinges, instrument permissions, power and beacon telemetry.
6. **Verify completion** requests `CS_JOIN_WAIT`. In manual mode, keep advancing steps until the sequence ends.
7. **Recordings → Finish and save mission** preserves native events, sequence outcomes and physical states for replay.

**Save plan** retains up to 32 named plans in local operator storage. **Load saved** restores one. A loaded or edited plan must be validated against the current mission dictionary. Validated binaries belong to their recording and cannot be substituted without revalidation.

## Timing and safety

Plans contain 1–64 steps. Each relative delay is an integer from 0 to 86400 seconds. Total delay is at most seven days and the compiled binary must fit the native 8192-byte buffer. Guided fields cover six common commands; remaining operational commands expose dictionary arguments and examples.

In automatic mode, delays begin after the previous command response; the first delay starts at sequence execution. In manual mode, delays begin at `CS_START` or `CS_STEP`. Zero-delay steps can share a simulated timestamp.

`CS_RUN` uses `NO_BLOCK`, allowing physics to advance. Native `CS_CommandComplete`, `CS_CommandError`, `CS_SequenceComplete` and `CS_SequenceCanceled` events determine outcomes. The load ACK confirms loading; the completion event confirms the sequence finished.

The `TB_PROC_TIME` clock follows simulated seconds. Every frame schedules the native sequencer and waits for dispatcher/sequencer queue barriers before sampling the passive mission core. Temporal resolution is the scenario step, normally **0.5 s**. Attitude commands use **degrees** and delays use **seconds**.

**Pause** stops physics and the sequencer clock. **Resume** advances both. Immediate operator commands may be accepted while paused; physical effects require the next frame. **Cancel** stops future steps and retains accepted commands. To stop an already requested orbital maneuver, also send `CANCEL_BURN`. Closing a mission cancels an active sequence before finalizing evidence.

## Evidence and limits

Recordings preserve `.seq` source, `.bin` binary, sequence/dictionary SHA-256, native packets and events, opcode responses, step states and applied stimuli. `sequence-commands.csv` records timing. JSON/HTML reports count completed, cancelled and failed sequences. Replay restores sequence state without dispatching commands; strategy comparisons reapply accepted stimuli at their recorded physical boundaries.

An ACK confirms command acceptance. Convergence can take longer, and energy or faults can inhibit activity. Delays do not wait on telemetry conditions. Absolute UTC scheduling, arbitrary sequence uploads, concurrent sequences and restoration of physical simulation from replay are outside this implementation.

See the [NASA F Prime 4.3 sequencer documentation](https://fprime.jpl.nasa.gov/v4.3.0/Svc/CmdSequencer/docs/sdd/), [vehicle operations](vehicle-operations.md) and [model limits](model.md).
