class_name Movement
extends RefCounted
## Movement over the stacked BattleMap for any grid shape and Size: where a unit fits, what a
## step costs, pathfinding, and the movement-arrow preview. Pure queries: plan() and
## reachable() never change the GameState.
##
## Book rules used (lancer-data text):
## - Difficult terrain: each space moved into costs 2 (glossary: Difficult Terrain).
## - Climbing: half speed, each space climbed costs 2 (glossary: Jumping and Climbing).
## - Engaged by an equal-or-larger hostile during a move: stop, lose the rest (statuses: Engaged).
## - Hidden characters don't cause engagement (statuses: Hidden, actions: Hide).
## - Flight: up to SPEED in any direction, in a straight line; Hover needn't be straight
##   (glossary: Flight/Hover).
## - Prone: Slowed and moves as if in difficult terrain (statuses: Prone).
## - Involuntary movement: straight line, no engagement stops, blocked by obstructions
##   (glossary: Involuntary Movement).
## PROVISIONAL (docs/RULES_TODO.md "Movement"): a step up or down d levels costs 1 + 2d;
## climbing down costs the same as up; allies can be passed through but not stopped on;
## hostile characters and deployables block; a big mech on uneven ground is a table ruling;
## flying ignores difficult terrain; a footprint needs room for `Size` levels of height.

const MODE_MOVE := "move"
const MODE_BOOST := "boost"
const RULING_UNEVEN := "big_mech_uneven_ground"
const REF_ENGAGED := "statuses: Engaged"
const REF_DIFFICULT := "glossary: Difficult Terrain"
const REF_CLIMB := "glossary: Jumping and Climbing"
const REF_FLIGHT := "glossary: Flight/Hover"
const REF_MOVE := "actions: Move"
const REF_PROVISIONAL := "PROVISIONAL Core: Movement (docs/RULES_TODO.md)"
const REF_DANGEROUS := "glossary: Dangerous Terrain"


static func _key(cell: Vector2i, level: int) -> Vector3i:
	return Vector3i(cell.x, cell.y, level)


static func _cell(k: Vector3i) -> Vector2i:
	return Vector2i(k.x, k.y)


## Can a unit of `size` occupy `anchor` at `level`? Terrain only (not other units).
## Returns {ok, standing (ground under every space), uneven, airborne, reason, rule_ref}.
static func placement(state: GameState, size: float, anchor: Vector2i, level: int) -> Dictionary:
	var out := {"ok": false, "standing": false, "uneven": false, "airborne": false, "reason": "", "rule_ref": REF_PROVISIONAL}
	if level < 0:
		out["reason"] = "Below the ground."
		return out
	var cells := state.map.grid.footprint(anchor, size)
	var h := GridLayout.spaces_per_side(size)
	var supported := 0
	for c in cells:
		var col := state.map.column(c)
		if col == null:
			out["reason"] = "Off the map."
			return out
		if col.has_tag(BattleMap.TAG_IMPASSABLE):
			out["reason"] = "Impassable terrain."
			return out
		for k in range(h):
			if Sight.is_solid(state.map, c, level + k):
				out["reason"] = "Not enough room for a Size %s mech here." % _size_text(size)
				return out
		if level == 0 or Sight.is_solid(state.map, c, level - 1):
			supported += 1
	out["ok"] = true
	out["standing"] = supported == cells.size()
	out["uneven"] = supported > 0 and supported < cells.size()
	out["airborne"] = supported == 0
	return out


## Heights a unit of `size` could stand at with its footprint anchored at `anchor`.
static func surface_levels(state: GameState, size: float, anchor: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for c in state.map.grid.footprint(anchor, size):
		var col := state.map.column(c)
		if col == null:
			return []
		for lv in [col.ground, col.gap_bottom if col.gap_top > 0 else col.ground]:
			if not out.has(lv):
				out.append(lv)
	out.sort()
	return out


static func uneven_choice(state: GameState) -> String:
	return String(state.rulings.get(RULING_UNEVEN, {}).get("choice", ""))


## Other units as {"body": Sight.Body, "unit": Unit, "blocks": bool (hostile or object)}.
static func _others(state: GameState, u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Unit in state.units.values():
		if o == u or not Combat.is_present(o):
			continue
		var blocks := o.side != u.side or o.kind == Unit.KIND_DEPLOYABLE
		out.append({"body": Sight.body_of(state, o), "unit": o, "blocks": blocks})
	return out


static func _overlaps(a: Sight.Body, b: Sight.Body) -> bool:
	if a.level >= b.level + b.height or b.level >= a.level + a.height:
		return false
	for c in a.cells:
		if b.cells.has(c):
			return true
	return false


## Hostile characters that would engage `u` at `body`.
static func _engagers(state: GameState, u: Unit, body: Sight.Body, others: Array[Dictionary]) -> Array[Unit]:
	var out: Array[Unit] = []
	if u.has_status("Hidden"):
		return out
	for o in others:
		var ou: Unit = o["unit"]
		if ou.side == u.side or ou.kind == Unit.KIND_DEPLOYABLE or ou.has_status("Hidden"):
			continue
		if Sight.distance(state, body, o["body"]) <= 1:
			out.append(ou)
	return out


## Does entering this body stop the move? Returns the hostile that stops it, or null.
static func _stopper(state: GameState, u: Unit, body: Sight.Body, others: Array[Dictionary], engaged_at_start: Array[Unit]) -> Unit:
	if u.turn.get("disengaged", false):
		return null
	for e in _engagers(state, u, body, others):
		if not engaged_at_start.has(e) and (e.size >= u.size or Effects.has(e, "maze")):
			return e
	return null


static func _blocked_by_unit(body: Sight.Body, others: Array[Dictionary], ending: bool) -> bool:
	for o in others:
		if (o["blocks"] or ending) and _overlaps(body, o["body"]):
			return true
	return false


## Movement budget left for a standard move or Boost this turn.
static func budget(u: Unit, mode: String) -> int:
	if mode == MODE_BOOST:
		return u.speed
	return maxi(0, u.speed - int(u.turn.get("move_spent", 0)))


## The cheapest legal path to a destination, with its cost and everything the movement arrow
## should show. `level` -1 picks the best height there. `fly` uses flight (needs a flight
## system). Never changes the state.
## Returns {ok, reason, rule_ref, path: [[x, y, level]...], cost, budget, remaining,
##   needs_boost, stopped_by (unit id or ""), warnings: [{type, text, rule_ref, at}],
##   grey_area (ruling id or "")}.
static func plan(state: GameState, u: Unit, dest: Vector2i, level: int = -1, mode: String = MODE_MOVE, fly: bool = false) -> Dictionary:
	var out := {"ok": false, "reason": "", "rule_ref": REF_MOVE, "path": [], "cost": 0,
		"budget": budget(u, mode), "remaining": 0, "needs_boost": false, "stopped_by": "",
		"warnings": [], "grey_area": ""}
	if fly and u.flight == "":
		out["reason"] = "This mech can't fly."
		out["rule_ref"] = REF_FLIGHT
		return out
	var start_place := placement(state, u.size, u.cell, u.level)
	if not fly and start_place["airborne"]:
		out["reason"] = "You're in the air: fly, or you'll fall at the end of the turn."
		out["rule_ref"] = REF_FLIGHT
		return out
	var cap: int = out["budget"]
	if mode == MODE_MOVE:
		cap += u.speed  # look far enough to say "needs a Boost"
	var result: Dictionary
	if fly and u.flight != "hover":
		result = _straight_flight(state, u, dest, level, cap)
	else:
		var search := _search(state, u, cap, fly)
		result = _pick(state, u, search, dest, level)
	if not result.get("found", false):
		out["reason"] = result.get("reason", "Can't get there.")
		out["rule_ref"] = result.get("rule_ref", REF_MOVE)
		return out
	var path: Array = result["path"]
	out["path"] = path
	out["cost"] = result["cost"]
	out["stopped_by"] = result.get("stopped_by", "")
	if path.size() < 2:
		out["reason"] = "You're already there."
		return out
	out["warnings"] = _warnings(state, u, path, result, fly)
	if result.get("uneven", false):
		var choice := uneven_choice(state)
		if choice == "":
			out["grey_area"] = RULING_UNEVEN
		elif choice == "forbid":
			out["reason"] = "By your table's ruling, a big mech can't stand on uneven ground."
			out["rule_ref"] = REF_PROVISIONAL
			return out
	if int(out["cost"]) > int(out["budget"]):
		out["needs_boost"] = mode == MODE_MOVE
		out["reason"] = "Too far: this costs %d movement and you have %d left." % [out["cost"], out["budget"]]
		if out["needs_boost"]:
			out["reason"] += " Boost to move further."
		out["rule_ref"] = REF_MOVE
		return out
	out["remaining"] = int(out["budget"]) - int(out["cost"])
	out["ok"] = true
	return out


## Every place the unit could move to with its remaining budget (for greying out spaces).
## Returns {"budget": int, "spaces": [{"cell": [x, y], "level": int, "cost": int,
## "stops": bool (an Engaged stop), "ruling": bool (needs the uneven-ground ruling)}]}.
static func reachable(state: GameState, u: Unit, mode: String = MODE_MOVE, fly: bool = false) -> Dictionary:
	var cap := budget(u, mode)
	var spaces: Array = []
	if fly and u.flight != "hover":
		var top := _max_ground(state) + cap + GridLayout.spaces_per_side(u.size)
		for c in state.map.grid.cells_within(u.cell, cap):
			for lv in range(0, top + 1):
				var r := _straight_flight(state, u, c, lv, cap)
				if r.get("found", false) and int(r["cost"]) > 0 and (r["path"] as Array).size() > 1:
					var last: Array = (r["path"] as Array).back()
					if last[0] == c.x and last[1] == c.y and last[2] == lv:
						spaces.append({"cell": [c.x, c.y], "level": lv, "cost": r["cost"], "stops": r.get("stopped_by", "") != ""})
	else:
		var search := _search(state, u, cap, fly)
		var nodes: Dictionary = search["nodes"]
		for k: Vector3i in nodes:
			var n: Dictionary = nodes[k]
			if n["cost"] > 0 and n["can_end"]:
				spaces.append({"cell": [k.x, k.y], "level": k.z, "cost": n["cost"], "stops": n["stop"] != "", "ruling": n["uneven"]})
	return {"budget": cap, "spaces": spaces}


## Dijkstra over (anchor, level) nodes. Ground movement walks and climbs; hover flies freely.
static func _search(state: GameState, u: Unit, cap: int, fly: bool) -> Dictionary:
	var others := _others(state, u)
	var engaged_at_start := _engagers(state, u, Sight.body_of(state, u), others)
	var start := _key(u.cell, u.level)
	var nodes := {start: {"cost": 0, "parent": null, "stop": "", "can_end": false, "uneven": false, "difficult": false, "dangerous": false}}
	var open: Array[Vector3i] = [start]
	var done := {}
	var top := _max_ground(state) + cap + GridLayout.spaces_per_side(u.size)
	var prone := u.has_status("Prone")
	while not open.is_empty():
		var best := 0
		for i in range(1, open.size()):
			if nodes[open[i]]["cost"] < nodes[open[best]]["cost"]:
				best = i
		var k: Vector3i = open[best]
		open.remove_at(best)
		if done.has(k):
			continue
		done[k] = true
		var node: Dictionary = nodes[k]
		if node["stop"] != "":
			continue  # engagement ended the move here
		var here := _cell(k)
		var here_cells := state.map.grid.footprint(here, u.size)
		for step in _steps(state, u, here, k.z, fly, top):
			var nb: Vector2i = step[0]
			var lv: int = step[1]
			var nk := _key(nb, lv)
			if done.has(nk):
				continue
			var place := placement(state, u.size, nb, lv)
			if not place["ok"]:
				continue
			if not fly and place["airborne"]:
				continue
			if place["uneven"] and uneven_choice(state) == "forbid":
				continue
			if not _clearance(state, u.size, here, k.z, nb, lv):
				continue
			var body := Sight.make_body(state, nb, lv, u.size)
			if _blocked_by_unit(body, others, false):
				continue
			var difficult := false
			var dangerous := false
			for c in state.map.grid.footprint(nb, u.size):
				if here_cells.has(c):
					continue
				var col := state.map.column(c)
				difficult = difficult or col.has_tag(BattleMap.TAG_DIFFICULT)
				dangerous = dangerous or col.has_tag(BattleMap.TAG_DANGEROUS)
			var cost := 1
			if not fly:
				if difficult or prone:
					cost = 2
				cost += 2 * absi(lv - k.z)
			var total: int = node["cost"] + cost
			if total > cap:
				continue
			if nodes.has(nk) and nodes[nk]["cost"] <= total:
				continue
			var stopper := _stopper(state, u, body, others, engaged_at_start)
			nodes[nk] = {"cost": total, "parent": k, "stop": stopper.id if stopper else "",
				"can_end": not _blocked_by_unit(body, others, true),
				"uneven": node["uneven"] or place["uneven"], "difficult": difficult and not fly,
				"dangerous": dangerous, "climb": absi(lv - k.z) if not fly else 0}
			open.append(nk)
	return {"nodes": nodes}


## Candidate next nodes from (cell, level): [[cell, level], ...].
static func _steps(state: GameState, u: Unit, cell: Vector2i, level: int, fly: bool, top: int) -> Array:
	var out: Array = []
	if fly:
		for dl in [-1, 0, 1]:
			for nb in state.map.grid.neighbors(cell):
				if level + dl >= 0 and level + dl <= top:
					out.append([nb, level + dl])
		for dl in [-1, 1]:
			if level + dl >= 0 and level + dl <= top:
				out.append([cell, level + dl])
		return out
	for nb in state.map.grid.neighbors(cell):
		for lv in surface_levels(state, u.size, nb):
			out.append([nb, lv])
	return out


## Room to rise or drop between two neighbouring positions: the column you climb in must be
## open for your whole height over the climb.
static func _clearance(state: GameState, size: float, a: Vector2i, la: int, b: Vector2i, lb: int) -> bool:
	if la == lb:
		return true
	var h := GridLayout.spaces_per_side(size)
	var at: Vector2i = a if lb > la else b
	var lo := mini(la, lb)
	var hi := maxi(la, lb) + h
	for c in state.map.grid.footprint(at, size):
		for lv in range(lo, hi):
			if Sight.is_solid(state.map, c, lv):
				return false
	return true


static func _pick(state: GameState, u: Unit, search: Dictionary, dest: Vector2i, level: int) -> Dictionary:
	var nodes: Dictionary = search["nodes"]
	var best: Variant = null
	for k: Vector3i in nodes:
		if _cell(k) != dest or (level >= 0 and k.z != level):
			continue
		if not nodes[k]["can_end"] and k != _key(u.cell, u.level):
			continue
		if best == null or nodes[k]["cost"] < nodes[best]["cost"]:
			best = k
	if best == null:
		return {"found": false, "reason": _why_not(state, u, dest, level)}
	var path: Array = []
	var k: Variant = best
	while k != null:
		path.push_front([k.x, k.y, k.z])
		k = nodes[k]["parent"]
	var n: Dictionary = nodes[best]
	return {"found": true, "path": path, "cost": n["cost"], "stopped_by": n["stop"], "uneven": n["uneven"], "nodes": nodes}


static func _why_not(state: GameState, u: Unit, dest: Vector2i, level: int) -> String:
	var levels: Array[int] = [level] if level >= 0 else surface_levels(state, u.size, dest)
	if levels.is_empty():
		return "Off the map."
	for lv in levels:
		var p := placement(state, u.size, dest, lv)
		if not p["ok"]:
			return p["reason"]
		var body := Sight.make_body(state, dest, lv, u.size)
		if _blocked_by_unit(body, _others(state, u), true):
			return "That space is occupied."
	return "No path there within your movement (blocked, too far, or an Engaged stop on the way)."


## Flight in a straight line (glossary: Flight/Hover).
static func _straight_flight(state: GameState, u: Unit, dest: Vector2i, level: int, cap: int) -> Dictionary:
	var lv_end := level if level >= 0 else u.level
	var line := state.map.grid.line(u.cell, dest)
	var dl := lv_end - u.level
	var n := maxi(line.size() - 1, absi(dl))
	if n == 0:
		return {"found": true, "path": [[u.cell.x, u.cell.y, u.level]], "cost": 0}
	if n > cap:
		return {"found": false, "reason": "Too far to fly in one move.", "rule_ref": REF_FLIGHT}
	var others := _others(state, u)
	var engaged_at_start := _engagers(state, u, Sight.body_of(state, u), others)
	var path: Array = [[u.cell.x, u.cell.y, u.level]]
	var stopped_by := ""
	for i in range(1, n + 1):
		var c: Vector2i = line[roundi(float(i) * (line.size() - 1) / n)]
		var lv := u.level + roundi(float(i) * dl / n)
		var place := placement(state, u.size, c, lv)
		if not place["ok"]:
			return {"found": false, "reason": "Flight path blocked: " + String(place["reason"]), "rule_ref": REF_FLIGHT}
		var body := Sight.make_body(state, c, lv, u.size)
		if _blocked_by_unit(body, others, i == n):
			return {"found": false, "reason": "Flight path blocked by another character.", "rule_ref": REF_FLIGHT}
		path.append([c.x, c.y, lv])
		var stopper := _stopper(state, u, body, others, engaged_at_start)
		if stopper:
			stopped_by = stopper.id
			break
	return {"found": true, "path": path, "cost": path.size() - 1, "stopped_by": stopped_by}


static func _warnings(state: GameState, u: Unit, path: Array, result: Dictionary, fly: bool) -> Array:
	var out: Array = []
	var nodes: Dictionary = result.get("nodes", {})
	for p: Array in path.slice(1):
		var n: Dictionary = nodes.get(Vector3i(p[0], p[1], p[2]), {})
		if n.get("difficult", false):
			out.append({"type": "difficult", "text": "Difficult terrain: this space costs 2.", "rule_ref": REF_DIFFICULT, "at": p})
		if int(n.get("climb", 0)) > 0:
			out.append({"type": "climb", "text": "Climbing %d level(s): costs 2 per level." % n["climb"], "rule_ref": REF_CLIMB, "at": p})
		var dangerous: bool = n.get("dangerous", false)
		if fly:
			var col := state.map.column(Vector2i(p[0], p[1]))
			dangerous = col != null and col.has_tag(BattleMap.TAG_DANGEROUS) and int(p[2]) <= col.ground
		if dangerous:
			out.append({"type": "dangerous", "text": "Dangerous terrain: Engineering check or take 5 damage (once per round).", "rule_ref": REF_DANGEROUS, "at": p})
	if result.get("stopped_by", "") != "":
		out.append({"type": "engagement_stop", "text": "You become Engaged with %s here and stop moving." % result["stopped_by"], "rule_ref": REF_ENGAGED, "at": path.back()})
	if u.has_status("Engaged") and not u.turn.get("disengaged", false):
		var threats := threatened_by(state, u)
		if not threats.is_empty():
			out.append({"type": "provokes", "text": "Moving away while Engaged can provoke reactions (e.g. Overwatch) from: %s." % ", ".join(threats), "rule_ref": "actions: Overwatch", "at": path[0], "units": threats})
	if fly and u.flight != "hover":
		out.append({"type": "flight", "text": "Flying: you must move at least 1 space each turn or fall.", "rule_ref": REF_FLIGHT, "at": path.back()})
	if result.get("uneven", false):
		out.append({"type": "ruling", "text": "A Size %s mech on uneven ground: the book doesn't say if that's allowed. The table decides." % _size_text(u.size), "rule_ref": REF_PROVISIONAL, "at": path.back()})
	return out


## Hostiles whose weapon THREAT covers `u` where it stands (they could Overwatch a move).
## All weapons have THREAT 1 unless specified otherwise (glossary: Threat).
static func threatened_by(state: GameState, u: Unit) -> Array[String]:
	var out: Array[String] = []
	if u.has_status("Hidden"):
		return out
	for o: Unit in state.units.values():
		if o.side == u.side or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE:
			continue
		var reach := 0
		for w: Dictionary in o.loadout.get("weapons", []):
			reach = maxi(reach, Weapons.threat(w))
		if reach > 0 and Sight.unit_distance(state, o, u) <= reach:
			out.append(o.id)
	return out


## Straight-line involuntary movement (knockback) of up to `spaces` directly away from
## `origin`. Stops at obstructions. Returns the path including the start.
static func push_path(state: GameState, u: Unit, origin: Vector2i, spaces: int) -> Array:
	var path: Array = [[u.cell.x, u.cell.y, u.level]]
	var dir := u.cell - origin
	if dir == Vector2i.ZERO or spaces <= 0:
		return path
	var d := maxi(1, state.map.grid.distance(origin, u.cell))
	var far := u.cell + dir * (spaces / d + 2)
	var line := state.map.grid.line(u.cell, far)
	var others := _others(state, u)
	for i in range(1, mini(spaces + 1, line.size())):
		var c: Vector2i = line[i]
		var place := placement(state, u.size, c, u.level)
		if not place["ok"]:
			break
		var body := Sight.make_body(state, c, u.level, u.size)
		var hit := false
		for o in others:
			if _overlaps(body, o["body"]):
				hit = true
		if hit:
			break
		path.append([c.x, c.y, u.level])
	return path


static func _max_ground(state: GameState) -> int:
	var top := 0
	for c in state.map.cells():
		top = maxi(top, state.map.ground_height(c))
	return top


static func _size_text(size: float) -> String:
	return "1/2" if size < 1.0 else str(int(size))
