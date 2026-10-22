extends Node3D
## Battlefield preview: builds a board in one world style with a few mechs for scale, so
## terrain and scenery can be checked by screenshot. Tags are "<map>[:<kit>][@<view>]":
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/world_preview.tscn "out_%s.jpg" 3 hills urban@close
## Maps: hills, urban, alien, gen<seed> (MissionGenerator). Views: wide (default), close,
## vista (low, no grid), top.

var content: ContentDB
var view: BattleView
var shape := GridLayout.Shape.HEX


func _ready() -> void:
	content = ContentDB.new()
	content.load_all()
	view = BattleView.new()
	view.content = content
	add_child(view)


func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["hills"]


func screenshot_stage(tag: String) -> void:
	var at := tag.split("@")
	var spec := at[0].split(":")
	var cam := at[1] if at.size() > 1 else "wide"
	shape = GridLayout.Shape.SQUARE if spec[0].ends_with("_sq") else GridLayout.Shape.HEX
	var map_name := spec[0].trim_suffix("_sq")
	var map: BattleMap
	var kit := ""
	if map_name.begins_with("gen"):
		var g := MissionGenerator.generate(int(map_name.trim_prefix("gen")), {"db": content, "shape": "square" if shape == GridLayout.Shape.SQUARE else "hex"})
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
			_:
				map = DemoMap.build(shape)
				kit = "urban_ruins"
	if spec.size() > 1:
		kit = spec[1]
	view.set_map(map, kit)
	_place_mechs(map)
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
	match cam:
		"close":
			t.look_at_point(mid + Vector3(-span * 0.12, 1.0, span * 0.08), 11.0)
			t.pitch = -30
			t.yaw = -20
		"vista":
			view.terrain.set_grid_visible(false)
			t.look_at_point(mid + Vector3(0, 3.0, 0), span * 0.55)
			t.pitch = -8
			t.yaw = 30
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
