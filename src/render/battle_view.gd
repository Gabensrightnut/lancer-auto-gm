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
## Where the cockpit looks when the player aims with the mouse (a direction); zero = at
## cockpit_target, or straight ahead.
var cockpit_aim := Vector3.ZERO
var sun: DirectionalLight3D
var world_env: WorldEnvironment
## Keeps nameplates apart and out from under the HUD (set active_unit / hover_unit on it).
var labels: LabelDeclutter
## Smoke, sealant, caltrops, bunkers... left on the field (state.zones).
var zones: ZoneLayer
## 0 in daylight, up to 1 on night maps: how much mechs are lit up to stay readable.
var mech_lift := 0.0
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
	labels = LabelDeclutter.new(self)
	add_child(labels)
	zones = ZoneLayer.new(self)
	add_child(zones)
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
	if view.get("mission") is Dictionary:
		show_mission(view["mission"], String(view.get("phase", GameState.PHASE_SETUP)))
	clear_units()
	for pass_deployables: bool in [false, true]:  # owners first: deployables take their colors
		for id: String in view.get("units", {}):
			var u: Dictionary = view["units"][id]
			if u.get("hidden", false) or VisibleParts.is_deployable(u) != pass_deployables:
				continue  # Hidden enemies: only what the rules reveal (last known position later).
			add_unit(u)
	sync_parts(view.get("units", {}))


func clear_units() -> void:
	for c in _units_root.get_children():
		c.queue_free()
	units.clear()


func add_unit(u: Dictionary) -> MechView:
	var mv := MechView.new()
	_units_root.add_child(mv)
	units[String(u.get("id", ""))] = mv
	mv.setup(u, self)
	mv.model.set_fx("lift", mech_lift)
	return mv


## Makes the board match GameState for parts that leave a mech (data/game/visible_parts.json):
## docked drones that are out leave gaps, destroyed weapons are gone from the body, thrown
## weapons lie where the state says, and units the state no longer has (a recalled drone) go.
## Call after every state update with the view's units (ViewFilter.view_for()["units"]).
var _thrown_props: Dictionary = {}


func sync_parts(view_units: Dictionary) -> void:
	for id: String in units.keys():
		if not view_units.has(id):
			var gone: MechView = units[id]
			units.erase(id)
			if is_instance_valid(gone):
				gone.queue_free()
	var lying := {}
	var latched := {}
	for id: String in units:
		var mv: MechView = units[id]
		var u: Dictionary = view_units.get(id, {})
		for k: String in ["counters", "loadout", "mounts_lost"]:
			if u.has(k):
				mv.unit[k] = u[k]
		if mv.model == null:
			continue
		var thrown := VisibleParts.thrown_weapons(mv.unit)
		mv.model.set_weapons_gone(VisibleParts.destroyed_weapons(mv.unit) + thrown.keys())
		var out := VisibleParts.out_counts(view_units, id)
		var counters: Dictionary = mv.unit.get("counters", {})
		var att := VisibleParts.frame_attach(mv.model.frame_id)
		var host := String(counters.get(att.get("counter", "-"), "")) if not att.is_empty() else ""
		if host != "" and units.has(host):
			out[att["name"]] = 1
			latched[id] = true
			_latch(id, att, units[host])
		mv.model.set_docks_out(out)
		var swarm_on := VisibleParts.core_active_look(mv.model.frame_id) == "swarm" and bool(counters.get("core_active", false))
		var swarm: Node3D = mv.get_node_or_null("Hellswarm")
		if swarm_on and swarm == null:
			mv.add_child(_swarm(mv.model))
		elif not swarm_on and swarm:
			swarm.queue_free()
		for wid: String in thrown:
			var key := "%s:%s" % [id, wid]
			lying[key] = true
			if not _thrown_props.has(key) and content:
				_thrown_props[key] = _lay_weapon(content.weapon(wid), thrown[wid])
	for key: String in _thrown_props.keys():
		if not lying.has(key):
			var n: Node3D = _thrown_props[key]
			_thrown_props.erase(key)
			if is_instance_valid(n):
				n.queue_free()
	for owner_id: String in _latched.keys():
		if not latched.has(owner_id):
			var n: Node3D = _latched[owner_id]
			_latched.erase(owner_id)
			if is_instance_valid(n):
				n.queue_free()


var _latched: Dictionary = {}


## A frame's part clamped onto another unit (Lancaster's Latch Drone on an ally's back).
func _latch(owner_id: String, att: Dictionary, host: MechView) -> void:
	var n: Node3D = _latched.get(owner_id)
	if n and is_instance_valid(n) and n.get_parent() == host:
		return
	if n and is_instance_valid(n):
		n.queue_free()
	n = Node3D.new()
	n.name = "Latched_" + owner_id
	host.add_child(n)
	n.position = Vector3(0, host.model.height * 0.72, host.model.height * 0.16)
	var owner_mv: MechView = units.get(owner_id)
	DeployableBuilder.shape(n, att["spec"], MechStyles.palette(owner_mv.model.manufacturer) if owner_mv and owner_mv.model else {}, 0.5)
	_latched[owner_id] = n


## The Balor's Hellswarm: a cloak of tiny drones orbiting the body.
func _swarm(m: MechModel) -> Node3D:
	var root := Node3D.new()
	root.name = "Hellswarm"
	var mat := MeshKit.mech_material(Color(0.1, 0.1, 0.11), 0.6, 0.4, Color.BLACK, false)
	for ring in range(3):
		var r := Node3D.new()
		r.position.y = m.height * (0.3 + ring * 0.22)
		root.add_child(r)
		for i in range(14):
			var a := i * TAU / 14.0 + ring
			var rad := m.height * (0.42 + 0.06 * MeshKit.hash01("hs", i + ring * 20))
			var p := MeshKit.part(r, MeshKit.sphere(0.018, 4), mat, Vector3(cos(a) * rad, (MeshKit.hash01("hs", i + 50) - 0.5) * 0.12, sin(a) * rad))
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.spinners.append({"node": r, "axis": Vector3.UP, "speed": 1.6 * (1.0 if ring % 2 == 0 else -1.0)})
	return root


## A thrown weapon at rest on the ground (tags: Thrown) at [x, y, level].
func _lay_weapon(w: Dictionary, at: Array) -> Node3D:
	var model := WeaponBuilder.build(w)
	fx_root.add_child(model)
	var c := Vector2i(int(at[0]), int(at[1]))
	model.position = map.grid.to_world(c, int(at[2]) if at.size() > 2 else map.ground_height(c)) + Vector3.UP * 0.04 if map else Vector3.ZERO
	model.rotation_degrees = Vector3(0, MeshKit.hash01(str(at), 1) * 360.0, 90)
	return model


## Switches between the tactical camera and the cockpit of `unit_id`. First person shows what
## the pilot would see (data/game/visible_parts.json "first_person"): a cockpit around the view
## for most frames; for drone-bodied frames (the Hydra) no cockpit, just your own remaining
## body (gaps where drones are out) and the drones you can see out in the world.
func set_camera_mode(mode: String, unit_id: String = "", target_id: String = "") -> void:
	if unit_id != "":
		cockpit_unit = unit_id
	if target_id != "":
		cockpit_target = target_id
	# Show the previous cockpit unit's head again.
	for mv: MechView in units.values():
		if mv.model and mv.model.head:
			mv.model.head.visible = true
	if _shell:
		_shell.queue_free()
		_shell = null
	camera_mode = mode
	cockpit_aim = Vector3.ZERO
	if mode == "cockpit" and units.has(cockpit_unit):
		var mv: MechView = units[cockpit_unit]
		if mv.model.head:
			mv.model.head.visible = false
		if first_person_style(mv) == "cockpit":
			_shell = CockpitShell.build(MechStyles.palette(mv.model.manufacturer))
			cockpit_cam.add_child(_shell)
		cockpit_cam.current = true
		_update_cockpit(true)
	else:
		camera_mode = "tactical"
		tactical.camera.current = true


var _shell: Node3D


## "cockpit" or "body" for a unit's first-person view (pilots on foot see from their eyes).
func first_person_style(mv: MechView) -> String:
	if mv == null or mv.model == null or String(mv.unit.get("kind", "")) == "pilot" or VisibleParts.is_deployable(mv.unit):
		return "eyes"
	return VisibleParts.first_person(mv.model.frame_id)


func _process(delta: float) -> void:
	if camera_mode == "cockpit":
		_update_cockpit(false, delta)
	elif sun:
		# Shadows reach as far as the zoomed-out view does.
		sun.directional_shadow_max_distance = clampf(tactical.distance * 2.4, 60.0, 200.0)


func _update_cockpit(snap: bool, delta: float = 0.0) -> void:
	var mv: MechView = units.get(cockpit_unit)
	if mv == null:
		return
	var eye := mv.model.eye.global_position if mv.model.eye else mv.body_center()
	var fwd := -mv.model.global_transform.basis.z
	if first_person_style(mv) == "body":
		# No cockpit: the view rides just above and behind the sensor, so you see what's left
		# of your own body (and its gaps) below you.
		eye += Vector3.UP * mv.model.height * 0.14 - fwd * mv.model.height * 0.22
	var look := eye + fwd * 5.0 - Vector3.UP * (mv.model.height * 0.35 if first_person_style(mv) == "body" else 0.0)
	var tgt: MechView = units.get(cockpit_target)
	if cockpit_aim != Vector3.ZERO:
		look = eye + cockpit_aim * 5.0
	elif tgt:
		look = tgt.body_center()
	var xf := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye + fwd * 0.02)
	if snap:
		cockpit_cam.global_transform = xf
	else:
		cockpit_cam.global_transform = cockpit_cam.global_transform.interpolate_with(xf, 1.0 - exp(-10.0 * delta))


## The board keeps its own copy of the map, so a later copy of the rules' map can be
## compared with it (refresh_map) and destroyed terrain collapses on screen.
func set_map(battle_map: BattleMap, kit: String = "urban_ruins") -> void:
	map = BattleMap.from_dict(battle_map.to_dict())
	terrain.build(map, kit)
	apply_biome(kit)
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for cell in map.cells():
		var p := map.grid.to_world(cell)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	# Big boards (up to ~60 spaces a side): zooming out must still fit the whole board.
	tactical.max_distance = maxf(40.0, maxf(hi.x - lo.x, hi.z - lo.z) * 1.35)
	tactical.look_at_point((lo + hi) * 0.5 + Vector3(0, 1, 0), maxf(hi.x - lo.x, hi.z - lo.z) * 0.95)
	tactical.snap()


## The sitrep's objectives as this seat may see them: {"zones": {name: [[x, y]]},
## "deployment": {side: [[x, y]]}} (Mission.zones / Mission.deployment, from the seat's view,
## never the host's full mission). Deployment areas show only during setup. Zone names that
## mark a secret ("_" prefix, "true"/"secret" in the name: Recon's True Control Zone) are
## dropped as a safeguard; the view filter is the real gate.
var mission_view: Dictionary = {}
var phase := GameState.PHASE_SETUP


func show_mission(m: Dictionary, battle_phase: String = GameState.PHASE_SETUP) -> void:
	mission_view = m.duplicate(true)
	phase = battle_phase
	var zones := {}
	var src: Dictionary = m.get("zones", {}) if m.get("zones") is Dictionary else {}
	for zname: String in src:
		var low := zname.to_lower()
		if zname.begins_with("_") or "true" in low or "secret" in low:
			continue
		zones[zname] = src[zname]
	var dep: Dictionary = m.get("deployment", {}) if m.get("deployment") is Dictionary else {}
	terrain.show_objectives(zones, dep, phase == GameState.PHASE_SETUP)


## Combat started (or anything else changing the phase): deployment tints go away.
func set_phase(battle_phase: String) -> void:
	if battle_phase == phase:
		return
	phase = battle_phase
	if not mission_view.is_empty():
		show_mission(mission_view, phase)


## Brings the board up to date with the rules' current map: destroyed terrain collapses
## (TerrainRenderer.sync_map), anything else changed is rebuilt. Does nothing if nothing
## changed. Returns the cells that broke.
func refresh_map(current: BattleMap) -> Array:
	if current == null or map == null:
		return []
	var d := current.to_dict()
	if d == map.to_dict():
		return []
	map = BattleMap.from_dict(d)
	return terrain.sync_map(BattleMap.from_dict(d))


## Lighting, sky and fog for the board's world style (src/render/world/atmosphere.gd).
func apply_biome(_kit: String = "") -> void:
	terrain.apply_environment(world_env.environment, sun, get_node_or_null("Fill") as DirectionalLight3D)
	var env := world_env.environment
	var light := sun.light_energy * sun.light_color.get_luminance() + env.ambient_light_energy * env.ambient_light_color.get_luminance() * 1.5
	mech_lift = clampf((1.9 - light) / 1.3, 0.0, 1.0)
	for mv: MechView in units.values():
		mv.model.set_fx("lift", mech_lift)


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
