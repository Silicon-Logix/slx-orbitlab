<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Verification

Checks run against real native F Prime and Basilisk integration. Acceptance includes command encoding, native responses, physical decisions, data delivery, replay, desktop interaction and proprietary SDK compatibility. [Acceptance evidence](../validation/README.md) records the validated release and scope.

## Repeating checks

From the Windows checkout, build with `scripts/build-windows.ps1`. This runs three CTest checks: C ABI/safety contracts, Qt startup and local deployed-runtime loading without Qt in PATH.

```powershell
./scripts/verify-all.ps1 -SkipBuild -DesktopConsole -DesktopSequences -DesktopOrbits
```

Linux tests use the isolated environment's `python -m pytest tests/ -q`. They cover native command examples/events, CRC validation, automatic/manual sequencing, completion waits, cancellation, orbit/fuel effects, target correction, energy/sensor holds, multiple deliveries, numerical repeatability, ownership, replay integrity, recording recovery and policy comparisons. The separate publication tests run without the SDK.

Interactive GUI checks run **sequentially**, with the test window active:

```powershell
python tools/check-desktop-runtime.py --console --extended --port 8901 --output validation/desktop-usability-0.7.0.json
python tools/check-desktop-runtime.py --sequences --port 8902 --output validation/desktop-sequences-0.7.0.json
python tools/check-desktop-runtime.py --orbits --port 8903 --output validation/desktop-orbits-0.7.0.json
```

The first check exercises examples, preserved operator edits, diagnostic explanations, goal-specific previews, two verified deliveries, stable beacon captions, channel scrolling, all five embedded scenes and physical attitude maneuvers. The sequence check validates/runs an eight-step native plan, verifies simulated delays/ACKs, reusable plans, recording-card bounds, scroll and replay. The orbit check sends +2 m/s, verifies measured thrust, fuel debit and orbit change, then schedules New York from its actual preset.

`--application <package>/build/windows-mingw/slx-orbitlab.exe` selects an independently built evaluation package. `tools/check-binary-sdk.py` checks a delivered image and physical burn against the approved Linux library hash without private sources. `--startup` checks clean exit while a service is preparing. `-Campaign` adds the nine-case campaign; [continuous operations](continuous-operations.md) documents longer runs.

## 3D and publication checks

With a mission loaded in the local service:

```powershell
./build/tools/godot/Godot_v4.5-stable_win64_console.exe --headless --path SLX_OrbitLab_3D --script res://godot/test_mission.gd
```

Godot checks real telemetry, scene selection, finite transforms, absolute pivot poses, axis signs, deployment/tracking and recorded orbital history. Mechanism inspection cannot modify ground-station telemetry. Geometry/source checks and numerical integration checks have separate scope.

`python tools/audit-source.py` checks attribution, English operator text, links and embedded resources. In a fresh publication tree, add `--public --github --git` to check files, staged contents and local history. Original source implementation hashes are also compared during export.

## Evidence interpretation

Finalized local runs retain SQLite segments, scenario, sequence source/binary, optical products, received files, native packets, reports, CSV and a SHA-256 manifest. The manifest detects content changes; it is not a signature or proof of flight qualification. Public acceptance summaries exclude operator data, developer paths and raw diagnostics.

RTEMS/Renode acceptance is specific to the [qualified firmware and loader](embedded.md). The controller demonstrates software communication and emulated execution; qualification of physical flight hardware is outside this demonstration. Review [model limits](model.md) with every report.
