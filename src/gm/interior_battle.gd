class_name InteriorBattle
extends RefCounted
## A fight inside a building, on foot (pilots and soldier squads): the battle map is built from
## the same interior layout the squad walked through in the hub (Interiors.layout: same kind,
## culture and seed, so the saloon you walked into is the saloon you fight in), at SPACE_M meters
## per space. PROVISIONAL table ruling (docs/RULES_TODO.md "Pilot-scale spaces"): the book uses
## the same grid rules for pilots (Size 1/2) as for mechs but fixes no real-world scale.
##
## Terrain follows the book's rules: walls are terrain two levels high (hard cover, block line
## of sight; breakable, Core p.68), counters, tables and crates one level (cover by height),
## doors open ground marked with their lock level (`lock_N`, Interiors' 0-2), the street out in
## front where the squad deploys, the far rooms where the defenders start. Ground floor only
## (stairs up are marked `stairs`). Look tags carry the interior's ids: `room_<id>`,
## `door_<id>`, `container_<id>`.

const SPACE_M := 1.5   # meters per space at pilot scale (the one place this lives)
const STREET := 6      # rows of street in front of the building (the squad's side)
const YARD := 2        # rows behind it
const MARGIN := 2      # columns either side


## {map, layout (SitrepLayout-shaped: deployment, zones, clear, first_side, sitrep, band),
##  interior (the Interiors layout), size [w, h]}
static func build(kind: String, culture: String, seed_value: int, shape: GridLayout.Shape, sitrep_id: String = "sitrep_standardcombat") -> Dictionary:
	var lay := Interiors.layout(kind, culture, seed_value)
	if lay.is_empty():
		return {}
	var size: Array = lay["size"]
	var bw := int(ceil(float(size[0]) / SPACE_M))
	var bd := int(ceil(float(size[1]) / SPACE_M))
	var w := bw + 2 * MARGIN
	var h := bd + STREET + YARD
	var map := BattleMap.flat(shape, w, h)
	var x0 := MARGIN            # first column of the building
	var r0 := YARD              # first row of the building (back wall side)
	# Meters (interior space: origin at the building's center, +z toward the street) per cell.
	var meters := func(c: int, r: int) -> Vector2:
		return Vector2((c - x0 + 0.5) * SPACE_M - float(size[0]) * 0.5, (r - r0 + 0.5) * SPACE_M - float(size[1]) * 0.5)
	var rooms: Dictionary = lay["rooms"]
	var deploy_players: Array = []
	var deploy_enemies: Array = []
	var far_room := _far_room(lay)
	for r in range(h):
		for c in range(w):
			var cell := SitrepLayout.cell_of(c, r, shape)
			if not map.has_cell(cell):
				continue
			var col := map.column(cell)
			var m: Vector2 = meters.call(c, r)
			var inside := absf(m.x) <= float(size[0]) * 0.5 and absf(m.y) <= float(size[1]) * 0.5
			if not inside:
				# The street in front (where the squad deploys), yard and alleys elsewhere.
				col.tags = PackedStringArray(["road", "road_x"] if r >= r0 + bd + 1 and r <= r0 + bd + 3 else ["lot"])
				if r >= h - 2 and c >= MARGIN and c < w - MARGIN:
					deploy_players.append([cell.x, cell.y])
				continue
			var room := _room_at(rooms, m)
			col.tags = PackedStringArray(["floor", "room_" + room] if room != "" else ["floor"])
			if _on_wall(lay, m):
				col.ground = 2
				col.tags = PackedStringArray(["wall", BattleMap.TAG_DESTRUCTIBLE, "interior_wall"])
				continue
			if room == far_room:
				deploy_enemies.append([cell.x, cell.y])
	# Doors, furniture and containers from the layout (ground floor only).
	var to_cell := func(p: Array) -> Vector2i:
		var c := int(floor((float(p[0]) + float(size[0]) * 0.5) / SPACE_M)) + x0
		var r := int(floor((float(p[2]) + float(size[1]) * 0.5) / SPACE_M)) + r0
		return SitrepLayout.cell_of(clampi(c, 0, w - 1), clampi(r, 0, h - 1), shape)
	for d: Dictionary in lay["doors"]:
		if float(d["pos"][1]) > 0.1:
			continue
		var cell: Vector2i = to_cell.call(d["pos"])
		if map.has_cell(cell):
			var col := map.column(cell)
			col.ground = 0
			col.tags = PackedStringArray(["door", "door_" + str(d["id"]), "lock_%d" % int(d["lock"])])
	for f: Dictionary in lay["furniture"]:
		if float(f["pos"][1]) > 0.1:
			continue
		var cell: Vector2i = to_cell.call(f["pos"])
		if not map.has_cell(cell) or map.column(cell).has_tag("door") or map.column(cell).has_tag("wall"):
			continue
		var col := map.column(cell)
		if float(f["size"][1]) >= 0.7:  # waist-high or taller: cover by height
			col.ground = 1
			col.tags.append_array(["furniture", str(f["kind"]), BattleMap.TAG_DESTRUCTIBLE])
	for k: Dictionary in lay["containers"]:
		if float(k["pos"][1]) > 0.1:
			continue
		var cell: Vector2i = to_cell.call(k["pos"])
		if map.has_cell(cell) and not map.column(cell).has_tag("wall"):
			map.column(cell).tags.append("container_" + str(k["id"]))
	for s: Dictionary in lay["stairs"]:
		var cell: Vector2i = to_cell.call([float(s["start"][0]), 0.0, float(s["start"][1])])
		if map.has_cell(cell):
			map.column(cell).tags.append("stairs")
	deploy_enemies = deploy_enemies.filter(func(p: Array) -> bool: return map.ground_height(Vector2i(p[0], p[1])) == 0)
	var layout := {"deployment": {Mission.PLAYERS: deploy_players, Mission.ENEMIES: deploy_enemies}, "zones": {}, "clear": [],
		"first_side": "", "sitrep": sitrep_id, "band": [0, h]}
	return {"map": map, "layout": layout, "interior": lay, "size": [w, h]}


## The ground-floor room deepest inside (farthest from the street door): where defenders start.
static func _far_room(lay: Dictionary) -> String:
	var best := ""
	var best_z := INF
	for id: String in lay["rooms"]:
		var r: Dictionary = lay["rooms"][id]
		if int(r["floor"]) != 0 or str(r.get("use", "")) in ["stairs", "corridor"]:
			continue
		var rc: Array = r["rect"]
		var z := float(rc[1]) + float(rc[3]) * 0.5
		if z < best_z:
			best_z = z
			best = id
	return best


static func _room_at(rooms: Dictionary, m: Vector2) -> String:
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		if int(r["floor"]) != 0:
			continue
		var rc: Array = r["rect"]
		if Rect2(float(rc[0]), float(rc[1]), float(rc[2]), float(rc[3])).has_point(m):
			return id
	return ""


## True if a wall of any ground-floor room runs through this space (outside its doorways).
static func _on_wall(lay: Dictionary, m: Vector2) -> bool:
	var half := SPACE_M * 0.5
	for r: Dictionary in (lay["rooms"] as Dictionary).values():
		if int(r["floor"]) != 0:
			continue
		var rc: Array = r["rect"]
		var x0 := float(rc[0])
		var z0 := float(rc[1])
		var x1 := x0 + float(rc[2])
		var z1 := z0 + float(rc[3])
		var near_x := (absf(m.y - z0) < half or absf(m.y - z1) < half) and m.x > x0 - half and m.x < x1 + half
		var near_z := (absf(m.x - x0) < half or absf(m.x - x1) < half) and m.y > z0 - half and m.y < z1 + half
		if near_x or near_z:
			for d: Dictionary in lay["doors"]:
				var dp: Array = d["pos"]
				if float(dp[1]) < 0.1 and Vector2(float(dp[0]) - m.x, float(dp[2]) - m.y).length() < float(d["width"]) * 0.5 + half * 0.5:
					return false
			return true
	return false
