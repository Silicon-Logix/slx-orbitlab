<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# SLX OrbitLab 3D assets

Original Silicon LogiX satellite geometry, articulated solar panels, optical instrument, antennas, internal subsystems, orbital environment and ground station. The application extends the Godot 4.5 viewer while retaining geometry, hierarchies, names and pivots.

The public package contains sixteen approved GLB exports and the integration manifest. Native Blender source scenes remain outside public distribution. This illustrative geometry supports software integration and inspection; it is not a qualified spacecraft construction design.

## Using the viewer

Start from the Qt console's **3D view** for synchronized telemetry and component commands. Alternatively import `project.godot` in Godot **4.5 stable** and press F5. The Compatibility renderer loads models from `exports/`.

Five views provide satellite close-up, interior, exploded components, orbit and ground station. Right drag orbits the camera, the wheel zooms and clicking selects a component. Mechanisms follow absolute backend telemetry. Station sliders are read-only; reset affects the camera. Without a backend, the view displays the asset reference pose and a disconnected status.

The scene uses metres with native Z-up. glTF uses Y-up. Satellite/station dimensions are metric; the presentation Earth has illustrative scale. See [Godot integration](GODOT_INTEGRATION.md) for frame conversion and pivot contracts, and [the application README](../README.md) for startup and verification.

## Attribution

Demonstration geometry and Silicon LogiX branding are supplied by Silicon LogiX under the repository's Evaluation License. Natural Earth land outlines are public domain; terrain colors and clouds are illustrative rather than observed imagery or current weather. See [Earth texture sources](assets/earth/SOURCES.md) and [asset notices](../NOTICE.txt).
