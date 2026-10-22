class_name HubScene
extends Node3D
## A hub the squad walks around as pilots, in real time (DESIGN.md "Scenes, not just
## fights"): a town, base or station built from HubLayout, the hub's people standing by
## their buildings, the squad's mechs parked on the gantries. WASD or click to walk, Q/E to
## turn the camera, F (or click a person) to talk, Tab for downtime actions, J for the job
## board. Conversations, checks and downtime all go through StoryEngine.
##
## Multiplayer: each seat walks its own pilot; remote positions come in through
## set_avatar_position() (the session layer sends them; they're cosmetic, not game state).

signal story_events(events: Array)
## A scene started a fight or the squad took a job: build the mission (CampaignLoop).
signal mission_requested(hook: Dictionary)

const WALK_SPEED := 4.2
const TALK_RANGE := 2.6
const CAM_DIST := 14.0
const CAM_PITCH := deg_to_rad(40.0)
const TALK_PITCH := deg_to_rad(24.0)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var db: ContentDB
var local_seat := "p1"

var avatars: Dictionary = {}  # seat -> PilotFigure
var npc_nodes: Dictionary = {}  # npc id -> PilotFigure
var _target: Variant = null  # Vector3 click-to-move goal
var _yaw := 0.6
var _cam: Camera3D
var _world: Node3D
var _blockers: Array = []  # [{xf: Transform3D (inverse), half: Vector2}]
var _near_npc := ""
var _buildings: Array = []  # [{"root": Node3D, "radius": float}] faded when they hide your pilot

var ui: CanvasLayer
var dialogue: DialogueView
var popup: StoryCheckPopup
var downtime_panel: DowntimePanel
var downtime_screen: DowntimeScreen
var hud: HubHud
var level_panel: LevelUpPanel
var gear_panel: PilotGearPanel
var tutorial_panel: TutorialPanel


func setup(e: StoryEngine, s: StoryState, c: Campaign, content: ContentDB, seat: String = "p1") -> void:
	engine = e
	story = s
	campaign = c
	db = content
	local_seat = seat
	_build_ui()
	rebuild()


## Builds the 3D town from story.hub.
func rebuild() -> void:
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)
	avatars.clear()
	npc_nodes.clear()
	_blockers.clear()
	_buildings.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.hub.get("seed", 0), "hub_props"])
	_environment()
	_ground(rng)
	for spot: Dictionary in story.hub.get("spots", []):
		_building(spot, rng)
	_props(rng)
	_place_npcs()
	_place_squad()
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 50
		add_child(_cam)
	_update_camera(1.0)
	hud.refresh()


# --- World -------------------------------------------------------------------------------

func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.5, 0.68)
	mat.sky_horizon_color = Color(0.86, 0.74, 0.6)
	mat.ground_bottom_color = Color(0.3, 0.26, 0.22)
	mat.ground_horizon_color = Color(0.78, 0.66, 0.54)
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.8, 0.7, 0.6)
	e.fog_density = 0.004
	e.ssao_enabled = true
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	_world.add_child(sun)


func _ground(rng: RandomNumberGenerator) -> void:
	var kind := str(story.hub.get("kind", "town"))
	var dirt := Color(0.56, 0.47, 0.36) if kind != "station" else Color(0.32, 0.34, 0.37)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	pm.subdivide_width = 1
	ground.mesh = pm
	ground.material_override = MeshKit.paint(dirt, 0.0, 0.95, 0.0)
	_world.add_child(ground)
	# Plaza paving and roads out to each building.
	var pave := MeshKit.paint(dirt.lightened(0.18) if kind != "station" else Color(0.42, 0.44, 0.47), 0.05, 0.9, 0.25)
	MeshKit.part(_world, MeshKit.cylinder(8.5, 0.06, 28), pave, Vector3(0, 0.03, 0))
	for spot: Dictionary in story.hub.get("spots", []):
		if str(spot["kind"]) == "plaza":
			continue
		var to := Vector3(float(spot["door"][0]), 0, float(spot["door"][1]))
		var len := to.length()
		var road := MeshKit.part(_world, MeshKit.chamfer_box(Vector3(2.6, 0.05, len), 0.01), pave, to * 0.5 + Vector3(0, 0.025, 0))
		road.rotation.y = atan2(to.x, to.z)
	# Scrub and rocks out past the buildings (towns), deck plates (stations).
	for i in range(70):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(26.0, 60.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if kind == "station":
			MeshKit.part(_world, MeshKit.chamfer_box(Vector3(rng.randf_range(2, 5), rng.randf_range(0.5, 6), rng.randf_range(2, 5)), 0.05), MeshKit.paint(Color(0.3, 0.32, 0.36), 0.6, 0.5, 0.4), p + Vector3(0, 0.5, 0))
		elif rng.randf() < 0.6:
			MeshKit.part(_world, MeshKit.sphere(rng.randf_range(0.4, 1.4), 8), MeshKit.paint(Color(0.45, 0.4, 0.33).darkened(rng.randf_range(0, 0.2)), 0.0, 0.95, 0.0), p, Vector3(0, rng.randf_range(0, 90), 0), Vector3(1.2, 0.6, 1.0))
		else:
			MeshKit.part(_world, MeshKit.cylinder(0.5, 0.8, 6, 0.1), MeshKit.paint(Color(0.42, 0.48, 0.3), 0.0, 0.9, 0.0), p + Vector3(0, 0.4, 0))
	# A hill line on the horizon.
	for i in range(14):
		var a := TAU * i / 14.0 + rng.randf_range(-0.1, 0.1)
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(70, 78)
		MeshKit.part(_world, MeshKit.sphere(rng.randf_range(10, 18), 10), MeshKit.paint(dirt.darkened(0.15), 0.0, 1.0, 0.0), p, Vector3.ZERO, Vector3(1.6, rng.randf_range(0.35, 0.6), 1.2))


func _building(spot: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind := str(spot["kind"])
	var pos := Vector3(float(spot["pos"][0]), 0, float(spot["pos"][1]))
	var sz: Array = spot["size"]
	var w := float(sz[0])
	var d := float(sz[1])
	var h := float(sz[2])
	var col := Color.html(str(spot["color"]))
	var root := Node3D.new()
	root.position = pos
	# Front (+Z local) faces the plaza.
	root.rotation.y = atan2(-pos.x, -pos.z) if pos.length() > 0.1 else 0.0
	_world.add_child(root)
	var label_h := 1.0
	if kind == "landing":
		_landing(root, w, d)
		label_h = 0.5
	elif kind != "plaza":
		var wall := MeshKit.paint(col, 0.15, 0.8, 0.35)
		var roof := MeshKit.paint(col.darkened(0.35), 0.3, 0.7, 0.5)
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, h, d), 0.12), wall, Vector3(0, h / 2.0, 0))
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(w + 0.6, 0.35, d + 0.6), 0.06), roof, Vector3(0, h + 0.17, 0))
		# Door, awning and lit windows on the plaza side.
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.6, 2.4, 0.12), 0.02), MeshKit.paint(Color(0.12, 0.1, 0.09), 0.2, 0.6, 0.0), Vector3(0, 1.2, d / 2.0 + 0.02))
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(3.2, 0.12, 1.4), 0.02), MeshKit.paint(_accent_for(kind), 0.1, 0.7, 0.0), Vector3(0, 2.75, d / 2.0 + 0.6))
		var glow := MeshKit.paint(Color(1.0, 0.78, 0.45), 0.0, 0.4, 0.0, Color(1.0, 0.7, 0.35) * 1.6)
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.0, 0.7, 0.08), 0.01), glow, Vector3(sx * w * 0.3, 1.8, d / 2.0 + 0.03))
		if kind == "workshop" or kind == "printer":
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.55, h * 0.6, 0.1), 0.02), MeshKit.paint(Color(0.3, 0.32, 0.34), 0.6, 0.5, 0.6), Vector3(w * 0.15, h * 0.3, d / 2.0 + 0.04))
			MeshKit.part(root, MeshKit.cylinder(0.5, h * 0.6), MeshKit.paint(Color(0.5, 0.5, 0.52), 0.7, 0.4, 0.0), Vector3(-w * 0.35, h + 0.6, -d * 0.2))
		if kind == "office":
			MeshKit.part(root, MeshKit.cylinder(0.05, 3.0), MeshKit.paint(Color(0.6, 0.6, 0.62), 0.8, 0.3, 0.0), Vector3(w * 0.4, h + 1.8, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.9, 0.55, 0.03), 0.005), MeshKit.paint(_accent_for(kind), 0.0, 0.8, 0.0), Vector3(w * 0.4 + 0.46, h + 2.9, 0))
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.4, d / 2.0 + 1.2)
		light.light_color = Color(1.0, 0.75, 0.45)
		light.omni_range = 6.0
		light.light_energy = 0.8
		root.add_child(light)
		_blockers.append({"inv": root.transform.affine_inverse(), "half": Vector2(w / 2.0 + 0.35, d / 2.0 + 0.35)})
		_buildings.append({"root": root, "radius": maxf(w, d) * 0.6, "faded": false})
		label_h = h + 1.4
	var sign := Label3D.new()
	sign.text = str(spot["name"]).to_upper()
	sign.font_size = 56
	sign.outline_size = 12
	sign.pixel_size = 0.0075
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(1.0, 0.88, 0.6) if kind != "plaza" else Color(0.85, 0.9, 1.0, 0.0)
	sign.position = Vector3(0, label_h, d / 2.0 if kind != "landing" else 0.0)
	sign.visibility_range_begin = 9.0  # signs right next to the camera would fill the screen
	if kind != "plaza":
		root.add_child(sign)


func _accent_for(kind: String) -> Color:
	return {"bar": Color(0.75, 0.25, 0.2), "office": Color(0.2, 0.45, 0.75), "market": Color(0.8, 0.6, 0.2),
		"workshop": Color(0.85, 0.55, 0.15), "printer": Color(0.3, 0.6, 0.55)}.get(kind, Color(0.5, 0.5, 0.5))


## Mech gantries with the squad's mechs parked in them.
func _landing(root: Node3D, w: float, d: float) -> void:
	var metal := MeshKit.paint(Color(0.38, 0.4, 0.43), 0.7, 0.45, 0.6)
	var hazard := MeshKit.paint(Color(0.85, 0.65, 0.15), 0.2, 0.6, 0.0)
	MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.2, d), 0.04), MeshKit.paint(Color(0.3, 0.31, 0.33), 0.5, 0.6, 0.5), Vector3(0, 0.1, 0))
	MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.03, 0.3), 0.005), hazard, Vector3(0, 0.22, d / 2.0 - 0.3))
	var squad := CampaignLoop.squad(campaign, story)
	var n := maxi(squad.size(), 2)
	for i in range(n):
		var x := lerpf(-w / 2.0 + 2.5, w / 2.0 - 2.5, float(i) / maxf(n - 1, 1))
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.35, 9.0, 0.35), 0.03), metal, Vector3(x + sx * 1.8, 4.5, -1.5))
		MeshKit.part(root, MeshKit.chamfer_box(Vector3(4.0, 0.35, 0.6), 0.03), metal, Vector3(x, 8.8, -1.5))
		if i < squad.size() and db != null:
			var mech: Dictionary = squad[i]["mech"]
			var frame := db.frame(str(mech.get("frame", Campaign.STARTER_FRAME)))
			if not frame.is_empty():
				var model := MechBuilder.build(frame, mech.get("loadout", {}), db)
				model.scale = Vector3.ONE * 4.2
				model.position = Vector3(x, 0.2, -1.2)
				model.rotation.y = PI
				root.add_child(model)
	_blockers.append({"inv": root.transform.affine_inverse() * Transform3D(Basis(), Vector3(0, 0, -1.5)), "half": Vector2(w / 2.0, 1.6)})


func _props(rng: RandomNumberGenerator) -> void:
	var crate := MeshKit.paint(Color(0.45, 0.38, 0.26), 0.05, 0.85, 0.4)
	var barrel := MeshKit.paint(Color(0.35, 0.45, 0.4), 0.5, 0.5, 0.0)
	for i in range(26):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(9.5, 24.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _blocked(Vector2(p.x, p.z)) or _near_door(Vector2(p.x, p.z)):
			continue
		if rng.randf() < 0.5:
			var s := rng.randf_range(0.6, 1.1)
			MeshKit.part(_world, MeshKit.chamfer_box(Vector3(s, s, s), 0.04), crate, p + Vector3(0, s / 2.0, 0), Vector3(0, rng.randf_range(0, 90), 0))
		else:
			MeshKit.part(_world, MeshKit.cylinder(0.32, 0.95), barrel, p + Vector3(0, 0.48, 0))
		_blockers.append({"inv": Transform3D(Basis(), p).affine_inverse(), "half": Vector2(0.55, 0.55)})
	# Lamp posts round the plaza, and a well in the middle.
	for i in range(6):
		var a := TAU * i / 6.0 + 0.3
		var p := Vector3(cos(a), 0, sin(a)) * 8.0
		MeshKit.part(_world, MeshKit.cylinder(0.07, 3.6), MeshKit.paint(Color(0.2, 0.2, 0.22), 0.8, 0.4, 0.0), p + Vector3(0, 1.8, 0))
		MeshKit.part(_world, MeshKit.sphere(0.18), MeshKit.paint(Color(1, 0.85, 0.6), 0.0, 0.3, 0.0, Color(1.0, 0.8, 0.5) * 2.0), p + Vector3(0, 3.7, 0))
	MeshKit.part(_world, MeshKit.cylinder(1.3, 0.8, 16), MeshKit.paint(Color(0.5, 0.48, 0.45), 0.1, 0.9, 0.4), Vector3(0, 0.4, 0))
	MeshKit.part(_world, MeshKit.cylinder(1.05, 0.05, 16), MeshKit.paint(Color(0.2, 0.35, 0.45), 0.6, 0.15, 0.0), Vector3(0, 0.78, 0))
	_blockers.append({"inv": Transform3D.IDENTITY, "half": Vector2(1.4, 1.4)})


func _near_door(p: Vector2) -> bool:
	for spot: Dictionary in story.hub.get("spots", []):
		var d := Vector2(float(spot["door"][0]), float(spot["door"][1]))
		if p.distance_to(d) < 4.0 or p.length() < 9.0 and p.normalized().dot(d.normalized()) > 0.97:
			return true
	return false


func _place_npcs() -> void:
	var per_spot := {}
	for id: String in story.hub.get("npcs", []):
		var npc: Dictionary = story.npcs[id]
		if bool(npc.get("dead", false)):
			continue
		var kind := str(npc.get("spot", "plaza"))
		var idx := int(per_spot.get(kind, 0))
		per_spot[kind] = idx + 1
		var p := HubLayout.npc_position(story.hub, kind, idx)
		var fig := PilotFigure.new().build(npc.get("look", {}), str(npc["name"]), str(npc["title"]))
		fig.position = Vector3(p.x, 0, p.y)
		fig.rotation.y = atan2(-p.x, -p.y) + PI  # face the plaza
		_world.add_child(fig)
		npc_nodes[id] = fig


func _place_squad() -> void:
	var seats := story.seats.keys()
	seats.sort()
	var i := 0
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		var p: Dictionary = campaign.pilots.get(pid, {})
		if p.is_empty() or not story.is_alive(pid):
			continue
		var fig := PilotFigure.new().build(Portrait.look_for_pilot(p), str(p.get("callsign", "")), "", true)
		fig.position = Vector3(-1.5 + i * 1.4, 0, 5.5 + (i % 2) * 0.8)
		_world.add_child(fig)
		avatars[s] = fig
		i += 1


# --- Moving and talking ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	if me == null:
		return
	var busy := dialogue.visible or downtime_screen.visible or hud.board_open() or level_panel.visible or gear_panel.visible
	var dir := Vector3.ZERO
	if not busy:
		var f := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var r := Vector3(cos(_yaw), 0, -sin(_yaw))
		if Input.is_action_pressed("cam_pan_up"):
			dir += f
		if Input.is_action_pressed("cam_pan_down"):
			dir -= f
		if Input.is_action_pressed("cam_pan_right"):
			dir += r
		if Input.is_action_pressed("cam_pan_left"):
			dir -= r
		if Input.is_action_pressed("cam_rotate_left"):
			_yaw += delta * 1.8
		if Input.is_action_pressed("cam_rotate_right"):
			_yaw -= delta * 1.8
	if dir != Vector3.ZERO:
		_target = null
	elif _target is Vector3 and not busy:
		var to: Vector3 = (_target as Vector3) - me.position
		to.y = 0
		if to.length() < 0.25:
			_target = null
		else:
			dir = to
	_move(me, dir.normalized() * WALK_SPEED * delta)
	_follow_squad(delta)
	_update_near()
	_update_camera(delta)


func _move(fig: PilotFigure, step: Vector3) -> void:
	fig.walking = move_toward(fig.walking, 1.0 if step.length() > 0.001 else 0.0, 0.15)
	if step.length() <= 0.0001:
		return
	var p := Vector2(fig.position.x + step.x, fig.position.z + step.z)
	p = _push_out(p)
	if p.length() > HubLayout.BOUNDS:
		p = p.normalized() * HubLayout.BOUNDS
	fig.position = Vector3(p.x, 0, p.y)
	fig.rotation.y = lerp_angle(fig.rotation.y, atan2(-step.x, -step.z), 0.25)


## AI squadmates (and seats with no live position) trail the local pilot.
func _follow_squad(delta: float) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	var i := 0
	for s: String in avatars:
		if s == local_seat:
			continue
		i += 1
		var fig: PilotFigure = avatars[s]
		if fig.has_meta("remote"):
			continue
		var back := Vector3(sin(_yaw), 0, cos(_yaw)) * 1.6 * i + Vector3(cos(_yaw), 0, -sin(_yaw)) * (1.2 if i % 2 else -1.2)
		var goal := me.position + back
		var to := goal - fig.position
		to.y = 0
		_move(fig, to.normalized() * minf(to.length(), WALK_SPEED * 1.1 * delta) if to.length() > 0.6 else Vector3.ZERO)


func set_avatar_position(seat: String, pos: Vector3, facing: float) -> void:
	var fig: PilotFigure = avatars.get(seat)
	if fig != null and seat != local_seat:
		fig.set_meta("remote", true)
		fig.walking = 1.0 if fig.position.distance_to(pos) > 0.02 else 0.0
		fig.position = pos
		fig.rotation.y = facing


func _push_out(p: Vector2) -> Vector2:
	for b: Dictionary in _blockers:
		var inv: Transform3D = b["inv"]
		var half: Vector2 = b["half"]
		var lp := inv * Vector3(p.x, 0, p.y)
		if absf(lp.x) < half.x and absf(lp.z) < half.y:
			var dx := half.x - absf(lp.x)
			var dz := half.y - absf(lp.z)
			if dx < dz:
				lp.x = signf(lp.x if lp.x != 0 else 1.0) * half.x
			else:
				lp.z = signf(lp.z if lp.z != 0 else 1.0) * half.y
			var wp := inv.affine_inverse() * lp
			p = Vector2(wp.x, wp.z)
	return p


func _blocked(p: Vector2) -> bool:
	return _push_out(p) != p


func _update_near() -> void:
	var me: PilotFigure = avatars.get(local_seat)
	var best := ""
	var best_d := TALK_RANGE
	for id: String in npc_nodes:
		var d := (npc_nodes[id] as PilotFigure).position.distance_to(me.position)
		if d < best_d:
			best_d = d
			best = id
	if best != _near_npc:
		if npc_nodes.has(_near_npc):
			(npc_nodes[_near_npc] as PilotFigure).set_highlight(false)
		_near_npc = best
		if best != "":
			(npc_nodes[best] as PilotFigure).set_highlight(true)
	var npc: Dictionary = story.npcs.get(_near_npc, {})
	hud.set_prompt("" if npc.is_empty() or dialogue.visible else "[F]  Talk to %s, %s" % [npc["name"], npc["title"]])


func _update_camera(delta: float) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	var focus := me.position if me != null else Vector3.ZERO
	if dialogue != null and dialogue.visible and npc_nodes.has(str(story.dialogue.get("ctx", {}).get("npc", ""))):
		focus = focus.lerp((npc_nodes[str(story.dialogue["ctx"]["npc"])] as PilotFigure).position, 0.5)
	var talking := dialogue != null and dialogue.visible
	var dist := CAM_DIST * (0.55 if talking else 1.0)
	var pitch := TALK_PITCH if talking else CAM_PITCH
	var off := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * dist
	var want := focus + off + Vector3(0, 1.0, 0)
	_cam.position = _cam.position.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
	_fade_occluders(focus)
	# While talking, aim low so the speakers sit above the conversation panel.
	_cam.look_at(focus + Vector3(0, -1.2 if talking else 1.0, 0), Vector3.UP)


## Buildings between the camera and your pilot turn see-through.
func _fade_occluders(focus: Vector3) -> void:
	var a := Vector2(_cam.position.x, _cam.position.z)
	var b := Vector2(focus.x, focus.z)
	for bd: Dictionary in _buildings:
		var root: Node3D = bd["root"]
		var c := Vector2(root.position.x, root.position.z)
		var t := clampf((c - a).dot(b - a) / maxf((b - a).length_squared(), 0.01), 0.0, 1.0)
		var hide := (a + (b - a) * t).distance_to(c) < float(bd["radius"]) and t < 0.98
		if hide != bool(bd["faded"]):
			bd["faded"] = hide
			for m in root.find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).transparency = 0.8 if hide else 0.0


func talk_to(npc_id: String) -> void:
	var r := engine.submit(story, campaign, {"type": "talk", "seat": local_seat, "params": {"npc": npc_id}})
	if not r["ok"]:
		hud.toast(str(r["reason"]), StoryStyle.RED)
		return
	_target = null
	var me: PilotFigure = avatars.get(local_seat)
	var npc_fig: PilotFigure = npc_nodes.get(npc_id)
	if me != null and npc_fig != null:
		var to := npc_fig.position - me.position
		me.rotation.y = atan2(-to.x, -to.z)
		npc_fig.rotation.y = atan2(to.x, to.z)
	_handle(r["events"])


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match (ev as InputEventKey).keycode:
			KEY_F:
				if _near_npc != "" and not dialogue.visible:
					talk_to(_near_npc)
			KEY_TAB:
				if not dialogue.visible:
					downtime_screen.visible = not downtime_screen.visible
					downtime_screen.refresh()
					hud.set_busy(downtime_screen.visible)
			KEY_J:
				if not dialogue.visible:
					hud.toggle_board()
			KEY_ESCAPE:
				downtime_screen.visible = false
				gear_panel.visible = false
				hud.close_board()
				hud.set_busy(false)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not dialogue.visible and not downtime_screen.visible:
		var from := _cam.project_ray_origin(ev.position)
		var dir := _cam.project_ray_normal(ev.position)
		if absf(dir.y) > 0.001:
			var hit := from + dir * (-from.y / dir.y)
			for id: String in npc_nodes:
				if (npc_nodes[id] as PilotFigure).position.distance_to(hit) < 0.9:
					var me: PilotFigure = avatars.get(local_seat)
					if me != null and me.position.distance_to(hit) <= TALK_RANGE + 0.5:
						talk_to(id)
						return
					_target = (npc_nodes[id] as PilotFigure).position.lerp(me.position, 1.6 / maxf(me.position.distance_to(hit), 1.6))
					return
			_target = hit


# --- UI ----------------------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	hud = HubHud.new()
	ui.add_child(hud)
	hud.bind(engine, story, campaign, local_seat)
	hud.story_events.connect(_handle)
	downtime_screen = DowntimeScreen.new()
	ui.add_child(downtime_screen)
	downtime_screen.bind(engine, story, campaign, local_seat)
	downtime_screen.story_events.connect(_handle)
	downtime_panel = downtime_screen.panel
	dialogue = DialogueView.new()
	ui.add_child(dialogue)
	dialogue.bind(engine, story, campaign, local_seat)
	dialogue.story_events.connect(_handle)
	gear_panel = PilotGearPanel.new()
	ui.add_child(gear_panel)
	gear_panel.bind(engine, story, campaign, local_seat)
	gear_panel.story_events.connect(_handle)
	level_panel = LevelUpPanel.new()
	ui.add_child(level_panel)
	level_panel.bind(engine, story, campaign, local_seat)
	level_panel.story_events.connect(_handle)
	popup = StoryCheckPopup.new()
	ui.add_child(popup)
	tutorial_panel = TutorialPanel.new()
	ui.add_child(tutorial_panel)
	tutorial_panel.bind(campaign)


func _center(c: Control) -> void:
	c.reset_size()
	var vp := get_viewport().get_visible_rect().size
	c.position = (vp - c.size) / 2.0


## Everything the story engine reports: pop-ups, toasts, panels to open, missions to start.
func _handle(events: Array) -> void:
	popup.dock = "corner" if downtime_screen.visible else ("bottom" if hud.board_open() else "top")
	tutorial_panel.show_events(events)
	for e: Dictionary in events:
		var who: String = str(campaign.pilots.get(str(e.get("pilot", "")), {}).get("callsign", ""))
		match str(e.get("type", "")):
			"narrative_check":
				popup.show_check(e["check"], who)
			"downtime_result":
				if e.has("check"):
					popup.show_check({"total": e["check"]["total"], "outcome": "fail" if e["band"] == "low" else "success", "label": "%s (%s)" % [e["name"], {"low": "9 or less", "mid": "10-19", "high": "20+"}[e["band"]]],
						"d20": e["check"]["d20"], "bonus_sources": e["check"]["bonus_sources"], "accuracy_roll": e["check"]["accuracy_roll"], "target": 10, "rule_ref": e["rule_ref"]}, who)
			"reserve_gained":
				hud.toast("%s gained a reserve: %s" % [who, e["reserve"]["name"]], StoryStyle.GREEN)
			"standing_changed":
				hud.toast("%s: now %s" % [e["faction"], e["label"]], StoryStyle.BLUE if int(e["to"]) > int(e["from"]) else StoryStyle.RED)
			"contact_added":
				hud.toast("New contact: %s" % e["name"], StoryStyle.DIM)
			"hook_added":
				hud.toast("New job on the board: %s" % e["hook"]["title"], StoryStyle.GOLD)
			"obligation_added":
				hud.toast("Favor owed: %s" % e["obligation"]["what"], StoryStyle.RED)
			"pilot_harmed":
				hud.toast("%s takes %d damage (HP %d)" % [who, int(e["amount"]), int(e["hp"])], StoryStyle.RED)
			"down_and_out_roll":
				hud.toast("%s hits 0 HP: rolled %d on 1d6: %s" % [who, int(e["roll"]), {"close_call": "a close call, back to 1 HP", "down_and_out": "DOWN AND OUT", "dead": "killed"}[e["result"]]], StoryStyle.RED)
			"pilot_gear_set":
				hud.toast("%s's kit: %s" % [who, ", ".join(PackedStringArray((e["gear"] as Array).map(func(g: Variant) -> String: return str(db.get_entry("pilot_gear", str(g)).get("name", g)))))], StoryStyle.DIM)
			"pilot_rested":
				hud.toast("%s rests: HP %d" % [who, int(e["hp"])], StoryStyle.GREEN)
			"ai_chose":
				if e.has("action"):
					hud.toast(str(e["why"]), StoryStyle.DIM)
			"action_refused":
				hud.toast(str(e["reason"]), StoryStyle.RED)
			"ui_requested":
				match str(e["ui"]):
					"downtime":
						downtime_screen.open(str(e["params"].get("action", "")), str(e.get("npc", "")), str(e["params"].get("subject", "")))
					"hooks":
						hud.toggle_board()
					"pilot_gear":
						gear_panel.open()
			"boots_on_the_ground":
				mission_requested.emit(e["hook"])
	# A downtime action taken from a conversation: show its result, and its choice if it has one.
	if events.any(func(x: Dictionary) -> bool: return str(x.get("type", "")) == "downtime_result" and story.seat_of(str(x.get("pilot", ""))) == local_seat) and not downtime_screen.visible:
		downtime_screen.open()
		downtime_panel.show_events(events)
	dialogue.refresh()
	downtime_screen.refresh()
	hud.refresh()
	level_panel.refresh()
	if level_panel.visible and dialogue.visible:
		level_panel.visible = false  # after the debrief conversation
	hud.set_busy(dialogue.visible or downtime_screen.visible or level_panel.visible)
	story_events.emit(events)


# --- Screenshots -------------------------------------------------------------------------

## godot --path . -s res://tools/screenshot.gd -- res://scenes/explore/hub.tscn "out_%s.png" 30
func screenshot_setup(args: Array) -> Array:
	if args.has("tutorial"):
		var t := HubDemo.make_tutorial()
		setup(t["engine"], t["story"], t["campaign"], t["db"], "p1")
		_handle(t["events"])
		return ["tutorial_briefing", "tutorial_hub"]
	var culture := ""
	for a: Variant in args:
		if str(a).begins_with("culture="):
			culture = str(a).substr(8)
	var d := HubDemo.make(12, culture)
	setup(d["engine"], d["story"], d["campaign"], d["db"], "p1")
	return ["walk", "talk", "choices", "check", "downtime", "supplies", "gear", "board", "briefing", "levelup"]


func screenshot_stage(tag: String) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	match tag:
		"tutorial_briefing":
			dialogue.advance()
		"tutorial_hub":
			while Dialogue.is_open(story):
				var o := Dialogue.offered(story)
				var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}}
				_handle(engine.submit(story, campaign, a)["events"])
			tutorial_panel._next()
			_handle(engine.submit(story, campaign, {"type": "confirm_reserves", "seat": "gm", "params": {}})["events"])
			_handle(Tutorial.observe_battle(story, campaign, [{"type": "combat_started"}, {"type": "turn_started", "unit": "p1"}], ["p1"]))
		"walk":
			me.position = Vector3(2, 0, 3)
			_yaw = 0.9
		"talk", "choices", "check":
			if not Dialogue.is_open(story):
				var bar := ""
				for id: String in npc_nodes:
					if story.npcs[id]["role"] == "bartender":
						bar = id
				var p := (npc_nodes[bar] as PilotFigure).position
				me.position = p.lerp(Vector3.ZERO, 2.0 / maxf(p.length(), 2.0))
				_yaw = atan2(me.position.x - p.x, me.position.z - p.z) + 0.9
				talk_to(bar)
			if tag != "talk":
				var guard := 0
				while Dialogue.offered(story).is_empty() and Dialogue.is_open(story) and guard < 4:
					dialogue.advance()
					guard += 1
			if tag == "check":
				for o: Dictionary in Dialogue.offered(story):
					if o.has("check"):
						dialogue.choose(str(o["id"]))
						break
		"downtime":
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			downtime_screen.open("dt_get_a_damn_drink")
			downtime_panel._subject.text = "Collect gossip"
			downtime_panel._go()
		"supplies":
			downtime_screen.visible = false
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			var qm := ""
			for id: String in npc_nodes:
				if story.npcs[id]["role"] == "quartermaster":
					qm = id
			var qp := (npc_nodes[qm] as PilotFigure).position
			me.position = qp.lerp(Vector3.ZERO, 2.0 / maxf(qp.length(), 2.0))
			_yaw = atan2(me.position.x - qp.x, me.position.z - qp.z) + 0.9
			talk_to(qm)
			var guard := 0
			while Dialogue.offered(story).is_empty() and Dialogue.is_open(story) and guard < 4:
				dialogue.advance()
				guard += 1
			dialogue.choose("supplies")
			dialogue.advance()
		"gear":
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			gear_panel.open()
		"board":
			gear_panel.visible = false
			downtime_screen.visible = false
			while not story.pending_choice.is_empty():
				var o: Array = story.pending_choice["options"]
				var picks: Array = o.slice(0, int(story.pending_choice.get("count", 1))).map(func(x: Dictionary) -> String: return str(x["id"]))
				_handle(engine.submit(story, campaign, {"type": "downtime_choose", "seat": "gm", "params": {"picks": picks}})["events"])
			_handle(engine.submit(story, campaign, {"type": "end_downtime", "seat": "gm", "params": {}})["events"])
			hud.toggle_board()
		"briefing":
			hud.close_board()
			_handle(engine.submit(story, campaign, {"type": "choose_hook", "seat": "gm", "params": {"hook": story.hooks[0]["id"]}})["events"])
			dialogue.advance()
		"levelup":
			while Dialogue.is_open(story):
				var o := Dialogue.offered(story)
				var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}}
				_handle(engine.submit(story, campaign, a)["events"])
			_handle(engine.submit(story, campaign, {"type": "confirm_reserves", "seat": "gm", "params": {}})["events"])
			_handle(engine.submit(story, campaign, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory", "reason": "All enemy forces have been defeated."}})["events"])
			while Dialogue.is_open(story):
				var o := Dialogue.offered(story)
				var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}}
				_handle(engine.submit(story, campaign, a)["events"])
			_handle(engine.submit(story, campaign, {"type": "level_up", "seat": "gm", "params": {}})["events"])
	for i in range(3):
		await get_tree().process_frame
