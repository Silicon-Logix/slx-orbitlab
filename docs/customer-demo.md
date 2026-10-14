<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Customer demonstration

SLX OrbitLab demonstrates F Prime mission software, autonomous C++ decisions, Basilisk physics and a Qt console with Godot inspection. Commands, telemetry, protection and repeatable evidence are central to the presentation. Silicon LogiX branding identifies the product; NASA/F Prime references identify technology without implying endorsement or certification.

| Demonstration | Action | Evidence |
| --- | --- | --- |
| Nominal mission | Rome → Start observation | Native commands, deployment, pointing, onboard image and checksum-confirmed delivery. |
| Additional target | Add New York in Targets and data | Correct coordinates, priority and access prediction. |
| Propulsion | +2 m/s in Orbit and passes | Alignment, measured thrust, changed apogee and fuel debit. |
| Native sequence | Prepare, validate and run a delayed plan | GDS compilation, native CRC, dispatcher ACKs, simulated timing, manual steps and completion. |
| Insufficient energy | Dedicated scenario | Reduced loads and a deferred activity with a recorded reason. |
| Sensor outage | Scenario or 3D fault injection | Acquisition/thrust held, visible availability and recovery. |
| Evidence and replay | Finish, report and Recordings | Balances, pointing precision, verified data, synchronized replay and policy comparison. |

The clock runs until **Finish**. Delays use simulated seconds. Use 1× for the beacon and 60× for mission progress; achievable acceleration depends on the PC. Saved plans require validation against each session's dictionary. Time delays do not wait for attitude convergence.

## Environment and acceptance

Start through the **SLX OrbitLab** shortcut or `Run-SLX-OrbitLab.cmd`. The validated setup uses Windows, WSL Ubuntu, isolated Linux dependencies and locally deployed Qt/Godot. Physical hardware is unnecessary. Public source contains the GUI, adapters, public ABI, scenarios, firmware example, tests, approved GLB assets and licenses. The proprietary mission core is supplied separately as an evaluation binary SDK.

`scripts/verify-all.ps1 -DesktopConsole -DesktopSequences -DesktopOrbits` checks the integrations. Acceptance includes startup outside the checkout without Qt in PATH, acquisitions and verified transfers, synchronized 3D, stable scrolling/operator input, native sequences and physical burns. RTEMS/Renode qualification remains specific to its platform and firmware.

Customer developments define mission requirements, target platforms, sensor/actuator models, performance, fault management and acceptance criteria. The core remains separable as a binary library. Review [the model and limits](model.md) and [distribution](distribution.md).
