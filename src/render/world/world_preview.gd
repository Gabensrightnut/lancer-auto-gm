extends Node3D
## Battlefield preview: builds a board in one world style with a few mechs for scale, so
## terrain and scenery can be checked by screenshot. Tags are "<map>[=<landscape-culture>][@<view>]":
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/world_preview.tscn "out_%s.jpg" 3 hills urban@close
## Maps: hills, urban, alien, gen<seed> (MissionGenerator). Views: wide (default), close,
## vista (low, no grid), top.

var content: ContentDB
var view: BattleView
var shape := GridLayout.Shape.HEX


func _ready() -> void:
	if OS.get_environment("LANCER_QUALITY") != "":
		WorldQuality.set_preset(OS.get_environment("LANCER_QUALITY"), get_viewport())
	content = ContentDB.new()
	content.load_all()
	view = BattleView.new()
	view.content = content
	add_child(view)


func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["hills"]


func screenshot_stage(tag: String) -> void:
	var at := tag.split("@")
	# "map=landscape-culture" (file-name safe) or "map:landscape/culture".
	var spec := at[0].replace("=", ":").split(":")
	var cam := at[1] if at.size() > 1 else "wide"
	shape = GridLayout.Shape.SQUARE if spec[0].ends_with("_sq") else GridLayout.Shape.HEX
	var map_name := spec[0].trim_suffix("_sq")
	var map: BattleMap
	var kit := ""
	if map_name.begins_with("hub"):
		# hub-<culture>[~<dawn|day|evening|night>]
		var hub_tag := map_name.trim_prefix("hub").trim_prefix("-")
		await _hub(hub_tag.get_slice("~", 0), cam, hub_tag.get_slice("~", 1) if "~" in hub_tag else "day")
		return
	var sitrep := ""
	if "^" in map_name:
		sitrep = "sitrep_" + map_name.get_slice("^", 1)
		map_name = map_name.get_slice("^", 0)
	if map_name.begins_with("town"):
		# town<seed>+<hub culture>[+sitrep]: a fight in a hub's own town (story.hub layout).
		var tp := map_name.trim_prefix("town").split("+")
		var hrng := RandomNumberGenerator.new()
		hrng.seed = int(tp[0])
		var hub := {"kind": "town", "culture": tp[1] if tp.size() > 1 else "old_west", "seed": int(tp[0]), "spots": HubLayout.spots("town", hrng)}
		var tg := MissionGenerator.generate(int(tp[0]), {"db": content, "hub": hub, "sitrep": "sitrep_" + (tp[2] if tp.size() > 2 else "standardcombat"), "players": 2})
		map = (tg["state"] as GameState).map
		view.set_map(map, (tg["mission"] as Mission).flavor["kit"])
		view.terrain.show_objectives((tg["mission"] as Mission).zones, (tg["mission"] as Mission).deployment)
		print("town: ", (tg["mission"] as Mission).briefing, " fairness ok: ", tg["fairness"]["ok"])
		_place_mechs(map)
		await _aim_camera(map, cam)
		return
	if map_name.begins_with("gen"):
		# gen<seed>[+landscape[+culture]][+size][^sitrep] (control, holdout, gauntlet, escort,
		# extraction, recon, standardcombat)
		var parts := map_name.trim_prefix("gen").split("+")
		var opts := {"db": content, "shape": "square" if shape == GridLayout.Shape.SQUARE else "hex"}
		if parts.size() > 1:
			opts["landscape"] = parts[1]
		if parts.size() > 2:
			opts["culture"] = parts[2]
		if parts.size() > 3:
			opts["size"] = int(parts[3])
		if sitrep != "":
			# Any sitrep's map, including ones the GM doesn't generate yet.
			var rng := RandomNumberGenerator.new()
			rng.seed = int(parts[0])
			var wr := RandomNumberGenerator.new()
			wr.seed = int(parts[0]) + 1
			var sz := int(parts[3]) if parts.size() > 3 else 30
			var bf := MissionGenerator.battlefield(rng, wr, sitrep, sz, int(sz * 0.85), shape, parts[1] if parts.size() > 1 else "", parts[2] if parts.size() > 2 else "")
			map = bf["map"]
			kit = TerrainGen.kit(bf["world"][0], bf["world"][1])
			view.set_map(map, kit)
			view.terrain.show_objectives(bf["layout"]["zones"], bf["layout"]["deployment"])
			print("fairness: ", bf["fairness"])
			_place_mechs(map)
			await _aim_camera(map, cam)
			return
		var g := MissionGenerator.generate(int(parts[0]), opts)
		print("briefing: ", (g["mission"] as Mission).briefing)
		map = (g["state"] as GameState).map
		kit = (g["mission"] as Mission).flavor.get("kit", "grassy_hills")
	else:
		match map_name:
			"hills":
				map = DemoMap.build_hills(shape)
				kit = "grassy_hills"
			"alien":
				map = DemoMap.build_alien(shape)
				kit = "alien_wilds"
			"truth":
				map = DemoMap.build_showcase(shape)
				kit = "grassy_hills"
			_:
				map = DemoMap.build(shape)
				kit = "urban_ruins"
	if spec.size() > 1:
		kit = spec[1].replace("-", "/")
	view.set_map(map, kit)
	view.terrain.show_objectives({})
	_place_mechs(map)
	await _aim_camera(map, cam)


func _aim_camera(map: BattleMap, cam: String) -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in map.cells():
		var p := map.grid.to_world(c)
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var mid := (lo + hi) * 0.5
	var span := maxf(hi.x - lo.x, hi.z - lo.z)
	var t := view.tactical
	view.terrain.set_grid_visible(true)
	if "," in cam:
		# Custom camera: "x,z,distance,pitch,yaw[,grid]".
		var v := cam.split(",")
		t.look_at_point(Vector3(float(v[0]), 1.0, float(v[1])), float(v[2]))
		t.pitch = float(v[3])
		t.yaw = float(v[4])
		view.terrain.set_grid_visible(v.size() < 6 or v[5] != "nogrid")
		cam = "custom"
	match cam:
		"custom":
			pass
		"close":
			t.look_at_point(mid + Vector3(-span * 0.12, 1.0, span * 0.08), 11.0)
			t.pitch = -30
			t.yaw = -20
		"vista":
			view.terrain.set_grid_visible(false)
			t.look_at_point(mid + Vector3(0, 3.0, 0), span * 0.55)
			t.pitch = -8
			t.yaw = 30
		"break":
			# Knock down the destructible wall and watch it fall apart.
			var newer := BattleMap.from_dict(map.to_dict())
			var n := 0
			for c in newer.cells():
				if newer.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE):
					newer.column(c).ground = 0
					# The rules decide what's left: here half rubble (difficult), half clear.
					newer.column(c).tags = PackedStringArray(["difficult"] if n % 2 == 0 else [])
					n += 1
			view.map = newer
			view.terrain.sync_map(newer)
			# Aim at the first thing that broke (the showcase wall, or a city building).
			var focus := mid + Vector3(-4.0, 0.5, 2.0)
			for c in newer.cells():
				if map.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE) and map.column(c).ground >= 2:
					focus = map.grid.to_world(c) + Vector3.UP * 1.0
					break
			t.look_at_point(focus, 9.0)
			t.pitch = -24
			t.yaw = -10
			t.snap()
			var wait := int(OS.get_environment("LANCER_BREAK_FRAMES")) if OS.get_environment("LANCER_BREAK_FRAMES") != "" else 18
			for i in range(wait):
				await get_tree().process_frame
			return
		"eye":
			# Cockpit view: a camera at mech-eye height (about 1.1 units) looking across.
			var eye := Camera3D.new()
			eye.fov = 75.0
			eye.near = 0.02
			eye.far = 400.0
			add_child(eye)
			var c0: Vector2i = map.cells()[0]
			var best := c0
			for cc in map.cells():
				var pw := map.grid.to_world(cc)
				if pw.distance_to(mid + Vector3(-span * 0.15, 0, span * 0.2)) < map.grid.to_world(best).distance_to(mid + Vector3(-span * 0.15, 0, span * 0.2)) and map.column(cc).tags.is_empty():
					best = cc
			var p := map.grid.to_world(best) + Vector3.UP * (map.ground_height(best) + 1.1)
			eye.position = p
			eye.look_at(p + Vector3(0.6, -0.12, -1.0), Vector3.UP)
			eye.current = true
			view.terrain.set_grid_visible(false)
			await get_tree().process_frame
			return
		"top":
			t.look_at_point(mid, span * 1.25)
			t.pitch = -80
			t.yaw = 0
		_:
			t.look_at_point(mid + Vector3(0, 1.0, span * 0.05), span * 1.0)
			t.pitch = -42
			t.yaw = -20
	t.snap()
	await get_tree().process_frame


## A few mechs near the middle, standing on the ground, for scale.
func _place_mechs(map: BattleMap) -> void:
	view.clear_units()
	var cells := map.cells()
	cells.sort()
	var mid := cells[cells.size() / 2]
	var picks := [["mf_standard_pattern_i_everest", "players", Vector2i(0, 0)], ["mf_blackbeard", "players", Vector2i(2, 1)],
		["mf_sherman", "enemies", Vector2i(-3, 2)]]
	for i in range(picks.size()):
		var p: Array = picks[i]
		var c: Vector2i = mid + p[2]
		if not map.has_cell(c) or map.column(c).has_tag("water") or map.column(c).has_tag("toxic"):
			continue
		var frame := content.frame(p[0])
		var u := {"id": "m%d" % i, "name": str(frame.get("name", "")), "side": p[1], "content_id": p[0],
			"size": float(frame.get("stats", {}).get("size", 1)), "cell": [c.x, c.y], "level": map.ground_height(c),
			"loadout": {"mounts": [], "systems": []}, "statuses": {}}
		view.add_unit(u)



# --- Hub towns (WorldKits) ---------------------------------------------------------------

var _hub_root: Node3D


## A small on-foot town laid out like the story hubs (HubLayout), dressed with WorldKits.
## Tag: hub-<culture>[~time] (story or map culture id; time of day), views wide or close.
func _hub(culture: String, cam: String, period: String = "day") -> void:
	view.visible = false
	if _hub_root:
		_hub_root.queue_free()
	_hub_root = Node3D.new()
	add_child(_hub_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	env.environment = e
	_hub_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	_hub_root.add_child(sun)
	view.world_env.environment = e
	WorldKits.apply_hub_environment(culture, e, sun, period)
	var colors := WorldKits.hub_ground(culture)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	ground.material_override = MeshKit.paint(colors["ground"], 0.0, 0.95, 0.3)
	_hub_root.add_child(ground)
	MeshKit.part(_hub_root, MeshKit.cylinder(8.5, 0.06, 28), MeshKit.paint(colors["pave"], 0.05, 0.9, 0.3), Vector3(0, 0.03, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for spot: Dictionary in HubLayout.spots("town", rng):
		var pos := Vector3(float(spot["pos"][0]), 0, float(spot["pos"][1]))
		var to := Vector3(float(spot["door"][0]), 0, float(spot["door"][1]))
		if str(spot["kind"]) != "plaza":
			var road := MeshKit.part(_hub_root, MeshKit.chamfer_box(Vector3(2.6, 0.05, to.length()), 0.01), MeshKit.paint(colors["pave"], 0.05, 0.9, 0.3), to * 0.5 + Vector3(0, 0.025, 0))
			road.rotation.y = atan2(to.x, to.z)
		var b := WorldKits.build_hub_building(culture, spot, 3)
		b.position = pos
		b.rotation.y = atan2(-pos.x, -pos.z) if pos.length() > 0.1 else 0.0
		_hub_root.add_child(b)
	var center := WorldKits.build_hub_centerpiece(culture, 1)
	_hub_root.add_child(center)
	var kinds := WorldKits.hub_prop_kinds(culture)
	for i in range(18):
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(9.5, 13.0) if i % 3 else 8.0
		var prop := WorldKits.build_hub_prop(culture, "lamp" if i % 3 == 0 else kinds[i % kinds.size()], i)
		prop.position = Vector3(cos(a) * r, 0, sin(a) * r)
		prop.rotation.y = rng.randf() * TAU
		_hub_root.add_child(prop)
	# People for scale (1.8 m capsules).
	for i in range(4):
		var p := MeshKit.part(_hub_root, MeshKit.cylinder(0.25, 1.8, 10), MeshKit.paint(Color(0.3, 0.4, 0.55), 0.1, 0.7, 0.0), Vector3(-2.0 + i * 1.3, 0.9, 5.5))
		p.name = "Person"
	WorldKits.set_hub_time(_hub_root, period)
	var c3 := Camera3D.new()
	c3.fov = 50
	_hub_root.add_child(c3)
	if cam == "close":
		c3.position = Vector3(2, 4.5, 16)
		c3.look_at(Vector3(0, 2.0, 0))
	else:
		c3.position = Vector3(0, 22, 30)
		c3.look_at(Vector3(0, 0, 0))
	c3.current = true
	await get_tree().process_frame
