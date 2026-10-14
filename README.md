<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# SLX OrbitLab

**Silicon LogiX mission software, simulation and verification demonstrator.** NASA F Prime runs the native command/telemetry deployment on Linux. A proprietary C++ library performs mission decisions, Basilisk integrates spacecraft physics, and a Qt desktop console presents the operational evidence. Godot 4.5 provides synchronized 3D inspection.

![Silicon LogiX](assets/brand/Silicon_LogiX_logo_cropped.png)

## What the demonstration does

Select a ground target and priority. Flight software predicts access, assesses available energy, commands pointing, acquires a synthetic image, stores it onboard and transfers it during ground contact. Energy and sensor faults can defer operations, reduce loads and trigger protection, with recorded reasons.

Version **0.7.0** provides an English interface and documentation, 28 dictionary commands with argument examples, native F Prime sequence execution, finite orbital burns, propellant accounting and 24-hour access predictions. The console foregrounds flight software, telemetry and verification.

- **F Prime 4.3.0:** FPP interfaces, native dispatcher, events, command responses, generated dictionary and `Svc.CmdSequencer` validation/execution. Reusable plans support relative simulated-time delays, automatic/manual steps, cancellation and completion ACKs.
- **Basilisk 2.12.0:** C++ rigid-body dynamics, reaction wheels, navigation messages, articulated solar generation, eclipse, finite battery and applied thrust. Power and fuel accounting affect mission authorization.
- **Qt 6.12.0:** mission workflow, native command console, stable telemetry tables, recordings, sequence editor, orbit/access controls, reports, About and licensing.
- **Godot 4.5:** satellite, interior, exploded, orbit and ground views. Selected components expose subsystem state; panels, attitude, beacon and antenna follow confirmed telemetry.
- **Evidence:** segmented SQLite recording, native packet preservation, synchronized replay, checksum-confirmed products, HTML/JSON reports, CSV, SHA-256 manifests and same-mission policy comparison.
- **Optional RTEMS 5 / Renode 1.16.1:** separately qualified LEON3 energy-controller firmware. F Prime remains a Linux process; physical hardware is unnecessary.

Three repeatable scenarios cover nominal observation, insufficient energy and temporary attitude-sensor outage. A nine-case campaign also covers actuator/solar/link faults, multiple products, full storage and continuous operation.

## Public source and proprietary SDK

This repository contains the presentation, integration adapters, public ABI, firmware example, scenarios, tests and approved GLB assets under the [Silicon LogiX Evaluation License](LICENSE). **The proprietary mission-core implementation is excluded.** Building a functional demonstrator from public source requires the matching evaluation binary SDK, supplied separately by Silicon LogiX. This is source-available evaluation software; commercial development and integration require an agreement.

Place the approved SDK at `sdk/windows-mingw/` and `sdk/linux-x86_64/`. The Windows pair is `SiliconLogiX.OrbitLab.Core.dll` and `.dll.a`; Linux uses `SiliconLogiX.OrbitLab.Core.so`. Required core version: **0.6.0 or newer, ABI 2**, with the orbital interfaces. See [distribution and protection](docs/distribution.md).

## Build and start

The validated environment is **Windows with WSL2 Ubuntu 22.04**, Qt 6.12.0 / MinGW 13.1.0 and Python. The scripts install pinned backend tools in an isolated Linux cache. Install the approved SDK before building public source.

From the repository root in PowerShell:

```powershell
$orbitLinuxRoot = (wsl -d Ubuntu-22.04 -- wslpath -a -u $PWD.Path.Replace('\', '/')).Trim()
wsl -d Ubuntu-22.04 -- bash "$orbitLinuxRoot/scripts/bootstrap-backend.sh"
wsl -d Ubuntu-22.04 -- bash "$orbitLinuxRoot/scripts/build-backend.sh"
./scripts/build-windows.ps1
./scripts/start-orbitlab.ps1
```

The build deploys Qt and installs the pinned Godot runtime locally. Change `-QtRoot` and `-ToolchainBin` when using a different compatible installation. Linux tools are isolated from the Qt installation.

After setup, double-click the generated **SLX OrbitLab** shortcut or use `Run-SLX-OrbitLab.cmd`. The launcher coordinates the hidden Linux service and desktop, reuses an existing service and closes a service it owns on exit. The executable resolves its local runtime outside the checkout working directory. On Linux, use the bootstrap/build/start backend scripts and build the frontend against a matching Qt kit; Windows/WSL is the validated embedded-viewer environment.

## First observation

Wait for **SERVICE READY**, then select **Mission → Nominal mission → Rome · first observation → Start observation**. Follow **Target → Pointing → Image onboard → Delivered**. The initial speed is 10×; the first access occurs after a few hundred simulated seconds. The image is a synthetic sensor product used to verify acquisition, storage and downlink.

**3D view** provides component inspection and native vehicle commands. **F Prime** shows dictionary arguments, responses and telemetry. **F Prime sequences** prepares command plans. **Targets and data** adds live targets while retaining the orbit. **Orbit and passes** predicts access and executes physical burns. **Recordings** replays evidence; **Tests and comparisons** runs campaigns. Continuous missions run until **Finish**.

Read [the first-observation guide](docs/first-observation.md), [commands and targets](docs/commands-and-targets.md), [sequences](docs/sequences.md), [orbital operations](docs/orbital-operations.md) and [the customer demonstration](docs/customer-demo.md).

## Verification and model scope

```powershell
python tools/audit-source.py
./scripts/verify-all.ps1 -SkipBuild -DesktopConsole -DesktopSequences -DesktopOrbits
```

Interactive GUI checks run sequentially and need their test window active. See [verification](docs/validation.md) and [acceptance evidence](validation/README.md). GitHub Actions checks publication boundaries without requiring the proprietary SDK.

The 3D Earth has illustrative scale. Physics uses explicit SI units and declared frames; the Godot coordinate conversion is applied once. Synthetic imagery, simplified energy/propulsion and access models have documented limits. See [model](docs/model.md), [architecture](docs/architecture.md), [Godot integration](SLX_OrbitLab_3D/GODOT_INTEGRATION.md) and [embedded qualification](docs/embedded.md).

## Custom development and rights

The **Engineering** page presents services on commission: F Prime components, guidance/navigation, energy calibration, verification and embedded integration. Selected areas can be saved locally as a project enquiry. [Contact Silicon LogiX](https://www.siliconlogix.it/contatti) to discuss a development.

Copyright © 2026 Marco Pezzullo · Silicon LogiX. Preserve attribution and the [Evaluation License](LICENSE). Third parties retain their own licenses; see [notices](THIRD_PARTY_NOTICES.md) and [asset attribution](NOTICE.txt). Technology references imply no NASA or other vendor endorsement or flight certification.
