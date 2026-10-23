class_name Garrison
extends RefCounted
## Units inside buildings on mech-scale maps.
##
## Book rules (always on):
## - A wall with a window is hard cover for whoever is next to it, and they can still shoot
##   out through it and be shot at: "If a character in hard cover could shoot over, through,
##   or around the source of their cover, the cover does not block their line of sight or
##   obscure their attacks" (Core p.66). Columns tagged "window" block movement, let lines of
##   sight through, and count as hard cover (Sight). Flanking still beats it (Core p.66).
## - Doors are open ground (a column with a gap from the floor up): they block nothing.
## - Standing on a building that's destroyed: the book's falling rule (Core p.63, TerrainDamage).
##
## House rule "Garrisoned buildings" (hr_garrisoned_buildings, your idea, on by default):
## - Building rooms (columns tagged "interior": a gap from the floor up) hold more than one
##   unit per space: one Size 1 or larger unit alone, or up to two Size 1/2 units (pilots,
##   single soldiers, half-size mechs) plus one squad. Elsewhere nobody ends a move in an
##   occupied space (Core p.62).
## - When the room's roof and walls come down (TerrainDamage destroys the span over the gap),
##   everyone inside takes damage as if they fell the building's height (the book's falling
##   numbers, Core p.63: 3 AP kinetic per 3 spaces, up to 9) and is moved to the nearest
##   free space.
##
## Map tags (agreed with the world session): "interior" (a room space), "window", "door",
## and the building's own id tag (e.g. a spot id) for the collapse message.

const HOUSE_RULE := "hr_garrisoned_buildings"
const TAG_INTERIOR := "interior"
const TAG_WINDOW := "window"
const TAG_DOOR := "door"
const REF := "House rule: Garrisoned buildings"


static func on(state: GameState) -> bool:
	return HouseRuleSwitches.on(state, HOUSE_RULE)


## Is the space at `cell` and `level` inside a building room?
static func is_room(state: GameState, cell: Vector2i, level: int) -> bool:
	var col := state.map.column(cell)
	return col != null and col.has_tag(TAG_INTERIOR) and col.gap_top > 0 and level >= col.gap_bottom and level < col.gap_top


## Is `u` inside a building room?
static func inside(state: GameState, u: Unit) -> bool:
	for c in state.map.grid.footprint(u.cell, u.size):
		if not is_room(state, c, u.level):
			return false
	return true


## Next to a window (from inside, that's a firing position with hard cover).
static func at_window(state: GameState, cell: Vector2i) -> bool:
	for n in state.map.grid.neighbors(cell):
		var col := state.map.column(n)
		if col != null and col.has_tag(TAG_WINDOW):
			return true
	return false


## May `u` end a move at `body`, sharing a room's spaces with `others` (Movement's list of
## {body, unit, blocks})? Only allies, never objects or wrecks, and only within capacity.
static func may_share(state: GameState, u: Unit, body: Sight.Body, others: Array) -> bool:
	if not on(state):
		return false
	for c in body.cells:
		if not is_room(state, c, body.level):
			return false
	var by_cell := {}
	for o: Dictionary in others:
		var ob: Sight.Body = o["body"]
		var ou: Unit = o["unit"]
		if ob.level >= body.level + body.height or body.level >= ob.level + ob.height:
			continue
		for c in body.cells:
			if ob.cells.has(c):
				if o.get("wreck", false) or ou.kind == Unit.KIND_DEPLOYABLE or ou.side != u.side or ou.destroyed:
					return false
				if not by_cell.has(c):
					by_cell[c] = []
				(by_cell[c] as Array).append(ou)
	for c: Vector2i in by_cell:
		if not fits((by_cell[c] as Array) + [u]):
			return false
	return true


## The capacity rule for one room space: one unit of Size 1 or more on its own, or up to two
## Size 1/2 units and one squad.
static func fits(units: Array) -> bool:
	var big := 0
	var small := 0
	var squads := 0
	for x: Unit in units:
		if Soldiers.is_squad(x):
			squads += 1
		elif x.size >= 1.0:
			big += 1
		else:
			small += 1
	if big > 0:
		return units.size() == 1
	return small <= 2 and squads <= 1


## TerrainDamage destroyed the span over a room at `cell` (the gap [gap_bottom, gap_top) under
## a roof that stood `old_top` high): everyone who was inside is caught.
static func collapse(state: GameState, cell: Vector2i, gap_bottom: int, gap_top: int, old_top: int, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var col := state.map.column(cell)
	if col == null or not col.has_tag(TAG_INTERIOR):
		return events
	var caught: Array = []
	for u: Unit in state.units.values():
		if u.destroyed or not Combat.is_present(u) or u.kind == Unit.KIND_DEPLOYABLE:
			continue
		if state.map.grid.footprint(u.cell, u.size).has(cell) and u.level >= gap_bottom and u.level < gap_top:
			caught.append(u)
	if caught.is_empty() or not on(state):
		return events
	var name := building_name(col)
	var report: Array = []
	for u: Unit in caught:
		var height := maxi(0, old_top - u.level)
		var dmg := mini(9, (height / 3) * 3)  # the book's falling damage for that height (Core p.63)
		var who := u.name if u.name != "" else u.id
		report.append({"unit": u.id, "height": height, "damage": dmg,
			"text": "The %s came down on %s: %d kinetic, like a %d-space fall." % [name, who, dmg, height]})
		if dmg > 0:
			events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": dmg}], {"ap": true, "source": "collapse"}))
	# Then the survivors are dropped out, one at a time, to the nearest space nobody shares.
	for i in range(caught.size()):
		var u: Unit = caught[i]
		var entry: Dictionary = report[i]
		if not u.destroyed:
			var to: Variant = nearest_free(state, u)
			if to != null:
				var dest: Array = to
				var from := [u.cell.x, u.cell.y, u.level]
				u.cell = Vector2i(int(dest[0]), int(dest[1]))
				u.level = int(dest[2])
				events.append({"type": "moved", "unit": u.id, "path": [from, dest], "mode": "pushed", "cost": 0, "rule_ref": REF})
				entry["to"] = dest
	events.push_front({"type": "building_collapsed", "cell": [cell.x, cell.y], "building": name, "caught": report, "source": source, "rule_ref": REF})
	return events


## A plain name for the building ("building" unless its tags say more).
static func building_name(col: BattleMap.Column) -> String:
	for t in col.tags:
		if t.begins_with("name:"):
			return t.substr(5)
	return "building"


## The nearest space (by grid distance, up to 6 away) where `u` stands on solid ground and
## shares no space with anyone. [x, y, level] or null.
static func nearest_free(state: GameState, u: Unit) -> Variant:
	var grid := state.map.grid
	for r in range(0, 7):
		var ring: Array[Vector2i] = []
		for c in state.map.cells():
			if grid.distance(u.cell, c) == r:
				ring.append(c)
		ring.sort()
		for c in ring:
			for lv in Movement.surface_levels(state, u.size, c):
				if not Movement.placement(state, u.size, c, lv)["standing"]:
					continue
				var body := Sight.make_body(state, c, lv, u.size)
				var clear := true
				for o: Unit in state.units.values():
					if o != u and Combat.is_present(o) and Movement._overlaps(body, Sight.body_of(state, o)):
						clear = false
						break
				if clear:
					return [c.x, c.y, lv]
	return null
