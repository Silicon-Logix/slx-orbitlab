<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Your first observation

Open the **SLX OrbitLab** shortcut created by the Windows build. Wait for the Linux service connection; **Start observation** becomes available when the operator session is ready. The 3D engine is installed during setup and models are imported automatically at first use.

1. Keep **Nominal mission** and **Rome · first observation**, then click **Start observation**. Initial speed is 10×. Automatic flight software handles the observation.
2. Follow **Target → Pointing → Image onboard → Delivered**. Rome access is approximately 240–330 simulated seconds; the workflow explains any hold.
3. Acquisition creates a simulated 256 × 256 sensor frame from spacecraft position, attitude and the Earth texture. The preview shows the region, target and geographic footprint. Click it to enlarge.
4. During ground contact, delivery is confirmed by integrity verification. Click **Open received data** to inspect the file. **Targets and data** adds jobs and shows the archive.
5. Open **Satellite in 3D** or **3D view**. Select a component to see purpose and telemetry. Try **Rotate [degrees]**, **Deploy panels**, **Stow** or **Enable flashing**. These issue native F Prime commands. Use **Time 1×** for beacon pulses, then **Resume automatic mission** to continue observations. **Focus** and **Isolate component** aid inspection.
6. **Pause** preserves state, **Resume** continues and **Finish** prepares the report. The session otherwise remains open for new targets. Repeat intervals default to zero; use **Advanced options** for repeated jobs, priorities, faults and the optional controller. **Recordings** provides replay; **Tests and comparisons** runs campaigns and compares strategies.

On **F Prime**, select `OrbitLab.mission.MANEUVER` with `[3,45]` for a slew or `OrbitLab.mission.SET_BEACON` with `[1,4]` for flashing. **Use example** restores arguments. The panel explains types, units, conditions and outcomes. `CMD_NO_OP` verifies the dispatcher. See [commands and targets](commands-and-targets.md).

**F Prime sequences** prepares, saves, validates and executes ordered command plans. Try **Example · attitude and beacon → Validate sequence → Run automatically → Check effects in the 3D view**. See [sequence timing and evidence](sequences.md).

F Prime decides and commands; Basilisk integrates dynamics, sensors, actuators and energy; Qt/Godot present telemetry. Images are synthetic, the 3D Earth is illustrative and inspection poses are graphical. Review [model limits](model.md).

**Reopen 3D** restarts the viewer while the mission continues. **Repair 3D** restores a missing engine from the local runtime or official download. Embedding is validated on Windows; other platforms use a separate viewer window.
