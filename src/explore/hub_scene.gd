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
## The campaign ended and the player wants the main menu.
signal menu_requested
## The squad split on a vote and the countdown ran out (host): run the player-vs-player arena
## fight with teams by vote ({id, sides: {option: [seats]}, fight, options}), then submit
## split_resolved {winner: option id}.
signal arena_requested(split: Dictionary)
## A mounted pilot walked out of town (the edge of the hub): the flow puts them on the world
## map at the town's site (after squad_mounted).
signal walked_out(seat: String)

const WALK_SPEED := 4.2
## The world/maps session's culture kits for hub towns (buildings, props, plaza, sky). Used
## when present; until then the town is built from plain blocks.
const WORLD_KITS := "res://src/render/world/world_kits.gd"
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
var _buildings: Array = []
var _kits: Variant = null  # the WorldKits script, or null  # [{"root": Node3D, "radius": float}] faded when they hide your pilot

var ui: CanvasLayer
var dialogue: DialogueView
var popup: StoryCheckPopup
var decision_panel: DecisionPanel
var downtime_panel: DowntimePanel
var downtime_screen: DowntimeScreen
var hud: HubHud
var level_panel: LevelUpPanel
var gear_panel: PilotGearPanel
var tutorial_panel: TutorialPanel
var epilogue: EpilogueScreen
var codex: CodexPanel
var map: CampaignMap
var gm_panel: GmPanel
var market: MarketPanel
var fp: FirstPerson
## Inside a building (HubInterior): its plan, the 3D room, the story room you're in.
var _inside: Dictionary = {}
var _interior: Node3D
var _iroom := ""
var _mechs: Array = []  # parked mechs to aim at: [{pid, name, pos: Vector3}]
var _gantry_at: Dictionary = {}  # pilot id -> where their mech parks (world position)
var _walked_out := false
var _inner_blockers: Array = []  # inside: furniture you walk around
var _cursor_toggled := false  # show_cursor in toggle mode
var _bay_armed := -100.0  # when the repair bay's "press E again" was shown (seconds)
var _jump_h := 0.0
var _jump_v := 0.0
var _orbit := false  # third person: right mouse held, dragging turns the camera
var _shown_floor := -1  # inside, seen from above: the highest floor drawn
var _keep_pos := Vector3.INF  # where the local pilot stood inside, across a rebuild
var _near_thing: Dictionary = {}  # inside: the door or thing in reach {kind: "door"|"item"|"exit", ...}


func setup(e: StoryEngine, s: StoryState, c: Campaign, content: ContentDB, seat: String = "p1") -> void:
	engine = e
	story = s
	campaign = c
	db = content
	local_seat = seat
	BattleKeys.ensure()  # WASD / arrows and camera turning, even before any battle has run
	_build_ui()
	# This player's "Auto-eat and drink" setting, for the pilots they look after (Survival).
	if StoryHouseRules.on(campaign, Economy.R_FOOD):
		for pid: String in Inventory.mine_of(story, local_seat):
			if bool(Inventory.of(story, pid).get("auto_eat", true)) != StorySettings.auto_eat():
				engine.submit(story, campaign, {"type": "set_auto_eat", "seat": local_seat, "params": {"pilot": pid, "on": StorySettings.auto_eat()}})
	rebuild()


## Builds the 3D town from story.hub.
func rebuild() -> void:
	if not _inside.is_empty() and avatars.has(local_seat):
		_keep_pos = (avatars[local_seat] as Node3D).position
	if _world != null:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)
	avatars.clear()
	npc_nodes.clear()
	_blockers.clear()
	_mechs.clear()
	_gantry_at.clear()
	_buildings.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.hub.get("seed", 0), "hub_props"])
	_kits = load(WORLD_KITS) if ResourceLoader.exists(WORLD_KITS) else null
	_environment()
	_ground(rng)
	for spot: Dictionary in story.hub.get("spots", []):
		_building(spot, rng)
	_props(rng)
	_place_npcs()
	_place_squad()
	if _kits != null:
		_kits.set_hub_time(_world, TownLife.period(story))  # lamps and windows by the clock
	if not _inside.is_empty():
		_show_inside(true)
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
	if _kits != null:
		_kits.apply_hub_environment(_culture(), e, sun, TownLife.period(story), int(story.hub.get("seed", 0)) & 0x7fffffff)


func _ground(rng: RandomNumberGenerator) -> void:
	var kind := str(story.hub.get("kind", "town"))
	var dirt := Color(0.56, 0.47, 0.36) if kind != "station" else Color(0.32, 0.34, 0.37)
	var pave_col := dirt.lightened(0.18) if kind != "station" else Color(0.42, 0.44, 0.47)
	if _kits != null:
		var gc: Dictionary = _kits.hub_ground(_culture())
		dirt = gc.get("ground", dirt)
		pave_col = gc.get("pave", pave_col)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	pm.subdivide_width = 1
	ground.mesh = pm
	ground.material_override = MeshKit.paint(dirt, 0.0, 0.95, 0.0)
	_world.add_child(ground)
	# Plaza paving and roads out to each building.
	var pave := MeshKit.paint(pave_col, 0.05, 0.9, 0.25)
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
	elif kind != "plaza" and _kits != null:
		# The culture's own building (door toward +Z, walls inside the footprint).
		root.add_child(_kits.build_hub_building(_culture(), spot, int(story.hub.get("seed", 0))))
		_blockers.append({"inv": root.transform.affine_inverse(), "half": Vector2(w / 2.0 + 0.35, d / 2.0 + 0.35)})
		_buildings.append({"root": root, "radius": maxf(w, d) * 0.6, "faded": false})
		label_h = h + 1.6
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
		if i < squad.size():
			_gantry_at[str((squad[i]["pilot"] as Dictionary).get("id", ""))] = root.transform * Vector3(x, 0.2, -1.2)
		if i < squad.size() and Journeys.mounted(story, str((squad[i]["pilot"] as Dictionary).get("id", ""))):
			continue  # its pilot has climbed in and walked it off the gantry
		if i < squad.size() and db != null:
			var mech: Dictionary = squad[i]["mech"]
			var frame := db.frame(str(mech.get("frame", Campaign.STARTER_FRAME)))
			if not frame.is_empty():
				var model := MechBuilder.build(frame, mech.get("loadout", {}), db)
				model.scale = Vector3.ONE * 4.2
				model.position = Vector3(x, 0.2, -1.2)
				model.rotation.y = PI
				root.add_child(model)
				var pid := str((squad[i]["pilot"] as Dictionary).get("id", ""))
				_mechs.append({"pid": pid, "name": "%s's %s" % [(squad[i]["pilot"] as Dictionary).get("callsign", "the squad"), frame.get("name", "mech")],
					"local": Vector3(x, 4.5, -1.2), "root": root})
	_blockers.append({"inv": root.transform.affine_inverse() * Transform3D(Basis(), Vector3(0, 0, -1.5)), "half": Vector2(w / 2.0, 1.6)})


func _props(rng: RandomNumberGenerator) -> void:
	if _kits != null:
		_kit_props(rng)
		return
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


## Props, lamps and the plaza centerpiece in the hub culture's style (WorldKits).
func _kit_props(rng: RandomNumberGenerator) -> void:
	var c := _culture()
	var kinds: Array = _kits.hub_prop_kinds(c)
	var radius: Dictionary = _kits.PROP_RADIUS
	var small: Array = kinds.filter(func(k: String) -> bool: return k != "lamp")
	if small.is_empty():
		small = kinds
	for i in range(26):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(9.5, 24.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if _blocked(Vector2(p.x, p.z)) or _near_door(Vector2(p.x, p.z)):
			continue
		# The culture's favourite kinds come first in its list, so weight toward them.
		var kind := str(small[mini(rng.randi_range(0, small.size() - 1), rng.randi_range(0, small.size() - 1))])
		var prop: Node3D = _kits.build_hub_prop(c, kind, rng.randi())
		prop.position = p
		prop.rotation.y = rng.randf_range(0, TAU)
		_world.add_child(prop)
		var pr := float(radius.get(kind, 0.6))
		_blockers.append({"inv": Transform3D(Basis(), p).affine_inverse(), "half": Vector2(pr, pr)})
	if kinds.has("lamp"):
		for i in range(6):
			var a := TAU * i / 6.0 + 0.3
			var lamp: Node3D = _kits.build_hub_prop(c, "lamp", i)
			lamp.position = Vector3(cos(a), 0, sin(a)) * 8.0
			_world.add_child(lamp)
	_world.add_child(_kits.build_hub_centerpiece(c, int(story.hub.get("seed", 0))))
	_blockers.append({"inv": Transform3D.IDENTITY, "half": Vector2(1.6, 1.6)})


func _culture() -> String:
	return str(story.hub.get("culture", ""))


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
		var where := TownLife.where_npc(story, id)
		var room_public := bool(TownLife.room_info(TownLife.spot_kind(story, str(where["spot"])), str(where["room"])).get("public", false))
		if bool(where["asleep"]) or bool(where["out"]) or not room_public:
			continue
		kind = str(where["spot"])
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
		# Mounted up: they walk the town in their mech (Journeys).
		if Journeys.mounted(story, pid):
			fig.set_mech(_mech_model(p))
			if _gantry_at.has(pid):
				fig.position = _gantry_at[pid] + Vector3(0, 0, 3.0)
		i += 1


# --- Moving and talking ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	if me == null:
		return
	var busy := decision_panel.visible or dialogue.visible or downtime_screen.visible or hud.board_open() or level_panel.visible or gear_panel.visible or codex.visible or map.visible
	var dir := Vector3.ZERO
	var first := fp != null and fp.enabled
	_capture_mouse(first and not busy and not dialogue.visible and not _cursor_free())
	var speed := ExploreInput.speed(not busy and InputMap.has_action("run") and Input.is_action_pressed("run"), fp != null and fp.sneaking)
	var in_mech := Journeys.mounted(story, story.pilot_of_seat(local_seat))
	if in_mech:
		speed *= 2.2  # a mech's stride
	if not busy:
		var ax := ExploreInput.axes()
		dir = ExploreInput.direction(_yaw, ax.y, ax.x)
		# Third person turns with keys (and right-drag); first person turns with the mouse.
		if not first and InputMap.has_action("turn_left"):
			if Input.is_action_pressed("turn_left"):
				_yaw += delta * 1.8
			if Input.is_action_pressed("turn_right"):
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
	me.position.y -= _jump_h
	_move(me, dir.normalized() * speed * delta)
	if first:
		me.rotation.y = lerp_angle(me.rotation.y, _yaw, clampf(delta * 12.0, 0.0, 1.0))
	var j := ExploreInput.jump_step(_jump_h, _jump_v, delta) if _jump_h > 0.0 or _jump_v > 0.0 else Vector2.ZERO
	_jump_h = j.x
	_jump_v = j.y
	me.position.y += _jump_h
	_follow_squad(delta)
	_update_near()
	_update_camera(delta)


func _move(fig: PilotFigure, step: Vector3) -> void:
	fig.walking = move_toward(fig.walking, 1.0 if step.length() > 0.001 else 0.0, 0.15)
	if step.length() <= 0.0001:
		return
	if not _inside.is_empty():
		_move_inside(fig, step)
		return
	var p := Vector2(fig.position.x + step.x, fig.position.z + step.z)
	p = _push_out(p)
	if p.length() > HubLayout.BOUNDS:
		p = p.normalized() * HubLayout.BOUNDS
		# Walking out of town in your mech: the flow takes the squad onto the world map.
		if fig == avatars.get(local_seat) and Journeys.mounted(story, story.pilot_of_seat(local_seat)) and not _walked_out:
			_walked_out = true
			walked_out.emit(local_seat)
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
	_update_near_thing(me)
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
	var prompt := "" if npc.is_empty() else "[F]  Talk to %s, %s" % [npc["name"], npc["title"]]
	if prompt == "":
		prompt = _thing_prompt()
	if fp != null:
		fp.inside_prompt = _thing_prompt()
	hud.set_prompt("" if prompt == "" or dialogue.visible or (fp != null and fp.enabled) else prompt)


func _update_camera(delta: float) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	# First person on foot (V): the camera in your pilot's eyes, crosshair and prompts.
	var face_talk := dialogue != null and dialogue.visible and StorySettings.dialogue_view() == "first"
	if fp != null and fp.enabled and me != null and not face_talk:
		fp.cockpit = Journeys.mounted(story, story.pilot_of_seat(local_seat))
		fp.place_camera(_cam, me, _yaw, delta)
		_set_ceiling(true)
		fp.pick(_cam, npc_nodes, story.hub.get("spots", []) if _inside.is_empty() else [], story, _aim_targets())
		fp.show(story, story.pilot_of_seat(local_seat), "")
		return
	if me != null and not me.visible:
		me.visible = true
	# Face to face (first-person conversation): the camera holds on the person's face.
	var npc_id := str(story.dialogue.get("ctx", {}).get("npc", "")) if dialogue != null and dialogue.visible else ""
	if npc_id != "" and npc_nodes.has(npc_id) and me != null and StorySettings.dialogue_view() == "first" and str(story.dialogue.get("mode", "talk")) != "radio":
		var fig := npc_nodes[npc_id] as PilotFigure
		var face_at := fig.position + Vector3(0, 1.62, 0)
		var from := me.position + Vector3(0, 1.6, 0)
		var eye := face_at + (from - face_at).normalized() * 1.25 + Vector3(0, -0.02, 0)
		_cam.position = _cam.position.lerp(eye, clampf(delta * 6.0, 0.0, 1.0))
		_cam.look_at(face_at + Vector3(0, -0.12, 0), Vector3.UP)
		# Face animation, when the figure supports it (visuals' people: expressions, blinks, talking).
		if fig.has_method("set_expression"):
			fig.call("set_expression", str(story.dialogue.get("expression", "neutral")))
		if fig.has_method("set_talking"):
			fig.call("set_talking", str(story.dialogue.get("speaker", "")) == "npc")
		return
	var focus := me.position if me != null else Vector3.ZERO
	if dialogue != null and dialogue.visible and npc_nodes.has(str(story.dialogue.get("ctx", {}).get("npc", ""))):
		focus = focus.lerp((npc_nodes[str(story.dialogue["ctx"]["npc"])] as PilotFigure).position, 0.5)
	var talking := dialogue != null and dialogue.visible
	var dist := CAM_DIST * (0.55 if talking else 1.0) * (1.8 if Journeys.mounted(story, story.pilot_of_seat(local_seat)) else 1.0)
	var pitch := TALK_PITCH if talking else CAM_PITCH
	if not _inside.is_empty():
		# Inside: a closer camera, looking down through the roof (the ceiling is hidden).
		_set_ceiling(false)
		dist = 9.0 if not talking else 5.0
		pitch = deg_to_rad(74.0) if not talking else deg_to_rad(50.0)
	var off := Vector3(sin(_yaw) * cos(pitch), sin(pitch), cos(_yaw) * cos(pitch)) * dist
	var want := focus + off + Vector3(0, 1.0, 0)
	if not _inside.is_empty():
		# Stay over the building, not out past its front wall.
		var size: Array = _inside["layout"].get("size", [10.0, 8.0])
		want.x = clampf(want.x, -float(size[0]) / 2.0 + 0.5, float(size[0]) / 2.0 - 0.5)
		want.z = clampf(want.z, -float(size[1]) / 2.0 + 0.5, float(size[1]) / 2.0 - 0.5)
	_cam.position = _cam.position.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
	if _inside.is_empty():
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


## Using what's under the crosshair in first person (E, or R for the rough way).
func _fp_use(rough: bool) -> void:
	var pid := story.pilot_of_seat(local_seat)
	var t := fp.target
	if str(t.get("kind", "")) == "mech":
		if rough:
			_bay_use()
		else:
			_climb(str(t["id"]), true)
		return
	if str(t.get("kind", "")) == "bay":
		_bay_use()
		return
	if t.is_empty() and Journeys.mounted(story, pid) and not rough:
		_climb(pid, false)
		return
	if not _inside.is_empty() and t.get("kind", "") != "npc":
		if str(t.get("kind", "")) in ["item", "exit", "idoor"]:
			_near_thing = t.duplicate()
			if str(t["kind"]) == "idoor":
				_near_thing["kind"] = "door"
		_inside_use(rough)
		return
	var a := {}
	if t.get("kind", "") == "npc":
		var id := str(t["id"])
		var w := TownLife.where_npc(story, id)
		engine.submit(story, campaign, {"type": "go", "seat": local_seat, "params": {"pilot": pid, "spot": w["spot"], "room": w["room"]}})
		if not fp.sneaking and not rough:
			talk_to(id)
			return
		if rough:
			a = {"type": "take_out", "params": {"pilot": pid, "npc": id}}
		else:
			for it: Dictionary in (story.flags.get("_items", {}) as Dictionary).values():
				if str(it["owner"]) == id and str(it["kept"]) == "person" and str(it["holder"]) == "":
					a = {"type": "pickpocket", "params": {"pilot": pid, "npc": id, "item": it["id"]}}
	elif t.get("kind", "") == "door":
		var spot := str(t["spot"])
		var kind := TownLife.spot_kind(story, spot)
		var rooms: Dictionary = TownLife.data().get("rooms", {}).get(kind, {})
		var pub := ""
		var priv := ""
		for r: String in rooms:
			if bool(rooms[r].get("public", false)):
				pub = r if pub == "" else pub
			elif priv == "":
				priv = r
		if not fp.sneaking and not rough:
			a = {"type": "go", "params": {"pilot": pid, "spot": spot, "room": pub}}
		elif priv != "":
			var locked := int(rooms[priv].get("lock", 0)) > 0 and not TownLife.is_open(story, spot, priv)
			if rough and locked:
				a = {"type": "break_in", "params": {"pilot": pid, "spot": spot, "room": priv}}
			elif locked:
				a = {"type": "pick_lock", "params": {"pilot": pid, "spot": spot, "room": priv}}
			else:
				a = {"type": "sneak", "params": {"pilot": pid, "spot": spot, "room": priv}}
	else:
		# Nothing in the crosshair: take something kept in the room you're in.
		var at := TownLife.pilot_at(story, pid)
		var here := TownLife.items_here(story, str(at["spot"]), str(at["room"]))
		if not here.is_empty():
			a = {"type": "take", "params": {"pilot": pid, "item": here[0]["id"]}}
	if a.is_empty():
		return
	a["seat"] = local_seat
	fp.used()
	var r := engine.submit(story, campaign, a)
	if not r["ok"]:
		hud.toast(str(r["reason"]), StoryStyle.RED)
		return
	for e: Dictionary in r["events"]:
		if e.has("text") and str(e.get("type", "")) != "dialogue_line":
			hud.toast(str(e["text"]), StoryStyle.GOLD if str(e["type"]) in ["item_taken", "moved", "opened", "learned"] else StoryStyle.TEXT)
	_handle(r["events"])
	# Through a building's door: you're inside it now.
	if t.get("kind", "") == "door" and str(a["type"]) in ["go", "sneak", "break_in"] and HubInterior.has_interior(story, str(t["spot"])):
		enter_building(str(t["spot"]), str(a["params"].get("room", "")), false)


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
	if fp != null and fp.enabled and ev is InputEventMouseMotion and not dialogue.visible \
			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
		_yaw = fp.look((ev as InputEventMouseMotion).relative, _yaw)
		return
	if ev is InputEventMouseMotion and _orbit:
		_yaw -= (ev as InputEventMouseMotion).relative.x * ExploreInput.LOOK * StorySettings.look_sensitivity()
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_orbit = ev.pressed and not (fp != null and fp.enabled)
	# Walking actions (rebindable, data/game/keybinds.json).
	if InputMap.has_action("show_cursor") and ev.is_action_pressed("show_cursor") and not ev.is_echo() and StorySettings.cursor_mode() == "toggle":
		_cursor_toggled = not _cursor_toggled
		return
	if InputMap.has_action("jump") and ev.is_action_pressed("jump") and not dialogue.visible and _jump_h <= 0.0:
		_jump_v = ExploreInput.JUMP_SPEED
		_jump_h = 0.001
		return
	if InputMap.has_action("use") and ev.is_action_pressed("use") and not ev.is_echo() and not dialogue.visible:
		if fp.enabled:
			_fp_use(false)
		else:
			_use_nearby(false)
		return
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
			KEY_K:
				if not dialogue.visible:
					codex.visible = not codex.visible
					if codex.visible:
						codex.open()
					hud.set_busy(codex.visible)
			KEY_J:
				if not dialogue.visible:
					hud.toggle_board()
			KEY_M:
				if not dialogue.visible and not map.visible:
					open_map()
			KEY_V:
				if not dialogue.visible:
					fp.set_enabled(not fp.enabled, _cam)
					_cursor_toggled = false
					if fp.enabled and StorySettings.take_cursor_hint():
						var k := BattleKeys.keys_text("show_cursor")
						hud.toast(("Hold %s to use the mouse" if StorySettings.cursor_mode() == "hold" else "Press %s to use the mouse") % (k if k != "" else "Alt"), StoryStyle.BLUE)
			KEY_C:
				if fp.enabled and not dialogue.visible:
					fp.sneaking = not fp.sneaking
			KEY_R:
				if fp.enabled and not dialogue.visible:
					_fp_use(true)
				elif not dialogue.visible:
					_use_nearby(true)
			KEY_T:
				if not dialogue.visible:
					var wr := engine.submit(story, campaign, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
					_handle(wr["events"])
					for e: Dictionary in wr["events"]:
						if str(e.get("type", "")) == "time_passed":
							hud.toast(str(e["text"]), StoryStyle.BLUE)
					rebuild()
			KEY_B:
				if MarketPanel.available(campaign) and not dialogue.visible:
					market.visible = not market.visible
					if market.visible:
						market.open()
					hud.set_busy(market.visible)
			KEY_G:
				if gm_enabled():
					gm_panel.visible = not gm_panel.visible
					if gm_panel.visible:
						gm_panel.open()
			KEY_ESCAPE:
				codex.visible = false
				downtime_screen.visible = false
				gear_panel.visible = false
				hud.close_board()
				hud.set_busy(false)
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and fp != null and fp.enabled and not dialogue.visible and not downtime_screen.visible:
		# First person: left click uses what's under the crosshair (not while the cursor is out
		# for clicking buttons).
		if not _cursor_free():
			_fp_use(false)
		return
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



# --- Inside buildings (HubInterior) ------------------------------------------------------

## Goes into the building at `spot_id` (its public room, or `room` if the squad got into a
## private one). With `walk_in`, it's a TownLife "go" first (refused if it isn't allowed).
func enter_building(spot_id: String, room: String = "", walk_in: bool = true) -> bool:
	var p := HubInterior.plan(story, spot_id)
	if p.is_empty():
		return false
	var entry := str(p.get("entry", ""))
	var sr: Array = p["rooms"].get(entry, [spot_id, ""])
	if walk_in:
		var r := engine.submit(story, campaign, {"type": "go", "seat": local_seat, "params": {"pilot": story.pilot_of_seat(local_seat), "spot": sr[0], "room": sr[1]}})
		if not r["ok"]:
			hud.toast(str(r["reason"]), StoryStyle.RED)
			return false
	_inside = p
	_iroom = entry
	if room != "":
		var ir := HubInterior.room_for(p, spot_id, room)
		if ir != "":
			_iroom = ir
	_show_inside(false)
	hud.toast("%s." % TownLife.room_name(story, str(sr[0]), str(sr[1])).capitalize(), StoryStyle.BLUE)
	return true


## Builds (or rebuilds, after time passes) the interior and puts the squad in it.
func _show_inside(keep_place: bool) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	var was := Vector3.INF
	if keep_place:
		was = _keep_pos if _keep_pos != Vector3.INF else (me.position if me != null and _interior != null and me.get_parent() == _interior else Vector3.INF)
	_keep_pos = Vector3.INF
	var old := _interior
	HubInterior.refresh(story, _inside)
	_interior = Interiors.build(_inside["layout"])
	add_child(_interior)
	_world.visible = false
	# The people here, where their day puts them (in bed at night).
	for id: String in npc_nodes:
		(npc_nodes[id] as Node3D).queue_free()
	npc_nodes.clear()
	for n: Dictionary in _inside["npcs"]:
		var npc: Dictionary = story.npcs[str(n["id"])]
		var fig := PilotFigure.new().build(npc.get("look", {}), str(npc["name"]), str(npc["title"]))
		fig.position = Vector3(float(n["pos"][0]), float(n["pos"][1]), float(n["pos"][2]))
		fig.rotation.y = float(n.get("facing", 0.0))
		if bool(n["asleep"]):
			fig.rotation.z = PI / 2.0
			fig.position.y += 0.55
		_interior.add_child(fig)
		if not bool(n["asleep"]):
			npc_nodes[str(n["id"])] = fig
	# Things kept here: a faint glint where they are.
	for it: Dictionary in _inside["items"]:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.12, 0.18)
		mark.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.8, 0.35)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.45, 0.1)
		mark.material_override = m
		mark.position = Vector3(float(it["pos"][0]), float(it["pos"][1]) + 1.0, float(it["pos"][2]))
		mark.name = "Item_" + str(it["id"])
		_interior.add_child(mark)
	# The squad, just inside the door (or where they were).
	var start := _room_center(_iroom)
	for d: Dictionary in _inside["doors"]:
		if bool(d["outside"]) and (d["rooms"] as Array).has(_iroom):
			var dp := Vector3(float(d["pos"][0]), float(d["pos"][1]), float(d["pos"][2]))
			start = dp + (start - dp).normalized() * 1.2
			break
	var inward := (_room_center(_iroom) - start).normalized()
	var i := 0
	for s: String in avatars:
		var fig: PilotFigure = avatars[s]
		fig.reparent(_interior, false)
		fig.position = (was if s == local_seat and was != Vector3.INF else start + inward * 0.9 * i + inward.cross(Vector3.UP) * (0.5 if i % 2 else -0.5) * signf(i))
		i += 1
	_shown_floor = -1
	# The furniture you walk around (not rugs or anything you'd step over).
	_inner_blockers.clear()
	for f: Dictionary in _inside["layout"].get("furniture", []):
		var sz: Array = f["size"]
		if float(sz[1]) < 0.25 or float(sz[0]) * float(sz[2]) < 0.08:
			continue
		var at := Vector3(float(f["pos"][0]), float(f["pos"][1]), float(f["pos"][2]))
		_inner_blockers.append({"inv": Transform3D(Basis(Vector3.UP, float(f.get("yaw", 0.0))), at).affine_inverse(), "half": Vector2(float(sz[0]) / 2.0 + 0.22, float(sz[2]) / 2.0 + 0.22), "y": at.y})
	if old != null:
		old.queue_free()


func _room_center(ir: String) -> Vector3:
	var lay: Dictionary = _inside["layout"]
	var r: Dictionary = lay["rooms"].get(ir, {})
	if r.is_empty():
		return Vector3.ZERO
	var rc: Array = r["rect"]
	return Vector3(float(rc[0]) + float(rc[2]) / 2.0, int(r.get("floor", 0)) * float(lay["floor_height"]), float(rc[1]) + float(rc[3]) / 2.0)


func leave_building() -> void:
	if _inside.is_empty():
		return
	var spot_id := str(_inside["spot"])
	engine.submit(story, campaign, {"type": "go", "seat": local_seat, "params": {"pilot": story.pilot_of_seat(local_seat), "spot": "plaza", "room": "square"}})
	_inside = {}
	_iroom = ""
	if _interior != null:
		_interior.queue_free()
		_interior = null
	rebuild()
	var door := HubLayout.spot_named(story.hub, TownLife.spot_kind(story, spot_id))
	var me: PilotFigure = avatars.get(local_seat)
	if me != null and not door.is_empty():
		var dp := Vector2(float(door["door"][0]), float(door["door"][1]))
		var out := dp + (-dp.normalized() * 1.2 if dp.length() > 0.1 else Vector2(0, 1.2))
		me.position = Vector3(out.x, 0, out.y)


func _set_ceiling(on: bool) -> void:
	if _interior != null and _interior.has_node("Ceiling"):
		(_interior.get_node("Ceiling") as Node3D).visible = on
	# From above, the floors over your pilot's would hide them: show only up to theirs.
	var me: PilotFigure = avatars.get(local_seat)
	if _interior == null or me == null:
		return
	var fh := float(_inside["layout"]["floor_height"])
	var f := 99 if on else int(round(me.position.y / fh))
	if f == _shown_floor:
		return
	_shown_floor = f
	for c: Node in _interior.get_children():
		if c is Node3D and not c is PilotFigure and c.name != "Ceiling":
			(c as Node3D).visible = (c as Node3D).position.y < (f + 1) * fh - 0.15


## Walking inside: only within rooms and through doorways; into another story room through a
## door is a TownLife go (or sneak), refused when the door is locked or you're not welcome.
func _move_inside(fig: PilotFigure, step: Vector3) -> void:
	var fh := float(_inside["layout"]["floor_height"])
	var from := Vector2(fig.position.x, fig.position.z)
	var to := from + Vector2(step.x, step.z)
	var floor_i := int(round(fig.position.y / fh))
	var y := floor_i * fh
	var st := HubInterior.on_stair(_inside, to)
	if not st.is_empty():
		var rooms: Dictionary = _inside["layout"]["rooms"]
		var f0 := int(rooms.get(str(st["stair"]["from"]), {}).get("floor", 0))
		var f1 := int(rooms.get(str(st["stair"]["to"]), {}).get("floor", 1))
		y = lerpf(f0 * fh, f1 * fh, float(st["t"]))
		floor_i = f1 if float(st["t"]) > 0.5 else f0
	var here := HubInterior.room_at(_inside, from, int(round(fig.position.y / fh)), 0.0)
	to = _push_inner(to, y)
	var there := HubInterior.room_at(_inside, to, floor_i, 0.25)
	if there == "" and st.is_empty():
		var d := HubInterior.door_near(_inside, to, y, 0.6)
		if d.is_empty() or bool(d["outside"]):
			return
		there = here
	var is_me: bool = fig == avatars.get(local_seat)
	if is_me and there != _iroom and there != "":
		var door := HubInterior.door_near(_inside, from.lerp(to, 0.5), y, 1.4)
		var act := HubInterior.step_action(story, _inside, _iroom, there, door, fp != null and fp.sneaking)
		if act == "locked":
			return  # the prompt says how to get through (_update_near_thing)
		if act != "":
			var sr: Array = _inside["rooms"][there]
			var r := engine.submit(story, campaign, {"type": act, "seat": local_seat, "params": {"pilot": story.pilot_of_seat(local_seat), "spot": sr[0], "room": sr[1]}})
			if not r["ok"]:
				hud.toast(str(r["reason"]), StoryStyle.RED)
				return
			_handle(r["events"])
		_iroom = there
	fig.position = Vector3(to.x, y, to.y)
	fig.rotation.y = lerp_angle(fig.rotation.y, atan2(-step.x, -step.z), 0.25)


## Inside: the door, way out or thing within reach.
func _update_near_thing(me: PilotFigure) -> void:
	_near_thing = {}
	if _inside.is_empty() or me == null:
		return
	var at := Vector2(me.position.x, me.position.z)
	var best := 1.6
	for it: Dictionary in _inside["items"]:
		var d := Vector2(float(it["pos"][0]), float(it["pos"][2])).distance_to(at)
		if d < best and absf(float(it["pos"][1]) - me.position.y) < 1.5:
			best = d
			_near_thing = {"kind": "item", "id": it["id"], "name": it["name"], "container": it["container"]}
	if not _near_thing.is_empty():
		return
	for b: Dictionary in _bays_inside():
		if Vector2(b["pos"].x, b["pos"].z).distance_to(at) < 2.5 and absf(b["pos"].y - 1.2 - me.position.y) < 1.5:
			_near_thing = b
			return
	var dr := HubInterior.door_near(_inside, at, me.position.y, 1.6)
	if dr.is_empty():
		return
	if bool(dr["outside"]):
		_near_thing = {"kind": "exit", "door": dr}
	elif bool(dr["locked"]):
		var target := ""
		for r: String in dr["rooms"]:
			if r != _iroom and _inside["rooms"].has(r):
				target = r
		if target != "":
			_near_thing = {"kind": "door", "door": dr, "room": target}


func _thing_prompt() -> String:
	match str(_near_thing.get("kind", "")):
		"item":
			return "[E] Take %s" % _near_thing["name"]
		"exit":
			return "[E] Go back out"
		"bay":
			return "[E] Repair bay: Full Repair (10 hours)"
		"door":
			var sr: Array = _inside["rooms"].get(str(_near_thing["room"]), ["", ""])
			return "Locked: %s.   [E] Pick the lock   [R] Force it" % TownLife.room_name(story, str(sr[0]), str(sr[1]))
	return ""


## E / R in third person: inside, use what's in reach; outside, go into the building whose door
## you're standing at.
func _use_nearby(rough: bool) -> void:
	if not _inside.is_empty():
		_inside_use(rough)
		return
	var me: PilotFigure = avatars.get(local_seat)
	if me == null:
		return
	# In your mech: E climbs out (anywhere in town is safe).
	if Journeys.mounted(story, story.pilot_of_seat(local_seat)):
		if not rough:
			_climb(story.pilot_of_seat(local_seat), false)
		return
	# At the gantries: E climbs into your mech, R is the repair bay.
	for m: Dictionary in _mechs:
		var root: Node3D = m["root"]
		if is_instance_valid(root) and Vector2(root.position.x, root.position.z).distance_to(Vector2(me.position.x, me.position.z)) < 6.0:
			if rough:
				_bay_use()
			else:
				_climb(story.pilot_of_seat(local_seat), true)
			return
	for spot: Dictionary in story.hub.get("spots", []):
		if str(spot["kind"]) in ["plaza", "landing"]:
			continue
		var dp := Vector2(float(spot["door"][0]), float(spot["door"][1]))
		if dp.distance_to(Vector2(me.position.x, me.position.z)) < 2.6 and HubInterior.has_interior(story, str(spot["id"])):
			enter_building(str(spot["id"]))
			return


func _inside_use(rough: bool) -> void:
	var pid := story.pilot_of_seat(local_seat)
	var a := {}
	match str(_near_thing.get("kind", "")):
		"item":
			a = {"type": "take", "params": {"pilot": pid, "item": _near_thing["id"]}}
		"exit":
			leave_building()
			return
		"bay":
			_bay_use()
			return
		"door":
			var sr: Array = _inside["rooms"][str(_near_thing["room"])]
			a = {"type": "break_in" if rough else "pick_lock", "params": {"pilot": pid, "spot": sr[0], "room": sr[1]}}
	if a.is_empty():
		return
	a["seat"] = local_seat
	if fp != null:
		fp.used()
	var r := engine.submit(story, campaign, a)
	if not r["ok"]:
		hud.toast(str(r["reason"]), StoryStyle.RED)
		return
	for e: Dictionary in r["events"]:
		if e.has("text") and str(e.get("type", "")) != "dialogue_line":
			hud.toast(str(e["text"]), StoryStyle.GOLD if str(e["type"]) in ["item_taken", "opened"] else StoryStyle.TEXT)
	_handle(r["events"])
	if not _inside.is_empty():
		_show_inside(true)


# --- Walking controls (ExploreInput) ------------------------------------------------------

## The show-cursor key (Alt, rebindable): held, or toggled (Settings), the cursor is free to
## click buttons and the view stops turning.
func _cursor_free() -> bool:
	if not InputMap.has_action("show_cursor"):
		return false
	if StorySettings.cursor_mode() == "toggle":
		return _cursor_toggled
	return Input.is_action_pressed("show_cursor")


## First person: the mouse is captured while you walk; any panel or conversation frees it.
func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want


## Inside: pushed out of furniture on this floor.
func _push_inner(p: Vector2, y: float) -> Vector2:
	for b: Dictionary in _inner_blockers:
		if absf(float(b["y"]) - y) > 1.5:
			continue
		var inv: Transform3D = b["inv"]
		var half: Vector2 = b["half"]
		var lp := inv * Vector3(p.x, y, p.y)
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


## Things the crosshair can land on besides people and building doors: inside, what's kept
## here, the doors and the way out; outside, the squad's parked mechs.
func _aim_targets() -> Array:
	var out: Array = []
	if not _inside.is_empty():
		out.append_array(_bays_inside())
		for it: Dictionary in _inside["items"]:
			out.append({"kind": "item", "id": it["id"], "name": it["name"], "container": it["container"],
				"pos": Vector3(float(it["pos"][0]), float(it["pos"][1]) + 1.0, float(it["pos"][2]))})
		for d: Dictionary in _inside["doors"]:
			var dp := Vector3(float(d["pos"][0]), float(d["pos"][1]) + 1.2, float(d["pos"][2]))
			if bool(d["outside"]):
				out.append({"kind": "exit", "id": d["id"], "door": d, "pos": dp, "name": "the way out"})
			elif bool(d["locked"]):
				var target := ""
				for r: String in d["rooms"]:
					if r != _iroom and _inside["rooms"].has(r):
						target = r
				if target != "":
					out.append({"kind": "idoor", "id": d["id"], "door": d, "room": target, "locked": true, "pos": dp, "name": "a locked door"})
		return out
	for m: Dictionary in _mechs:
		var root: Node3D = m["root"]
		if is_instance_valid(root):
			out.append({"kind": "mech", "id": m["pid"], "name": m["name"], "pos": root.transform * (m["local"] as Vector3), "reach": 3.0})
	return out


## Climbs into your mech at the gantry (or back out): a moment's climb, then you walk the
## town in it, first person from the cockpit (Journeys.mount_up / dismount).
func _climb(pid: String, up: bool) -> void:
	if up and pid != story.pilot_of_seat(local_seat):
		hud.toast("That's %s's mech." % campaign.pilots.get(pid, {}).get("callsign", "someone else"), StoryStyle.DIM)
		return
	var r := engine.submit(story, campaign, {"type": "mount_up" if up else "dismount", "seat": local_seat, "params": {"pilot": story.pilot_of_seat(local_seat)}})
	if not r["ok"]:
		hud.toast(str(r["reason"]), StoryStyle.RED)
		return
	if fp != null:
		fp.used()
	var me: PilotFigure = avatars.get(local_seat)
	var where := me.position if me != null else Vector3.ZERO
	_handle(r["events"])
	for e: Dictionary in r["events"]:
		if str(e.get("type", "")) == "squad_mounted":
			hud.toast(str(e["text"]), StoryStyle.GOLD)
	rebuild()
	me = avatars.get(local_seat)
	if me != null and not up:
		me.position = Vector3(where.x, 0, where.z)
	if fp != null:
		fp.cockpit = Journeys.mounted(story, story.pilot_of_seat(local_seat))


## A squad mech's model, as it stands on the gantry.
func _mech_model(p: Dictionary) -> Node3D:
	if db == null:
		return null
	var mech: Dictionary = {}
	for m: Dictionary in p.get("mechs", []):
		if m.get("id", "") == p.get("active_mech", "") or mech.is_empty():
			mech = m
	var frame := db.frame(str(mech.get("frame", Campaign.STARTER_FRAME)))
	if frame.is_empty():
		return null
	var model := MechBuilder.build(frame, mech.get("loadout", {}), db)
	model.scale = Vector3.ONE * 4.2
	model.rotation.y = PI
	return model


## Inside: rooms where mechs are worked on (a hangar, engineering, a printer floor) have a bay.
func _bays_inside() -> Array:
	var out: Array = []
	var lay: Dictionary = _inside["layout"]
	for id: String in lay["rooms"]:
		if str(lay["rooms"][id].get("use", "")) in ["workshop", "engineering", "printer"]:
			var c := _room_center(id)
			out.append({"kind": "bay", "id": "bay_" + id, "name": "the repair bay", "pos": c + Vector3(0, 1.2, 0)})
	return out


## The repair bay (the gantries outside, a hangar or engineering inside): the first E shows
## what a Full Repair would fix and what it costs; E again within a few seconds does it.
func _bay_use() -> void:
	var why := RepairBay.refusal(story, campaign)
	if why != "":
		hud.toast(why, StoryStyle.BLUE if not RepairBay.needed(story) else StoryStyle.RED)
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _bay_armed > 6.0:
		_bay_armed = now
		for line: String in RepairBay.summary(story, campaign):
			hud.toast(line, StoryStyle.TEXT)
		hud.toast(RepairBay.PLAIN + " Press E again to start.", StoryStyle.GOLD)
		return
	_bay_armed = -100.0
	if fp != null:
		fp.used()
	var r := engine.submit(story, campaign, {"type": "full_repair", "seat": local_seat, "params": {}})
	if not r["ok"]:
		hud.toast(str(r["reason"]), StoryStyle.RED)
		return
	for e: Dictionary in r["events"]:
		if e.has("text"):
			hud.toast(str(e["text"]), StoryStyle.GOLD if str(e.get("type", "")) == "full_repair_done" else StoryStyle.TEXT)
	_handle(r["events"])
	rebuild()

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
	decision_panel = DecisionPanel.new()
	ui.add_child(decision_panel)
	decision_panel.bind(engine, story, campaign, db, local_seat)
	decision_panel.story_events.connect(_handle)
	decision_panel.arena_requested.connect(func(split: Dictionary) -> void: arena_requested.emit(split))
	codex = CodexPanel.new()
	ui.add_child(codex)
	epilogue = EpilogueScreen.new()
	ui.add_child(epilogue)
	epilogue.sequel_requested.connect(_sequel)
	epilogue.menu_requested.connect(func() -> void: menu_requested.emit())
	tutorial_panel = TutorialPanel.new()
	ui.add_child(tutorial_panel)
	tutorial_panel.bind(campaign)
	tutorial_panel.codex_requested.connect(func(q: String) -> void: codex.open(q))
	hud.codex_requested.connect(func() -> void: codex.open())
	fp = FirstPerson.new()
	add_child(fp)
	fp.attach(ui)
	map = CampaignMap.new()
	ui.add_child(map)
	map.bind(engine, story, campaign)
	map.travelled.connect(_travelled)
	map.closed.connect(func() -> void: hud.set_busy(false))
	hud.map_requested.connect(open_map)
	market = MarketPanel.new()
	ui.add_child(market)
	market.bind(engine, story, campaign, local_seat)
	market.story_events.connect(func(evs: Array) -> void: _handle(evs))
	hud.market_requested.connect(func() -> void:
		market.open()
		hud.set_busy(true))
	gm_panel = GmPanel.new()
	ui.add_child(gm_panel)
	gm_panel.bind(engine, story, campaign)
	gm_panel.story_events.connect(func(evs: Array) -> void:
		_handle(evs)
		dialogue.refresh()
		if evs.any(func(x: Dictionary) -> bool: return str(x.get("type", "")) in ["npc_added", "npc_edited"]):
			rebuild())


## The GM tools (G) are for a human GM: the gm seat, or a campaign set up with one.
func gm_enabled() -> bool:
	return local_seat == "gm" or bool(campaign.options.get("human_gm", false))


## The sector map (M): where the squad is, the worlds around it, standing, travel.
func open_map() -> void:
	map.open()
	hud.set_busy(true)


## The squad arrived somewhere else: a new town to walk around.
func _travelled(events: Array) -> void:
	hud.set_busy(false)
	rebuild()
	for e: Dictionary in events:
		if str(e.get("type", "")) == "travelled":
			hud.toast(str(e["text"]), StoryStyle.GOLD)
	_handle(events)
	story_events.emit(events)


func _center(c: Control) -> void:
	c.reset_size()
	var vp := get_viewport().get_visible_rect().size
	c.position = (vp - c.size) / 2.0


## Everything the story engine reports: pop-ups, toasts, panels to open, missions to start.
func _handle(events: Array) -> void:
	decision_panel.show_events(events)
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
			"tip":
				hud.toast(str(e["text"]), StoryStyle.BLUE)
			"obligation_added":
				hud.toast("Favor owed: %s" % e["obligation"]["what"], StoryStyle.RED)
			"pilot_harmed":
				hud.toast("%s takes %d damage (HP %d)" % [who, int(e["amount"]), int(e["hp"])], StoryStyle.RED)
			"down_and_out_roll":
				hud.toast("%s hits 0 HP: rolled %d on 1d6: %s" % [who, int(e["roll"]), {"close_call": "a close call, back to 1 HP", "down_and_out": "DOWN AND OUT", "dead": "killed"}[e["result"]]], StoryStyle.RED)
			"pilot_gear_set":
				hud.toast("%s's kit: %s" % [who, ", ".join(PackedStringArray((e["gear"] as Array).map(func(g: Variant) -> String: return str(db.get_entry("pilot_gear", str(g)).get("name", g)))))], StoryStyle.DIM)
			"banter":
				hud.toast("%s: \"%s\"" % [who, e["text"]], StoryStyle.TEXT)
			"bond_changed", "bond_reward":
				hud.toast(str(e["text"]), StoryStyle.BLUE)
			"story_hint":
				hud.toast(str(e["text"]), StoryStyle.GOLD)
			"chapter_started":
				hud.toast("%s%s: %s" % [("Act %d, %s. " % [int(e["act"]), e["act_name"]]) if str(e.get("act_name", "")) != "" else "", e["title"], e["text"]], StoryStyle.GOLD)
			"campaign_premise":
				hud.toast(str(e["text"]), StoryStyle.TEXT)
			"house_rule_changed", "paid", "earned", "salvage", "rations", "hungry", "mech_wrecked", "mech_reprinted", "wallet_started", "rations_started", "deal_off", "bought":
				hud.toast(str(e["text"]), StoryStyle.GOLD if str(e["type"]) in ["house_rule_changed", "earned", "bought", "mech_reprinted"] else StoryStyle.TEXT)
			"campaign_ended":
				epilogue.show_ending(e["ending"])
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


## The same pilots in a new campaign, at a new hub.
func _sequel() -> void:
	var next := CampaignLoop.sequel(campaign, story, engine)
	ui.queue_free()
	setup(engine, next["story"], next["campaign"], db, local_seat)
	_handle(next["events"])


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
	if args.has("ending"):
		_stage_ending()
		return ["ending"]
	if args.has("codex"):
		return ["codex"]
	if args.has("map"):
		return ["map"]
	if args.has("first"):
		StorySettings.persist = false
		return ["fp_look", "fp_sneak"]
	if args.has("modes"):
		StorySettings.persist = false
		return ["face", "radio", "jammed"]
	if args.has("house"):
		StorySettings.persist = false
		for id: String in ["hr_wallet", "hr_printers", "hr_paid_travel", "hr_fight_for_it", "hr_survival"]:
			engine.submit(story, campaign, {"type": "house_rule", "seat": "gm", "params": {"id": id, "on": true}})
		Economy.wallet(story)["manna"] = 40
		story.flags[Economy.WRECKED] = [story.pilot_of_seat("p2")]
		hud.refresh()
		return ["house_hud", "house_market"]
	if args.has("gm"):
		campaign.options["human_gm"] = true
		return ["gm_scene", "gm_played", "gm_jobs"]
	if args.has("parley"):
		StorySettings.persist = false
		return ["parley", "log"]
	if args.has("inside"):
		StorySettings.persist = false
		return ["inside_bar", "inside_fp"]
	if args.has("vote"):
		StorySettings.persist = false
		return ["vote"]
	return ["walk", "talk", "choices", "check", "downtime", "supplies", "gear", "board", "briefing", "levelup"]


## Plays a short campaign to its end (simulated results) for the epilogue screenshot.
func _stage_ending() -> void:
	campaign.options["campaign_arcs"] = 1
	var guard := 0
	while story.phase != "ending" and guard < 12:
		guard += 1
		if story.phase == "downtime":
			while not story.all_choices().is_empty():
				var pc: Dictionary = story.all_choices()[0]
				engine.submit(story, campaign, {"type": "downtime_choose", "seat": "gm", "params": {"pilot": pc["pilot"], "picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])}})
			engine.submit(story, campaign, {"type": "end_downtime", "seat": "gm", "params": {}})
		var hook: Dictionary = story.hooks[0]
		for h: Dictionary in story.hooks:
			if h.has("arc"):
				hook = h
		engine.submit(story, campaign, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
		Dialogue.close(story)
		engine.submit(story, campaign, {"type": "confirm_reserves", "seat": "gm", "params": {}})
		engine.submit(story, campaign, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory", "reason": "",
			"summary": {"rounds": 5, "kills": 4, "lost": [], "mvp": "Kettle"}, "dead": [story.pilot_of_seat("p4")] if guard == 2 else []}})
		Dialogue.close(story)
		var r := engine.submit(story, campaign, {"type": "level_up", "seat": "gm", "params": {}})
		_handle(r["events"])
		if story.phase != "ending":
			for pid: String in story.pending_picks:
				engine.submit(story, campaign, {"type": "level_picks", "seat": "gm", "params": {"pilot": pid, "trigger": "sk_spot", "mech_skill": "hull"}})
			engine.submit(story, campaign, {"type": "start_downtime", "seat": "gm", "params": {}})


func screenshot_stage(tag: String) -> void:
	var me: PilotFigure = avatars.get(local_seat)
	match tag:
		"codex":
			codex.open("engaged")
		"map":
			open_map()
		"fp_look":
			fp.set_enabled(true, _cam)
			var bar_spot: Dictionary = {}
			for sp: Dictionary in story.hub.get("spots", []):
				if str(sp["kind"]) == "bar":
					bar_spot = sp
			var door := Vector2(float(bar_spot["door"][0]), float(bar_spot["door"][1]))
			var stand := door.lerp(Vector2.ZERO, 2.6 / maxf(door.length(), 2.6))
			me.position = Vector3(stand.x, 0, stand.y)
			_yaw = atan2(-(door.x - stand.x), -(door.y - stand.y))
			fp.pitch = deg_to_rad(-4)
		"fp_sneak":
			fp.sneaking = true
		"vote":
			var seats := story.seats.keys()
			seats.sort()
			if seats.size() > 1:
				engine.submit(story, campaign, {"type": "set_seat", "seat": "gm", "params": {"seat": seats[1], "pilot": story.pilot_of_seat(seats[1]), "ai": false}})
			var ev := StoryEffects.apply({"decision": {"id": "fork", "prompt": "The canyon forks. Which way do we take the convoy?",
				"options": [{"id": "left", "label": "Left: the dry riverbed"}, {"id": "right", "label": "Right: the high road"}]}}, story, campaign, {})
			ev.append_array(engine.submit(story, campaign, {"type": "decide", "seat": seats[0], "params": {"option": "left"}})["events"])
			if seats.size() > 1:
				ev.append_array(engine.submit(story, campaign, {"type": "decide", "seat": seats[1], "params": {"option": "right"}})["events"])
			_handle(ev)
		"inside_bar":
			enter_building("bar")
			_yaw = 0.0
		"inside_fp":
			fp.set_enabled(true, _cam)
			_yaw = 0.0
			fp.pitch = deg_to_rad(-8)
		"face":
			StorySettings.set_dialogue_view("first")
			screenshot_stage("talk")
		"radio":
			StorySettings.set_dialogue_view("third")
			screenshot_stage("parley")
		"jammed":
			var ctx: Dictionary = story.dialogue.get("ctx", {}).duplicate(true)
			_handle(Dialogue.close(story))
			story.flags[Dialogue.JAMMED] = [str(ctx.get("speaker", ""))]
			_handle(Dialogue.start(story, campaign, "parley", ctx))
			dialogue.refresh()
		"house_hud":
			pass
		"house_market":
			market.open()
		"gm_scene":
			gm_panel.open()
			gm_panel._scene_lines.text = "You're the lancers who blew the dam.
narrator: The bar goes quiet.
(angry) Give me one reason not to call the marshal."
			(gm_panel._scene_choices[0]["text"] as LineEdit).text = "We saved the valley. -> ...Fine. One drink."
			(gm_panel._scene_choices[1]["text"] as LineEdit).text = "Call them. We'll wait."
			(gm_panel._scene_choices[0]["fx"] as OptionButton).select(1)
		"gm_played":
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			gm_panel._send("gm_scene", gm_panel._scene_params(true))
			gm_panel.visible = false
			dialogue.refresh()
		"gm_jobs":
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			dialogue.refresh()
			gm_panel.open()
			gm_panel._tabs.current_tab = 1
		"parley":
			# Mid-battle terms with the enemy commander (Rivals), shown over the hub for the picture.
			if Dialogue.is_open(story):
				_handle(Dialogue.close(story))
			engine.submit(story, campaign, {"type": "end_downtime", "seat": "gm", "params": {}})
			Dialogue.close(story)
			engine.submit(story, campaign, {"type": "choose_hook", "seat": "gm", "params": {"hook": story.hooks[0]["id"]}})
			Dialogue.close(story)
			engine.submit(story, campaign, {"type": "confirm_reserves", "seat": "gm", "params": {}})
			CampaignLoop.build_mission(campaign, story, db)
			var b := Rivals.battle(story)
			story.npcs[b["rival"]]["personality"] = "honorable"
			var evs: Array = [{"type": "round_started", "round": 2}]
			for id: String in b["enemy_ids"]:
				if id != str(b["unit"]):
					evs.append({"type": "unit_destroyed", "unit": id})
			_handle(engine.submit(story, campaign, {"type": "battle_events", "seat": "gm", "params": {"events": evs}})["events"])
			var guard := 0
			while Dialogue.offered(story).is_empty() and Dialogue.is_open(story) and guard < 4:
				dialogue.advance()
				guard += 1
		"log":
			StorySettings.set_text_scale(1.3)
			dialogue.refresh()
			dialogue.toggle_log()
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
