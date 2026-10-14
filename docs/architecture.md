<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Architecture

The application separates `src/` and `qml/` for Qt, `core/include/SiliconLogiX/OrbitLab/` for the public C ABI, `private/core/` for numerical implementation, and `scripts/`, `tests/`, `docs/`, `assets/` and `examples/` for reproducible delivery. The 3D asset pack has its own directory.

The Qt process talks to a local JSON-line service on TCP loopback port 8765. Godot attaches as a read-only viewer. A single operator connection owns a control lease. The service coordinates a real F Prime executable and Basilisk; it does not substitute Python mission logic for the C++ core.

FPP defines `OrbitLab.mission`, the ground `OrbitLab.transport`, the sequence `OrbitLab.seqAdapter`, `OrbitLab.cmdDisp` and `OrbitLab.cmdSeq`. The two adapter instances preserve the dispatcher's matched ground/sequence port arrays. The generated topology connects commanding, events, telemetry and the simulation clock. GDS encodes command arguments and decodes native packets from the deployment dictionary. The local host adapter removes GDS framing and passes native command packets to `Svc.CommandDispatcher`. Telemetry and event packets retain F Prime serialization.

The passive mission component wraps a bounded C ABI. Planning, energy authorization and sensor-driven attitude control execute there. The physical boundary supplies SI measurements and validity flags. The core's action is then applied to Basilisk reaction wheels, power loads and mechanical deployment. The next frame contains the physical response. GUI frame rate does not advance simulation time.

Initial setup is an immediate GDS-compiled `.seq`/`.bin` sequence run by `Svc.CmdSequencer` in `BLOCK` mode. The operator editor compiles bounded vehicle plans, validates them with `CS_VALIDATE`, then uses `CS_RUN NO_BLOCK` for relative-time automatic execution or manual stepping. The simulation drives the sequencer's `schedIn`. Native ping barriers drain the dispatcher and sequencer queues before the passive mission is sampled. Actual sequence-command responses are preserved with native opcodes and simulation times. Arbitrary sequence paths and nested sequence commands remain excluded. See [operational sequencing](sequences.md). The autonomous observation/acquisition/downlink workflow is implemented by the C++ mission state machine.

The recorder preserves configurations, native command packets, events, physical snapshots, data products and ground checksums. Replay reads this state rather than re-running control. The most recent 1024 native command IDs are idempotent; clients must use fresh IDs after reconnecting. Comparing strategies constructs fresh processes with the same initial mission, seed, recorded operator commands and injected fault intervals over a finite evaluation horizon.

The public core API contains fixed-size structs, explicit units, bounded target storage and an opaque mission handle. It contains no Qt, Godot, Python or F Prime types. Core code can therefore be replaced by an ABI-compatible shared library independently of the presentation layer.
