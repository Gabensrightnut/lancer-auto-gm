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
	"toxic_marsh": 1, "molten_world": 1, "toxic_swamp": 1, "city": 3, "station": 1, "starship": 1, "moon": 1, "asteroid": 1, "ocean": 1, "jungle": 2}
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
	"moon": ["", "", "union", "retro"],
	"asteroid": [""],
	"ocean": ["", "east_asian", "retro", "union"],
	"jungle": ["", "", "east_asian", "medieval"],
	"city": ["ruins", "cyberpunk", "burning", "union", "retro", "east_asian", "medieval", "old_west"],
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
		"station", "starship":
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
}


static func pick_weather(rng: RandomNumberGenerator, landscape: String, culture: String = "") -> String:
	var options: Array = WEATHER.get(landscape, [""])
	if culture == "burning":
		return "ashfall"
	if culture == "cyberpunk":
		options = ["rain", "rain", "storm"]
	return str(options[rng.randi_range(0, options.size() - 1)])


## Kit name for the renderer ("landscape" or "landscape/culture").
static func kit(landscape: String, culture: String) -> String:
	return landscape if culture == "" else "%s/%s" % [landscape, culture]


static func generate(rng: RandomNumberGenerator, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary, landscape: String, culture: String) -> BattleMap:
	var g := TerrainGen.new()
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
		"moon":
			g._moon(false)
		"asteroid":
			g._moon(true)
		"ocean":
			g._ocean()
		"jungle":
			g._jungle()
		"molten_world":
			g._molten()
		"toxic_swamp":
			g._swamp()
		_:
			g._hills()
	if landscape != "city" and culture != "":
		g._settlement(culture)
	g._clear_blocked()
	return g.map


var rng: RandomNumberGenerator
var w := 0
var h := 0
var shape: GridLayout.Shape
var blocked: Dictionary
var map: BattleMap
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
	_patches(area / 55, Vector2i(1, 3), ["rock"], 2)
	_patches(area / 110, Vector2i(3, 7), [Sight.TAG_SOFT_COVER, BattleMap.TAG_DIFFICULT, "woods"])
	_patches(area / 140, Vector2i(2, 5), [BattleMap.TAG_DIFFICULT])


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
	_patches(area / 70, Vector2i(1, 2), ["rock"], 1)
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
	_patches(area / 60, Vector2i(1, 3), ["rock"], 2)
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
	_patches(area / 50, Vector2i(1, 3), ["rock"], 2)
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
	var tall: int = {"cyberpunk": 6, "union": 6, "ruins": 5, "burning": 5, "retro": 4, "east_asian": 4}.get(culture, 3)
	var ruined := culture in ["ruins", "burning"]
	var bx := 0
	var off_c := rng.randi_range(-2, 1)
	var off_r := rng.randi_range(-2, 1)
	for r0 in range(off_r, h, block + street):
		for c0 in range(off_c, w, block + street):
			var kind := rng.randf()
			if kind < 0.18:
				_plaza(c0, r0, block)
				continue
			# Split the block into lots; each lot is a building of its own height.
			var lots := _split_block(c0, r0, block)
			for lot: Rect2i in lots:
				var height := rng.randi_range(1, tall)
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
			bx += 1
	var area := w * h
	if ruined:
		# Rubble spills into the streets, craters and burning wrecks.
		_patches(area / 140, Vector2i(2, 4), [BattleMap.TAG_DIFFICULT, "rubble"], 0, true)
		_patches(area / (180 if culture == "burning" else 400), Vector2i(1, 3), [BattleMap.TAG_DANGEROUS], 0, true)
	# Destructible barricades: short walls across some streets.
	for i in range(area / 220):
		var at := _random_cell()
		if _free(at) and map.ground_height(at) == 0:
			var line := _blob(at, rng.randi_range(2, 3))
			for cell in line:
				if _free(cell) and map.ground_height(cell) == 0:
					var col := map.column(cell)
					col.ground = 1
					_tag(col, ["wall", BattleMap.TAG_DESTRUCTIBLE])


func _split_block(c0: int, r0: int, block: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var cut_c := c0 + rng.randi_range(2, block - 2)
	var cut_r := r0 + rng.randi_range(2, block - 2)
	match rng.randi_range(0, 2):
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
			elif not park and rng.randf() < 0.08:
				var col := map.column(cell)
				col.ground = 1
				_tag(col, ["wall"])  # monument plinths, planters


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


## Binary space partition into rooms; walls are drawn on each split line with doorways.
func _split(r: Rect2i, min_room: int, rooms: Array[Rect2i], depth: int) -> void:
	var can_x := r.size.x >= min_room * 2 + 1
	var can_y := r.size.y >= min_room * 2 + 1
	if (not can_x and not can_y) or (depth > 1 and rng.randf() < 0.15) or depth > 6:
		rooms.append(r)
		return
	var vertical := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5))
	var destructible := rng.randf() < 0.3
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
	_patches(area / 70, Vector2i(1, 2), ["rock"], 1)
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
	_patches(area / 90, Vector2i(1, 3), ["rock"], 2)
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
	_patches(area / 55, Vector2i(1, 3), ["rock"], 2)
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
	_patches(area / 90, Vector2i(1, 2), ["rock"], 2)


# --- Settlements -------------------------------------------------------------------------

## A village or outpost in the culture's style: clusters of 1-4 cell buildings (1-3 levels)
## on level ground, and for medieval worlds a stretch of town wall.
func _settlement(culture: String) -> void:
	var area := w * h
	var clusters := maxi(2, area / 260)
	var max_h: int = {"union": 4, "retro": 3}.get(culture, 2)
	for k in range(clusters):
		var at := _random_cell()
		if not _free(at):
			continue
		var base := map.ground_height(at)
		var houses := rng.randi_range(2, 5)
		for i in range(houses):
			var start := at
			for n in range(rng.randi_range(0, 4)):
				var next := map.grid.neighbors(start)
				var cand: Vector2i = next[rng.randi_range(0, next.size() - 1)]
				if map.has_cell(cand):
					start = cand
			var footprint := _blob(start, rng.randi_range(1, 4))
			var height := rng.randi_range(1, max_h)
			for cell in footprint:
				if not _free(cell) or map.ground_height(cell) != base:
					continue
				var col := map.column(cell)
				col.ground = base + height
				_tag(col, ["building"])
	if culture == "medieval":
		# A broken run of town wall (hard cover; destructible) with gaps to walk through.
		var at := _random_cell()
		var dir := map.grid.neighbors(Vector2i.ZERO)[rng.randi_range(0, 5 if shape == GridLayout.Shape.HEX else 3)]
		var cell := at
		for i in range(rng.randi_range(6, 12)):
			if _free(cell) and rng.randf() > 0.2:
				var col := map.column(cell)
				col.ground += 1
				_tag(col, ["wall", BattleMap.TAG_DESTRUCTIBLE])
			cell += dir
			if not map.has_cell(cell):
				break


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
