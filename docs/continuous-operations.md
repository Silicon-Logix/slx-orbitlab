<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Continuous operations

The desktop remains active until **Concludi**. Completing an observation preserves orbit, time, battery and sensor state. **Pausa/Riprendi** retains the physical state; **Concludi** finalizes evidence. The default observation targets Rome once at 10× simulated time. Repetition, mission strategy, embedded control and manual faults are available in **Opzioni avanzate**. Operator disconnection pauses execution. The launcher finalizes its owned backend when closed. Reference scenarios remain finite for batch testing; clear the continuous option to use their configured end time in the GUI.

## Observation jobs and products

**Operations** supplies an Earth-fixed map using the original Natural Earth texture. Clicking selects WGS84 coordinates; city presets include Rome, New York, Paris and Tokyo. Scheduling, coordinate corrections, priority changes and retirement enter F Prime through native commands. Jobs support repeat intervals and absolute deadlines. Sixteen active slots are available; completed slots are recycled. A repeat interval starts after storage acknowledgement and still requires a physical pass. Accessible ready windows take precedence; priority orders ready jobs. The 24-hour access scan uses a 10-second grid for the first 12000 seconds, then 30 seconds, refreshed every 60 seconds. **Orbita e passaggi** shows per-target windows and finite propulsion operations.

Each acquisition creates a deterministic 256 × 256 grayscale PGM sampling the Earth texture through the simulated camera, with a derived geographic preview. The default logical onboard capacity is 2 MiB; each product requires 65588 bytes. Queued transfers resume from the last byte offset. Matching ground checksums free logical onboard memory; source files remain as evidence. The GUI previews actual files and retains 64 recent products. Full history remains on disk.

## Energy and faults

Energy-aware planning checks a 600-second forecast in addition to current-energy guards. It propagates the measured two-body orbit through Earth shadow and holds measured solar power during predicted sunlight. It does not predict future attitude or battery chemistry. Reserve violation enters safe mode at 18 W; below 2% charge the load drops to 5 W. Recovery requires reserve plus 3% capacity. Continued baseline consumption can still exhaust the battery. An orbital burn requires reserve plus 5000 J and the remaining ideal thrust-duration load budget; energy hold suspends propulsion and returns to Sun pointing.

Sensor outage freezes the last valid sensor quaternion and inhibits acquisition and commanded attitude torque. Wheel outage inhibits wheel actuation and enters safe mode. Solar loss sets effective generation area to zero in Basilisk. Ground-link outage inhibits data transfer and preserves the queue. Fault intervals use simulation seconds; changed solar generation appears at the next integration boundary. Recovery continues the same spacecraft state.

The optional qualified RTEMS/Renode LEON3 controller remains separate from the F Prime Linux process. Its actual permissions affect applied loads and discretionary operations; qualification must match the ELF hash.

## Evidence and recovery

SQLite recording rotates every 1800 simulated seconds by default, commits every five seconds and hashes closed segments. `SEGMENTS.json` indexes them and `checkpoint.json` identifies committed evidence time. Finalization creates streaming telemetry/event CSV, HTML/JSON reports and a hash manifest. Replay validates these artifacts and synchronizes frames, commands, events, map history and 3D across segment boundaries. Inactive pointing intervals appear as chart gaps.

The default per-run recording quota is 2 GiB, checked every 60 simulated seconds. Writes during that interval can exceed the quota. Less than 100 MiB free disk space also pauses recording with an explicit cause; records are not silently discarded. Continuous sessions have no scheduled end, but remain limited by resources and model fidelity.

**Verification → Recover evidence** rejects active writers, checks committed SQLite data and closed-segment hashes, then finalizes a recovered/aborted recording. Uncommitted frames can be lost. Recovery does not reconstruct or resume the Basilisk physical state.

## Campaigns and comparisons

The GUI runs nine cases per deterministic seed, with one to eight seeds: nominal, low energy, sensor, wheel, solar and link outages, two products, storage pressure and continuous operation. Requirement IDs identify executed safety, pointing, storage and file-integrity checks. Campaign HTML links each run; JSON preserves evidence-manifest digests. Cancellation stops the current batch at a physical boundary and finalizes it as aborted. This is demonstrator integration evidence, not flight certification.

Strategy comparison uses a finite interval even for continuous operator sessions. Both runs receive identical initial configuration, seed, recorded operator commands and injected faults within that interval. A state-dependent command rejection is reported rather than ignored.

Operator commands are replayed before or after their recorded physical frame boundary, matching the original execution order. Acknowledged job metadata updates while paused; it does not read sensors, advance the simulation or consume a transfer quantum.

```powershell
./scripts/verify-all.ps1 -Campaign -DesktopMission
```

The multi-orbit stress test adds targets on later propagated passes. Run from the checkout with the isolated Linux environment:

```bash
~/.cache/slx-orbitlab/venv/bin/python tools/run-verification.py --soak-duration 12400 --output validation/multi-orbit-stress.json
```

Data lacking a usable ground contact remains queued. Runtime identity and [model limits](model.md) accompany each report.
