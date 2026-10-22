class_name Sight
extends RefCounted
## Distance, line of sight and cover in 3D, for any grid shape and Size. Pure queries: nothing
## here changes the GameState, so the renderer can call them for overlays (no-LOS dimming,
## cover highlights) and get exactly what the rules will apply.
##
## PROVISIONAL (docs/RULES_TODO.md "Line of sight in 3D", "Cover", "Distance in 3D"):
## - A character fills `Size` levels (rounded up to 1) above each footprint space.
## - Line of sight: a clear straight line from any sample point of the attacker (middle of each
##   level it fills, and the top of its head) to any sample point of the target. Only solid
##   terrain blocks it; other characters don't.
## - Hard cover: solid terrain next to the target (within 1 space of its footprint) hides at
##   least half the target's height from the attacker, while some of the target is still in
##   line of sight. +2 Difficulty.
## - Soft cover: the target is inside, or every clear line to it passes through, terrain tagged
##   "soft_cover" (smoke, foliage). +1 Difficulty. Hard and soft cover don't stack.
## - Distance in 3D: the larger of ground distance between footprints and the height gap.
## Only ranged attacks are affected by cover (actions: Fight; tags: Thrown, Seeking).

## BattleMap column tag for soft cover (smoke, foliage...). The whole column above the ground.
const TAG_SOFT_COVER := "soft_cover"
const REF_COVER := "PROVISIONAL Core: Cover (docs/RULES_TODO.md)"
const REF_LOS := "PROVISIONAL Core: Line of sight (docs/RULES_TODO.md)"
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


## Distance in spaces between two bodies. PROVISIONAL: larger of ground and height distance.
static func distance(state: GameState, a: Body, b: Body) -> int:
	var flat := state.map.grid.footprint_distance(a.cells, b.cells)
	var a_top := a.level + a.height - 1
	var b_top := b.level + b.height - 1
	var vertical := maxi(0, maxi(b.level - a_top, a.level - b_top))
	return maxi(flat, vertical)


static func unit_distance(state: GameState, a: Unit, b: Unit) -> int:
	return distance(state, body_of(state, a), body_of(state, b))


static func line_of_sight(state: GameState, from: Body, to: Body) -> bool:
	var skip := _skip_cells(from, to)
	var eyes := _points(state, from, true)
	for p in _points(state, to, true):
		for eye in eyes:
			if not _trace(state, p, eye, skip)["blocked"]:
				return true
	return false


static func unit_line_of_sight(state: GameState, a: Unit, b: Unit) -> bool:
	return line_of_sight(state, body_of(state, a), body_of(state, b))


## Cover `target` has against a ranged attack from `attacker`.
## Returns {los: bool, cover: "none"/"soft"/"hard", difficulty: int,
## cover_cells: [[x, y], ...] (terrain giving hard cover), reason: String, rule_ref: String}.
static func cover(state: GameState, attacker: Body, target: Body) -> Dictionary:
	var skip := _skip_cells(attacker, target)
	var eyes := _points(state, attacker, true)
	var top_eye: Vector3 = eyes[eyes.size() - 1]
	var mids := _points(state, target, false)
	var all_points := _points(state, target, true)
	var los := false
	var all_soft := true
	var covered_mids := 0
	var cover_cells := {}
	for p in all_points:
		var visible := false
		var clear := false
		for eye in eyes:
			var r := _trace(state, p, eye, skip)
			if not r["blocked"]:
				visible = true
				if not r["soft"]:
					clear = true
					break
		if visible:
			los = true
			if clear:
				all_soft = false
			continue
		# Blocked from every eye: is it terrain right next to the target that blocks it?
		var r := _trace(state, p, top_eye, skip)
		var block: Array[Vector2i] = [r["first_block"]]
		if r["blocked"] and state.map.grid.footprint_distance(target.cells, block) <= 1:
			cover_cells[block[0]] = true
			if mids.has(p):
				covered_mids += 1
	var out := {"los": los, "cover": "none", "difficulty": 0, "cover_cells": [], "reason": "", "rule_ref": REF_COVER}
	if not los:
		out["reason"] = "No line of sight."
		out["rule_ref"] = REF_LOS
		return out
	if covered_mids > 0 and covered_mids * 2 >= mids.size():
		out["cover"] = "hard"
		out["difficulty"] = HARD_COVER_DIFFICULTY
		out["reason"] = "Hard cover: terrain next to the target hides at least half of it."
		for c: Vector2i in cover_cells:
			(out["cover_cells"] as Array).append([c.x, c.y])
	elif all_soft or _in_soft_cover(state, target):
		out["cover"] = "soft"
		out["difficulty"] = SOFT_COVER_DIFFICULTY
		out["reason"] = "Soft cover: the target is in or behind smoke/foliage."
	return out


static func unit_cover(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	return cover(state, body_of(state, attacker), body_of(state, target))


## Cover a unit would have at a hypothetical position against every hostile unit.
## For the "hovered destination" overlay. Returns {enemy_id: cover dict}.
static func cover_at(state: GameState, u: Unit, anchor: Vector2i, level: int) -> Dictionary:
	var me := make_body(state, anchor, level, u.size)
	var out := {}
	for other: Unit in state.units.values():
		if other.side == u.side or other.destroyed or other.kind == Unit.KIND_DEPLOYABLE:
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


static func _skip_cells(a: Body, b: Body) -> Dictionary:
	var skip := {}
	for c in a.cells:
		skip[c] = true
	for c in b.cells:
		skip[c] = true
	return skip


## Sample points: middle of each level the body fills, plus (if `tops`) the top of its head.
## The middles come first, in the order cells x levels.
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


## Walks from p0 to p1. Returns {blocked, first_block (cell nearest p0), soft}.
static func _trace(state: GameState, p0: Vector3, p1: Vector3, skip: Dictionary) -> Dictionary:
	var n := maxi(1, ceili(p0.distance_to(p1) / STEP))
	var soft := false
	var grid := state.map.grid
	for i in range(1, n):
		var p := p0.lerp(p1, float(i) / n)
		var cell := grid.from_world(p)
		if skip.has(cell):
			continue
		var col := state.map.column(cell)
		if col == null:
			continue
		var lvl := floori(p.y / GridLayout.LEVEL_HEIGHT + 0.0001)
		if is_solid(state.map, cell, lvl):
			return {"blocked": true, "first_block": cell, "soft": soft}
		if col.has_tag(TAG_SOFT_COVER) and lvl >= col.ground:
			soft = true
	return {"blocked": false, "first_block": Vector2i.ZERO, "soft": soft}
