class_name Garrison
extends RefCounted
## Units inside buildings on mech-scale maps.
##
## Map tags (from the world session's TerrainGen._building_interiors): every building cell is
## "interior" (with "storeys_N", its height), "window_<i>" for each outside face (i = the face's
## index in GridLayout.neighbors order, so hex and square both work), and one cell per building
## "entrance" + "door_face_<i>". A building cell stays a solid column; with the house rule on,
## its ground storey is a room (Sight.is_solid leaves that level open, BattleMap.rooms_open).
##
## Book rules:
## - A character in a room at a window is next to the wall, which is hard cover, and "if a
##   character in hard cover could shoot over, through, or around the source of their cover,
##   the cover does not block their line of sight or obscure their attacks" (Core p.66). So
##   lines of sight cross a window face, cover lines don't: hard cover (+2) against anyone
##   outside, unless they flank it (a line totally clear of hard cover, e.g. through the open
##   door or from inside the building; Core p.66).
## - Standing on a building that's destroyed: the book's falling rule (Core p.63, TerrainDamage).
##
## House rule "Garrisoned buildings" (hr_garrisoned_buildings, Joe's Rules, off by default):
## - Ground-storey rooms can be entered, through the door face only (and between a building's
##   own cells); walls and windows can't be crossed. Off: buildings are solid, as in the book.
## - A room space holds one Size 1 or larger unit on its own, or up to two Size 1/2 units
##   (pilots, single soldiers, half-size mechs) plus one squad. Elsewhere nobody ends a move in
##   an occupied space (Core p.62).
## - When the room's own section is destroyed, everyone inside takes damage as if they fell the
##   building's height (the book's falling numbers, Core p.63: 3 AP kinetic per 3 spaces, up to
##   9) and is moved to the nearest free space.

const HOUSE_RULE := "hr_garrisoned_buildings"
const TAG_INTERIOR := "interior"
const REF := "House rule: Garrisoned buildings"
const REF_COVER := "Core p.66 Cover"

## crossing() answers.
const OPEN := ""
const WALL := "wall"
const WINDOW := "window"


static func on(state: GameState) -> bool:
	return HouseRuleSwitches.on(state, HOUSE_RULE)


## Called before every rules check: rooms are open while the house rule is on.
static func sync(state: GameState) -> void:
	if state.map != null:
		state.map.rooms_open = on(state)


## The level of a building cell's ground-storey room (its floor).
static func room_level(col: BattleMap.Column) -> int:
	return TerrainDamage.floor_of(col)


## Is (cell, level) inside a building room?
static func is_room(map: BattleMap, cell: Vector2i, level: int) -> bool:
	if not map.rooms_open:
		return false
	var col := map.column(cell)
	return col != null and col.has_tag(TAG_INTERIOR) and level == room_level(col) and level < col.ground


static func inside(state: GameState, u: Unit) -> bool:
	for c in state.map.grid.footprint(u.cell, u.size):
		if not is_room(state.map, c, u.level):
			return false
	return true


## For the hover card: what a building space can hold ("" if it isn't enterable).
static func capacity_text(state: GameState, cell: Vector2i) -> String:
	var col := state.map.column(cell)
	if col == null or not col.has_tag(TAG_INTERIOR):
		return ""
	if not on(state):
		return "A building (solid: the Garrisoned buildings house rule is off)."
	var inside: Array = []
	for u: Unit in state.units.values():
		if Combat.is_present(u) and state.map.grid.footprint(u.cell, u.size).has(cell) and u.level == room_level(col):
			inside.append(u.name if u.name != "" else u.id)
	var text := "Enterable: holds 2 half-size units (pilots, soldiers or Size 1/2 mechs) and a squad, or 1 Size 1 mech."
	if not inside.is_empty():
		text += " Inside: %s." % ", ".join(PackedStringArray(inside))
	return text


## A room space with a window (a firing position).
static func at_window(state: GameState, cell: Vector2i) -> bool:
	var col := state.map.column(cell)
	if col == null:
		return false
	for t in col.tags:
		if t.begins_with("window_"):
			return true
	return false


## Going from (a, la) to (b, lb), what wall is crossed? OPEN (none, an open doorway, or a window
## for a line of sight), WINDOW (a window face, for cover and movement) or WALL. `open` cells:
## the shooter's own spaces, whose windows it fires through (Core p.66).
static func crossing(map: BattleMap, a: Vector2i, la: int, b: Vector2i, lb: int, sight: bool, open: Dictionary = {}) -> String:
	if a == b:
		return OPEN
	var ra := is_room(map, a, la)
	var rb := is_room(map, b, lb)
	if ra == rb:
		return OPEN  # outside to outside, or between rooms of the building
	var room := a if ra else b
	var other := b if ra else a
	var i := map.grid.neighbors(room).find(other)
	if i < 0:
		return WALL
	var col := map.column(room)
	if col.has_tag("door_face_%d" % i):
		return OPEN
	if col.has_tag("window_%d" % i):
		return OPEN if sight or open.has(room) else WINDOW
	return WALL


## Movement: may a step go from (a, la) to (b, lb)? Only through doors (and within a building).
static func step_ok(map: BattleMap, a: Vector2i, la: int, b: Vector2i, lb: int) -> bool:
	return crossing(map, a, la, b, lb, false) == OPEN


## May `u` end a move at `body`, sharing a room's spaces with `others` (Movement's list of
## {body, unit, blocks})? Only allies, never objects or wrecks, and only within capacity.
static func may_share(state: GameState, u: Unit, body: Sight.Body, others: Array) -> bool:
	if not on(state):
		return false
	for c in body.cells:
		if not is_room(state.map, c, body.level):
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


## The building's height in levels (storeys_N, else its ground before the hit).
static func height_of(col: BattleMap.Column, old_ground: int) -> int:
	for t in col.tags:
		if t.begins_with("storeys_"):
			return maxi(int(t.substr(8)), old_ground)
	return old_ground


## TerrainDamage destroyed the room section of a building cell (it stood `old_ground` high):
## everyone who was inside is caught. Call before the column is lowered past the room.
static func collapse(state: GameState, cell: Vector2i, old_ground: int, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var col := state.map.column(cell)
	if col == null or not col.has_tag(TAG_INTERIOR):
		return events
	var floor_lv := room_level(col)
	var caught: Array = []
	for u: Unit in state.units.values():
		if u.destroyed or not Combat.is_present(u) or u.kind == Unit.KIND_DEPLOYABLE:
			continue
		if state.map.grid.footprint(u.cell, u.size).has(cell) and u.level == floor_lv:
			caught.append(u)
	var tags := col.tags
	tags.remove_at(tags.find(TAG_INTERIOR))  # rubble now
	col.tags = tags
	if caught.is_empty() or not on(state):
		return events
	var name := building_name(col)
	var height := maxi(0, height_of(col, old_ground) - floor_lv)
	var dmg := mini(9, (height / 3) * 3)  # the book's falling damage for that height (Core p.63)
	var report: Array = []
	for u: Unit in caught:
		var who := u.name if u.name != "" else u.id
		report.append({"unit": u.id, "height": height, "damage": dmg,
			"text": "The %s came down on %s: %d kinetic, like a %d-space fall." % [name, who, dmg, height]})
		if dmg > 0:
			events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": dmg}], {"ap": true, "source": "collapse"}))
	# Then the survivors are dropped out, one at a time, to the nearest space nobody shares.
	for i in range(caught.size()):
		var u: Unit = caught[i]
		if u.destroyed:
			continue
		var to: Variant = nearest_free(state, u)
		if to != null:
			var dest: Array = to
			var from := [u.cell.x, u.cell.y, u.level]
			u.cell = Vector2i(int(dest[0]), int(dest[1]))
			u.level = int(dest[2])
			if dest != from:
				events.append({"type": "moved", "unit": u.id, "path": [from, dest], "mode": "pushed", "cost": 0, "rule_ref": REF})
			report[i]["to"] = dest
	events.push_front({"type": "building_collapsed", "cell": [cell.x, cell.y], "building": name, "caught": report, "source": source, "rule_ref": REF})
	return events


## A plain name for the building ("building" unless a "name:<text>" tag says more).
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
				if Soldiers.spreads(u):
					if Soldiers.spread_ok(state, u, c, lv, u.size):
						return [c.x, c.y, lv]
					continue
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
