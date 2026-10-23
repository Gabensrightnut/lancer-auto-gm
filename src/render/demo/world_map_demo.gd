extends Node3D
## World map demo (tools/screenshot.gd stage "map"): a made-up region in net's region shape
## (WorldMapSession), the squad walking toward a town, an ambush springing from the woods.

var view: WorldMapView


static func sample_region() -> Dictionary:
	var tiles := {}
	var w := 24
	var h := 18
	for y in range(h):
		for x in range(w):
			var n := sin(x * 0.45) * cos(y * 0.38) + sin((x + y) * 0.21) * 0.6
			var t := "plains"
			if x < 3 or y > 15:
				t = "sea"
			elif x < 4:
				t = "sand"
			elif n > 0.95:
				t = "mountain"
			elif n > 0.55:
				t = "hills"
			elif n < -0.7:
				t = "lake"
			elif n < -0.25:
				t = "forest"
			elif x > 17 and y < 6:
				t = "desert"
			if y == 9 and x >= 4:
				t = "road"
			tiles["%d,%d" % [x, y]] = {"terrain": t, "cost": 1.0, "mech": t not in ["sea", "lake"], "foot": t not in ["sea", "lake"]}
	return {"id": "demo", "size": [w, h], "tiles": tiles, "sites": [
		{"id": "town", "kind": "town", "at": [14, 8], "name": "Hercynia Crossing"},
		{"id": "job", "kind": "job", "at": [19, 12], "name": "Salvage job"},
		{"id": "post", "kind": "outpost", "at": [8, 4], "name": "Relay outpost"},
		{"id": "camp", "kind": "safe", "at": [6, 11], "name": "Camp"}]}


func _ready() -> void:
	view = WorldMapView.new()
	var db := ContentDB.new()
	db.load_all()
	view.content = db
	add_child(view)
	view.load_region(sample_region())
	view.local_seat = "a"
	view.show_view({"squad": {"a": {"at": [10.0, 9.0], "on": "mech", "in_area": ""}, "b": {"at": [9.2, 9.6], "on": "mech", "in_area": "", "frame": "mf_goblin"}}})
	view.camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	add_child(env)


func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["map"]


func screenshot_stage(_tag: String) -> void:
	view.show_view({"squad": {"a": {"at": [12.0, 9.0], "on": "mech", "in_area": ""}, "b": {"at": [11.2, 9.6], "on": "mech", "in_area": "", "frame": "mf_goblin"}}})
	view.spring_ambush([{"id": "x1", "content_id": "mf_goblin", "at": [13, 6]}, {"id": "x2", "content_id": "mf_standard_pattern_i_everest", "at": [15, 7]}], [12, 9])
	await get_tree().create_timer(1.1).timeout
