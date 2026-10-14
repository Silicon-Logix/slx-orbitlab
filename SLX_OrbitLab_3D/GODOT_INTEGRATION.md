<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Godot integration contract

`project.godot` starts `res://godot/viewer.tscn`; `godot/viewer.gd` loads the GLBs with the Compatibility renderer. Qt owns commands and sequences. Godot presents confirmed state and graphical inspection.

`mission_client.gd` connects as a read-only observer to TCP loopback port 8765; `--backend-port` selects another port. Live and replay share timestamps, attitude, hinges, events and recorded orbital history. A missing service produces a disconnected status. See [protocol](../docs/protocol.md) and [physical model](../docs/model.md).

## Coordinates and roots

Import GLBs as scenes and retain hierarchy and node names. glTF already converts native Blender `(x, y, z)` to `(x, z, -y)`. Apply this conversion once. Initialize application containers with the identity transform. Orbital display transforms belong to the spacecraft container, leaving internal component transforms intact.

| Meaning | Blender | GLB / Godot |
| --- | --- | --- |
| X axis | `+X` | `+X` |
| Y axis | `+Y` | `-Z` |
| Up axis | `+Z` | `+Y` |
| Satellite/station lengths | metres | metres |
| Presentation Earth | illustrative scale | illustrative scale |

| Export | Required roots |
| --- | --- |
| `SLX_OrbitLab_Spacecraft_Deployed.glb` | `Spacecraft_Root` |
| `SLX_OrbitLab_Spacecraft_Stowed.glb` | `Spacecraft_Root` |
| `SLX_OrbitLab_Spacecraft_Cutaway.glb` | `Spacecraft_Root` |
| `SLX_OrbitLab_Spacecraft_Exploded.glb` | `EXP_Spacecraft_Root` |
| `SLX_OrbitLab_OrbitalEnvironment.glb` | `ENV_OrbitalDisplay` |
| `SLX_OrbitLab_OrbitalScene.glb` | `ORBIT_Spacecraft_Root`, `ENV_OrbitalDisplay` |
| `SLX_OrbitLab_GroundStation.glb` | `GroundStation_Root` |
| `Component_*.glb` | Assembly root declared by the manifest |

Component exports retain their spacecraft-relative placement. Center presentation catalogs in an explicit container; preserve original transforms when reassembling the satellite.

## Articulation

The contract is `scene/asset_manifest.json`. Instances in other views can have prefixes; resolve pivots relative to the selected instance root.

| Node | Native axis | Godot axis | Native pose |
| --- | --- | --- | --- |
| `Solar_Left_Deploy` | local `+Y` | local `-Z` | deployed 0°, stowed +90° |
| `Solar_Right_Deploy` | local `+Y` | local `-Z` | deployed 0°, stowed −90° |
| `Solar_Left_Fold` | local `+Y` | local `-Z` | open 0°, folded 180° |
| `Solar_Right_Fold` | local `+Y` | local `-Z` | open 0°, folded 180° |
| `Solar_Left_Track`, `Solar_Right_Track` | local `+X` | local `+X` | −30° to +30° |
| `GroundStation_AzimuthPivot` | local `+Z` | local `+Y` | −180° to +180°, nominal 0° |
| `GroundStation_ElevationPivot` | local `+X` | local `+X` | 10° to 85°, nominal 20° |

A positive native +Y angle becomes a positive angle about Godot −Z, equivalent to a negative +Z angle. Preserve the sign throughout motion. Resolve exact named pivots; their children carry frames, cells, hinges and supports.

Tracking pivots are children of deployment pivots. Keep tracking at zero during deployment and enable tracking after the deployed pose is confirmed. The optical axis is native `-Y`, hence glTF `+Z`; a Godot `Camera3D` looks along its local `-Z` and requires explicit payload alignment.

Store imported reference transforms. Reconstruct absolute poses from that reference on each update, avoiding accumulated rotations. Deployed variants use zero panel angles; stowed variants already include initial rotations. The continuous mission uses the deployed variant with absolute telemetry poses. An `AnimationPlayer` must not concurrently write transforms controlled by backend telemetry.

Exploded/interior views are inspection states. They never feed positions back into physics, and hidden access surfaces retain required nodes. Selection uses semantic assembly IDs and simple collision shapes rather than detailed screw/cell collision meshes.

## Rendering and verification

PBR materials are retained, with Godot lighting/exposure adjusted for inspection. The presentation Earth and background do not determine numerical orbit, eclipse or irradiance. Those values come from Basilisk. Any level-of-detail optimization must preserve pivot centers and contract names.

`godot/test_mission.gd` requires a loaded mission and checks confirmed poses, component selection, finite transforms and orbital history. Compare deployed, stowed and inspection poses, rotation signs, embedded textures and branding before releasing new assets.
