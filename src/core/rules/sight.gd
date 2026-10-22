class_name Sight
extends RefCounted
## Distance, line of sight and cover in 3D, for any grid shape and Size. Pure queries: nothing
## here changes the GameState, so the renderer can call them for overlays (no-LOS dimming,
## cover highlights) and get exactly what the rules will apply.
##
## Book rules (Core p.59, 62, 64-66, 82):
## - A SIZE N character is N spaces on each side and N spaces high; under 1 rounds up.
## - Adjacent = within one space in any direction, including diagonally and vertically.
## - Line of sight: a line can be traced to some part of the target. Characters only grant
##   cover if they have GUARDIAN; wrecks of destroyed mechs give hard cover.
## - Hard cover (+2 Difficulty): the target is adjacent to the cover, is the same Size as it
##   or smaller, and isn't flanked (flanked: a line totally clear of hard cover can be drawn
##   between a space of the attacker and a space of the target).
## - Soft cover (+1): the line from the attacker's center to the target's center is
##   significantly obstructed (smoke, foliage...), or the target is obscured by hard cover it
##   isn't adjacent to. Hard and soft don't stack. Characters shoot over cover no bigger than
##   themselves.
## Engine geometry (docs/RULES_TODO.md "Engine geometry"; the book describes a flat map):
## - Lines are sampled between the middles of the spaces (voxels) characters fill, plus the
##   tops of their heads for line of sight; a column's terrain "size" is its height above the
##   target's base.
## - Adjacency counts height (Core p.62); Range/Threat/Sensors with height follow the table's
##   "distance_3d" ruling (range_distance).
## - A column tagged "soft_cover" is soft cover over its whole height.
## Only ranged attacks are affected by cover (Core p.64: melee and tech attacks ignore cover).

## BattleMap column tag for soft cover (smoke, foliage...). The whole column above the ground.
const TAG_SOFT_COVER := "soft_cover"
const REF_COVER := "Core p.66 Cover"
const REF_LOS := "Core p.65 Line of Sight"
const HARD_COVER_DIFFICULTY := 2
const SOFT_COVER_DIFFICULTY := 1
## Ray sample spacing in world units.
const STEP := 0.2


## Where something is and the space it fills.
class Body:
	var cells: Array[Vector2i] = []
	var level: int = 0
	var height: int = 1
	var size: float = 1.0


static func body_of(state: GameState, u: Unit) -> Body:
	return make_body(state, u.cell, u.level, u.size)


static func make_body(state: GameState, anchor: Vector2i, level: int, size: float) -> Body:
	var b := Body.new()
	b.cells = state.map.grid.footprint(anchor, size)
	b.level = level
	b.height = GridLayout.spaces_per_side(size)
	b.size = size
	return b


## Solid terrain at this cell and height level (cells off the map are open air).
static func is_solid(map: BattleMap, cell: Vector2i, level: int) -> bool:
	var c := map.column(cell)
	if c == null:
		return false
	if level < 0:
		return true
	if level >= c.ground:
		return false
	return not (c.gap_top > 0 and level >= c.gap_bottom and level < c.gap_top)


## Distance in spaces in any direction: the larger of ground distance and height gap
## (adjacency, Core p.62). For Range/Threat/Sensors use range_distance().
static func distance(state: GameState, a: Body, b: Body) -> int:
	var flat := state.map.grid.footprint_distance(a.cells, b.cells)
	var a_top := a.level + a.height - 1
	var b_top := b.level + b.height - 1
	var vertical := maxi(0, maxi(b.level - a_top, a.level - b_top))
	return maxi(flat, vertical)


## Distance for Range, Threat and Sensors. When heights differ, the table's "distance_3d"
## ruling decides between spaces in any direction and ground only; `ask` pauses to ask during
## resolution, otherwise previews use the suggested reading.
static func range_distance(state: GameState, a: Body, b: Body, ask: bool = false) -> int:
	var full := distance(state, a, b)
	var flat := state.map.grid.footprint_distance(a.cells, b.cells)
	if full == flat:
		return full
	var c := Rulings.ask(state, "distance_3d") if ask else Rulings.choice_or_suggested(state, "distance_3d")
	return flat if c == "ground_only" else full


## Within `reach` under the table's distance ruling? Returns {ok, grey_area} where grey_area
## names the ruling to ask when the readings disagree and the table hasn't decided.
static func within(state: GameState, a: Body, b: Body, reach: int) -> Dictionary:
	var full := distance(state, a, b)
	var flat := state.map.grid.footprint_distance(a.cells, b.cells)
	if (full <= reach) == (flat <= reach):
		return {"ok": full <= reach, "grey_area": ""}
	if not Rulings.decided(state, "distance_3d"):
		return {"ok": false, "grey_area": "distance_3d"}
	return {"ok": range_distance(state, a, b) <= reach, "grey_area": ""}


static func unit_distance(state: GameState, a: Unit, b: Unit) -> int:
	return distance(state, body_of(state, a), body_of(state, b))


## Wrecks of destroyed mechs: objects that block lines and give hard cover (Core p.74, 82).
## A mech vaporized by a reactor meltdown leaves no wreck (Core p.81).
static func wreck_bodies(state: GameState) -> Array[Body]:
	var out: Array[Body] = []
	for u: Unit in state.units.values():
		if u.destroyed and u.kind == Unit.KIND_MECH and not u.counters.get("vaporized", false):
			out.append(body_of(state, u))
		# PROVISIONAL (RULES_TODO "Deployables as cover"): solid deployed objects are hard cover.
		elif not u.destroyed and u.kind == Unit.KIND_DEPLOYABLE and String(u.counters.get("deploy_type", "")) in ["Deployable", "Object"]:
			out.append(body_of(state, u))
	return out


static func line_of_sight(state: GameState, from: Body, to: Body) -> bool:
	var skip := _skip_cells(from, to)
	var walls := _voxels(wreck_bodies(state), from, to)
	var eyes := _points(state, from, true)
	for p in _points(state, to, true):
		for eye in eyes:
			if not _trace(state, p, eye, skip, walls)["blocked"]:
				return true
	return false


static func unit_line_of_sight(state: GameState, a: Unit, b: Unit) -> bool:
	return line_of_sight(state, body_of(state, a), body_of(state, b))


## Cover `target` has against a ranged attack from `attacker`. `guardians`: bodies of allied
## GUARDIAN characters next to the target, which it may use as hard cover.
## Returns {los: bool, cover: "none"/"soft"/"hard", difficulty: int, flanked: bool,
## cover_cells: [[x, y], ...] (what gives the cover), reason: String, rule_ref: String}.
static func cover(state: GameState, attacker: Body, target: Body, guardians: Array[Body] = []) -> Dictionary:
	var out := {"los": false, "cover": "none", "difficulty": 0, "flanked": true, "cover_cells": [], "reason": "", "rule_ref": REF_COVER}
	var skip := _skip_cells(attacker, target)
	var wrecks := _voxels(wreck_bodies(state), attacker, target)
	if not line_of_sight(state, attacker, target):
		out["reason"] = "No line of sight."
		out["rule_ref"] = REF_LOS
		return out
	out["los"] = true
	var hard_objects := wrecks.duplicate()
	hard_objects.merge(_voxels(guardians, attacker, target))
	# Flanked: some line between a space of the attacker and a space of the target is
	# totally clear of hard cover.
	var flanked := false
	# Target: middle of each space plus the top of its head (so an attacker high above can
	# see past low cover); attacker: middle of each of its spaces. PROVISIONAL.
	var t_mids := _points(state, target, true)
	var a_mids := _points(state, attacker, false)
	for t in t_mids:
		for a in a_mids:
			if not _trace(state, t, a, skip, hard_objects)["blocked"]:
				flanked = true
				break
		if flanked:
			break
	out["flanked"] = flanked
	# Center to center, ignoring cover next to the attacker that it can shoot over.
	var line_skip := skip.duplicate()
	for c in _low_cover_near(state, attacker, target):
		line_skip[c] = true
	var r := _trace(state, _center(state, target), _center(state, attacker), line_skip, hard_objects)
	if not flanked and r["blocked"]:
		var block: Array[Vector2i] = [r["first_block"]]
		var adjacent := state.map.grid.footprint_distance(target.cells, block) <= 1
		var big_enough := int(r["block_top"]) >= target.level + target.height
		if adjacent and big_enough:
			out["cover"] = "hard"
			out["difficulty"] = HARD_COVER_DIFFICULTY
			out["cover_cells"] = [[block[0].x, block[0].y]]
			out["reason"] = "Hard cover: it's next to cover at least its own Size, and you can't see around it."
			return out
	if r["blocked"] or r["soft"] or _in_soft_cover(state, target):
		out["cover"] = "soft"
		out["difficulty"] = SOFT_COVER_DIFFICULTY
		if r["blocked"]:
			out["cover_cells"] = [[r["first_block"].x, r["first_block"].y]]
			out["reason"] = "Soft cover: partly obscured by something it isn't right next to (or that's smaller than it)."
		else:
			out["reason"] = "Soft cover: in or behind smoke, foliage or similar."
	return out


static func unit_cover(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	return cover(state, body_of(state, attacker), body_of(state, target), Effects.guardians(state, target))


## Cover a unit would have at a hypothetical position against every hostile unit.
## For the "hovered destination" overlay. Returns {enemy_id: cover dict}.
static func cover_at(state: GameState, u: Unit, anchor: Vector2i, level: int) -> Dictionary:
	var me := make_body(state, anchor, level, u.size)
	var out := {}
	for other: Unit in state.units.values():
		if other.side == u.side or not Combat.is_present(other) or other.kind == Unit.KIND_DEPLOYABLE:
			continue
		out[other.id] = cover(state, body_of(state, other), me)
	return out


## True if every space of the body is in a soft cover zone.
static func fully_in_soft_cover(state: GameState, b: Body) -> bool:
	for c in b.cells:
		var col := state.map.column(c)
		if col == null or not col.has_tag(TAG_SOFT_COVER):
			return false
	return true


static func _in_soft_cover(state: GameState, b: Body) -> bool:
	for c in b.cells:
		var col := state.map.column(c)
		if col != null and col.has_tag(TAG_SOFT_COVER):
			return true
	return false


## Terrain next to the attacker no taller than it: it shoots over its own cover (Core p.66).
## Cover that is also next to the target still counts for the target.
static func _low_cover_near(state: GameState, b: Body, target: Body) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in b.cells:
		for n in state.map.grid.neighbors(c):
			var col := state.map.column(n)
			if col == null or b.cells.has(n) or col.ground > b.level + b.height:
				continue
			var one: Array[Vector2i] = [n]
			if state.map.grid.footprint_distance(target.cells, one) > 1:
				out.append(n)
	return out


static func _skip_cells(a: Body, b: Body) -> Dictionary:
	var skip := {}
	for c in a.cells:
		skip[c] = true
	for c in b.cells:
		skip[c] = true
	return skip


## Voxels (Vector3i(x, y, level) -> top level) of object bodies, minus attacker/target.
static func _voxels(bodies: Array[Body], a: Body, b: Body) -> Dictionary:
	var out := {}
	for body in bodies:
		for c in body.cells:
			if a.cells.has(c) or b.cells.has(c):
				continue
			for k in range(body.height):
				out[Vector3i(c.x, c.y, body.level + k)] = body.level + body.height
	return out


static func _center(state: GameState, b: Body) -> Vector3:
	var sum := Vector3.ZERO
	for c in b.cells:
		sum += state.map.grid.to_world(c, b.level)
	sum /= b.cells.size()
	return sum + Vector3(0, b.height * GridLayout.LEVEL_HEIGHT / 2.0, 0)


## Sample points: middle of each level the body fills, plus (if `tops`) the top of its head.
static func _points(state: GameState, b: Body, tops: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in b.cells:
		var base := state.map.grid.to_world(c, b.level)
		for k in range(b.height):
			out.append(base + Vector3(0, (k + 0.5) * GridLayout.LEVEL_HEIGHT, 0))
	if tops:
		for c in b.cells:
			out.append(state.map.grid.to_world(c, b.level + b.height))
	return out


## Walks from p0 to p1. Returns {blocked, first_block (cell nearest p0), block_top (top level
## of what blocks), soft}. `objects` are extra solid voxels (wrecks, Guardians).
static func _trace(state: GameState, p0: Vector3, p1: Vector3, skip: Dictionary, objects: Dictionary = {}) -> Dictionary:
	var n := maxi(1, ceili(p0.distance_to(p1) / STEP))
	var soft := false
	var grid := state.map.grid
	for i in range(1, n):
		var p := p0.lerp(p1, float(i) / n)
		var cell := grid.from_world(p)
		if skip.has(cell):
			continue
		var lvl := floori(p.y / GridLayout.LEVEL_HEIGHT + 0.0001)
		var key := Vector3i(cell.x, cell.y, lvl)
		if objects.has(key):
			return {"blocked": true, "first_block": cell, "block_top": objects[key], "soft": soft}
		var col := state.map.column(cell)
		if col == null:
			continue
		if is_solid(state.map, cell, lvl):
			return {"blocked": true, "first_block": cell, "block_top": col.ground, "soft": soft}
		if col.has_tag(TAG_SOFT_COVER) and lvl >= col.ground:
			soft = true
	return {"blocked": false, "first_block": Vector2i.ZERO, "block_top": 0, "soft": soft}
