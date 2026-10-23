class_name TerrainGen
extends RefCounted
## Battlefield terrain for the mission generator: a landscape's heights and features, then a
## culture's settlement on top. Everything is rules terrain (BattleMap columns and tags);
## the look tags it adds (rock, woods, building, wall, water, ice, lava, toxic, crystal,
## rubble, chasm) only tell the renderer what to draw and change no rules.
##
## Rules tags used: difficult (rough ground, woods, water, ice, rubble), dangerous (lava,
## toxic pools, fires), soft_cover (woods: see-through but obscuring), impassable (sheer
## spires, chasms). Raised columns are hard cover and obstacles by their height.
##
## `blocked` cells (deployment zones, objectives) are kept low, open and safe.

## Landscapes the generator can build, with their weight when picked at random.
const LANDSCAPES := {"grassy_hills": 4, "desert_mesas": 2, "tundra": 2, "volcanic": 1, "alien_wilds": 1, "crystal_fields": 1,
	"toxic_marsh": 1, "molten_world": 1, "toxic_swamp": 1, "city": 3, "station": 1, "starship": 1, "moon": 1, "asteroid": 1, "ocean": 1, "jungle": 2, "boarding": 1, "boarding_defend": 0, "boarding_assault": 0,
	"autumn_forest": 2, "salt_flats": 1}
## Cultures that fit each landscape ("" = wilderness, no settlement).
const CULTURES := {
	"grassy_hills": ["", "", "medieval", "old_west", "east_asian", "union", "retro"],
	"desert_mesas": ["", "old_west", "old_west", "retro"],
	"tundra": ["", "", "medieval", "union"],
	"volcanic": ["", ""],
	"alien_wilds": ["", ""],
	"crystal_fields": ["", ""],
	"toxic_marsh": ["", ""],
	"molten_world": [""],
	"toxic_swamp": ["", "", "medieval"],
	"station": [""],
	"starship": [""],
	"boarding": [""],
	"boarding_defend": [""],
	"boarding_assault": [""],
	"autumn_forest": ["", "", "medieval", "east_asian", "old_west", "union"],
	"salt_flats": ["", "old_west", "retro", "industrial", "industrial"],
	"moon": ["", "", "union", "retro"],
	"asteroid": [""],
	"ocean": ["", "east_asian", "retro", "union"],
	"jungle": ["", "", "east_asian", "medieval"],
	"city": ["ruins", "cyberpunk", "burning", "union", "retro", "east_asian", "medieval", "old_west", "industrial", "port"],
}


## Picks a landscape (and culture) with the mission's RNG. Wanted values win when known.
static func pick(rng: RandomNumberGenerator, landscape: String = "", culture: String = "") -> Array:
	if not LANDSCAPES.has(landscape):
		var total := 0
		for k: String in LANDSCAPES:
			total += int(LANDSCAPES[k])
		var roll := rng.randi_range(1, total)
		for k: String in LANDSCAPES:
			roll -= int(LANDSCAPES[k])
			if roll <= 0:
				landscape = k
				break
	var options: Array = CULTURES[landscape]
	if culture == "" or not (culture in options):
		culture = str(options[rng.randi_range(0, options.size() - 1)])
	return [landscape, culture]


## Look tags for a raised block of cover added by fairness repairs, per landscape.
static func cover_tags(landscape: String) -> Array:
	match landscape:
		"city":
			return ["wall"]
		"station", "starship", "boarding", "boarding_defend", "boarding_assault":
			return ["container"]
		"alien_wilds", "crystal_fields":
			return ["crystal"]
		"toxic_swamp", "jungle":
			return ["rock", Sight.TAG_SOFT_COVER, "woods"]
	return ["rock"]


## Plain-language name for briefings, from the shared biome data: "desert mesas, frontier
## boomtown", "neon megacity".
static func describe(landscape: String, culture: String) -> String:
	var names := []
	for f: String in ["landscapes", "cultures"]:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/biomes/%s.json" % f))
		names.append(d if d is Dictionary else {})
	var land: String = (names[0] as Dictionary).get(landscape, {}).get("name", landscape.replace("_", " "))
	if culture == "":
		return land
	var cult: String = (names[1] as Dictionary).get(culture, {}).get("name", culture.replace("_", " "))
	return cult if landscape == "city" else "%s, %s" % [land, cult]


## Weather that suits each landscape ("" = clear), picked with the world RNG. Look only:
## any rules effect comes from an environment the mission sets (see weather.json).
const WEATHER := {
	"grassy_hills": ["", "", "", "rain", "storm", "mist"], "desert_mesas": ["", "", "", "sandstorm"],
	"tundra": ["", "snow", "snow", "blizzard"], "volcanic": ["ashfall", "ashfall", ""], "alien_wilds": ["", "spores", "storm"],
	"crystal_fields": ["", "", "sandstorm"], "toxic_marsh": ["spores", "mist", "storm"],
	"molten_world": ["ashfall", "ashfall", "storm"], "toxic_swamp": ["mist", "mist", "spores", "rain"], "city": ["", "", "rain", "storm", "mist"],
	"station": [""], "starship": [""], "moon": [""], "asteroid": [""], "ocean": ["", "", "rain", "storm"],
	"jungle": ["", "rain", "rain", "mist", "storm"],
	"autumn_forest": ["", "", "rain", "mist", "storm"], "salt_flats": ["", "", "", "sandstorm"],
}


## Each city's own weather: the neon city is wet at night, the others mostly clear.
const CITY_WEATHER := {"cyberpunk": ["rain", "rain", "storm", ""], "union": ["", "", "", "rain"], "retro": ["", "", "", "rain"],
	"old_west": ["", "", "", "", "sandstorm"], "east_asian": ["", "", "mist", "rain"], "medieval": ["", "mist", "rain", ""],
	"ruins": ["", "mist", "storm", ""], "industrial": ["", "", "mist"], "port": ["", "", "rain", "mist"]}


static func pick_weather(rng: RandomNumberGenerator, landscape: String, culture: String = "") -> String:
	var options: Array = WEATHER.get(landscape, [""])
	if culture == "burning":
		return "ashfall"
	if landscape == "city" and CITY_WEATHER.has(culture):
		options = CITY_WEATHER[culture]
	return str(options[rng.randi_range(0, options.size() - 1)])


## Kit name for the renderer ("landscape" or "landscape/culture").
static func kit(landscape: String, culture: String) -> String:
	return landscape if culture == "" else "%s/%s" % [landscape, culture]


static func generate(rng: RandomNumberGenerator, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary, landscape: String, culture: String,
		hub: Dictionary = {}, area: bool = false, edges: Dictionary = {}) -> BattleMap:
	var g := TerrainGen.new()
	g.edges = edges
	g.rng = rng
	g.w = w
	g.h = h
	g.shape = shape
	g.blocked = blocked
	g.map = BattleMap.new(shape)
	match landscape:
		"desert_mesas":
			g._mesas()
		"tundra":
			g._tundra()
		"volcanic":
			g._volcanic()
		"alien_wilds":
			g._alien(1.0, 1.0)
		"crystal_fields":
			g._alien(0.3, 2.5)
		"toxic_marsh":
			g._alien(2.5, 0.4)
		"city":
			g._city(culture)
		"station":
			g._station(6)
		"starship":
			g._station(4)
		"boarding":
			g._boarding()
		"boarding_defend":
			g._ship_interior(true)
		"boarding_assault":
			g._ship_interior(false)
		"moon":
			g._moon(false)
		"asteroid":
			g._moon(true)
		"ocean":
			g._ocean()
		"jungle":
			g._jungle()
		"autumn_forest":
			g._hills()
			g._patches(w * h / 160, Vector2i(4, 8), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
		"salt_flats":
			g._flats()
		"molten_world":
			g._molten()
		"toxic_swamp":
			g._swamp()
		_:
			g._hills()
	if not hub.is_empty():
		g._town(hub, culture)
	elif landscape != "city" and culture != "":
		g._settlement(culture, landscape)
	if area and landscape not in ["city", "station", "starship", "boarding", "boarding_defend", "boarding_assault"]:
		g._area_ways()
	g._clear_rock_near_built()
	g._place_outcrops()
	g._clear_blocked()
	if area:
		g._area_edges()
	g._lane_tags()
	g._parked_vehicles(landscape, culture)
	g._materials(landscape, culture)
	return g.map


# --- Materials (Core p.68) -------------------------------------------------------------

## What built and natural cover is made of, by culture: [material, Armor]. Objects have 5
## Evasion and 10 HP per Size 1 section (Core p.68); "solid rock" and tough places 1-2 Armor,
## fortified places 3-4; flimsy wood or prefab none. The rules read "armor_N"
## (TerrainDamage); "material_*" picks how it looks when hit and when it breaks.
## Cities that build towers; the rest stay low like a city on modern Earth.
const MEGA_CITIES := ["cyberpunk", "union"]
const MATERIALS := {
	"old_west": ["wood", 0], "": ["wood", 0], "east_asian": ["wood", 0], "medieval": ["stone", 1],
	"cyberpunk": ["concrete", 1], "retro": ["concrete", 1], "ruins": ["concrete", 1], "burning": ["concrete", 1],
	"industrial": ["concrete", 1], "port": ["metal", 1],
	"union": ["fortified", 3],
}


## [material, armor] for a column with these look tags in this world.
static func material_for(col: BattleMap.Column, landscape: String, culture: String) -> Array:
	if col.has_tag("bulkhead"):
		if col.has_tag("hull") or landscape in ["starship", "boarding"]:
			return ["hull", 4]
		return ["fortified", 3]
	if col.has_tag("machinery"):
		return ["fortified", 2]
	if col.has_tag("container"):
		return ["metal", 1]
	if col.has_tag("rock"):
		return ["stone", 2]
	if col.has_tag("crystal"):
		return ["stone", 1]
	if col.has_tag("wall"):
		# Town walls of stone are tougher than the houses; barricades are what the city is.
		return ["stone", 2] if culture == "medieval" else (MATERIALS.get(culture, ["concrete", 1]) as Array)
	if col.has_tag("building") or col.has_tag("platform"):
		if landscape in ["station", "starship"]:
			return ["fortified", 3]
		return MATERIALS.get(culture, ["concrete", 1])
	return []


func _materials(landscape: String, culture: String) -> void:
	for cell in cells:
		var col := map.column(cell)
		if col.ground < 1 and not col.has_tag(BattleMap.TAG_DESTRUCTIBLE):
			continue
		var m := material_for(col, landscape, culture)
		if m.is_empty():
			continue
		_tag(col, ["material_" + str(m[0]), "armor_%d" % int(m[1])])


# --- Towns (a hub's own streets) --------------------------------------------------------

## Mech-scale battlefield of a hub (story.hub): the same buildings around the same plaza,
## with the same streets out to their doors, from the hub's own layout (HubLayout spots, in
## meters) at about 2 m per space. Small-town buildings are 1-2 levels and take up their
## spaces, so they're real cover, and they can be knocked down. More houses fill out the
## streets around them. The plaza's centerpiece stands in the middle.
const TOWN_SCALE := 2.0


func _town(hub: Dictionary, culture: String) -> void:
	var cc := w / 2
	var cr := h / 2
	# The fight starts at hub["at"] (a spot id): shift the town so that building stands in the
	# middle of the battle band, between the two deployment zones.
	for spot: Dictionary in hub.get("spots", []):
		if str(spot.get("id", "")) == str(hub.get("at", "")) and str(hub.get("at", "")) != "":
			cc -= int(round(float(spot["pos"][0]) / TOWN_SCALE))
			cr -= int(round(float(spot["pos"][1]) / TOWN_SCALE))
			break
	cc = clampi(cc, 6, w - 7)
	cr = clampi(cr, 6, h - 7)
	var used := {}
	var mark := func(c: int, r: int, levels: int, tags: Array) -> void:
		if c < 0 or r < 0 or c >= w or r >= h:
			return
		var cell := _cell(c, r)
		if not map.has_cell(cell) or blocked.has(cell):
			return
		var col := map.column(cell)
		col.ground = levels
		col.tags = PackedStringArray(tags)
		used[cell] = true
	# Level the town site: gentle ground, nothing in the way.
	var radius := int(24.0 / TOWN_SCALE) + 4
	for r in range(cr - radius, cr + radius + 1):
		for c in range(cc - radius, cc + radius + 1):
			if c < 0 or r < 0 or c >= w or r >= h:
				continue
			var cell := _cell(c, r)
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var col := map.column(cell)
			col.ground = 0
			col.tags = PackedStringArray()
	var doors: Array[Vector2i] = []
	var door_ids: Array[String] = []
	for spot: Dictionary in hub.get("spots", []):
		var kind := str(spot.get("kind", ""))
		var pos := Vector2(float(spot["pos"][0]), float(spot["pos"][1])) / TOWN_SCALE
		var sz: Array = spot.get("size", [8.0, 6.0, 4.0])
		var sw := maxi(2, int(round(float(sz[0]) / TOWN_SCALE)))
		var sd := maxi(2, int(round(float(sz[1]) / TOWN_SCALE)))
		var levels := clampi(int(round(float(sz[2]) / 3.5)), 1, 2)
		var c0 := cc + int(round(pos.x)) - sw / 2
		var r0 := cr + int(round(pos.y)) - sd / 2
		if kind == "plaza":
			# The centerpiece (well, fountain, statue...): one low block in the middle.
			mark.call(cc, cr, 1, ["wall", BattleMap.TAG_DESTRUCTIBLE])
			continue
		if kind == "landing":
			continue  # an open pad: the squad's mechs stood here
		# Facing the plaza: the long side toward it.
		if absf(pos.x) > absf(pos.y):
			var t := sw
			sw = sd
			sd = t
			c0 = cc + int(round(pos.x)) - sw / 2
			r0 = cr + int(round(pos.y)) - sd / 2
		# The hub's own building: its cells carry the spot id (the saloon you walked into on
		# foot is the same building in the fight), its door where the hub's door is.
		var sid := "spot_" + str(spot.get("id", kind))
		for r in range(r0, r0 + sd):
			for c in range(c0, c0 + sw):
				mark.call(c, r, levels, ["building", BattleMap.TAG_DESTRUCTIBLE, sid])
		var door := Vector2(float(spot["door"][0]), float(spot["door"][1])) / TOWN_SCALE
		doors.append(Vector2i(cc + int(round(door.x)), cr + int(round(door.y))))
		door_ids.append(str(spot.get("id", kind)))
	# Side streets: rows of small houses along the roads out of town.
	var houses := 6 + rng.randi_range(0, 6)
	for i in range(houses):
		var a := rng.randf() * TAU
		var dist := rng.randf_range(12.0, float(radius))
		var c0 := cc + int(cos(a) * dist)
		var r0 := cr + int(sin(a) * dist)
		var free := true
		for r in range(r0 - 1, r0 + 3):
			for c in range(c0 - 1, c0 + 3):
				if c >= 0 and r >= 0 and c < w and r < h and used.has(_cell(c, r)):
					free = false
		if not free:
			continue
		for r in range(r0, r0 + 2):
			for c in range(c0, c0 + 2):
				mark.call(c, r, 1, ["building", BattleMap.TAG_DESTRUCTIBLE])
	# Streets: clear lines from the plaza to every door.
	for d in doors:
		var from := Vector2(cc, cr)
		var to := Vector2(d.x, d.y)
		var n := int(from.distance_to(to)) + 1
		for k in range(n + 1):
			var p := from.lerp(to, float(k) / n)
			for dc in [0, 1]:
				var cell := _cell(int(round(p.x)) + dc, int(round(p.y)))
				if map.has_cell(cell) and not blocked.has(cell) and map.column(cell).has_tag("building"):
					map.column(cell).ground = 0
					map.column(cell).tags = PackedStringArray()
	# Some crates and carts in the streets: difficult going, not cover.
	_patches(maxi(2, w * h / 400), Vector2i(1, 2), [BattleMap.TAG_DIFFICULT, "rubble"], 0, true)
	# The ground between the buildings is the town's own: yards, sidewalks and the square.
	for r in range(cr - radius + 1, cr + radius):
		for c in range(cc - radius + 1, cc + radius):
			if c < 0 or r < 0 or c >= w or r >= h:
				continue
			var cell := _cell(c, r)
			if map.has_cell(cell) and not blocked.has(cell) and map.column(cell).tags.is_empty() and map.ground_height(cell) == 0:
				map.column(cell).tags = PackedStringArray(["lot"])
				built[cell] = true
		for c in range(cc - radius, cc + radius + 1):
			var cell := _cell(clampi(c, 0, w - 1), clampi(r, 0, h - 1))
			if used.has(cell):
				built[cell] = true
	# Each building's way in: the space in front of its door (open ground, look tags only).
	for i in range(doors.size()):
		var d := doors[i]
		if d.x < 0 or d.y < 0 or d.x >= w or d.y >= h:
			continue
		var dc := _cell(d.x, d.y)
		if map.has_cell(dc) and not map.column(dc).has_tag("building"):
			map.column(dc).tags.append_array(["door", "door_" + door_ids[i]])


var rng: RandomNumberGenerator
## Rock outcrops asked for by the landscape, placed after towns and castles (away from them).
var pending_outcrops := 0
var w := 0
var h := 0
var shape: GridLayout.Shape
var blocked: Dictionary
var map: BattleMap
## Share of inner bulkheads that can be broken through (ships' partitions are lighter).
var breakable_walls := 0.3
var cells: Array[Vector2i] = []


## Map coordinates are (col, row) on a rectangle; hex maps shear rows like BattleMap.flat().
func _cell(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row >> 1), row) if shape == GridLayout.Shape.HEX else Vector2i(col, row)


func _noise(freq: float, octaves: int = 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


## Fills the rectangle with ground from `height(col, row) -> int`.
func _fill(height: Callable) -> void:
	for r in range(h):
		for c in range(w):
			var cell := _cell(c, r)
			var gnd: int = height.call(c, r)
			if blocked.has(cell):
				gnd = mini(gnd, 1)
			map.set_column(cell, maxi(gnd, 0))
			cells.append(cell)


func _random_cell() -> Vector2i:
	return cells[rng.randi_range(0, cells.size() - 1)]


## A connected patch of up to `n` cells grown from `at`.
func _blob(at: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [at]
	var guard := 0
	while out.size() < n and guard < n * 8:
		guard += 1
		var from := out[rng.randi_range(0, out.size() - 1)]
		var next := map.grid.neighbors(from)
		var cell: Vector2i = next[rng.randi_range(0, next.size() - 1)]
		if map.has_cell(cell) and not out.has(cell):
			out.append(cell)
	return out


static func _tag(col: BattleMap.Column, tags: Array) -> void:
	var have := col.tags  # Packed arrays are values: change a copy and put it back.
	for t: String in tags:
		if not have.has(t):
			have.append(t)
	col.tags = have


func _free(cell: Vector2i) -> bool:
	return map.has_cell(cell) and not blocked.has(cell) and map.column(cell).tags.is_empty()


## Patches of tagged ground: `count` blobs of `size` cells.
func _patches(count: int, size: Vector2i, tags: Array, raise: int = 0, flat_only: bool = false) -> void:
	for i in range(count):
		var at := _random_cell()
		var base := map.ground_height(at)
		for cell in _blob(at, rng.randi_range(size.x, size.y)):
			if not _free(cell):
				continue
			if flat_only and map.ground_height(cell) != base:
				continue
			var col := map.column(cell)
			col.ground = mini(col.ground + raise, 6)
			_tag(col, tags)


# --- Landscapes --------------------------------------------------------------------------

## Rolling hills, a river, rock outcrops (hard cover), woods (soft cover, difficult), mud.
func _hills() -> void:
	var noise := _noise(rng.randf_range(0.035, 0.06))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.4) * 2.4)), 0, 3))
	if rng.randf() < 0.6:
		_river()
	var area := w * h
	_outcrops(area / 220)
	_patches(area / 110, Vector2i(3, 7), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_patches(area / 140, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT])


## Salt flats: dead level white crust for miles, cracked and soft in places (difficult), a few
## low pressure ridges in straight runs (one level: cover when you crouch behind them), rare rock
## islands, and abandoned mine spoil heaps. Little cover: the open ground is the danger.
func _flats() -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	var area := w * h
	for i in range(maxi(3, area / 300)):
		var at := Vector2i(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3))
		var dir := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		for k in range(rng.randi_range(4, 8)):
			var q := at + dir * k
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				break
			var cell := _cell(q.x, q.y)
			if _free(cell):
				map.column(cell).ground = 1
				_tag(map.column(cell), ["rock"])
	_outcrops(area / 400)
	_patches(area / 120, Vector2i(3, 8), [BattleMap.TAG_DIFFICULT], 0, true)
	_patches(area / 500, Vector2i(3, 5), ["rubble", BattleMap.TAG_DIFFICULT], 1, true)  # spoil heaps


## A winding river across the map: difficult water cells at the valley floor.
func _river() -> void:
	var vertical := rng.randf() < 0.5
	var length := h if vertical else w
	var across := w if vertical else h
	var pos := rng.randf_range(across * 0.3, across * 0.7)
	var phase := rng.randf() * TAU
	var width := rng.randi_range(1, 2)
	for i in range(length):
		var mid := pos + sin(i * 0.18 + phase) * across * 0.12
		for k in range(-width / 2 - 1, width / 2 + 1):
			var a := int(round(mid)) + k
			if a < 0 or a >= across:
				continue
			var cell := _cell(a, i) if vertical else _cell(i, a)
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var col := map.column(cell)
			var bank := k < -width / 2 or k >= width / 2 + (width % 2)
			if bank:
				col.ground = mini(col.ground, 1)
			else:
				col.ground = 0
				_tag(col, [BattleMap.TAG_DIFFICULT, "water"])


## Flat sand with mesas (2-4 level plateaus with sheer sides), rock spires, dunes (difficult).
func _mesas() -> void:
	var noise := _noise(rng.randf_range(0.04, 0.07))
	var detail := _noise(0.2, 2)
	_fill(func(c: int, r: int) -> int:
		var n := noise.get_noise_2d(c, r)
		var gnd := 0
		if n > 0.35:
			gnd = 3 if n > 0.5 else 2
		elif detail.get_noise_2d(c, r) > 0.45:
			gnd = 1
		return gnd)
	var area := w * h
	# Sheer rock spires: too steep to climb (impassable), tall hard cover.
	for i in range(area / 220):
		var at := _random_cell()
		if _free(at):
			var col := map.column(at)
			col.ground = mini(col.ground + rng.randi_range(3, 5), 7)
			_tag(col, ["rock", BattleMap.TAG_IMPASSABLE])
	_outcrops(area / 280)
	_patches(area / 90, Vector2i(3, 8), [BattleMap.TAG_DIFFICULT], 0, true)
	_patches(area / 260, Vector2i(2, 4), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])


## Snowy rolling ground, frozen lakes (ice: difficult), pine woods, rock outcrops.
func _tundra() -> void:
	var noise := _noise(rng.randf_range(0.03, 0.05))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.3) * 2.8)), 0, 3))
	var area := w * h
	# Frozen lakes in the low ground.
	for i in range(area / 260):
		var at := _random_cell()
		if map.ground_height(at) > 0:
			continue
		for cell in _blob(at, rng.randi_range(5, 12)):
			if _free(cell) and map.ground_height(cell) == 0:
				_tag(map.column(cell), [BattleMap.TAG_DIFFICULT, "ice"])
	_outcrops(area / 240)
	_patches(area / 120, Vector2i(3, 7), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_patches(area / 150, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT])


## Black rock terraces, lava channels (dangerous), ash fields (difficult), smoking vents.
func _volcanic() -> void:
	var noise := _noise(rng.randf_range(0.04, 0.06))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.35) * 3.0)), 0, 4))
	var area := w * h
	# Lava: winding channels of dangerous ground across the map, between the deployment strips.
	var flows := rng.randi_range(1, 2) + (1 if area > 900 else 0)
	for f in range(flows):
		var row := rng.randf_range(h * 0.3, h * 0.7)
		var phase := rng.randf() * TAU
		for c in range(w):
			row += rng.randf_range(-0.8, 0.8)
			row = clampf(row, h * 0.25, h * 0.75)
			var wiggle := sin(c * 0.25 + phase) * 1.5
			for k in range(2 if rng.randf() < 0.5 else 1):
				var cell := _cell(c, clampi(int(round(row + wiggle)) + k, 0, h - 1))
				if not map.has_cell(cell) or blocked.has(cell):
					continue
				var col := map.column(cell)
				col.ground = 0
				_tag(col, [BattleMap.TAG_DANGEROUS, "dangerous_energy", "lava"])
	_outcrops(area / 200)
	_patches(area / 80, Vector2i(3, 8), [BattleMap.TAG_DIFFICULT])
	# Cracked ground that glows: dangerous, small.
	_patches(area / 200, Vector2i(1, 3), [BattleMap.TAG_DANGEROUS], 0, true)


## Basalt terraces, crystal outcrops (hard cover), glowing fungus woods (soft cover), toxic
## pools (dangerous), ash flats (difficult) and the odd chasm (impassable).
func _alien(toxic: float, crystal: float) -> void:
	var noise := _noise(rng.randf_range(0.04, 0.06))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.3) * 3.2)), 0, 4))
	var area := w * h
	for i in range(int(area / 260.0 * toxic)):
		var at := _random_cell()
		for cell in _blob(at, rng.randi_range(4, 10)):
			if _free(cell):
				var col := map.column(cell)
				col.ground = 0
				_tag(col, [BattleMap.TAG_DANGEROUS, "toxic"])
	_patches(int(area / 60.0 * crystal), Vector2i(1, 3), ["crystal"], 2)
	_patches(area / 120, Vector2i(3, 6), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_patches(area / 120, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT])
	for i in range(area / 600):
		var at := _random_cell()
		for cell in _blob(at, rng.randi_range(2, 4)):
			if _free(cell):
				var col := map.column(cell)
				col.ground = 0
				_tag(col, [BattleMap.TAG_IMPASSABLE, "chasm"])


## City blocks between streets: buildings of 1-6 levels filling each block (some blocks are
## plazas or parks), wrecked or burning streets depending on the culture.
func _city(culture: String) -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	var block := rng.randi_range(5, 7)
	var street := 2
	# Only the mega-cities (neon sprawl, Union core) build towers; everywhere else is a city like
	# modern Earth: mostly one or two storeys, a few taller.
	var tall: int = {"cyberpunk": 6, "union": 6, "ruins": 3, "burning": 3, "retro": 3, "east_asian": 3, "industrial": 2, "port": 2}.get(culture, 2)
	var mega := culture in MEGA_CITIES
	var dock := _dock() if culture == "port" else Rect2i()
	var ruined := culture in ["ruins", "burning"]
	var bx := 0
	var off_c := rng.randi_range(-2, 1)
	var off_r := rng.randi_range(-2, 1)
	for r0 in range(off_r, h, block + street):
		for c0 in range(off_c, w, block + street):
			var kind := rng.randf()
			if dock.has_area() and Rect2i(c0, r0, block, block).intersects(dock.grow(1)):
				continue  # the harbor basin and quay
			if dock.has_area() and Rect2i(c0, r0, block, block).intersects(dock.grow(block + street + 1)) and kind < 0.6:
				_yard(c0, r0, block, "container")  # container stacks along the quay
				continue
			if culture == "industrial" and kind > 0.75:
				_yard(c0, r0, block, "machinery")  # tanks and pipe racks
				continue
			if kind < 0.18:
				_plaza(c0, r0, block)
				continue
			# Split the block into lots; each lot is a building of its own height. Outside the
			# mega-cities some lots stay empty (yards, car parks) and buildings leave alleys.
			var lots := _split_block(c0, r0, block, not mega)
			for lot_in: Rect2i in lots:
				if rng.randf() < (0.12 if mega else 0.3):
					continue
				var lot := lot_in
				if not mega:
					lot = Rect2i(lot.position, Vector2i(maxi(1, lot.size.x - (1 if lot.size.x >= 3 else 0)), maxi(1, lot.size.y - (1 if lot.size.y >= 3 else 0))))
				# Low buildings are the rule; towers are rare even in a mega-city.
				var height := 1 + int(floor(pow(rng.randf(), 2.2 if mega else 1.6) * tall))
				var lot_breakable := rng.randf() < (0.8 if ruined else 0.6)
				if ruined and rng.randf() < 0.25:
					height = 0  # collapsed: rubble lot
				for r in range(lot.position.y, lot.end.y):
					for c in range(lot.position.x, lot.end.x):
						if c < 0 or r < 0 or c >= w or r >= h:
							continue
						var cell := _cell(c, r)
						if blocked.has(cell):
							continue
						var col := map.column(cell)
						if height == 0:
							_tag(col, [BattleMap.TAG_DIFFICULT, "rubble"])
						else:
							col.ground = height
							_tag(col, ["building"])
							# Low buildings can be knocked down (Core: terrain and objects can be
							# destroyed); towers stand. Ruined cities are more fragile.
							if height <= (4 if ruined else 3) and lot_breakable:
								_tag(col, [BattleMap.TAG_DESTRUCTIBLE])
			bx += 1
	# A boulevard four lanes wide through the middle of the city (row band); in the
	# mega-cities an elevated highway runs over it on pillars (units pass under and walk on it).
	var band := h / 2 - 2
	for r in range(band, band + 4):
		for c in range(w):
			var cell := _cell(c, r)
			if map.has_cell(cell) and not blocked.has(cell):
				map.column(cell).ground = 0
				map.column(cell).tags = PackedStringArray()
	_tag_streets()
	if mega and w >= 36:
		_elevated(band + 1)
	# Every open space is a sidewalk, a lot or a square: no bare ground.
	for cell in cells:
		var col := map.column(cell)
		if col.ground == 0 and col.tags.is_empty() and col.gap_top == 0:
			col.tags = PackedStringArray(["lot"])
	var area := w * h
	if not ruined:
		# Even a living city has roadworks, wreckage and debris in the streets.
		_patches(maxi(2, area / 300), Vector2i(1, 3), [BattleMap.TAG_DIFFICULT, "rubble"], 0, true)
	if ruined:
		# Rubble spills into the streets, craters and burning wrecks.
		_patches(area / 140, Vector2i(2, 4), [BattleMap.TAG_DIFFICULT, "rubble"], 0, true)
		_patches(area / (180 if culture == "burning" else 400), Vector2i(1, 3), [BattleMap.TAG_DANGEROUS], 0, true)
	# Destructible barricades: short straight walls across some streets (not along them).
	for i in range(area / 220):
		var c := rng.randi_range(0, w - 1)
		var r := rng.randi_range(0, h - 1)
		var at := _cell(c, r)
		if not map.has_cell(at) or not map.column(at).has_tag("road") or map.column(at).has_tag("crossing"):
			continue
		var across := Vector2i(0, 1) if map.column(at).has_tag("road_x") else Vector2i(1, 0)
		for k in range(-1, 2):
			var q := Vector2i(c, r) + across * k
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
				continue
			var cell := _cell(q.x, q.y)
			if map.has_cell(cell) and not blocked.has(cell) and map.column(cell).has_tag("road") and map.ground_height(cell) == 0:
				var col := map.column(cell)
				col.ground = 1
				col.tags = PackedStringArray(["wall", BattleMap.TAG_DESTRUCTIBLE])


## A harbor basin along one long side of the map (columns at the left or right edge): deep
## water (difficult) with a quay road along it. Returns the basin's rectangle.
func _dock() -> Rect2i:
	var width := 3 + (1 if w >= 40 else 0)
	var c0 := 0 if rng.randf() < 0.5 else w - width
	for r in range(h):
		for c in range(c0, c0 + width):
			_put(c, r, 0, [BattleMap.TAG_DIFFICULT, "water"])
		var quay := c0 + width if c0 == 0 else c0 - 1
		_put(quay, r, 0, ["road", "road_z"])
	return Rect2i(c0, 0, width, h)


## A yard filling a city block: stacks of shipping containers (1-2 high) or industrial tanks
## and pipe racks (machinery, 1-2 high) in straight rows with aisles between them.
func _yard(c0: int, r0: int, block: int, tag: String) -> void:
	for r in range(r0, r0 + block):
		for c in range(c0, c0 + block):
			if c < 0 or r < 0 or c >= w or r >= h:
				continue
			var cell := _cell(c, r)
			if blocked.has(cell) or not map.has_cell(cell) or map.column(cell).has_tag("water"):
				continue
			# Rows of two with a one-space aisle: every third row stays open.
			if (r - r0) % 3 == 2 or c == c0 or c == c0 + block - 1:
				continue
			var col := map.column(cell)
			col.ground = 1 if rng.randf() < 0.55 else 2
			col.tags = PackedStringArray([tag, BattleMap.TAG_DESTRUCTIBLE] if tag == "container" else [tag])


## Open ground-level cells between city blocks become roads: running along the row (road_x),
## along the column (road_z), or a crossing where both meet. Look only (no rules effect).
func _tag_streets() -> void:
	# Open ground (level 0, no woods) on the w x h rectangle, then open run lengths along rows
	# and columns, each counted once per run.
	var open := PackedByteArray()
	open.resize(w * h)
	for r in range(h):
		for c in range(w):
			var cell := _cell(c, r)
			if map.has_cell(cell) and map.column(cell).ground == 0 and not map.column(cell).has_tag("woods"):
				open[r * w + c] = 1
	var run_x := PackedInt32Array()
	run_x.resize(w * h)
	var run_z := PackedInt32Array()
	run_z.resize(w * h)
	for r in range(h):
		var c := 0
		while c < w:
			var e := c
			while e < w and open[r * w + e] == 1:
				e += 1
			for k in range(c, e):
				run_x[r * w + k] = e - c
			c = e + 1
	for c in range(w):
		var r := 0
		while r < h:
			var e := r
			while e < h and open[e * w + c] == 1:
				e += 1
			for k in range(r, e):
				run_z[k * w + c] = e - r
			r = e + 1
	var is_open := func(c: int, r: int) -> bool:
		return c >= 0 and r >= 0 and c < w and r < h and open[r * w + c] == 1
	for r in range(h):
		for c in range(w):
			var i := r * w + c
			if open[i] == 0 or not map.column(_cell(c, r)).tags.is_empty():
				continue
			var axis := ""
			if run_x[i] >= 6 and run_z[i] >= 6:
				# A crossing has buildings on its diagonals; open all round is a plaza (paved,
				# no lanes).
				var closed := 0
				for d: Vector2i in [Vector2i(3, 3), Vector2i(-3, 3), Vector2i(3, -3), Vector2i(-3, -3)]:
					if not is_open.call(c + d.x, r + d.y):
						closed += 1
				axis = "crossing" if closed >= 2 else "plaza"
			elif run_x[i] >= 6:
				axis = "road_x"
			elif run_z[i] >= 6:
				axis = "road_z"
			if axis == "plaza":
				var cell := _cell(c, r)
				map.column(cell).tags = PackedStringArray(["plaza"])  # a paved square, no lanes
				built[cell] = true
			elif axis != "":
				var cell := _cell(c, r)
				map.column(cell).tags = PackedStringArray(["road", axis])
				built[cell] = true


func _split_block(c0: int, r0: int, block: int, no_monoliths: bool = false) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var cut_c := c0 + rng.randi_range(2, block - 2)
	var cut_r := r0 + rng.randi_range(2, block - 2)
	match rng.randi_range(1 if no_monoliths else 0, 2):
		0:
			out.append(Rect2i(c0, r0, block, block))
		1:
			out.append(Rect2i(c0, r0, cut_c - c0, block))
			out.append(Rect2i(cut_c, r0, c0 + block - cut_c, block))
		_:
			out.append(Rect2i(c0, r0, cut_c - c0, cut_r - r0))
			out.append(Rect2i(cut_c, r0, c0 + block - cut_c, cut_r - r0))
			out.append(Rect2i(c0, cut_r, cut_c - c0, r0 + block - cut_r))
			out.append(Rect2i(cut_c, cut_r, c0 + block - cut_c, r0 + block - cut_r))
	return out


## An open square or a small park (woods) in a city block.
func _plaza(c0: int, r0: int, block: int) -> void:
	var park := rng.randf() < 0.5
	for r in range(r0 + 1, r0 + block - 1):
		for c in range(c0 + 1, c0 + block - 1):
			if c < 0 or r < 0 or c >= w or r >= h:
				continue
			var cell := _cell(c, r)
			if blocked.has(cell):
				continue
			if park and rng.randf() < 0.55:
				_tag(map.column(cell), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
			elif not park and (c - c0 == 1 or c - c0 == block - 2) and (r - r0 == 1 or r - r0 == block - 2):
				var col := map.column(cell)
				col.ground = 1
				_tag(col, ["wall"])  # planters at the square's corners
			elif not park and c == c0 + block / 2 and r == r0 + block / 2:
				var col := map.column(cell)
				col.ground = 2
				_tag(col, ["wall"])  # the monument in the middle


# --- Space, moons, sea and jungle ------------------------------------------------------

## Station or ship interior: the deck split into rooms by bulkheads (3 levels: full-height
## walls, hard cover and line-of-sight blockers) with doorways; rooms are cargo bays
## (containers), machinery rooms, hangars (open) or plain. Some bulkhead runs are
## destructible. `min_room` is the smallest room side (ships have tighter rooms).
func _station(min_room: int) -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	var rooms: Array[Rect2i] = []
	_split(Rect2i(0, 0, w, h), min_room, rooms, 0)
	for room in rooms:
		var kind := rng.randf()
		var inner := room.grow(-1)
		if inner.size.x < 2 or inner.size.y < 2:
			continue
		if kind < 0.35:
			# Cargo bay: rows of shipping containers, 1-2 stacked, with aisles.
			for r in range(inner.position.y, inner.end.y, 3):
				for c in range(inner.position.x, inner.end.x - 1, 3):
					if rng.randf() < 0.65:
						var high := 1 if rng.randf() < 0.6 else 2
						for k in range(2):
							_raise(_cell(c + k, r), high, ["container"])
		elif kind < 0.55:
			# Machinery: a few big blocks (reactors, pumps) with leaking coolant (dangerous).
			for i in range(maxi(1, inner.get_area() / 25)):
				var at := Vector2i(rng.randi_range(inner.position.x, inner.end.x - 2), rng.randi_range(inner.position.y, inner.end.y - 2))
				var size := rng.randi_range(1, 2)
				for dr in range(size):
					for dc in range(size):
						_raise(_cell(at.x + dc, at.y + dr), 2, ["machinery"])
				if rng.randf() < 0.4:
					var leak := _cell(at.x + size, at.y)
					if _free(leak):
						_tag(map.column(leak), [BattleMap.TAG_DANGEROUS, "dangerous_energy"])
		elif kind < 0.7:
			# Debris and loose cargo: difficult ground.
			for i in range(maxi(1, inner.get_area() / 20)):
				var at := _cell(rng.randi_range(inner.position.x, inner.end.x - 1), rng.randi_range(inner.position.y, inner.end.y - 1))
				for cell in _blob(at, rng.randi_range(2, 4)):
					if _free(cell):
						_tag(map.column(cell), [BattleMap.TAG_DIFFICULT, "rubble"])
		# else: hangar or plain room, left open.


## Two ships docked side by side for a boarding fight: each side fights from its own ship's
## outer hull (armor ridges, turret housings, clamped cargo: cover), behind the armored hull
## rim along the edge, with open space between the hulls (impassable) crossed by boarding
## tubes. The far ship is the near one turned around, so both sides get the same ground.
func _boarding() -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	var gap := 4 if h % 2 == 0 else 3  # centered, so the mirror lands on the far ship
	var g0 := (h - gap) / 2
	# One ship's hull (rows 0 .. g0-1), built in a local scratch and mirrored onto the other.
	var plan := {}  # Vector2i(col, row) -> [ground, tags]
	var rim := g0 - 1
	var tubes: Array[int] = []
	var n_tubes := 2 + (1 if w >= 36 else 0)
	for i in range(n_tubes):
		tubes.append(clampi(int(w * (i + 1) / float(n_tubes + 1)) + rng.randi_range(-2, 1), 1, w - 3))
	for c in range(w):
		var in_tube := false
		for t in tubes:
			in_tube = in_tube or (c >= t and c < t + 2) or (w - 1 - c >= t and w - 1 - c < t + 2)
		# The hull rim: armored plating one level high, open where a tube docks and at a few
		# hatches.
		if not in_tube and c % 7 != 3:
			plan[Vector2i(c, rim)] = [1, ["bulkhead"]]
	# Armor ridges along the hull (straight runs), turret housings and clamped cargo.
	var row := rim - 3
	while row >= 2:
		var c := rng.randi_range(0, 3)
		while c < w - 2:
			var pick := rng.randf()
			if pick < 0.35:
				var run := rng.randi_range(3, 5)
				for k in range(run):
					if c + k < w:
						plan[Vector2i(c + k, row)] = [1, ["bulkhead", BattleMap.TAG_DESTRUCTIBLE]]
				c += run + rng.randi_range(2, 4)
			elif pick < 0.55:
				for dr in range(2):
					for dc in range(2):
						plan[Vector2i(c + dc, row - dr)] = [2, ["machinery"]]
				c += 2 + rng.randi_range(3, 5)
			elif pick < 0.75:
				var high := 1 if rng.randf() < 0.6 else 2
				for dc in range(2):
					plan[Vector2i(c + dc, row)] = [high, ["container", BattleMap.TAG_DESTRUCTIBLE]]
				c += 2 + rng.randi_range(3, 5)
			else:
				c += rng.randi_range(2, 4)
		row -= rng.randi_range(3, 5)
	# A boarding torpedo that punched through the hull: a hole in the rim, the torpedo's body
	# lodged in the deck, wreckage strewn around it (difficult).
	var bc := rng.randi_range(2, w - 5)
	for i in range(8):
		var clear := true
		for t in tubes:
			clear = clear and (bc + 2 < t - 1 or bc > t + 3) and (bc + 2 < w - t - 3 or bc > w - t)
		if clear:
			break
		bc = rng.randi_range(2, w - 5)
	for dc in range(3):
		plan[Vector2i(bc + dc, rim)] = [0, [BattleMap.TAG_DIFFICULT, "rubble"]]
		plan[Vector2i(bc + dc, rim - 2)] = [0, [BattleMap.TAG_DIFFICULT, "rubble"]]
	plan[Vector2i(bc, rim - 1)] = [0, [BattleMap.TAG_DIFFICULT, "rubble"]]
	plan[Vector2i(bc + 1, rim - 1)] = [1, ["machinery"]]  # the torpedo's body
	plan[Vector2i(bc + 2, rim - 1)] = [0, [BattleMap.TAG_DIFFICULT, "rubble"]]
	for cr: Vector2i in plan:
		var e: Array = plan[cr]
		for q: Vector2i in [cr, Vector2i(w - 1 - cr.x, h - 1 - cr.y)]:
			_put(q.x, q.y, int(e[0]), e[1])
	# Open space between the hulls; the tubes cross it.
	for r in range(g0, g0 + gap):
		for c in range(w):
			var tube := false
			for t in tubes:
				tube = tube or (c >= t and c < t + 2) or (w - 1 - c >= t and w - 1 - c < t + 2)
			if tube:
				_put(c, r, 0, ["deck"])
			else:
				_put(c, r, 0, [BattleMap.TAG_IMPASSABLE, "chasm", "void"])


## A ship's interior for a boarding fight. The outer hull (Armor 4) runs down both side edges;
## the enemy holds the top of the map, the squad the bottom. `defend` (the squad's own ship,
## boarded by pirates): boarding torpedoes have punched through the hull near the top, the
## breaches strewn with wreckage. Otherwise (the squad boards an enemy ship): they come in
## through a docking airlock in the hull near the bottom. Rooms by role: the bridge and control
## at the defenders' end, quarters, engineering and the mess in the middle, cargo holds and the
## airlock bay at the boarders' end. Inner bulkheads are often breakable; bunks and crates too.
func _ship_interior(defend: bool) -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	breakable_walls = 0.55
	# The ship's spine: a narrow corridor (2 wide) from end to end down the middle, bulkheads
	# either side with hatches into the rooms every few spaces; rooms fill both halves.
	var mid := w / 2
	var rooms: Array[Rect2i] = []
	_split(Rect2i(1, 0, mid - 3, h), 5, rooms, 0)
	_split(Rect2i(mid + 2, 0, w - mid - 3, h), 5, rooms, 0)
	for r in range(h):
		for c: int in [mid - 2, mid + 1]:
			var cell := _cell(c, r)
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var hatch := (r % 6) in [2, 3]
			var col := map.column(cell)
			col.ground = 0 if hatch else 3
			col.tags = PackedStringArray(["deck"] if hatch else ["bulkhead"])
		for c: int in [mid - 1, mid]:
			var cell := _cell(c, r)
			if map.has_cell(cell) and not blocked.has(cell):
				map.column(cell).ground = 0
				map.column(cell).tags = PackedStringArray(["deck"])
	# Rooms by how deep they lie from the boarders' edge (the top when pirates board the
	# squad's ship, the bottom when the squad boards): 0 at the breach, 1 at the far end.
	for room in rooms:
		var inner := room.grow(-1)
		if inner.size.x < 2 or inner.size.y < 2:
			continue
		var depth := float(room.get_center().y) / float(h)
		if not defend:
			depth = 1.0 - depth
		if depth > 0.7:
			_ship_room(inner, "bridge")
		elif depth > 0.35:
			_ship_room(inner, ["quarters", "engineering", "mess"][rng.randi_range(0, 2)])
		else:
			_ship_room(inner, "cargo")
	# The outer hull down both sides.
	for r in range(h):
		for c: int in [0, w - 1]:
			var cell := _cell(c, r)
			if map.has_cell(cell) and not blocked.has(cell):
				var col := map.column(cell)
				col.ground = 3
				col.tags = PackedStringArray(["bulkhead", "hull"])
	var band_r := 3 if defend else h - 4  # near the boarders' edge
	if defend:
		# Two torpedo breaches, one in each side hull, near the boarders' end.
		for side: int in [0, w - 1]:
			var r := clampi(band_r + rng.randi_range(0, 4), 1, h - 3)
			var inward := 1 if side == 0 else -1
			for dr in range(2):
				_put(side, r + dr, 0, ["breach", BattleMap.TAG_DIFFICULT, "rubble"])
				_put(side + inward * 2, r + dr, 0, [BattleMap.TAG_DIFFICULT, "rubble"])
			_put(side + inward, r, 1, ["machinery", "torpedo"])
			_put(side + inward, r + 1, 0, [BattleMap.TAG_DIFFICULT, "rubble"])
	else:
		# The docking airlock: a 2-wide opening in one side hull with a short passage in.
		var side := 0 if rng.randf() < 0.5 else w - 1
		var inward := 1 if side == 0 else -1
		var r := clampi(band_r - rng.randi_range(0, 3), 2, h - 3)
		for dr in range(2):
			_put(side, r + dr, 0, ["deck", "airlock"])
			for k in range(1, 4):
				var cell := _cell(side + inward * k, r + dr)
				if map.has_cell(cell) and not blocked.has(cell) and map.column(cell).ground > 0:
					_put(side + inward * k, r + dr, 0, ["deck"])


## Furnishes a ship room by its role: real cover, much of it breakable.
func _ship_room(inner: Rect2i, role: String) -> void:
	match role:
		"bridge":
			# Console banks in rows facing forward, a command dais (one level) in the middle.
			for r in range(inner.position.y + 1, inner.end.y - 1, 3):
				for c in range(inner.position.x + 1, inner.end.x - 1):
					if (c - inner.position.x) % 4 != 3:
						_raise(_cell(c, r), 1, ["machinery", "console", BattleMap.TAG_DESTRUCTIBLE])
		"quarters":
			# Bunk rows along the walls, lockers between.
			for r in range(inner.position.y, inner.end.y, 3):
				for c in range(inner.position.x, inner.end.x - 1, 3):
					for k in range(2):
						_raise(_cell(c + k, r), 1, ["platform", "bunk", BattleMap.TAG_DESTRUCTIBLE])
		"engineering":
			# Reactor housings and pumps (two levels), with coolant leaking from some.
			for i in range(maxi(1, inner.get_area() / 20)):
				var at := Vector2i(rng.randi_range(inner.position.x, inner.end.x - 2), rng.randi_range(inner.position.y, inner.end.y - 2))
				for dr in range(2):
					for dc in range(2):
						_raise(_cell(at.x + dc, at.y + dr), 2, ["machinery"])
				if rng.randf() < 0.5:
					var leak := _cell(at.x + 2, at.y)
					if _free(leak):
						_tag(map.column(leak), [BattleMap.TAG_DANGEROUS, "dangerous_energy"])
		"mess":
			# Tables in a grid (low, breakable) and a galley counter along one wall.
			for r in range(inner.position.y + 1, inner.end.y - 1, 3):
				for c in range(inner.position.x + 1, inner.end.x - 1, 3):
					_raise(_cell(c, r), 1, ["platform", "table", BattleMap.TAG_DESTRUCTIBLE])
			for c in range(inner.position.x, inner.end.x):
				_raise(_cell(c, inner.position.y), 1, ["machinery", "galley", BattleMap.TAG_DESTRUCTIBLE])
		_:
			# Cargo: rows of crates and containers (1-2 high) with aisles, some spilled.
			for r in range(inner.position.y, inner.end.y, 3):
				for c in range(inner.position.x, inner.end.x - 1, 3):
					if rng.randf() < 0.7:
						var high := 1 if rng.randf() < 0.6 else 2
						for k in range(2):
							_raise(_cell(c + k, r), high, ["container", BattleMap.TAG_DESTRUCTIBLE])
					elif rng.randf() < 0.5:
						var spill := _cell(c, r)
						if _free(spill):
							_tag(map.column(spill), [BattleMap.TAG_DIFFICULT, "rubble"])


## Binary space partition into rooms; walls are drawn on each split line with doorways.
func _split(r: Rect2i, min_room: int, rooms: Array[Rect2i], depth: int) -> void:
	var can_x := r.size.x >= min_room * 2 + 1
	var can_y := r.size.y >= min_room * 2 + 1
	if (not can_x and not can_y) or (depth > 1 and rng.randf() < 0.15) or depth > 6:
		rooms.append(r)
		return
	var vertical := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5))
	var destructible := rng.randf() < breakable_walls
	if vertical:
		var x := rng.randi_range(r.position.x + min_room, r.end.x - min_room - 1)
		_wall_line(Vector2i(x, r.position.y), Vector2i(0, 1), r.size.y, destructible)
		_split(Rect2i(r.position.x, r.position.y, x - r.position.x, r.size.y), min_room, rooms, depth + 1)
		_split(Rect2i(x + 1, r.position.y, r.end.x - x - 1, r.size.y), min_room, rooms, depth + 1)
	else:
		var y := rng.randi_range(r.position.y + min_room, r.end.y - min_room - 1)
		_wall_line(Vector2i(r.position.x, y), Vector2i(1, 0), r.size.x, destructible)
		_split(Rect2i(r.position.x, r.position.y, r.size.x, y - r.position.y), min_room, rooms, depth + 1)
		_split(Rect2i(r.position.x, y + 1, r.size.x, r.end.y - y - 1), min_room, rooms, depth + 1)


## A bulkhead along `n` cells from `start` (map col/row), with 1-2 doorways 2-3 wide.
func _wall_line(start: Vector2i, step: Vector2i, n: int, destructible: bool) -> void:
	var doors: Array[int] = []
	for i in range(1 if n < 12 else 2):
		doors.append(rng.randi_range(1, maxi(1, n - 4)))
	var width := rng.randi_range(2, 3)
	for i in range(n):
		var open := false
		for dpos in doors:
			if i >= dpos and i < dpos + width:
				open = true
		if open:
			continue
		var p := start + step * i
		var cell := _cell(p.x, p.y)
		if not map.has_cell(cell) or blocked.has(cell):
			continue
		var col := map.column(cell)
		col.ground = 3
		col.tags = PackedStringArray(["bulkhead", BattleMap.TAG_DESTRUCTIBLE] if destructible else ["bulkhead"])


## Raises a free cell by `levels` with tags (no-op on blocked or used cells).
func _raise(cell: Vector2i, levels: int, tags: Array) -> void:
	if not _free(cell):
		return
	var col := map.column(cell)
	col.ground += levels
	_tag(col, tags)


## Airless moon or asteroid: grey plains pocked with craters (raised rims, 1-2 levels:
## cover), boulders, loose scree (difficult). Asteroids are rougher, with rock spires and
## crevasses (impassable). Low gravity is look only here; its rules come from environments.
func _moon(asteroid: bool) -> void:
	var noise := _noise(rng.randf_range(0.04, 0.07))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + (0.2 if asteroid else 0.0)) * 2.0)), 0, 2 if asteroid else 1))
	var area := w * h
	for i in range(maxi(2, area / (160 if asteroid else 120))):
		var center := map.grid.to_world(_random_cell())
		var radius := rng.randf_range(2.5, 5.5)
		for cell in cells:
			if blocked.has(cell):
				continue
			var dist := map.grid.to_world(cell).distance_to(center)
			var col := map.column(cell)
			if dist < radius - 0.8:
				col.ground = 0
			elif dist < radius + 0.6:
				col.ground = mini(col.ground + (2 if radius > 4.0 else 1), 3)
				_tag(col, ["rock"])
	_outcrops(area / 280)
	_patches(area / 90, Vector2i(3, 7), [BattleMap.TAG_DIFFICULT], 0, true)
	if asteroid:
		for i in range(area / 200):
			var at := _random_cell()
			if _free(at):
				var col := map.column(at)
				col.ground = mini(col.ground + rng.randi_range(3, 5), 7)
				_tag(col, ["rock", BattleMap.TAG_IMPASSABLE])
		for i in range(maxi(1, area / 500)):
			for cell in _blob(_random_cell(), rng.randi_range(3, 6)):
				if _free(cell):
					var col := map.column(cell)
					col.ground = 0
					_tag(col, [BattleMap.TAG_IMPASSABLE, "chasm"])


## Open sea (shallow water: difficult) with sandy islands (palms: soft cover) and steel
## platforms on pylons (2 levels up) joined by walkways you can pass under, carrying
## containers and machinery (hard cover).
func _ocean() -> void:
	_fill(func(_c: int, _r: int) -> int: return 0)
	for cell in cells:
		if not blocked.has(cell):
			_tag(map.column(cell), [BattleMap.TAG_DIFFICULT, "water"])
	var area := w * h
	var noise := _noise(0.09)
	for cell in cells:
		if blocked.has(cell):
			continue
		var p := map.grid.to_world(cell)
		if noise.get_noise_2d(p.x, p.z) > 0.35:
			var col := map.column(cell)
			col.ground = 1
			col.tags = PackedStringArray()
	for cell in cells:
		var col := map.column(cell)
		if col.ground == 1 and col.tags.is_empty() and rng.randf() < 0.25:
			_tag(col, [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	var platforms: Array[Vector2i] = []
	for i in range(maxi(2, area / 180)):
		var c0 := rng.randi_range(2, w - 8)
		var r0 := rng.randi_range(5, h - 10)
		var pw := rng.randi_range(4, 7)
		var ph := rng.randi_range(3, 5)
		for r in range(r0, r0 + ph):
			for c in range(c0, c0 + pw):
				var cell := _cell(c, r)
				if not map.has_cell(cell) or blocked.has(cell):
					continue
				var col := map.column(cell)
				col.ground = 2
				col.tags = PackedStringArray(["platform"])
		platforms.append(Vector2i(c0 + pw / 2, r0 + ph / 2))
		# Deck cargo.
		for k in range(rng.randi_range(1, 3)):
			var at := _cell(rng.randi_range(c0, c0 + pw - 1), rng.randi_range(r0, r0 + ph - 1))
			if map.has_cell(at) and map.column(at).has_tag("platform") and not blocked.has(at):
				var col := map.column(at)
				col.ground += 1
				col.tags = PackedStringArray(["container" if rng.randf() < 0.6 else "machinery"])
	# Walkways between neighboring platforms: 2 levels up with open water underneath.
	for i in range(platforms.size() - 1):
		var a := platforms[i]
		var b := platforms[i + 1]
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for k in range(steps + 1):
			var t := float(k) / maxf(1.0, steps)
			var p := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
			var cell := _cell(p.x, p.y)
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var col := map.column(cell)
			if col.ground == 0:
				col.ground = 2
				col.gap_bottom = 0
				col.gap_top = 2
				col.tags = PackedStringArray(["platform"])


## Dense jungle: rolling ground, a river, and woods nearly everywhere (soft cover, difficult),
## with clearings, rocky outcrops and mud.
func _jungle() -> void:
	var noise := _noise(rng.randf_range(0.04, 0.06))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.35) * 2.2)), 0, 3))
	if rng.randf() < 0.8:
		_river()
	var area := w * h
	var woods := _noise(0.12)
	for cell in cells:
		if blocked.has(cell) or not map.column(cell).tags.is_empty():
			continue
		var p := map.grid.to_world(cell)
		if woods.get_noise_2d(p.x, p.z) > -0.15:
			_tag(map.column(cell), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_outcrops(area / 360)
	_patches(area / 160, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT])


## Molten world (env_moltenworld): black crust terraces and islands in lakes and rivers of
## lava. Lava is dangerous terrain (energy damage, "depending on the hazard", Core p.62); the
## environment's own lava rule keys off the "lava" tag. Basalt columns give cover.
func _molten() -> void:
	var noise := _noise(rng.randf_range(0.05, 0.08))
	var lava_noise := _noise(rng.randf_range(0.06, 0.09))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.3) * 2.6)), 0, 3))
	for cell in cells:
		if blocked.has(cell):
			continue
		var p := map.grid.to_world(cell)
		if lava_noise.get_noise_2d(p.x, p.z) > 0.18:
			var col := map.column(cell)
			col.ground = 0
			col.tags = PackedStringArray([BattleMap.TAG_DANGEROUS, "dangerous_energy", "lava"])
	var area := w * h
	_outcrops(area / 220)
	_patches(area / 120, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT], 0, true)


## Toxic swamp (env_primordealworld: "boiling mud creates numerous areas of both difficult
## and dangerous terrain"): bog water and mud (difficult), boiling mud pools (difficult and
## dangerous), dead and drowned woods (soft cover), low hummocks and rocks.
func _swamp() -> void:
	var noise := _noise(rng.randf_range(0.05, 0.08))
	var wet := _noise(rng.randf_range(0.07, 0.1))
	_fill(func(c: int, r: int) -> int: return clampi(int(floor((noise.get_noise_2d(c, r) + 0.2) * 1.8)), 0, 2))
	for cell in cells:
		if blocked.has(cell):
			continue
		var p := map.grid.to_world(cell)
		var v := wet.get_noise_2d(p.x, p.z)
		var col := map.column(cell)
		if v > 0.05 and col.ground == 0:
			col.tags = PackedStringArray([BattleMap.TAG_DIFFICULT, "water"])
		elif v > -0.1 and col.ground == 0:
			col.tags = PackedStringArray([BattleMap.TAG_DIFFICULT])
	var area := w * h
	for i in range(maxi(2, area / 130)):
		for cell in _blob(_random_cell(), rng.randi_range(2, 5)):
			if map.has_cell(cell) and not blocked.has(cell) and map.ground_height(cell) == 0:
				map.column(cell).tags = PackedStringArray([BattleMap.TAG_DIFFICULT, BattleMap.TAG_DANGEROUS, "toxic"])
	_patches(area / 80, Vector2i(3, 7), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_outcrops(area / 360)


# --- Settlements -------------------------------------------------------------------------

## A settlement built with purpose: a village on levelled ground straddling the middle of
## the battlefield (so both sides fight around it), with a main street and a cross street
## running out to the map's edges as roads (bridges where they cross a river), houses on
## plots along the streets, and fields on terraces around it with field walls in straight
## runs. Medieval worlds also get a castle: straight curtain walls, corner towers, a gate
## facing the village with a causeway over the moat, a keep, and a cleared field of fire.
func _settlement(culture: String, landscape: String) -> void:
	var cr := h / 2
	var cc := w / 2 + rng.randi_range(-w / 6, w / 6)
	if culture != "medieval":
		_village(cc, cr, culture, landscape, 0, w)
		return
	# The village's main street runs from the map edge on its side up to the castle gate;
	# the castle is built last so nothing of the village overlaps its walls.
	var side := 1 if rng.randf() < 0.5 else -1
	var kc := clampi(w / 2 + side * (w / 4), 9, w - 10)
	var vc := clampi(w / 2 - side * (w / 8), 8, w - 9)
	if side > 0:
		_village(vc, cr, culture, landscape, 0, kc)
	else:
		_village(vc, cr, culture, landscape, kc, w)
	_castle(kc, cr, culture, -side)


## Cells built on purpose (streets, plots, castles, fields): rocks and woods stay clear.
var built := {}


func _put(c: int, r: int, ground: int, tags: Array) -> bool:
	if c < 0 or r < 0 or c >= w or r >= h:
		return false
	var cell := _cell(c, r)
	if not map.has_cell(cell) or blocked.has(cell):
		return false
	var col := map.column(cell)
	col.ground = ground
	col.tags = PackedStringArray(tags)
	col.gap_top = 0
	col.gap_bottom = 0
	built[cell] = true
	return true


func _ground_at(c: int, r: int) -> int:
	var cell := _cell(clampi(c, 0, w - 1), clampi(r, 0, h - 1))
	return map.ground_height(cell) if map.has_cell(cell) else 0


# --- Exploring areas ----------------------------------------------------------------------

## An exploring area's edge profiles ({west, east, north, south}: [[ground, tags], ...] along
## the edge), shared with the neighbouring areas (MissionGenerator.area).
var edges: Dictionary = {}

## Width of the flat band along every edge of an exploring area, so neighbouring areas of a
## region meet on level ground.
const AREA_EDGE := 2


## The roads every exploring area shares: along the middle row and the middle column, out to
## all four edges, so walking off one area's east edge comes in on the next one's west edge on
## the same road.
func _area_ways() -> void:
	var row: Array = []
	for c in range(w):
		row.append(Vector2i(c, h / 2))
	_road(row, "road_x")
	var col: Array = []
	for r in range(h):
		col.append(Vector2i(w / 2, r))
	_road(col, "road_z")


## The seam to the next area: the band along each edge takes that edge's shared profile (the
## same on both sides of it), or level ground when there is none. Corners stay level.
func _area_edges() -> void:
	for r in range(h):
		for c in range(w):
			if c >= AREA_EDGE and r >= AREA_EDGE and c < w - AREA_EDGE and r < h - AREA_EDGE:
				continue
			var cell := _cell(c, r)
			if not map.has_cell(cell):
				continue
			var col := map.column(cell)
			col.gap_bottom = 0
			col.gap_top = 0
			var west := c < AREA_EDGE
			var east := c >= w - AREA_EDGE
			var north := r < AREA_EDGE
			var south := r >= h - AREA_EDGE
			var prof: Array = []
			var i := 0
			if (west or east) and not (north or south):
				prof = edges.get("west" if west else "east", [])
				i = r
			elif (north or south) and not (west or east):
				prof = edges.get("north" if north else "south", [])
				i = c
			if i < prof.size():
				col.ground = int(prof[i][0])
				col.tags = PackedStringArray(prof[i][1])
			else:
				col.ground = 0
				var on_road := ((west or east) and r == h / 2) or ((north or south) and c == w / 2)
				col.tags = PackedStringArray(["road", "road_x" if (west or east) else "road_z"] if on_road else [])


## A road along a line of map cells: keeps the ground (it follows the land), bridges water.
func _road(cells: Array, axis: String) -> void:
	for cr: Vector2i in cells:
		if cr.x < 0 or cr.y < 0 or cr.x >= w or cr.y >= h:
			continue
		var cell := _cell(cr.x, cr.y)
		if not map.has_cell(cell) or blocked.has(cell):
			continue
		var col := map.column(cell)
		if col.has_tag("water"):
			# A bridge: a deck one level up with the river open beneath it.
			col.ground = 1
			col.gap_bottom = 0
			col.gap_top = 1
			col.tags = PackedStringArray(["road", axis])
		elif col.has_tag("building") or col.has_tag("wall"):
			continue  # roads go round buildings and walls, never through them
		else:
			col.tags = PackedStringArray(["road", axis] if not col.has_tag("road") else ["road", "crossing"])
			col.ground = mini(col.ground, 2)
		built[cell] = true


func _village(cc: int, cr: int, culture: String, landscape: String, street_from: int, street_to: int) -> void:
	var rad := 7 + rng.randi_range(0, 3)
	var base := clampi(_ground_at(cc, cr), 0, 1)
	# Level the site.
	for r in range(cr - rad, cr + rad + 1):
		for c in range(cc - rad - 2, cc + rad + 3):
			var cell := _cell(clampi(c, 0, w - 1), clampi(r, 0, h - 1))
			if c < 0 or r < 0 or c >= w or r >= h or blocked.has(cell) or not map.has_cell(cell):
				continue
			if map.column(cell).has_tag("water"):
				continue
			_put(c, r, base, [])
	# Main street across the whole map, cross street through the middle.
	var main: Array = []
	var wide := culture in ["retro", "union", "industrial", "cyberpunk", "ruins", "burning", "port"]
	for c in range(street_from, street_to):
		main.append(Vector2i(c, cr))
		if wide:
			main.append(Vector2i(c, cr + 1))  # a two-lane highway through modern towns
	_road(main, "road_x")
	var cross: Array = []
	for r in range(cr - rad - 4, cr + rad + 5):
		cross.append(Vector2i(cc, r))
	_road(cross, "road_z")
	var mid := _cell(cc, cr)
	if map.has_cell(mid) and not blocked.has(mid):
		map.column(mid).tags = PackedStringArray(["road", "crossing"])
	# Houses on plots along both streets, facing them, with a gap between plots.
	var max_h: int = {"union": 3, "retro": 2}.get(culture, 2)
	var plot := func(c0: int, r0: int, pw: int, pd: int) -> void:
		# Mostly one-storey cottages and shops, a few taller houses.
		var height := 1 if rng.randf() < 0.6 else rng.randi_range(2, max_h)
		for r in range(r0, r0 + pd):
			for c in range(c0, c0 + pw):
				var cell := _cell(c, r)
				if c < 0 or r < 0 or c >= w or r >= h or not map.has_cell(cell) or blocked.has(cell):
					continue
				if map.column(cell).has_tag("road") or map.column(cell).has_tag("water"):
					continue
				_put(c, r, base + height, ["building", "house", BattleMap.TAG_DESTRUCTIBLE])
	var x := cc - rad
	while x < cc + rad - 1:
		var pw := rng.randi_range(2, 3)
		if absi(x - cc) > 1 and absi(x + pw - 1 - cc) > 1 and rng.randf() < 0.8:
			plot.call(x, cr - 3, pw, 2)
		if absi(x - cc) > 1 and absi(x + pw - 1 - cc) > 1 and rng.randf() < 0.8:
			plot.call(x, cr + 2, pw, 2)
		x += pw + 1
	var y := cr - rad + 1
	while y < cr + rad - 1:
		var pd := 2
		if absi(y - cr) > 3 and rng.randf() < 0.7:
			plot.call(cc - 3, y, 2, pd)
		if absi(y - cr) > 3 and rng.randf() < 0.7:
			plot.call(cc + 2, y, 2, pd)
		y += pd + 1
	# Yards and lots between the houses (the levelled site): paved, cobbled or packed earth.
	for r in range(cr - rad, cr + rad + 1):
		for c in range(cc - rad - 2, cc + rad + 3):
			if c < 0 or r < 0 or c >= w or r >= h:
				continue
			var cell := _cell(c, r)
			if map.has_cell(cell) and built.has(cell) and map.column(cell).tags.is_empty():
				map.column(cell).tags = PackedStringArray(["lot"])
	# A railway past the town on its own line, for frontier, industrial, port, atomic-age and
	# Union towns: a level bed, bridges over water, level crossings where it meets a road.
	if culture in RAIL_CULTURES and rng.randf() < 0.75:
		var rr := cr - rad - 3
		if rr >= 2:
			var line: Array = []
			for c in range(w):
				line.append(Vector2i(c, rr))
			_rail(line, base)
	# Fields around the village on terraces (levelled plots), with field walls.
	if landscape in ["grassy_hills", "tundra", "jungle", "toxic_swamp", "desert_mesas"] and culture != "cyberpunk":
		var want := 5 + rng.randi_range(0, 3)
		var got := 0
		for i in range(40):
			if got >= want:
				break
			var a := rng.randf() * TAU
			var d := rad + rng.randf_range(3.0, 10.0)
			var fc := cc + int(cos(a) * d)
			var fr := cr + int(sin(a) * d * 0.8)
			if _field(fc, fr, rng.randi_range(4, 6), rng.randi_range(3, 4), landscape == "desert_mesas"):
				got += 1


## A field: levelled to its lowest corner (a terrace on a slope), crop rows, and a field wall
## along one or two edges in a straight run with a gateway gap.
func _field(c0: int, r0: int, fw: int, fh: int, dry: bool) -> bool:
	var lowest := 99
	for r in range(r0, r0 + fh):
		for c in range(c0, c0 + fw):
			var cell := _cell(c, r)
			if c < 0 or r < 0 or c >= w or r >= h or not map.has_cell(cell) or blocked.has(cell) or built.has(cell):
				return false  # don't overlap anything built or a zone
			if map.column(cell).has_tag("water") or map.column(cell).has_tag(BattleMap.TAG_IMPASSABLE):
				return false
			lowest = mini(lowest, map.ground_height(cell))
	for r in range(r0, r0 + fh):
		for c in range(c0, c0 + fw):
			_put(c, r, lowest, ["farm"] if not dry else ["farm", "dry"])
	if rng.randf() < 0.7:
		var gate := rng.randi_range(1, fw - 2)
		for c in range(c0, c0 + fw):
			if c != gate + c0 and _ground_at(c, r0 - 1) <= lowest:
				var cell := _cell(c, r0 - 1)
				if map.has_cell(cell) and not built.has(cell):
					_put(c, r0 - 1, lowest + 1, ["wall", BattleMap.TAG_DESTRUCTIBLE])
	return true


## A castle centred on (cc, cr): straight curtain walls (2 levels) with 2x2 corner towers
## (3 levels), a 2-wide gate in the wall facing the village (gate_dir -1 west, +1 east) on the
## main street's row, a moat with a causeway, a keep at the back, and a cleared field of fire
## around it. Walls and towers are stone and can be breached.
func _castle(cc: int, cr: int, _culture: String, gate_dir: int) -> void:
	var iw := rng.randi_range(8, 10)
	var ih := rng.randi_range(6, 8)
	# Walls and moat must stand whole: shrink to stay clear of deployment and objective zones,
	# or build no castle at all.
	while ih >= 4 and _rect_blocked(Rect2i(cc - iw / 2 - 2, cr - ih / 2 - 2, iw + 4, ih + 4)):
		ih -= 2
		iw -= 2
	if ih < 4:
		return
	var c0 := cc - iw / 2 - 1
	var r0 := cr - ih / 2 - 1
	var cw := iw + 2
	var ch := ih + 2
	var base := 1
	# Field of fire: clear and level everything around (moat ring + 3).
	for r in range(r0 - 5, r0 + ch + 5):
		for c in range(c0 - 5, c0 + cw + 5):
			_put(c, r, base, [])
	# Moat.
	for r in range(r0 - 1, r0 + ch + 1):
		for c in range(c0 - 1, c0 + cw + 1):
			var edge := r == r0 - 1 or r == r0 + ch or c == c0 - 1 or c == c0 + cw
			if edge:
				_put(c, r, 0, [BattleMap.TAG_DIFFICULT, "water"])
	# Curtain walls and corner towers.
	var gate_col := c0 + cw - 1 if gate_dir > 0 else c0
	for r in range(r0, r0 + ch):
		for c in range(c0, c0 + cw):
			var on_wall := r == r0 or r == r0 + ch - 1 or c == c0 or c == c0 + cw - 1
			if not on_wall:
				continue
			if c == gate_col and (r == cr or r == cr - 1):
				_put(c, r, base, ["road", "road_x"])
				continue
			_put(c, r, base + 2, ["wall", BattleMap.TAG_DESTRUCTIBLE])
	for corner: Vector2i in [Vector2i(c0, r0), Vector2i(c0 + cw - 2, r0), Vector2i(c0, r0 + ch - 2), Vector2i(c0 + cw - 2, r0 + ch - 2)]:
		for dr in range(2):
			for dc in range(2):
				_put(corner.x + dc, corner.y + dr, base + 3, ["wall", BattleMap.TAG_DESTRUCTIBLE])
	# Keep against the back wall, courtyard in front of the gate.
	var keep_c := c0 + 1 if gate_dir > 0 else c0 + cw - 4
	for dr in range(3):
		for dc in range(3):
			_put(keep_c + dc, cr - 2 + dr, base + 3, ["building", "keep", BattleMap.TAG_DESTRUCTIBLE])
	# Causeway over the moat, then the gate road across the field of fire to the village.
	for rr: int in [cr - 1, cr]:
		_put(gate_col + gate_dir, rr, base, ["road", "road_x"])  # causeway
		var c := gate_col + 2 * gate_dir
		while c >= 0 and c < w:
			var cell := _cell(c, rr)
			if not map.has_cell(cell) or blocked.has(cell):
				break
			if map.column(cell).has_tag("road") and rr == cr and absi(c - gate_col) > 6:
				break  # met the village street
			if rr == cr - 1 and absi(c - gate_col) > 5:
				break  # the second lane only runs over the field of fire
			_road([Vector2i(c, rr)], "road_x")
			c += gate_dir


## Natural rock never stands in or against anything built: rock within two spaces of a
## building, wall, road, lot or field is levelled to the ground around it (outcrops placed
## later keep their own distance). Landscapes that raise ridges first (salt flats, mesas)
## would otherwise leave a rock wall running into a house.
func _clear_rock_near_built() -> void:
	var near := {}
	for cell in cells:
		var col := map.column(cell)
		if col.has_tag("rock"):
			continue
		for tag: String in ["building", "house", "keep", "wall", "road", "lot", "farm"]:
			if col.has_tag(tag):
				for n in map.grid.cells_within(cell, 2):
					near[n] = true
				break
	for cell in cells:
		var col := map.column(cell)
		if not col.has_tag("rock") or not near.has(cell):
			continue
		var low := 99
		for n in map.grid.neighbors(cell):
			if map.has_cell(n) and not map.column(n).has_tag("rock"):
				low = mini(low, map.ground_height(n))
		col.ground = 0 if low == 99 else low
		col.tags = PackedStringArray()


## Parked vehicles along the curbs of streets two lanes or wider (outer lanes only, never at
## crossings, crosswalks or on the highway): objects on the board, soft cover and breakable.
## PROVISIONAL (docs/RULES_TODO.md "Parked vehicles"): the book gives objects Evasion 5 and
## 10 HP per Size (Core p.68) but doesn't say whether something this much smaller than a mech
## covers it; read as soft cover until the rules session confirms.
func _parked_vehicles(landscape: String, culture: String) -> void:
	if landscape in ["station", "starship", "boarding", "boarding_defend", "boarding_assault"]:
		return
	if culture in ["medieval"]:
		return  # carts on cobbles stay scenery-sized; no motor traffic
	var rate := 0.1 if landscape == "city" else 0.07
	for cell in cells:
		var col := map.column(cell)
		if not col.has_tag("road") or col.gap_top > 0 or blocked.has(cell):
			continue
		if col.has_tag("crossing") or col.has_tag("crosswalk") or col.has_tag("highway") or col.has_tag("rail"):
			continue
		var outer := false
		for t in col.tags:
			if t.begins_with("lane"):
				var p := t.trim_prefix("lane").split("_")
				outer = int(p[1]) >= 2 and (int(p[0]) == 0 or int(p[0]) == int(p[1]) - 1)
		if outer and rng.randf() < rate:
			col.tags.append_array(["vehicle", Sight.TAG_SOFT_COVER, BattleMap.TAG_DESTRUCTIBLE])


## Towns that get a railway past them.
const RAIL_CULTURES := ["old_west", "industrial", "port", "retro", "union"]


## A railway along a line of map cells on a level bed: over water a bridge, over a road a
## level crossing (still a road), buildings and walls left alone. Look only: track is open ground.
func _rail(cells: Array, level: int) -> void:
	for cr: Vector2i in cells:
		if cr.x < 0 or cr.y < 0 or cr.x >= w or cr.y >= h:
			continue
		var cell := _cell(cr.x, cr.y)
		if not map.has_cell(cell) or blocked.has(cell):
			continue
		var col := map.column(cell)
		if col.has_tag("building") or col.has_tag("wall") or col.has_tag("house"):
			continue
		if col.has_tag("water"):
			col.ground = level + 1
			col.gap_bottom = 0
			col.gap_top = level + 1
			col.tags = PackedStringArray(["rail", "rail_x"])
		elif col.has_tag("road"):
			col.tags.append("rail")  # a level crossing
		else:
			col.ground = level
			col.tags = PackedStringArray(["rail", "rail_x"])
		built[cell] = true


## An elevated highway along two rows (row0, row0 + 1): a deck two levels up on pillars, the
## street open beneath it (gap columns: units pass under and stand on top), ramps down to the
## ground at both ends.
func _elevated(row0: int) -> void:
	for r in [row0, row0 + 1]:
		for c in range(w):
			var cell := _cell(c, r)
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var col := map.column(cell)
			var lift := 2
			if c < 2 or c >= w - 2:
				lift = 1  # the ramps
			col.ground = lift
			col.gap_bottom = 0
			col.gap_top = lift
			col.tags = PackedStringArray(["road", "road_x", "highway"])
			built[cell] = true
	# On- and off-ramps: from the boulevard's outer lanes up to the deck, two spaces long (one
	# level a step), one on each side, a third of the way along.
	for side: Array in [[row0 - 1, w / 3], [row0 + 2, (w * 2) / 3]]:
		for k in range(2):
			var c: int = side[1] + k
			var cell := _cell(c, side[0])
			if not map.has_cell(cell) or blocked.has(cell):
				continue
			var col := map.column(cell)
			col.ground = k + 1
			col.gap_bottom = 0
			col.gap_top = k + 1
			col.tags = PackedStringArray(["road", "road_x", "highway", "ramp"])


## Lane tags for the road markings: for each straight road cell, its place across the road and
## the road's width ("lane<i>_<n>": i from the low side, n up to 6). One space: an alley or a
## lane; two or three: a street with lane lines; four or more: a boulevard with a median.
func _lane_tags() -> void:
	var road_at := func(c: int, r: int, axis: String) -> bool:
		if c < 0 or r < 0 or c >= w or r >= h:
			return false
		var cell := _cell(c, r)
		return map.has_cell(cell) and map.column(cell).has_tag("road") and map.column(cell).has_tag(axis) and not map.column(cell).has_tag("crossing")
	for r in range(h):
		for c in range(w):
			var cell := _cell(c, r)
			if not map.has_cell(cell):
				continue
			var col := map.column(cell)
			if not col.has_tag("road") or col.has_tag("crossing"):
				continue
			var axis := "road_z" if col.has_tag("road_z") else "road_x"
			var step := Vector2i(0, 1) if axis == "road_x" else Vector2i(1, 0)
			var lo := 0
			while road_at.call(c - step.x * (lo + 1), r - step.y * (lo + 1), axis):
				lo += 1
			var hi := 0
			while road_at.call(c + step.x * (hi + 1), r + step.y * (hi + 1), axis):
				hi += 1
			var n := mini(lo + hi + 1, 6)
			col.tags.append("lane%d_%d" % [mini(lo, n - 1), n])
			# A crosswalk on the stretch right before an intersection (streets, not alleys).
			var ahead := Vector2i(1, 0) if axis == "road_x" else Vector2i(0, 1)
			if n >= 2:
				for sgn: int in [-1, 1]:
					var q := Vector2i(c, r) + ahead * sgn
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
						var qc := _cell(q.x, q.y)
						if map.has_cell(qc) and map.column(qc).has_tag("crossing"):
							col.tags.append("crosswalk")
							break


func _rect_blocked(r: Rect2i) -> bool:
	for rr in range(r.position.y, r.end.y):
		for c in range(r.position.x, r.end.x):
			if c < 0 or rr < 0 or c >= w or rr >= h or blocked.has(_cell(c, rr)):
				return true
	return false


## Rock outcrops in believable clusters: a tall core with lower stones around it, only on
## open land away from anything built, roads and water (4+ spaces).
func _outcrops(count: int) -> void:
	pending_outcrops += count


func _place_outcrops() -> void:
	var near := {}
	for cell: Vector2i in built:
		for n in map.grid.cells_within(cell, 4):
			near[n] = true
	for cell in cells:
		var col := map.column(cell)
		if col.has_tag("water") or col.has_tag("building") or col.has_tag("road"):
			for n in map.grid.cells_within(cell, 2):
				near[n] = true
	var placed := 0
	var tries := 0
	while placed < pending_outcrops and tries < pending_outcrops * 8:
		tries += 1
		var at := _random_cell()
		if near.has(at) or not _free(at):
			continue
		var base := map.ground_height(at)
		var size := rng.randi_range(3, 7)
		var core := _blob(at, size)
		for cell in core:
			if near.has(cell) or not _free(cell) or absi(map.ground_height(cell) - base) > 1:
				continue
			var col := map.column(cell)
			var tall := cell == at or (cell in map.grid.neighbors(at) and rng.randf() < 0.4)
			col.ground = mini(base + (2 if tall else 1), 6)
			_tag(col, ["rock"])
			near[cell] = true
		placed += 1


## Deployment and objective cells stay low, open and safe whatever was built.
func _clear_blocked() -> void:
	for cell: Vector2i in blocked:
		if not map.has_cell(cell):
			continue
		var col := map.column(cell)
		col.ground = mini(col.ground, 1)
		col.gap_top = 0
		col.gap_bottom = 0
		var keep := PackedStringArray()
		if col.has_tag(BattleMap.TAG_DIFFICULT) and not col.has_tag(Sight.TAG_SOFT_COVER) and col.tags.size() == 1:
			keep.append(BattleMap.TAG_DIFFICULT)  # plain rough ground may stay
		col.tags = keep
