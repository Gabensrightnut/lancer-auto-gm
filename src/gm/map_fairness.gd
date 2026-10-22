class_name MapFairness
extends RefCounted
## Checks and fixes a generated battlefield so neither side starts ahead:
## - cover balance: each half of the map (the players' side and the enemy's) has a similar
##   amount of cover (raised terrain and soft cover);
## - no spawn camping: a good part of each deployment zone is out of sight of the whole
##   opposing deployment zone (solid terrain in between), so nobody is shot as they arrive;
## - reachable objectives: mechs of Size 1, 2 and 3 can walk (and climb) from their
##   deployment zone to every zone and to the enemy, with room for their footprint.
## PROVISIONAL (GM choice, not a book rule): the thresholds below. The book only asks for
## "roughly symmetrical" Control Zones.

const MIN_COVER_RATIO := 0.6
const MIN_HIDDEN := 0.25
const SIZES := [1.0, 2.0, 3.0]
## Height of the line of sight above the ground: the upper part of a Size 1 mech.
const EYE := 0.9
const SAMPLES := 16
## Deployment cells tested per zone (spread evenly) when estimating how much is hidden.
const ZONE_SAMPLES := 48


## All checks. layout: SitrepLayout output (deployment, zones). Returns
## {"ok", "cover": [players, enemies], "hidden": {side: fraction}, "unreachable": [text]}.
static func check(map: BattleMap, layout: Dictionary, h: int) -> Dictionary:
	var cover := cover_counts(map, layout, h)
	var hidden := {}
	var dep: Dictionary = layout["deployment"]
	hidden[Mission.PLAYERS] = hidden_fraction(map, dep[Mission.PLAYERS], dep[Mission.ENEMIES])
	hidden[Mission.ENEMIES] = hidden_fraction(map, dep[Mission.ENEMIES], dep[Mission.PLAYERS])
	var unreachable := unreachable_objectives(map, layout)
	var ratio := _ratio(cover)
	# Destructible cover: when a map has a fair amount, neither side should hold most of it.
	var breakable := cover_counts(map, layout, h, true)
	var breakable_ok := maxi(breakable[0], breakable[1]) < 8 or _ratio(breakable) >= MIN_COVER_RATIO
	# Holdout puts the squad in the middle with the enemy on three sides by design (the book
	# protects them with fortifications instead), so only the attackers need hiding places.
	var players_need := 0.0 if str(layout.get("sitrep", "")) == "sitrep_holdout" else MIN_HIDDEN
	var ok := (ratio >= MIN_COVER_RATIO or maxi(cover[0], cover[1]) < 6) and float(hidden[Mission.PLAYERS]) >= players_need \
		and float(hidden[Mission.ENEMIES]) >= MIN_HIDDEN and unreachable.is_empty() and breakable_ok
	return {"ok": ok, "cover": cover, "cover_ratio": ratio, "hidden": hidden, "unreachable": unreachable,
		"destructible": breakable, "destructible_ratio": _ratio(breakable)}


## Cover cells in the players' half and the enemy's half (outside deployment zones).
## destructible_only: count only cover that can be destroyed.
static func cover_counts(map: BattleMap, layout: Dictionary, h: int, destructible_only: bool = false) -> Array:
	var skip := _cells_of_deployment(layout)
	var counts := [0, 0]
	for c in map.cells():
		if skip.has(c) or not is_cover(map, c):
			continue
		if destructible_only and not map.column(c).has_tag(BattleMap.TAG_DESTRUCTIBLE):
			continue
		var row := c.y
		if row * 2 + 1 == h:
			continue
		counts[0 if row * 2 >= h else 1] += 1
	return counts


static func is_cover(map: BattleMap, c: Vector2i) -> bool:
	var col := map.column(c)
	if col.has_tag(Sight.TAG_SOFT_COVER):
		return true
	var low := col.ground
	for n in map.grid.neighbors(c):
		if map.has_cell(n):
			low = mini(low, map.ground_height(n))
	return col.ground - low >= 1 and not col.has_tag(BattleMap.TAG_IMPASSABLE) or col.ground - low >= 2


## Share of `zone` cells that no sampled cell of `from` can see (eye height EYE above ground).
static func hidden_fraction(map: BattleMap, zone: Array, from: Array) -> float:
	if zone.is_empty() or from.is_empty():
		return 1.0
	var samples: Array[Vector2i] = []
	var step := maxf(1.0, float(from.size()) / SAMPLES)
	var f := 0.0
	while int(f) < from.size() and samples.size() < SAMPLES:
		samples.append(Vector2i(from[int(f)][0], from[int(f)][1]))
		f += step
	var hidden := 0
	var checked := 0
	var zstep := maxi(1, zone.size() / ZONE_SAMPLES)
	for zi in range(0, zone.size(), zstep):
		var z: Array = zone[zi]
		checked += 1
		var p := Vector2i(z[0], z[1])
		var seen := false
		for s in samples:
			if _sees(map, s, p):
				seen = true
				break
		if not seen:
			hidden += 1
	return float(hidden) / maxi(1, checked)


static func _sees(map: BattleMap, a: Vector2i, b: Vector2i) -> bool:
	var line := map.grid.line(a, b)
	var n := line.size()
	if n <= 2:
		return true
	var ya := map.ground_height(a) + EYE
	var yb := map.ground_height(b) + EYE
	for k in range(1, n - 1):
		var c: Vector2i = line[k]
		if not map.has_cell(c):
			continue
		var y := lerpf(ya, yb, float(k) / (n - 1))
		var col := map.column(c)
		if col.ground > y and not (col.gap_top > 0 and y >= col.gap_bottom and y < col.gap_top):
			return false
	return true


## Objectives (zones, the enemy deployment zone) that some Size can't reach on foot from its
## side's deployment zone. Climbing any height is allowed (it costs movement); impassable
## cells, the map's edge and footprint room are what stop a mech.
static func unreachable_objectives(map: BattleMap, layout: Dictionary) -> Array:
	var state := GameState.new(0, map.grid.shape)
	state.map = map
	var out: Array = []
	var dep: Dictionary = layout["deployment"]
	var targets := {"enemy deployment": dep[Mission.ENEMIES]}
	for z: String in layout["zones"]:
		targets[z] = layout["zones"][z]
	for size: float in SIZES:
		var reach := _reachable(state, size, dep[Mission.PLAYERS])
		if reach.is_empty():
			out.append("Size %s has nowhere to deploy" % size)
			continue
		for name: String in targets:
			var hit := false
			for t: Array in targets[name]:
				# The footprint only has to touch the zone.
				for c in map.grid.cells_within(Vector2i(t[0], t[1]), int(ceil(size)) - 1):
					if reach.has(c):
						hit = true
						break
				if hit:
					break
			if not hit:
				out.append("Size %s can't reach %s" % [size, name])
	return out


## Anchors a mech of `size` can stand on, connected to `starts`. Same test as
## Movement.placement (every footprint cell on the map and passable, room for the mech's
## height, standing on something), on cached column data for speed.
static func _reachable(state: GameState, size: float, starts: Array) -> Dictionary:
	var map := state.map
	var grid := map.grid
	var height := GridLayout.spaces_per_side(size)
	var offsets: Array[Vector2i] = []
	for c in grid.footprint(Vector2i.ZERO, size):
		offsets.append(c)
	var ok_cache := {}
	var can_stand := func(anchor: Vector2i) -> bool:
		if ok_cache.has(anchor):
			return ok_cache[anchor]
		var good := false
		var cols: Array = []
		var levels := {}
		for o in offsets:
			var col := map.column(anchor + o)
			if col == null or col.has_tag(BattleMap.TAG_IMPASSABLE):
				ok_cache[anchor] = false
				return false
			cols.append(col)
			levels[col.ground] = true
			if col.gap_top > 0:
				levels[col.gap_bottom] = true
		for lv: int in levels:
			var room := true
			var supported := 0
			for col: BattleMap.Column in cols:
				for k in range(height):
					var y := lv + k
					if y < col.ground and not (col.gap_top > 0 and y >= col.gap_bottom and y < col.gap_top):
						room = false
						break
				if not room:
					break
				var below := lv - 1
				if lv == 0 or (below < col.ground and not (col.gap_top > 0 and below >= col.gap_bottom and below < col.gap_top)):
					supported += 1
			if room and supported > 0:
				good = true
				break
		ok_cache[anchor] = good
		return good
	var seen := {}
	var queue: Array[Vector2i] = []
	for s: Array in starts:
		var c := Vector2i(s[0], s[1])
		if not seen.has(c) and can_stand.call(c):
			seen[c] = true
			queue.append(c)
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		for n in grid.neighbors(c):
			if not seen.has(n) and map.has_cell(n) and can_stand.call(n):
				seen[n] = true
				queue.append(n)
	return seen


static func _cells_of_deployment(layout: Dictionary) -> Dictionary:
	var out := {}
	for side: String in layout["deployment"]:
		for c: Array in layout["deployment"][side]:
			out[Vector2i(c[0], c[1])] = true
	return out


# --- Repairs -------------------------------------------------------------------------------

## Fixes what check() finds, changing only open ground between the deployment zones. New
## cover comes in mirrored pairs (point symmetry through the map's center), so fixing one
## side never favors it. `cover_tags` is the landscape's look for a raised block.
static func repair(map: BattleMap, layout: Dictionary, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary,
		rng: RandomNumberGenerator, cover_tags: Array) -> Dictionary:
	var dep: Dictionary = layout["deployment"]
	# Screens across sight lines between the deployment zones until both have hiding places.
	for side: String in [Mission.PLAYERS, Mission.ENEMIES]:
		if side == Mission.PLAYERS and str(layout.get("sitrep", "")) == "sitrep_holdout":
			continue
		var other := Mission.ENEMIES if side == Mission.PLAYERS else Mission.PLAYERS
		var guard := 0
		while guard < 36 and hidden_fraction(map, dep[side], dep[other]) < MIN_HIDDEN:
			guard += 1
			# A short wall across the line from a random enemy cell to a random friendly cell,
			# partway along it (nearer the zone being screened), plus its mirror image.
			var a: Array = dep[other][rng.randi_range(0, dep[other].size() - 1)]
			var b: Array = dep[side][rng.randi_range(0, dep[side].size() - 1)]
			var line := map.grid.line(Vector2i(a[0], a[1]), Vector2i(b[0], b[1]))
			if line.size() < 5:
				continue
			var at: Vector2i = line[int(line.size() * rng.randf_range(0.6, 0.85))]
			var dir := Vector2(b[0] - a[0], b[1] - a[1]).normalized()
			var across := Vector2(-dir.y, dir.x)
			var cr := _col_row(at, shape)
			for k in range(-2, 3):
				var p := Vector2(cr.x, cr.y) + across * k
				_raise_pair(map, int(round(p.x)), int(round(p.y)), w, h, shape, blocked, 1 if guard <= 12 else 2, cover_tags)
	# Cover balance: copy cover from the richer half into the poorer half, mirrored.
	var guard2 := 0
	var counts := cover_counts(map, layout, h)
	while guard2 < 60 and _ratio(counts) < MIN_COVER_RATIO and maxi(counts[0], counts[1]) >= 6:
		guard2 += 1
		var rich_players: bool = counts[0] > counts[1]
		var picks: Array[Vector2i] = []
		for cell in map.cells():
			if (cell.y * 2 >= h) == rich_players and is_cover(map, cell):
				picks.append(cell)
		if picks.is_empty():
			break
		for i in range(4):
			var src := picks[rng.randi_range(0, picks.size() - 1)]
			var col_row := _col_row(src, shape)
			var dst := SitrepLayout.cell_of(w - 1 - col_row.x, h - 1 - col_row.y, shape)
			if blocked.has(dst) or not map.has_cell(dst):
				# The mirror spot is a zone: use a random open spot in the poorer half instead.
				var row := rng.randi_range(h / 2, h - 1) if not rich_players else rng.randi_range(0, h / 2 - 1)
				dst = SitrepLayout.cell_of(rng.randi_range(0, w - 1), row, shape)
			_copy_cover(map, src, dst, blocked)
		counts = cover_counts(map, layout, h)
	# Destructible balance: mark cover destructible in the poorer half, mirroring the richer.
	var guard3 := 0
	var br := cover_counts(map, layout, h, true)
	while guard3 < 40 and maxi(br[0], br[1]) >= 8 and _ratio(br) < MIN_COVER_RATIO:
		guard3 += 1
		var rich_players: bool = br[0] > br[1]
		var picks: Array[Vector2i] = []
		for cell in map.cells():
			if (cell.y * 2 >= h) == rich_players and is_cover(map, cell) and map.column(cell).has_tag(BattleMap.TAG_DESTRUCTIBLE):
				picks.append(cell)
		if picks.is_empty():
			break
		for i in range(3):
			var src := picks[rng.randi_range(0, picks.size() - 1)]
			var col_row := _col_row(src, shape)
			var dst := SitrepLayout.cell_of(w - 1 - col_row.x, h - 1 - col_row.y, shape)
			if map.has_cell(dst) and is_cover(map, dst) and not map.column(dst).has_tag(BattleMap.TAG_IMPASSABLE):
				_tag_destructible(map, dst)
			else:
				# No cover there: knock the tag off the richer side instead.
				var tags := map.column(src).tags
				if tags.has(BattleMap.TAG_DESTRUCTIBLE):
					tags.remove_at(tags.find(BattleMap.TAG_DESTRUCTIBLE))
					map.column(src).tags = tags
		br = cover_counts(map, layout, h, true)
	# Reachability: open a path for whatever Size is stuck.
	var result := check(map, layout, h)
	if not (result["unreachable"] as Array).is_empty():
		var players: Array = dep[Mission.PLAYERS]
		var from := Vector2i(players[players.size() / 2][0], players[players.size() / 2][1])
		var goals: Array = [dep[Mission.ENEMIES]]
		for z: String in layout["zones"]:
			goals.append(layout["zones"][z])
		for g: Array in goals:
			var to := Vector2i(g[g.size() / 2][0], g[g.size() / 2][1])
			for c in map.grid.line(from, to):
				for n in map.grid.cells_within(c, 2):
					if not map.has_cell(n):
						continue
					var col := map.column(n)
					if col.has_tag(BattleMap.TAG_IMPASSABLE) or col.gap_top > 0:
						col.tags = PackedStringArray()
						col.gap_top = 0
						col.gap_bottom = 0
						col.ground = mini(col.ground, 1)
		result = check(map, layout, h)
	return result


static func _ratio(counts: Array) -> float:
	return float(mini(counts[0], counts[1])) / maxf(1.0, maxi(counts[0], counts[1]))


static func _tag_destructible(map: BattleMap, c: Vector2i) -> void:
	var tags := map.column(c).tags
	if not tags.has(BattleMap.TAG_DESTRUCTIBLE):
		tags.append(BattleMap.TAG_DESTRUCTIBLE)
		map.column(c).tags = tags


static func _col_row(cell: Vector2i, shape: GridLayout.Shape) -> Vector2i:
	return Vector2i(cell.x + (cell.y >> 1), cell.y) if shape == GridLayout.Shape.HEX else cell


static func _raise_pair(map: BattleMap, c: int, r: int, w: int, h: int, shape: GridLayout.Shape, blocked: Dictionary, levels: int, tags: Array) -> void:
	var pair: Array[Vector2i] = [SitrepLayout.cell_of(c, r, shape), SitrepLayout.cell_of(w - 1 - c, h - 1 - r, shape)]
	for cell in pair:
		if map.has_cell(cell) and _built(map, cell):
			return  # never raise a house, wall or street; the pair stays mirrored
	for cell in pair:
		if not map.has_cell(cell) or blocked.has(cell):
			continue
		var col := map.column(cell)
		if col.has_tag(BattleMap.TAG_IMPASSABLE) or col.gap_top > 0 or col.ground >= 3:
			continue
		col.ground += levels
		col.tags = PackedStringArray(_cover_look(map, cell, tags))


static func _copy_cover(map: BattleMap, src: Vector2i, dst: Vector2i, blocked: Dictionary) -> void:
	if not map.has_cell(dst) or blocked.has(dst) or _built(map, dst):
		return
	var a := map.column(src)
	var b := map.column(dst)
	if b.has_tag(BattleMap.TAG_IMPASSABLE) or b.gap_top > 0:
		return
	if a.has_tag(Sight.TAG_SOFT_COVER):
		b.tags = a.tags.duplicate()
		return
	var low := a.ground
	for n in map.grid.neighbors(src):
		if map.has_cell(n):
			low = mini(low, map.ground_height(n))
	b.ground = mini(b.ground + maxi(1, a.ground - low), 6)
	var tags: Array = []
	for t in a.tags:
		if not t in [BattleMap.TAG_DESTRUCTIBLE, BattleMap.TAG_IMPASSABLE]:
			tags.append(t)
	b.tags = PackedStringArray(_cover_look(map, dst, tags))


## Structures repairs never raise or overwrite (streets, yards and fields may get barricades).
const BUILT := ["building", "house", "keep", "wall"]


static func _built(map: BattleMap, cell: Vector2i) -> bool:
	var col := map.column(cell)
	for t: String in BUILT:
		if col.has_tag(t):
			return true
	return false


## Added cover next to a building is a low wall (crates, a barricade), never a rock jammed
## against the house. Look only: the rules see the same raised block either way.
static func _cover_look(map: BattleMap, cell: Vector2i, tags: Array) -> Array:
	if not tags.has("rock"):
		return tags
	for n in map.grid.cells_within(cell, 2):
		if map.has_cell(n) and (map.column(n).has_tag("building") or map.column(n).has_tag("house") or map.column(n).has_tag("lot") or map.column(n).has_tag("road")):
			var out := tags.filter(func(t: String) -> bool: return t != "rock")
			out.append("wall")
			return out
	return tags
