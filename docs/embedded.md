<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Embedded platform qualification

F Prime remains a Linux host process. RTEMS is a separate energy-controller node, and Basilisk remains the source of physical battery and load behavior.

STM32F4 Discovery has an RTEMS BSP and a Renode board model, but the generic Renode profile and BSP clock/memory assumptions require alignment. Documentation alone is not a boot qualification.

A qualified target is SPARC LEON3. The optional bootstrap installs RCC 1.3.2 (the bundle reports RTEMS 5.0.0 / GCC 10.5.0) and Renode 1.16.1 in the isolated cache. These tools are separate from the primary mission dependencies. The original Antmicro RTEMS/LEON3 example established a documented platform overlap; OrbitLab's own firmware is tested independently.

Sources: [Renode LEON3 support](https://renode.io/news/leon3-support-in-renode/), [RTEMS LEON3 example](https://github.com/antmicro/renode-rtems-leon3), [RCC release](https://download.gaisler.com/anonftp/rcc/rcc-1.3/1.3.2/).

`validation/rtems-renode.json` retains the successful qualification and ELF hash. It covers ELF loading, console UART, timer interrupts, a periodic RTEMS task, malformed CRC rejection, energy-dependent power permission and recovery. The firmware limits loads to 18 W below 5% battery energy and 5 W below 2%.

The ELF loader explicitly sets the initial stack to `0x40400000`, `CLOCK_SPEED` to 50 MHz and the GPTimer prescaler to 49. The latter produces the 1 MHz timer input expected by the BSP; the native Renode default of 255 is incompatible with the intended tick period. The kernel tick is 1 ms and the firmware heartbeat is 100 ms. CPU performance is configured at 50 MIPS for emulation; it is not a hardware benchmark. No PROM image or physical board is claimed.

The adapter uses Renode's remote UART tester with CRC-protected, sequence-correlated requests. Virtual time advances in bounded intervals, independently of wall-clock pacing, with a 100 µs emulation quantum. Boot time is distinct from mission time, which travels explicitly in each frame. A matching qualification report is required before applying permissions to Basilisk loads. Missing firmware responses stop the run; there is no automatic fallback to a host controller.

Enable the controller in the Qt configuration panel or use `start-backend.sh --batch nominal --rtems`. The Linux F Prime deployment, Basilisk physical state and Qt/Godot presentation retain their separate roles. This check demonstrates the software interface and emulator execution; it does not qualify a flight processor or analog power electronics.
