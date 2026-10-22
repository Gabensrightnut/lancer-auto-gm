extends TestCase
## Battlefield looks follow the rules terrain: what looks like cover, an obstacle or
## difficult/dangerous ground is exactly what the map data says, and decoration stays flat.

## Instance groups that are decoration on open ground: never taller than WorldDressing.FLAT.
const FLAT_GROUPS := ["Grass", "Flowers", "Pebbles", "Rough", "Rubble", "Rebar"]


func _build(map: BattleMap, kit: String) -> TerrainRenderer:
	var t := TerrainRenderer.new()
	t.build(map, kit)
	return t


func _showcase(shape: GridLayout.Shape) -> BattleMap:
	return DemoMap.build_showcase(shape)


## Every MultiMesh instance in groups whose name starts with `prefix`: [transform, mesh].
func _instances(t: TerrainRenderer, prefix: String) -> Array:
	var out: Array = []
	for n in t.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := n as MultiMeshInstance3D
		if not String(mmi.name).begins_with(prefix):
			continue
		for xf: Transform3D in mmi.get_meta("xforms", []):
			out.append([xf, mmi.multimesh.mesh])
	return out


func _free(t: TerrainRenderer) -> void:
	t.free()


func test_every_landscape_and_culture_resolves() -> void:
	var lands := WorldStyle.landscapes()
	expect(lands.size() >= 5, "several landscapes")
	for land: String in lands:
		var kits: Array = [land]
		for c: String in WorldStyle.cultures():
			kits.append("%s/%s" % [land, c])
		for kit: String in kits:
			var s := WorldStyle.resolve(kit)
			for key: String in ["ground", "sky", "light", "flora", "horizon"]:
				expect(s.has(key), "%s has %s" % [kit, key])
			expect_eq(s["kit"], kit)
	expect_eq(WorldStyle.resolve("urban_ruins")["kit"], "city/ruins", "old kit names still work")


func test_woods_only_on_soft_cover() -> void:
	for shape: GridLayout.Shape in [GridLayout.Shape.HEX, GridLayout.Shape.SQUARE]:
		var map := _showcase(shape)
		var t := _build(map, "grassy_hills")
		var trees := _instances(t, "Woods")
		expect(trees.size() > 0, "the soft cover patch has trees")
		var covered := {}
		for e: Array in trees:
			var cell := map.grid.from_world((e[0] as Transform3D).origin)
			expect(map.has_cell(cell) and map.column(cell).has_tag(Sight.TAG_SOFT_COVER), "tree at %s stands in soft cover" % cell)
			covered[cell] = true
		for c in map.cells():
			if map.column(c).has_tag(Sight.TAG_SOFT_COVER):
				expect(covered.has(c), "soft cover cell %s has foliage" % c)
		_free(t)


func test_decoration_stays_flat() -> void:
	var map := _showcase(GridLayout.Shape.HEX)
	for kit: String in ["grassy_hills", "desert_mesas", "tundra", "alien_wilds", "city/ruins"]:
		var t := _build(map, kit)
		for prefix: String in FLAT_GROUPS:
			for e: Array in _instances(t, prefix):
				var xf: Transform3D = e[0]
				var aabb: AABB = xf * (e[1] as Mesh).get_aabb()
				var cell := map.grid.from_world(xf.origin)
				var floor_y := t.floor_y(cell) if map.has_cell(cell) else 0.0
				expect(aabb.end.y - floor_y <= WorldDressing.FLAT + 0.02, "%s %s at %s is %.2f tall" % [kit, prefix, cell, aabb.end.y - floor_y])
		_free(t)


func test_rough_clutter_only_on_difficult_ground() -> void:
	var map := _showcase(GridLayout.Shape.HEX)
	var t := _build(map, "grassy_hills")
	for prefix: String in ["Rough", "Rubble", "Rebar"]:
		for e: Array in _instances(t, prefix):
			var cell := map.grid.from_world((e[0] as Transform3D).origin)
			expect(map.column(cell).has_tag(BattleMap.TAG_DIFFICULT), "%s at %s is on difficult ground" % [prefix, cell])
	_free(t)


func test_hazards_chasms_and_liquids_follow_tags() -> void:
	var map := _showcase(GridLayout.Shape.HEX)
	var t := _build(map, "grassy_hills")
	expect(t.find_child("Flames", true, false) != null, "dangerous ground burns")
	expect(t.find_child("Liquid_water", true, false) != null, "the river has water")
	for c in map.cells():
		var col := map.column(c)
		if col.has_tag(BattleMap.TAG_IMPASSABLE) and col.ground == 0:
			expect(t.is_chasm(c) and t.floor_y(c) < -1.0, "impassable ground at %s is a chasm" % c)
		if col.has_tag(BattleMap.TAG_DANGEROUS):
			expect_eq(t.surface(c), TerrainRenderer.KIND_HAZARD, "dangerous %s glows" % c)
		elif col.has_tag(BattleMap.TAG_DIFFICULT) and t.liquid_of(c) == "" and not col.has_tag(Sight.TAG_SOFT_COVER):
			expect_eq(t.surface(c), TerrainRenderer.KIND_ROUGH, "difficult %s looks rough" % c)
		if col.ground == 0 and col.tags.is_empty():
			expect_eq(t.surface(c), TerrainRenderer.KIND_GROUND, "open ground %s looks open" % c)
	_free(t)


func test_untagged_map_has_no_cover_looks() -> void:
	# A flat board with no tags: no trees, rough clutter, flames or chasms on it.
	var map := BattleMap.flat(GridLayout.Shape.SQUARE, 12, 12)
	var t := _build(map, "grassy_hills")
	expect(_instances(t, "Woods").is_empty(), "no woods")
	expect(_instances(t, "Rough").is_empty(), "no rough ground")
	expect(t.find_child("Flames", true, false) == null, "nothing burns")
	_free(t)


func test_hub_kits_fit_their_footprint() -> void:
	var cultures := ["", "frontier_colony", "medieval_tech", "old_west", "retrofuturistic", "cyberpunk", "east_asian", "union_core", "medieval", "retro", "union"]
	for c: String in cultures:
		expect(WorldKits.culture_id(c) == "" or WorldStyle.cultures().has(WorldKits.culture_id(c)), "%s maps to a known culture" % c)
		for kind: String in ["bar", "office", "market", "workshop", "printer"]:
			var spot := {"kind": kind, "size": [8.0, 6.0, 4.5]}
			var b := WorldKits.build_hub_building(c, spot, 5)
			var box := AABB()
			var first := true
			for m in b.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				var xf := b.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _local(b, mi)
				var bb := xf * mi.mesh.get_aabb()
				box = bb if first else box.merge(bb)
				first = false
			expect(box.position.x >= -4.0 - WorldKits.ROOF_OVERHANG - 0.05 and box.end.x <= 4.0 + WorldKits.ROOF_OVERHANG + 0.05, "%s %s width %s" % [c, kind, box])
			expect(box.position.z >= -3.0 - WorldKits.ROOF_OVERHANG - 0.05, "%s %s back %s" % [c, kind, box])
			b.free()
		for kind: String in WorldKits.hub_prop_kinds(c):
			var p := WorldKits.build_hub_prop(c, kind, 1)
			expect(p.get_child_count() > 0, "%s %s prop has parts" % [c, kind])
			p.free()
		var cp := WorldKits.build_hub_centerpiece(c, 1)
		expect(cp.get_child_count() > 0, "%s centerpiece" % c)
		cp.free()


## A child's transform relative to `root` without being in the scene tree.
func _local(root: Node3D, n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func test_destroyed_terrain_leaves_what_the_rules_say() -> void:
	var map := _showcase(GridLayout.Shape.HEX)
	var t := _build(map, "grassy_hills")
	var newer := BattleMap.from_dict(map.to_dict())
	var cleared: Array[Vector2i] = []
	var rough: Array[Vector2i] = []
	for c in newer.cells():
		if newer.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE):
			newer.column(c).ground = 0
			if cleared.size() <= rough.size():
				newer.column(c).tags = PackedStringArray()
				cleared.append(c)
			else:
				newer.column(c).tags = PackedStringArray([BattleMap.TAG_DIFFICULT])
				rough.append(c)
	var broke := t.sync_map(newer)
	expect_eq(broke.size(), cleared.size() + rough.size(), "every lowered destructible column breaks")
	for c in cleared:
		expect_eq(t.surface(c), TerrainRenderer.KIND_GROUND, "cleared %s is open ground" % c)
	for c in rough:
		expect_eq(t.surface(c), TerrainRenderer.KIND_ROUGH, "rubble %s is rough ground" % c)
	for e: Array in _instances(t, "Rough") + _instances(t, "Rubble"):
		var cell := newer.grid.from_world((e[0] as Transform3D).origin)
		expect(newer.column(cell).has_tag(BattleMap.TAG_DIFFICULT), "rubble only on difficult ground (%s)" % cell)
	expect(not _instances(t, "Debris").is_empty(), "cleared spots keep flat debris")
	for e: Array in _instances(t, "Debris"):
		var xf: Transform3D = e[0]
		expect((xf * (e[1] as Mesh).get_aabb()).end.y - xf.origin.y <= WorldDressing.FLAT, "debris stays flat")
	# A second sync with no change breaks nothing.
	expect(t.sync_map(newer).is_empty(), "nothing more to break")
	_free(t)


func test_weather_is_look_only() -> void:
	for w: String in WorldStyle.weathers():
		var s := WorldStyle.resolve("grassy_hills+" + w)
		expect(s.has("light") and s.has("sky"), "%s resolves" % w)
		if w != "clear":
			expect_eq(s["weather"], w)
	# Same map with or without weather: same surfaces (no rules change).
	var map := _showcase(GridLayout.Shape.SQUARE)
	var a := _build(map, "grassy_hills")
	var b := _build(map, "grassy_hills+storm")
	for c in map.cells():
		expect_eq(a.surface(c), b.surface(c))
	_free(a)
	_free(b)


func test_destroyed_buildings_come_down_to_the_new_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var wr := RandomNumberGenerator.new()
	wr.seed = 3
	var bf := MissionGenerator.battlefield(rng, wr, "sitrep_standardcombat", 24, 22, GridLayout.Shape.HEX, "city", "ruins")
	var map: BattleMap = bf["map"]
	var t := _build(map, "city/ruins")
	var newer := BattleMap.from_dict(map.to_dict())
	var knocked: Array[Vector2i] = []
	for c in newer.cells():
		if t.structure_cells.has(c) and newer.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE) and knocked.size() < 6:
			newer.column(c).ground = 0
			newer.column(c).tags = PackedStringArray([BattleMap.TAG_DIFFICULT])
			knocked.append(c)
	expect(knocked.size() > 0, "the city has breakable buildings")
	var broke := t.sync_map(newer)
	expect_eq(broke.size(), knocked.size(), "each knocked-down building cell breaks")
	for c in knocked:
		expect(not t.structure_cells.has(c), "%s is no longer drawn as a building" % c)
		expect_eq(t.surface(c), TerrainRenderer.KIND_ROUGH, "%s is rubble (difficult)" % c)
	_free(t)


func test_objective_markers_replace_and_clear() -> void:
	var map := BattleMap.flat(GridLayout.Shape.HEX, 12, 10)
	var t := _build(map, "grassy_hills")
	var zones := {"zone_1": [[2, 2], [3, 2]], "zone_2": [[6, 6]]}
	t.show_objectives(zones, {})
	t.show_objectives(zones, {})
	var count := 0
	for c in t.get_children():
		if String(c.name).begins_with("Objectives"):
			count += 1
	expect_eq(count, 1, "showing objectives again replaces the old markers")
	t.show_objectives({})
	expect(t.get_node_or_null("Objectives") == null, "empty zones clear the markers")
	_free(t)


func test_every_place_has_its_own_look() -> void:
	var a := WorldStyle.resolve("city/retro+rain#5")
	var b := WorldStyle.resolve("city/retro+rain#6")
	var again := WorldStyle.resolve("city/retro+rain#5")
	expect_eq(a["kit"], "city/retro+rain#5", "the kit keeps its place seed")
	expect_eq(a["light"]["sun_yaw"], again["light"]["sun_yaw"], "same place, same look")
	expect(a["light"]["sun_yaw"] != b["light"]["sun_yaw"] or a["architecture"]["walls"] != b["architecture"]["walls"], "another place looks different")
	expect_eq(WorldStyle.resolve("city/retro")["kit"], "city/retro", "no seed, the plain kit")


func test_hub_towns_follow_the_clock() -> void:
	var day := WorldStyle.resolve("desert_mesas/old_west")
	var night := WorldStyle.resolve("desert_mesas/old_west")
	WorldKits.time_of_day(day, "day")
	WorldKits.time_of_day(night, "night")
	expect(float(night["light"]["sun_energy"]) < float(day["light"]["sun_energy"]) * 0.3, "night is dark")
	var neon := WorldStyle.resolve("city/cyberpunk")
	var neon_night_sun := float(neon["light"]["sun_energy"])
	WorldKits.time_of_day(neon, "night")
	expect_eq(float(neon["light"]["sun_energy"]), neon_night_sun, "the neon city's own look is its night")
	# Lamps burn only after dark; more windows are lit at night.
	var town := Node3D.new()
	var lamp := WorldKits.build_hub_prop("medieval", "lamp", 1)
	town.add_child(lamp)
	town.add_child(WorldKits.build_hub_building("medieval", {"kind": "bar", "size": [8.0, 6.0, 4.0]}, 1))
	var lights: Array[Light3D] = []
	var walls: Array[ShaderMaterial] = []
	var stack: Array[Node] = [town]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Light3D and n.has_meta(WorldKits.NIGHT_LIGHT):
			lights.append(n)
		if n is MeshInstance3D and n.name == "Walls":
			walls.append((n as MeshInstance3D).material_override)
		stack.append_array(n.get_children())
	expect(not lights.is_empty() and not walls.is_empty(), "lamps and walls found")
	WorldKits.set_hub_time(town, "day")
	expect(lights.all(func(l: Light3D) -> bool: return not l.visible), "lamps off by day")
	var lit_day := float(walls[0].get_shader_parameter("lit"))
	WorldKits.set_hub_time(town, "night")
	expect(lights.all(func(l: Light3D) -> bool: return l.visible), "lamps on at night")
	expect(float(walls[0].get_shader_parameter("lit")) > lit_day, "more windows lit at night")
	town.free()
