# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

extends Control
## Telemetry-driven inspector extending the original, verified asset hierarchy.

const SCENES := [
    {"title": "Satellite", "file": "SLX_OrbitLab_Spacecraft_Deployed.glb", "prefix": "", "solar": true},
    {"title": "Inspectable interior", "file": "SLX_OrbitLab_Spacecraft_Cutaway.glb", "prefix": "", "solar": true},
    {"title": "Exploded components", "file": "SLX_OrbitLab_Spacecraft_Exploded.glb", "prefix": "EXP_", "solar": false},
    {"title": "Orbital view", "file": "SLX_OrbitLab_OrbitalScene.glb", "prefix": "ORBIT_", "solar": false},
    {"title": "Ground station", "file": "SLX_OrbitLab_GroundStation.glb", "prefix": "", "solar": false}
]
const INK := Color("101727")
const PANEL := Color("172135")
const ACCENT := Color("8fb4ff")
const TEXT := Color("e7edf8")

var stage: Node3D
var asset: Node3D
var camera: Camera3D
var view: SubViewport
var view_container: SubViewportContainer
var selector: OptionButton
var solar_button: Button
var status_label: Label
var metrics_label: Label
var ground_controls: VBoxContainer
var azimuth_slider: HSlider
var elevation_slider: HSlider
var azimuth_label: Label
var elevation_label: Label
var scene_heading: Label
var current_scene := 0
var target := Vector3.ZERO
var distance := 6.0
var initial_distance := 6.0
var yaw := 0.65
var pitch := 0.30
var dragging := false
var pivots: Dictionary = {}
var rest_transforms: Dictionary = {}
var metrics: Dictionary = {}
var backend_snapshot: Dictionary = {}
var mission_client: Node
var spacecraft_display: Node3D
var selected_component := ""
var selection_label: Label
var component_selector: OptionButton
var orbital_trace: MeshInstance3D
var trace_points: Array[Vector3] = []
var applied_frames := 0
var embedded := false
var ui_port := 0
var presentation := PacketPeerUDP.new()
var pending_pick := Vector2(-1, -1)
var focused := false
var isolated := false
var highlight: MeshInstance3D
var beacon: MeshInstance3D
var thrust_arrow: MeshInstance3D
var picked_component := ""
var pick_count := 0
var mission_overlay: MeshInstance3D
var target_marker: MeshInstance3D
const NATIVE_TO_GLTF := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    embedded = args.has("--embedded")
    var ui_index := args.find("--ui-port")
    if ui_index >= 0 and ui_index + 1 < args.size():
        ui_port = int(args[ui_index + 1])
        if presentation.bind(0, "127.0.0.1") == OK:
            presentation.set_dest_address("127.0.0.1", ui_port)
            print("SLX_VIEWER_ENDPOINT ", presentation.get_local_port())
    _build_view()
    _build_ui()
    set_scene(0)
    mission_client = load("res://godot/mission_client.gd").new()
    mission_client.state_changed.connect(_backend_state)
    mission_client.connection_changed.connect(_connection_state)
    add_child(mission_client)
    var view_index := args.find("--view")
    if view_index >= 0 and view_index + 1 < args.size():
        set_scene(int(args[view_index + 1]))
    get_viewport().size_changed.connect(_resize_view)
    call_deferred("_resize_view")
    # Read-only presentation acknowledgement for the owning Qt process.
    var presentation_timer := Timer.new()
    presentation_timer.wait_time = 1.0
    presentation_timer.timeout.connect(_report_viewer_state)
    add_child(presentation_timer)
    presentation_timer.start()

func _report_viewer_state() -> void:
    print("SLX_VIEWER_STATE " + JSON.stringify({
        "scene": current_scene, "asset_loaded": asset != null, "selected_component": selected_component,
        "beacon_visible": beacon != null and beacon.visible,
        "propulsion_visible": thrust_arrow != null and thrust_arrow.visible,
        "isolated": isolated, "focused": focused,
        "picked_component": picked_component, "pick_count": pick_count,
        "connected": mission_client.connected,
        "run_id": backend_snapshot.get("run_id", ""),
        "time_s": backend_snapshot.get("time_s", 0),
        "applied_frames": applied_frames,
        "viewport_size": [get_viewport_rect().size.x, get_viewport_rect().size.y],
        "window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
        "quaternion_body_to_eci": backend_snapshot.get("visual", {}).get("quaternion_body_to_eci", []),
        "pivots_native_deg": backend_snapshot.get("visual", {}).get("pivots_native_deg", {})
    }))

func _build_view() -> void:
    var background := ColorRect.new()
    background.color = INK
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)
    view_container = SubViewportContainer.new()
    view_container.stretch = true
    view_container.anchor_right = 1.0
    view_container.anchor_bottom = 1.0
    view_container.offset_left = 0.0 if embedded else 312.0
    view_container.offset_top = 0.0 if embedded else 72.0
    view_container.offset_right = 0.0 if embedded else -12.0
    view_container.offset_bottom = 0.0 if embedded else -12.0
    view_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(view_container)
    view = SubViewport.new()
    view.own_world_3d = true
    view.transparent_bg = false
    view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    view.msaa_3d = Viewport.MSAA_4X
    view_container.add_child(view)
    stage = Node3D.new()
    stage.name = "InspectionStage"
    view.add_child(stage)
    camera = Camera3D.new()
    camera.name = "InspectionCamera"
    camera.fov = 43.0
    camera.near = 0.02
    camera.far = 1000.0
    camera.current = true
    stage.add_child(camera)
    var world := WorldEnvironment.new()
    var env := Environment.new()
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("10182d")
    sky_material.sky_horizon_color = Color("35435e")
    sky_material.ground_bottom_color = Color("0c1425")
    sky_material.ground_horizon_color = Color("28354b")
    sky.sky_material = sky_material
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("afbedb")
    env.ambient_light_energy = 0.65
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world.environment = env
    stage.add_child(world)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
    key.light_color = Color("fff5e8")
    key.light_energy = 2.0
    key.shadow_enabled = true
    stage.add_child(key)
    var rim := DirectionalLight3D.new()
    rim.rotation_degrees = Vector3(25.0, 145.0, 0.0)
    rim.light_color = Color("9fbaff")
    rim.light_energy = 0.85
    stage.add_child(rim)

func _build_ui() -> void:
    var theme := Theme.new()
    theme.default_font_size = 16
    set_theme(theme)
    var header := Panel.new()
    header.visible = not embedded
    header.anchor_right = 1.0
    header.offset_bottom = 60.0
    var header_style := StyleBoxFlat.new()
    header_style.bg_color = PANEL
    header.add_theme_stylebox_override("panel", header_style)
    add_child(header)
    var title := Label.new()
    title.text = "ORBITLAB 3D"
    title.position = Vector2(132, 17)
    title.add_theme_font_size_override("font_size", 21)
    title.add_theme_color_override("font_color", TEXT)
    header.add_child(title)
    var logo_image := Image.new()
    if logo_image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/branding/Silicon_LogiX_logo_cropped.png")) == OK:
        var logo := TextureRect.new()
        logo.texture = ImageTexture.create_from_image(logo_image)
        logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        logo.position = Vector2(24, 6)
        logo.size = Vector2(88, 48)
        logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
        header.add_child(logo)
    var note := Label.new()
    note.text = "MISSION-CONFIRMED STATE"
    note.anchor_left = 1.0
    note.anchor_right = 1.0
    note.offset_left = -260.0
    note.offset_right = -24.0
    note.offset_top = 22.0
    note.add_theme_font_size_override("font_size", 12)
    note.add_theme_color_override("font_color", ACCENT)
    header.add_child(note)
    var sidebar := Panel.new()
    sidebar.visible = not embedded
    sidebar.anchor_bottom = 1.0
    sidebar.offset_top = 72.0
    sidebar.offset_left = 12.0
    sidebar.offset_right = 300.0
    sidebar.offset_bottom = -12.0
    var sidebar_style := StyleBoxFlat.new()
    sidebar_style.bg_color = PANEL
    sidebar_style.corner_radius_top_left = 12
    sidebar_style.corner_radius_top_right = 12
    sidebar_style.corner_radius_bottom_left = 12
    sidebar_style.corner_radius_bottom_right = 12
    sidebar.add_theme_stylebox_override("panel", sidebar_style)
    add_child(sidebar)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "top", "right", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 20)
    sidebar.add_child(margin)
    var sidebar_scroll := ScrollContainer.new()
    sidebar_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(sidebar_scroll)
    var column := VBoxContainer.new()
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation", 15)
    sidebar_scroll.add_child(column)
    _add_label(column, "SATELLITE INSPECTION", 12, ACCENT)
    selector = OptionButton.new()
    selector.custom_minimum_size.y = 44
    for item in SCENES:
        selector.add_item(item.title)
    selector.item_selected.connect(set_scene)
    column.add_child(selector)
    scene_heading = _add_label(column, "", 21, TEXT)
    metrics_label = _add_label(column, "", 13, Color("bdcbe3"))
    column.add_child(HSeparator.new())
    _add_label(column, "COMMANDED MECHANISMS", 12, ACCENT)
    solar_button = Button.new()
    solar_button.text = "Panels: F Prime / Basilisk state"
    solar_button.custom_minimum_size.y = 44
    solar_button.disabled = true
    column.add_child(solar_button)
    ground_controls = VBoxContainer.new()
    ground_controls.add_theme_constant_override("separation", 8)
    column.add_child(ground_controls)
    azimuth_label = _add_label(ground_controls, "Azimuth  0°", 14, TEXT)
    azimuth_slider = HSlider.new()
    azimuth_slider.min_value = -180
    azimuth_slider.max_value = 180
    azimuth_slider.step = 1
    azimuth_slider.value_changed.connect(_ground_pose)
    ground_controls.add_child(azimuth_slider)
    elevation_label = _add_label(ground_controls, "Elevation  20°", 14, TEXT)
    elevation_slider = HSlider.new()
    elevation_slider.min_value = 10
    elevation_slider.max_value = 85
    elevation_slider.step = 1
    elevation_slider.value = 20
    elevation_slider.value_changed.connect(_ground_pose)
    ground_controls.add_child(elevation_slider)
    var reset := Button.new()
    reset.text = "Reset camera"
    reset.custom_minimum_size.y = 44
    reset.pressed.connect(reset_view)
    column.add_child(reset)
    status_label = _add_label(column, "", 13, ACCENT)
    status_label.custom_minimum_size.y = 42
    selection_label = _add_label(column, "Select a component to see its mission state.", 12, TEXT)
    component_selector = OptionButton.new()
    component_selector.custom_minimum_size.y = 35
    component_selector.item_selected.connect(func(index):
        selected_component = str(component_selector.get_item_metadata(index))
        _update_selection())
    column.add_child(component_selector)
    var spacer := Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(spacer)
    column.add_child(HSeparator.new())
    _add_label(column, "Right drag: orbit camera\nWheel: zoom\nClick: select a component", 13, TEXT)

func _add_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label

func _resize_view() -> void:
    # The stretched SubViewportContainer manages its child viewport size.
    pass

func set_scene(index: int) -> void:
    if index < 0 or index >= SCENES.size():
        return
    if asset != null:
        stage.remove_child(asset)
        asset.queue_free()
    pivots.clear()
    rest_transforms.clear()
    if highlight != null:
        highlight.queue_free()
    highlight = null
    beacon = null
    thrust_arrow = null
    isolated = false
    focused = false
    if mission_overlay != null:
        mission_overlay.visible = index in [3, 4]
    if target_marker != null:
        target_marker.visible = index == 3
    spacecraft_display = null
    orbital_trace = null
    trace_points.clear()
    current_scene = index
    var resource = load("res://exports/" + SCENES[index].file)
    if not resource is PackedScene:
        status_label.text = "Unable to load the 3D model."
        push_error("Asset could not be loaded: " + SCENES[index].file)
        return
    asset = resource.instantiate()
    stage.add_child(asset)
    _stop_imported_animations(asset)
    var prefix: String = SCENES[index].prefix
    var spacecraft_root := find_exact(asset, prefix + "Spacecraft_Root") as Node3D
    if spacecraft_root != null and index != 2:
        spacecraft_display = Node3D.new()
        spacecraft_display.name = "MissionPresentation"
        spacecraft_root.get_parent().add_child(spacecraft_display)
        spacecraft_root.reparent(spacecraft_display, false)
    for name in ["Solar_Left_Deploy", "Solar_Right_Deploy", "Solar_Left_Fold", "Solar_Right_Fold", "Solar_Left_Track", "Solar_Right_Track", "GroundStation_AzimuthPivot", "GroundStation_ElevationPivot"]:
        var pivot := find_exact(asset, prefix + name) as Node3D
        if pivot != null:
            pivots[name] = pivot
            rest_transforms[name] = pivot.transform
    metrics = measure_asset(asset)
    var bounds: AABB = metrics.bounds
    target = bounds.position + bounds.size * 0.5
    initial_distance = maxf(2.5, bounds.size.length() * 1.05)
    distance = initial_distance
    yaw = 0.65
    pitch = 0.30
    if index == 3:
        pitch = 0.13
    selector.select(index)
    scene_heading.text = SCENES[index].title
    metrics_label.text = "%s meshes\n%s triangles" % [str(metrics.meshes), str(metrics.triangles)]
    solar_button.visible = SCENES[index].solar
    solar_button.disabled = true
    ground_controls.visible = index == 4
    azimuth_slider.set_value_no_signal(0)
    elevation_slider.set_value_no_signal(20)
    azimuth_slider.editable = false
    elevation_slider.editable = false
    _ground_pose(0)
    status_label.text = "Waiting for mission telemetry."
    _build_pick_areas(prefix)
    component_selector.clear()
    for component_name in ["Battery_Module", "Power_Controller", "Optical_Payload", "Navigation_Sensors", "Reaction_Wheel_Assembly", "Onboard_Computer", "Solar_Left_Deploy", "Solar_Right_Deploy", "Communications", "Structure", "GroundStation_AzimuthPivot", "GroundStation_ElevationPivot"]:
        if find_exact(asset, prefix + component_name) != null:
            component_selector.add_item(component_name)
            component_selector.set_item_metadata(component_selector.item_count - 1, component_name)
    selected_component = "GroundStation_Root" if current_scene == 4 else "Optical_Payload"
    _build_beacon(prefix)
    _build_propulsion_arrow(prefix)
    _update_selection()
    if index == 3:
        var overlay := find_exact(asset, "ENV_OrbitalOverlay") as Node3D
        if overlay != null:
            overlay.visible = false
        orbital_trace = MeshInstance3D.new()
        orbital_trace.name = "ConfirmedOrbitalTrace"
        asset.add_child(orbital_trace)
    _apply_backend_state()
    _update_camera()

func _stop_imported_animations(node: Node) -> void:
    if node is AnimationPlayer:
        node.stop()
    for child in node.get_children():
        _stop_imported_animations(child)

static func find_exact(node: Node, wanted: String) -> Node:
    if str(node.name) == wanted:
        return node
    for child in node.get_children():
        var result := find_exact(child, wanted)
        if result != null:
            return result
    return null

static func measure_asset(node: Node3D) -> Dictionary:
    var meshes := 0
    var triangles := 0
    var initialized := false
    var bounds := AABB()
    var nodes: Array[Node] = [node]
    while not nodes.is_empty():
        var item: Node = nodes.pop_back()
        for child in item.get_children():
            nodes.append(child)
        if item is MeshInstance3D and item.mesh != null:
            meshes += 1
            var aabb: AABB = item.global_transform * item.get_aabb()
            bounds = bounds.merge(aabb) if initialized else aabb
            initialized = true
            for surface in range(item.mesh.get_surface_count()):
                var indices: int = item.mesh.surface_get_array_index_len(surface)
                triangles += int(indices / 3) if indices > 0 else int(item.mesh.surface_get_array_len(surface) / 3)
    return {"meshes": meshes, "triangles": triangles, "bounds": bounds}

func _apply_solar_angle(key: String, native_degrees: float) -> void:
    if not pivots.has(key):
        return
    var reference: Transform3D = rest_transforms[key]
    var pivot: Node3D = pivots[key]
    # glTF converts native +Y to Godot local -Z; origin and scale retained.
    var axis := Vector3.RIGHT if key.ends_with("Track") else Vector3(0, 0, -1)
    pivot.transform = Transform3D(reference.basis * Basis(axis, deg_to_rad(native_degrees)), reference.origin)

func run_solar_sequence() -> void:
    # Retained entry point for older integrations; mechanisms remain backend-owned.
    _apply_backend_state()

func _ground_pose(_value: float) -> void:
    if azimuth_slider == null or elevation_slider == null:
        return
    azimuth_label.text = "Azimuth  %d°" % int(azimuth_slider.value)
    elevation_label.text = "Elevation  %d°" % int(elevation_slider.value)
    if pivots.has("GroundStation_AzimuthPivot"):
        var reference: Transform3D = rest_transforms["GroundStation_AzimuthPivot"]
        pivots["GroundStation_AzimuthPivot"].transform = Transform3D(reference.basis * Basis(Vector3.UP, deg_to_rad(azimuth_slider.value)), reference.origin)
    if pivots.has("GroundStation_ElevationPivot"):
        var reference: Transform3D = rest_transforms["GroundStation_ElevationPivot"]
        pivots["GroundStation_ElevationPivot"].transform = Transform3D(reference.basis * Basis(Vector3.RIGHT, deg_to_rad(elevation_slider.value - 20.0)), reference.origin)

func reset_view() -> void:
    distance = initial_distance
    yaw = 0.65
    pitch = 0.13 if current_scene == 3 else 0.30
    _update_camera()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        pending_pick = event.position
    if event is InputEventMouseButton:
        var inside := view_container.get_global_rect().has_point(event.position)
        if event.button_index == MOUSE_BUTTON_RIGHT:
            dragging = event.pressed and inside
        if event.pressed and inside:
            if event.button_index == MOUSE_BUTTON_WHEEL_UP:
                distance = maxf(initial_distance * 0.12, distance * 0.88)
                _update_camera()
            elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                distance = minf(initial_distance * 5.0, distance * 1.12)
                _update_camera()
    elif event is InputEventMouseMotion and dragging:
        yaw -= event.relative.x * 0.006
        pitch = clampf(pitch + event.relative.y * 0.006, -1.30, 1.30)
        _update_camera()

func _update_camera() -> void:
    if camera == null:
        return
    camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
    camera.look_at(target, Vector3.UP)

func _connection_state(connected: bool) -> void:
    if not connected:
        status_label.text = "Service disconnected. Last confirmed state."

func _backend_state(snapshot: Dictionary, backend_status: Dictionary) -> void:
    if snapshot.is_empty():
        status_label.text = "Service connected. Start an observation on the Mission page."
        return
    if snapshot.get("schema") != "slx.orbitlab.snapshot/1":
        return
    if snapshot.get("run_id") != backend_snapshot.get("run_id") or float(snapshot.get("time_s", 0)) < float(backend_snapshot.get("time_s", 0)):
        trace_points.clear()
    backend_snapshot = snapshot
    _apply_backend_state()
    status_label.text = "%s · %.1f s\n%s\nBattery %.1f%% · %s" % [
        backend_status.get("mode", "LIVE"), float(snapshot.get("time_s", 0)),
        snapshot.get("phase", ""), float(snapshot.get("soc_percent", 0)),
        "sensor available" if snapshot.get("attitude_valid", false) else "sensor unavailable"]
    _update_selection()

func _apply_backend_state() -> void:
    if backend_snapshot.is_empty() or asset == null:
        return
    applied_frames += 1
    var visual: Dictionary = backend_snapshot.get("visual", {})
    var angles: Dictionary = visual.get("pivots_native_deg", {})
    if current_scene != 2:
        for key in ["Solar_Left_Deploy", "Solar_Right_Deploy", "Solar_Left_Fold", "Solar_Right_Fold", "Solar_Left_Track", "Solar_Right_Track"]:
            if angles.has(key):
                _apply_solar_angle(key, float(angles[key]))
    if current_scene == 4:
        azimuth_slider.set_value_no_signal(float(angles.get("GroundStation_AzimuthPivot", 0)))
        elevation_slider.set_value_no_signal(float(angles.get("GroundStation_ElevationPivot", 20)))
        _ground_pose(0)
        _ground_signal()
    if spacecraft_display == null:
        return
    var values: Array = visual.get("quaternion_body_to_eci", [1, 0, 0, 0])
    var native_attitude := Basis(Quaternion(float(values[1]), float(values[2]), float(values[3]), float(values[0])))
    var display_basis := NATIVE_TO_GLTF * native_attitude * NATIVE_TO_GLTF.inverse()
    var display_position := Vector3.ZERO
    var display_scale := 1.0
    if current_scene == 3:
        # The delivered globe's geography is R_x(-20 deg) * R_z(-72 deg).
        # Render in an Earth-fixed presentation frame; the physics remains ECI metres.
        var geography := Basis(Vector3.RIGHT, deg_to_rad(-20)) * Basis(Vector3(0, 0, 1), deg_to_rad(-72))
        var earth_fixed := Basis(Vector3(0, 0, 1), -float(visual.get("earth_angle_rad", 0)))
        display_basis = NATIVE_TO_GLTF * geography * earth_fixed * native_attitude * NATIVE_TO_GLTF.inverse()
        var position: Array = visual.get("orbit_position_ecef_display", [0, 0, 8.7])
        display_position = Vector3(0, -10.3, 0) + NATIVE_TO_GLTF * geography * Vector3(float(position[0]), float(position[1]), float(position[2]))
        display_scale = 0.16
        _orbital_overlays(geography, display_position)
        var past: Array = backend_snapshot.get("trail_ecef_display", [])
        if past.is_empty():
            for sample in backend_snapshot.get("presentation_history", []):
                if sample.has("orbit_position_ecef_display"):
                    past.append(sample.orbit_position_ecef_display)
        if not past.is_empty():
            trace_points.clear()
            for point in past:
                trace_points.append(Vector3(0, -10.3, 0) + NATIVE_TO_GLTF * geography * Vector3(float(point[0]), float(point[1]), float(point[2])))
        if trace_points.is_empty() or trace_points[-1].distance_to(display_position) > 0.0001:
            trace_points.append(display_position)
            if trace_points.size() > 720:
                trace_points.pop_front()
        _update_trace()
    spacecraft_display.transform = Transform3D(display_basis.scaled(Vector3.ONE * display_scale), display_position)

func _line_overlay(points: Array, color: Color) -> void:
    if mission_overlay == null:
        mission_overlay = MeshInstance3D.new()
        mission_overlay.name = "SLX_MissionLink"
        stage.add_child(mission_overlay)
    mission_overlay.visible = points.size() >= 2
    if points.size() < 2:
        return
    var mesh := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
    for point in points:
        mesh.surface_add_vertex(point)
    mesh.surface_end()
    mission_overlay.mesh = mesh

func _orbital_overlays(geography: Basis, spacecraft_position: Vector3) -> void:
    var targets: Array = backend_snapshot.get("targets", [])
    if targets.is_empty():
        _line_overlay([], Color.WHITE)
        return
    var active: Dictionary = targets[0]
    for candidate in targets:
        if int(candidate.id) == int(backend_snapshot.get("target_id", 0)):
            active = candidate
    var latitude := deg_to_rad(float(active.latitude_deg))
    var longitude := deg_to_rad(float(active.longitude_deg))
    var location := Vector3(0, -10.3, 0) + NATIVE_TO_GLTF * geography * Vector3(cos(latitude)*cos(longitude), cos(latitude)*sin(longitude), sin(latitude)) * 8.02
    if target_marker == null:
        target_marker = MeshInstance3D.new()
        target_marker.name = "SLX_EarthTarget"
        var sphere := SphereMesh.new()
        sphere.radius = 0.08
        sphere.height = 0.16
        target_marker.mesh = sphere
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color("ee574c")
        target_marker.material_override = material
        stage.add_child(target_marker)
    target_marker.visible = true
    target_marker.position = location
    if int(backend_snapshot.get("phase_id", 0)) in [4, 5] and int(backend_snapshot.get("vehicle", {}).get("maneuver_mode", 0)) == 0 and int(backend_snapshot.get("orbit", {}).get("burn_state", 0)) not in [1, 2, 5]:
        _line_overlay([spacecraft_position, location], Color("64d9c2"))
    elif bool(backend_snapshot.get("downlink", false)):
        var ground: Dictionary = backend_snapshot.get("ground_station", {})
        latitude = deg_to_rad(float(ground.get("latitude_deg", 0)))
        longitude = deg_to_rad(float(ground.get("longitude_deg", 0)))
        location = Vector3(0, -10.3, 0) + NATIVE_TO_GLTF * geography * Vector3(cos(latitude)*cos(longitude), cos(latitude)*sin(longitude), sin(latitude)) * 8.02
        _line_overlay([spacecraft_position, location], Color("ac8fff"))
    else:
        _line_overlay([], Color.WHITE)

func _ground_signal() -> void:
    if not bool(backend_snapshot.get("downlink", false)):
        _line_overlay([], Color.WHITE)
        return
    var elevation := float(backend_snapshot.get("ground_elevation_rad", 0))
    var azimuth := float(backend_snapshot.get("ground_azimuth_rad", 0))
    var pivot := find_exact(asset, "GroundStation_ElevationPivot") as Node3D
    if pivot != null:
        var direction := Vector3(cos(elevation)*sin(azimuth), sin(elevation), -cos(elevation)*cos(azimuth))
        _line_overlay([pivot.global_position, pivot.global_position + direction*5], Color("ac8fff"))

func _update_trace() -> void:
    if orbital_trace == null or trace_points.size() < 2:
        return
    var line := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color("64d9c2")
    line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
    for point in trace_points:
        line.surface_add_vertex(point)
    line.surface_end()
    orbital_trace.mesh = line

func _build_pick_areas(prefix: String) -> void:
    for name in ["Optical_Payload", "Navigation_Sensors", "Onboard_Computer", "Power_Controller", "Battery_Module", "Reaction_Wheel_Assembly", "Solar_Left_Deploy", "Solar_Right_Deploy", "Communications", "GroundStation_Root"]:
        var assembly := find_exact(asset, prefix + name) as Node3D
        if assembly == null:
            continue
        var nodes: Array[Node] = [assembly]
        var bounds := AABB()
        var initialized := false
        while not nodes.is_empty():
            var node: Node = nodes.pop_back()
            for child in node.get_children():
                nodes.append(child)
            if node is MeshInstance3D and node.mesh != null:
                var local_bounds: AABB = assembly.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
                bounds = bounds.merge(local_bounds) if initialized else local_bounds
                initialized = true
        if not initialized:
            continue
        var area := Area3D.new()
        area.name = "InspectionPickArea"
        area.set_meta("component", name)
        var shape := BoxShape3D.new()
        shape.size = Vector3(maxf(bounds.size.x, 0.04), maxf(bounds.size.y, 0.04), maxf(bounds.size.z, 0.04))
        var collision := CollisionShape3D.new()
        collision.shape = shape
        collision.position = bounds.position + bounds.size * 0.5
        area.add_child(collision)
        assembly.add_child(area)

func _pick_component(screen_position: Vector2) -> void:
    if not view_container.get_global_rect().has_point(screen_position):
        return
    var point := (screen_position - view_container.global_position) * Vector2(view.size) / view_container.size
    var origin := camera.project_ray_origin(point)
    var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * 500)
    query.collide_with_areas = true
    query.collide_with_bodies = false
    if camera == null or not camera.is_inside_tree() or camera.get_world_3d() == null:
        return
    var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
    if result.has("collider"):
        selected_component = str(result.collider.get_meta("component", ""))
        picked_component = selected_component
        pick_count += 1
        for index in range(component_selector.item_count):
            if str(component_selector.get_item_metadata(index)) == selected_component:
                component_selector.select(index)
        _update_selection()

func _update_selection() -> void:
    if selection_label == null or selected_component.is_empty():
        return
    var detail := "Mission component"
    if backend_snapshot.is_empty():
        detail = "Waiting for mission telemetry"
    elif selected_component == "Battery_Module" or selected_component == "Power_Controller":
        detail = "%.1f%% · %.0f J\nGeneration %.1f W / load %.1f W" % [float(backend_snapshot.get("soc_percent", 0)), float(backend_snapshot.get("energy_j", 0)), float(backend_snapshot.get("generation_w", 0)), float(backend_snapshot.get("consumed_w", 0))]
    elif selected_component == "Navigation_Sensors":
        detail = "Available" if backend_snapshot.get("attitude_valid", false) else "Unavailable · acquisition held"
    elif selected_component == "Optical_Payload":
        detail = "%s\nPointing error %.3f degrees" % [backend_snapshot.get("phase", ""), float(backend_snapshot.get("truth_pointing_error_deg", 0))]
    elif selected_component == "Reaction_Wheel_Assembly":
        detail = "Wheel speed [rad/s]\n%s" % str(backend_snapshot.get("wheel_speeds_radps", []))
    elif selected_component.begins_with("GroundStation_") or selected_component.begins_with("Solar_"):
        var angles: Dictionary = backend_snapshot.get("visual", {}).get("pivots_native_deg", {})
        detail = "Confirmed joint angle %.2f degrees" % float(angles.get(selected_component, 0))
    selection_label.text = selected_component + "\n" + detail
    _update_highlight()
    if isolated:
        _apply_isolation()
    if beacon != null:
        beacon.visible = bool(backend_snapshot.get("visual", {}).get("beacon_on", false)) and (not isolated or selected_component == "Communications")
    if thrust_arrow != null:
        thrust_arrow.visible = bool(backend_snapshot.get("visual", {}).get("propulsion_active", false)) and not isolated
    if ui_port > 0:
        presentation.put_packet(JSON.stringify({"component": selected_component}).to_utf8_buffer())

func _physics_process(_delta: float) -> void:
    if pending_pick.x >= 0:
        _pick_component(pending_pick)
        pending_pick = Vector2(-1, -1)

func _process(_delta: float) -> void:
    while presentation.get_available_packet_count() > 0:
        var bytes := presentation.get_packet()
        if presentation.get_packet_ip() != "127.0.0.1" or presentation.get_packet_port() != ui_port:
            continue
        var message = JSON.parse_string(bytes.get_string_from_utf8())
        if not message is Dictionary:
            continue
        match message.get("op", ""):
            "pick":
                pending_pick = view_container.get_global_rect().get_center()
            "select":
                var component := str(message.get("component", ""))
                if find_exact(asset, SCENES[current_scene].prefix + component) != null:
                    selected_component = component
                    _update_selection()
            "focus":
                focused = true
                var bounds := _component_bounds()
                target = bounds.get_center()
                distance = maxf(bounds.size.length() * 1.8, 0.15)
                _update_camera()
            "isolate":
                isolated = bool(message.get("enabled", false)) and current_scene in [1, 2]
                _apply_isolation()
            "reset":
                isolated = false
                focused = false
                _apply_isolation()
                reset_view()

func _component_bounds() -> AABB:
    var assembly := find_exact(asset, SCENES[current_scene].prefix + selected_component) as Node3D
    if assembly == null:
        return AABB(target - Vector3.ONE * 0.1, Vector3.ONE * 0.2)
    var bounds := AABB()
    var initialized := false
    var nodes: Array[Node] = [assembly]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        nodes.append_array(node.get_children())
        if node is MeshInstance3D and node.mesh != null and node != highlight and node != beacon:
            var box: AABB = node.global_transform * node.get_aabb()
            bounds = bounds.merge(box) if initialized else box
            initialized = true
    return bounds

func _update_highlight() -> void:
    if asset == null:
        return
    if highlight == null:
        highlight = MeshInstance3D.new()
        highlight.name = "SLX_ComponentSelection"
        stage.add_child(highlight)
    var box := _component_bounds()
    var geometry := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color("64d9c2")
    if selected_component == "Navigation_Sensors" and not backend_snapshot.get("attitude_valid", true):
        material.albedo_color = Color("ee574c")
    elif selected_component in ["Battery_Module", "Power_Controller"] and backend_snapshot.get("safety_active", false):
        material.albedo_color = Color("ee574c")
    elif selected_component == "Optical_Payload" and int(backend_snapshot.get("phase_id", 0)) == 5:
        material.albedo_color = Color("8fb4ff")
    geometry.surface_begin(Mesh.PRIMITIVE_LINES, material)
    for edge in [[0,1], [0,2], [0,4], [1,3], [1,5], [2,3], [2,6], [3,7], [4,5], [4,6], [5,7], [6,7]]:
        geometry.surface_add_vertex(box.get_endpoint(edge[0]))
        geometry.surface_add_vertex(box.get_endpoint(edge[1]))
    geometry.surface_end()
    highlight.mesh = geometry
    if focused:
        target = box.get_center()
        _update_camera()

func _apply_isolation() -> void:
    var assembly := find_exact(asset, SCENES[current_scene].prefix + selected_component)
    if assembly == null:
        return
    var nodes: Array[Node] = [asset]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        nodes.append_array(node.get_children())
        if node is MeshInstance3D and node != beacon:
            node.visible = not isolated or assembly == node or assembly.is_ancestor_of(node)
        if node is Area3D and node.has_meta("component"):
            node.collision_layer = 1 if not isolated or assembly.is_ancestor_of(node) else 0

func _build_beacon(prefix: String) -> void:
    var assembly := find_exact(asset, prefix + "Communications") as Node3D
    if assembly == null:
        return
    beacon = MeshInstance3D.new()
    beacon.name = "SLX_MissionBeacon"
    var sphere := SphereMesh.new()
    sphere.radius = 0.07
    sphere.height = 0.14
    beacon.mesh = sphere
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color("69e7c2")
    material.emission_enabled = true
    material.emission = Color("69e7c2")
    material.emission_energy_multiplier = 2
    beacon.material_override = material
    var bounds := AABB()
    var initialized := false
    var nodes: Array[Node] = [assembly]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        nodes.append_array(node.get_children())
        if node is MeshInstance3D and node.mesh != null:
            var local: AABB = assembly.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
            bounds = bounds.merge(local) if initialized else local
            initialized = true
    beacon.position = bounds.get_center() + Vector3(0, bounds.size.y * 0.5 + 0.08, 0)
    assembly.add_child(beacon)
    beacon.visible = false

func _build_propulsion_arrow(prefix: String) -> void:
    var spacecraft_root := find_exact(asset, prefix + "Spacecraft_Root") as Node3D
    if spacecraft_root == null:
        return
    thrust_arrow = MeshInstance3D.new()
    thrust_arrow.name = "SLX_ConfirmedThrustVector"
    var mesh := ImmediateMesh.new()
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color("ffc56c")
    material.no_depth_test = true
    var bounds := AABB()
    var initialized := false
    var structure := find_exact(asset, prefix + "Structure") as Node3D
    var nodes: Array[Node] = [structure if structure != null else spacecraft_root]
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        nodes.append_array(node.get_children())
        if node is MeshInstance3D and node.mesh != null:
            var local: AABB = spacecraft_root.global_transform.affine_inverse() * node.global_transform * node.get_aabb()
            bounds = bounds.merge(local) if initialized else local
            initialized = true
    var start := bounds.get_center() + Vector3(bounds.size.x * 0.5 + 0.08, 0, 0)
    var tip := start + Vector3(1.2, 0, 0)
    mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
    # Native body +X remains +X in glTF. This engineering arrow denotes measured force.
    for point in [start, tip, tip, tip + Vector3(-0.25, 0.18, 0), tip, tip + Vector3(-0.25, -0.18, 0)]:
        mesh.surface_add_vertex(point)
    mesh.surface_end()
    thrust_arrow.mesh = mesh
    spacecraft_root.add_child(thrust_arrow)
    thrust_arrow.visible = false
