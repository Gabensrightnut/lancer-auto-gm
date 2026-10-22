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
