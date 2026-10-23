class_name RegionMap
extends RefCounted
## A world's region as a map you walk around on (DESIGN.md "Exploring vs. fighting": the
## Final Fantasy VII/X style world map): a grid of terrain tiles with travel times, roads
## between the places on it, and the places themselves. Net builds the scene from this; every
## tile links to MissionGenerator.area() so stepping in gives the matching area, and
## neighbouring areas share their edge. The region seed fixes everything; the look reads from
## the region profile (landscape, culture, weather).
##
##   RegionMap.build(region, opts) -> {
##     seed, size [cols, rows], landscape, culture,
##     tiles: [[terrain, ...], ...] (row-major: tiles[y][x]),
##     travel: {terrain: hours to cross a tile on foot or in a mech},
##     mech_blocked: [terrain, ...] (a mech needs a dropship or vehicle to cross these),
##     places: [{id, kind, name, at [x, y], place (for area()), safe_point, repair?}],
##     roads: [[x, y], ...], start: [x, y] }
##   RegionMap.area_opts(region_map, x, y) -> opts for MissionGenerator.area()
## opts: "start": true for the campaign's first region (the starting town has a farm, a wreck
## site, an outpost and a landmark within a couple of tiles for the first jobs), "size" [c, r].

const TERRAINS := ["road", "plains", "hills", "forest", "swamp", "mountains", "water", "city"]
## Hours to cross one tile (our pacing: the book keeps no travel clock on a world).
const TRAVEL := {"road": 0.5, "plains": 1.0, "city": 0.75, "hills": 1.5, "forest": 1.5, "swamp": 2.5, "mountains": 4.0, "water": 0.0}
const MECH_BLOCKED := ["water"]
## Area place kind for each tile's place (MissionGenerator.area "place").
const AREA_PLACE := {"town": "town", "outpost": "outpost", "farm": "farm", "port": "port", "pad": "pad",
	"job_site": "camp", "wreck": "wreck", "landmark": "landmark", "safe_point": "camp", "mine": "mine", "ruins": "ruins", "relay": "relay"}

## Terrain weights by landscape: what the open country is mostly made of.
const LAND := {
	"grassy_hills": {"plains": 5, "hills": 3, "forest": 3, "water": 1},
	"autumn_forest": {"plains": 3, "hills": 2, "forest": 5, "water": 1},
	"desert_mesas": {"plains": 5, "hills": 3, "mountains": 2},
	"salt_flats": {"plains": 8, "hills": 1, "mountains": 1},
	"tundra": {"plains": 5, "hills": 3, "mountains": 2, "water": 1},
	"jungle": {"forest": 6, "swamp": 2, "hills": 2, "water": 1},
	"toxic_swamp": {"swamp": 5, "forest": 2, "plains": 2, "water": 2},
	"toxic_marsh": {"swamp": 5, "plains": 3, "water": 2},
	"volcanic": {"plains": 3, "hills": 3, "mountains": 4},
	"molten_world": {"plains": 3, "mountains": 5, "hills": 2},
	"alien_wilds": {"plains": 3, "forest": 4, "hills": 3},
	"crystal_fields": {"plains": 4, "hills": 4, "mountains": 2},
	"moon": {"plains": 5, "hills": 3, "mountains": 2},
	"asteroid": {"plains": 3, "hills": 3, "mountains": 4},
	"ocean": {"water": 8, "plains": 1, "hills": 1},
	"city": {"city": 6, "plains": 2, "hills": 1},
}


static func build(region: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var size: Array = opts.get("size", [24, 18])
	var cols := int(size[0])
	var rows := int(size[1])
	var seed_value := int(region.get("seed", 1))
	var landscape := str(region.get("landscape", "grassy_hills"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "region_map"])
	# Terrain: noise over the landscape's mix.
	var mix: Dictionary = LAND.get(landscape, LAND["grassy_hills"])
	var order: Array = mix.keys()
	var total := 0
	for k: String in order:
		total += int(mix[k])
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.11
	var tiles: Array = []
	for y in range(rows):
		var row: Array = []
		for x in range(cols):
			var v := (noise.get_noise_2d(x, y) + 1.0) * 0.5 * total
			var t: String = order[order.size() - 1]
			var acc := 0.0
			for k: String in order:
				acc += float(mix[k])
				if v <= acc:
					t = k
					break
			row.append(t)
		tiles.append(row)
	# Places: the town in the middle, others round it on land.
	var places: Array = []
	var start := Vector2i(cols / 2, rows / 2)
	_set_tile(tiles, start, "city" if landscape == "city" else "plains")
	places.append({"id": "town", "kind": "town", "name": str(region.get("name", "the town")), "at": [start.x, start.y], "safe_point": true, "repair": "bay"})
	var wanted: Array = ["farm", "wreck", "outpost", "landmark"] if bool(opts.get("start", false)) else []
	wanted.append_array(["outpost", "job_site", "mine" if mix.has("hills") or mix.has("mountains") else "job_site", "ruins", "relay", "landmark", "port" if mix.has("water") else "pad", "safe_point"])
	var taken := {start: true}
	for i in range(wanted.size()):
		var kind: String = wanted[i]
		# The starting town's first places are close (walking distance: 2-3 tiles); the rest spread out.
		var near := bool(opts.get("start", false)) and i < 4
		var at := _free_spot(rng, tiles, taken, start, 2 if near else 4, 3 if near else maxi(cols, rows) / 2)
		if at == Vector2i(-1, -1):
			continue
		taken[at] = true
		_set_tile(tiles, at, "plains" if _tile(tiles, at) in ["water", "mountains"] else _tile(tiles, at))
		var p := {"id": "%s_%d" % [kind, i], "kind": kind, "name": kind.replace("_", " "), "at": [at.x, at.y],
			"safe_point": kind in ["outpost", "safe_point", "pad"], "repair": "rig" if kind in ["outpost", "safe_point", "pad"] else ""}
		if str(p["repair"]) == "":
			p.erase("repair")
		places.append(p)
	# Roads from the town to every place (not across water: around it or a bridge where it must).
	var roads: Array = []
	for p: Dictionary in places:
		if p["id"] == "town":
			continue
		for c in _path(start, Vector2i(p["at"][0], p["at"][1])):
			if _tile(tiles, c) != "city":
				_set_tile(tiles, c, "road")
			if not roads.has([c.x, c.y]):
				roads.append([c.x, c.y])
	return {"seed": seed_value, "size": [cols, rows], "landscape": landscape, "culture": str(region.get("culture", "")),
		"region": region.duplicate(), "tiles": tiles, "travel": TRAVEL.duplicate(), "mech_blocked": MECH_BLOCKED.duplicate(),
		"places": places, "roads": roads, "start": [start.x, start.y]}


## Options for MissionGenerator.area() when stepping into tile (x, y): the region's look, the
## tile's place on the region grid, and what's there (the town, a village, open road or wilds).
static func area_opts(rm: Dictionary, x: int, y: int) -> Dictionary:
	var place := "wilds"
	for p: Dictionary in rm["places"]:
		if int(p["at"][0]) == x and int(p["at"][1]) == y:
			place = str(AREA_PLACE.get(str(p["kind"]), "wilds"))
	if place == "wilds" and str(rm["tiles"][y][x]) == "road":
		place = "road"
	return {"region": rm["region"], "at": [x, y], "place": place}


## Hours to walk or drive from tile a to tile b along the cheapest straight-ish route (sum of
## the tiles crossed); -1 if a mech can't get there without a dropship.
static func travel_hours(rm: Dictionary, a: Vector2i, b: Vector2i, mech: bool = true) -> float:
	var hours := 0.0
	for c in _path(a, b):
		var t := str(rm["tiles"][c.y][c.x])
		if mech and t in rm["mech_blocked"]:
			return -1.0
		hours += float(rm["travel"].get(t, 1.0))
	return hours


static func _tile(tiles: Array, c: Vector2i) -> String:
	return str(tiles[c.y][c.x])


static func _set_tile(tiles: Array, c: Vector2i, t: String) -> void:
	tiles[c.y][c.x] = t


## A tile ring_min..ring_max steps from `from`, on land, not taken yet.
static func _free_spot(rng: RandomNumberGenerator, tiles: Array, taken: Dictionary, from: Vector2i, ring_min: int, ring_max: int) -> Vector2i:
	var rows := tiles.size()
	var cols := (tiles[0] as Array).size()
	for t in range(80):
		var d := rng.randi_range(ring_min, ring_max)
		var a := rng.randf() * TAU
		var c := from + Vector2i(int(round(cos(a) * d)), int(round(sin(a) * d)))
		if c.x < 1 or c.y < 1 or c.x >= cols - 1 or c.y >= rows - 1 or taken.has(c):
			continue
		var near := false
		for o: Vector2i in taken:
			near = near or (absi(o.x - c.x) <= 1 and absi(o.y - c.y) <= 1)
		if near:
			continue
		return c
	return Vector2i(-1, -1)


## Tiles from a to b: along x, then along y (roads bend once).
static func _path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := a
	while c.x != b.x:
		c.x += signi(b.x - c.x)
		out.append(c)
	while c.y != b.y:
		c.y += signi(b.y - c.y)
		out.append(c)
	return out
