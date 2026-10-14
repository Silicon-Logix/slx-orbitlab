# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

## Validate the 3D contract against a running backend, including absolute poses and scene changes.
extends SceneTree
var viewer: Control
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	viewer = load("res://godot/viewer.tscn").instantiate()
	root.add_child(viewer)
	await create_timer(2.0).timeout
	_check(not viewer.backend_snapshot.is_empty(), "Actual backend telemetry is required")
	if viewer.backend_snapshot.is_empty():
		print(JSON.stringify({"passed": false, "failures": failures}))
		quit(1)
		return
	for index in [0, 1, 2, 3, 4]:
		viewer.set_scene(index)
		await process_frame
		viewer._apply_backend_state()
		_check(viewer.asset != null, "Scene %s failed to load" % index)
		_check(viewer.component_selector.item_count > 0 and not viewer.selected_component.is_empty(), "Component selection must describe this scene")
		if index != 2:
			var angles: Dictionary = viewer.backend_snapshot.visual.pivots_native_deg
			for key in viewer.pivots:
				var before: Transform3D = viewer.pivots[key].transform
				for repetition in range(12):
					viewer._apply_backend_state()
				_check(viewer.pivots[key].transform.is_equal_approx(before), "Accumulating rotation: " + key)
				_check(viewer.pivots[key].transform.origin.is_finite(), "Non-finite pivot: " + key)
				if key.begins_with("Solar"):
					var axis := Vector3.RIGHT if key.ends_with("Track") else Vector3(0, 0, -1)
					var expected: Basis = viewer.rest_transforms[key].basis * Basis(axis, deg_to_rad(float(angles[key])))
					_check(viewer.pivots[key].basis.is_equal_approx(expected), "Axis conversion: " + key)
		if index == 3:
			_check(viewer.spacecraft_display.transform.origin.is_finite(), "Orbital display position invalid")
			_check(viewer.find_exact(viewer.asset, "ENV_OrbitalOverlay").visible == false, "Static presentation trajectory must be hidden")
			if viewer.backend_snapshot.get("presentation_history", []).size() > 1 or viewer.backend_snapshot.get("trail_ecef_display", []).size() > 1:
				_check(viewer.trace_points.size() > 1 and viewer.orbital_trace.mesh != null, "Recorded orbital history must produce a visible trajectory")
		if index == 4:
			_check(not viewer.azimuth_slider.editable and not viewer.elevation_slider.editable, "Ground mechanics must be read-only")
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture")
	if capture >= 0 and capture + 1 < args.size():
		viewer.set_scene(3)
		await create_timer(0.5).timeout
		await process_frame
		var captured := root.get_texture().get_image()
		_check(captured.save_png(args[capture + 1]) == OK, "Could not save presentation capture")
	print(JSON.stringify({"schema": "slx.orbitlab.viewer-integration/1", "passed": failures.is_empty(), "run_id": viewer.backend_snapshot.get("run_id"), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
