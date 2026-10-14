<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Acceptance evidence

The [release acceptance summary](release-0.7.0.json) records checks for the English interface and publication boundary. It includes actual C ABI/Windows runtime tests, native Linux integrations, desktop command/sequence/orbit workflows and SDK verification. Result summaries retain useful counts, physical effects and qualification identity while excluding local paths, recordings and diagnostic transcripts.

The [LEON3 qualification](rtems-renode.json) records six firmware/emulator checks and the matching ELF SHA-256. Its scope is RTEMS 5, Renode 1.16.1, explicit ELF loader conditions, UART, timer/task operation, CRC rejection and energy-dependent permissions. It does not qualify a physical board or arbitrary firmware build.

Complete session evidence is generated locally and is excluded from GitHub. Follow [verification](../docs/validation.md) to reproduce the checks and [model limits](../docs/model.md) to interpret results. An acquisition or small pointing error alone does not count as ground delivery; transferred files require matching checksums.
