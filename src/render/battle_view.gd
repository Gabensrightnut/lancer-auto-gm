class_name BattleView
extends Node3D
## The 3D battle: terrain, units, effects, overlays and cameras. Fed by a seat's view
## (ViewFilter output) and animated by events through EventPlayer. Never touches GameState.

var map: BattleMap
var content: ContentDB
var terrain: TerrainRenderer
var units: Dictionary = {}  # unit id -> MechView
var fx_root: Node3D
var tactical: TacticalCamera
var overlays: TurnOverlays
var cockpit_cam: Camera3D
## "tactical" or "cockpit". Only changes the view, never what's known or legal.
var camera_mode := "tactical"
var cockpit_unit := ""
var cockpit_target := ""
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var _units_root: Node3D


func _init() -> void:
	_build_environment()
	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	_units_root = Node3D.new()
	_units_root.name = "Units"
	add_child(_units_root)
	overlays = TurnOverlays.new(self)
	add_child(overlays)
	tactical = TacticalCamera.new()
	tactical.name = "TacticalCamera"
	add_child(tactical)
	cockpit_cam = Camera3D.new()
	cockpit_cam.name = "CockpitCamera"
	cockpit_cam.fov = 75.0
	cockpit_cam.near = 0.02
	add_child(cockpit_cam)


## Builds the board and units from a seat's view (ViewFilter.view_for output).
func load_view(view: Dictionary) -> void:
	set_map(BattleMap.from_dict(view.get("map", {})))
	clear_units()
	for id: String in view.get("units", {}):
		var u: Dictionary = view["units"][id]
		if u.get("hidden", false):
			continue  # Hidden enemies: only what the rules reveal (last known position later).
		add_unit(u)


func clear_units() -> void:
	for c in _units_root.get_children():
		c.queue_free()
	units.clear()


func add_unit(u: Dictionary) -> MechView:
	var mv := MechView.new()
	_units_root.add_child(mv)
	units[String(u.get("id", ""))] = mv
	mv.setup(u, self)
	return mv


## Switches between the tactical camera and the cockpit of `unit_id`.
func set_camera_mode(mode: String, unit_id: String = "", target_id: String = "") -> void:
	if unit_id != "":
		cockpit_unit = unit_id
	if target_id != "":
		cockpit_target = target_id
	# Show the previous cockpit unit's head again.
	for mv: MechView in units.values():
		if mv.model and mv.model.head:
			mv.model.head.visible = true
	camera_mode = mode
	if mode == "cockpit" and units.has(cockpit_unit):
		var mv: MechView = units[cockpit_unit]
		mv.model.head.visible = false
		cockpit_cam.current = true
		_update_cockpit(true)
	else:
		camera_mode = "tactical"
		tactical.camera.current = true


func _process(delta: float) -> void:
	if camera_mode == "cockpit":
		_update_cockpit(false, delta)


func _update_cockpit(snap: bool, delta: float = 0.0) -> void:
	var mv: MechView = units.get(cockpit_unit)
	if mv == null:
		return
	var eye := mv.model.eye.global_position if mv.model.eye else mv.body_center()
	var fwd := -mv.model.global_transform.basis.z
	var look := eye + fwd * 5.0
	var tgt: MechView = units.get(cockpit_target)
	if tgt:
		look = tgt.body_center()
	var xf := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye + fwd * 0.02)
	if snap:
		cockpit_cam.global_transform = xf
	else:
		cockpit_cam.global_transform = cockpit_cam.global_transform.interpolate_with(xf, 1.0 - exp(-10.0 * delta))


func set_map(battle_map: BattleMap, kit: String = "urban_ruins") -> void:
	map = battle_map
	terrain.build(map, kit)
	apply_biome(kit)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for cell in map.cells():
		var p := map.grid.to_world(cell)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	tactical.look_at_point((lo + hi) * 0.5 + Vector3(0, 1, 0), maxf(hi.x - lo.x, hi.z - lo.z) * 0.95)
	tactical.snap()


## Lighting, sky and fog per biome.
func apply_biome(kit: String) -> void:
	var env := world_env.environment
	var sm := env.sky.sky_material as ProceduralSkyMaterial
	match kit:
		"grassy_hills":
			sm.sky_top_color = Color(0.22, 0.42, 0.75)
			sm.sky_horizon_color = Color(0.72, 0.8, 0.88)
			sm.ground_horizon_color = Color(0.55, 0.62, 0.55)
			sm.ground_bottom_color = Color(0.15, 0.2, 0.12)
			env.fog_light_color = Color(0.7, 0.78, 0.86)
			env.fog_density = 0.0045
			env.ambient_light_energy = 0.55
			env.adjustment_saturation = 1.0
			sun.light_color = Color(1.0, 0.93, 0.8)
			sun.light_energy = 2.3
			sun.rotation_degrees = Vector3(-38, -55, 0)
		_:
			sm.sky_top_color = Color(0.28, 0.37, 0.5)
			sm.sky_horizon_color = Color(0.78, 0.66, 0.55)
			sm.ground_horizon_color = Color(0.5, 0.44, 0.4)
			sm.ground_bottom_color = Color(0.12, 0.11, 0.1)
			env.fog_light_color = Color(0.62, 0.58, 0.55)
			env.fog_density = 0.006
			env.ambient_light_energy = 0.4
			env.adjustment_saturation = 1.05
			sun.light_color = Color(1.0, 0.88, 0.74)
			sun.light_energy = 2.2
			sun.rotation_degrees = Vector3(-42, -38, 0)


## World position of a cell's floor at a level.
func cell_pos(cell: Vector2i, level: int) -> Vector3:
	return map.grid.to_world(cell, level)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.37, 0.5)
	sm.sky_horizon_color = Color(0.78, 0.66, 0.55)
	sm.ground_horizon_color = Color(0.5, 0.44, 0.4)
	sm.ground_bottom_color = Color(0.12, 0.11, 0.1)
	sm.sun_angle_max = 20.0
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.5
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.58, 0.55)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.05
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.28
	fill.rotation_degrees = Vector3(-30, 140, 0)
	add_child(fill)
