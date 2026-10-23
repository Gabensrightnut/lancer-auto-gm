class_name ExploreRegion
extends RefCounted
## A region explored in real time, several of its areas in play at once (DESIGN.md "Exploring
## vs. fighting"): each area is its own NetHost (a GameState with the area's ground at mech
## scale, MissionGenerator.area, and the units in it: explore_move, start_combat, join_combat
## all go through its rules engine), and one NetRoom carries the friends, each in the area their
## units are in. Players roam independently: a unit that walks onto an edge carries on into the
## neighbouring area on the matching edge (areas share their edges, so the road continues), its
## followers come along, and its seat's connection moves with it. A fight in one area doesn't
## stop the others. gather() brings everyone to the lead's area (Decisions.gathering).
##
##   var r := ExploreRegion.new(seed, {"p1": {"name": "Ama", "side": "players"}, ...}, {"region": flavor.region})
##   var town := r.area_at(Vector2i.ZERO)       # NetHost of that area (created on first use)
##   r.place(unit, Vector2i.ZERO)               # put a squad unit in it
##   r.open(transport, code)                    # friends online (NetRoom)

signal area_opened(key: String, host: NetHost)
## A seat's units are now all in another area (its screen should show that area).
signal seat_moved(seat: String, key: String)
## A unit left one area for another.
signal crossed(unit_id: String, from_key: String, to_key: String)

const EDGES := {"west": Vector2i(-1, 0), "east": Vector2i(1, 0), "north": Vector2i(0, -1), "south": Vector2i(0, 1)}
const OPPOSITE := {"west": "east", "east": "west", "north": "south", "south": "north"}

var region_seed := 0
var seats: Dictionary = {}
var opts: Dictionary = {}
var room := NetRoom.new()
var areas: Dictionary = {}  # key "x,y" -> {key, at, host, area}
var _seat_area: Dictionary = {}
var _open := false


func _init(seed_value: int, seat_info: Dictionary, area_opts: Dictionary = {}) -> void:
	region_seed = seed_value
	seats = seat_info.duplicate(true)
	if not seats.has(NetHost.GM_SEAT):
		seats[NetHost.GM_SEAT] = {"name": "GM", "side": Mission.ENEMIES, "gm": true}
	opts = area_opts.duplicate(true)


static func key_of(at: Vector2i) -> String:
	return "%d,%d" % [at.x, at.y]


## The NetHost of the area at `at` on the region's grid, made the first time it's needed.
## `area_opts`: a site's own area description from the world map ({place, at, region}).
func area_at(at: Vector2i, area_opts: Dictionary = {}) -> NetHost:
	var key := key_of(at)
	if areas.has(key):
		return areas[key]["host"]
	var o := opts.duplicate(true)
	o.merge(area_opts, true)
	o["at"] = [at.x, at.y]
	if not o.has("place"):
		o["place"] = "town" if at == Vector2i.ZERO and o.has("hub") else "wilds"
	var a := MissionGenerator.area(absi(hash([region_seed, at])) % 1000000, o)
	var state := GameState.new(absi(hash([region_seed, at, "state"])) % 1000000, (a["map"] as BattleMap).grid.shape)
	state.map = a["map"]
	state.seats = seats.duplicate(true)
	var host := NetHost.new(state, RulesEngine.new())
	GmActions.register(host.engine)
	host.action_resolved.connect(func(_seat: String, _a: Dictionary, _r: RuleResult, events: Array) -> void: _on_events(key, events))
	areas[key] = {"key": key, "at": at, "host": host, "area": a}
	if _open:
		room.add_area(key, host)
	area_opened.emit(key, host)
	return host


func host_of(key: String) -> NetHost:
	return areas.get(key, {}).get("host")


## The area a seat's units are in ("" if none yet).
func area_of(seat: String) -> String:
	return str(_seat_area.get(seat, ""))


## Friends online: one room, each friend in the area their units are in.
func open(net: NetTransport, code: String = "") -> void:
	_open = true
	for key: String in areas:
		room.add_area(key, areas[key]["host"])
	for seat: String in _seat_area:
		room.default_area = _seat_area[seat]
		break
	room.open(net, code)


func poll() -> void:
	room.poll()


## Puts a unit in an area at `cell` (or the free space nearest the middle).
func place(u: Unit, at: Vector2i, cell: Variant = null) -> bool:
	var host := area_at(at)
	var a: Dictionary = areas[key_of(at)]["area"]
	var want: Vector2i = cell if cell is Vector2i else _cell_of(a, a.get("center", [0, 0]))
	if not _put(host.state, u, want):
		return false
	_note_seat(u.controller, key_of(at))
	host.send_updates([{"type": "unit_arrived", "unit": u.id}])
	return true


## Everyone to the lead's area, next to the lead's first unit (Decisions.gathering: a chapter
## starting, a decision, a split, boots on the ground...). Returns the area's key.
func gather(lead_seat: String) -> String:
	var to_key := area_of(lead_seat)
	if to_key == "":
		return ""
	var to_host := host_of(to_key)
	var lead: Unit = null
	for u: Unit in to_host.state.units.values():
		if u.controller == lead_seat and not u.destroyed:
			lead = u
			break
	for key: String in areas.keys():
		if key == to_key:
			continue
		for u: Unit in host_of(key).state.units.values().duplicate():
			if seats.has(u.controller) and u.controller != NetHost.GM_SEAT and not u.destroyed:
				_move(u, key, to_key, lead.cell if lead != null else _cell_of(areas[to_key]["area"], areas[to_key]["area"].get("center", [0, 0])))
	return to_key


func _on_events(key: String, events: Array) -> void:
	for e: Dictionary in events:
		if str(e.get("type", "")) != "moved":
			continue
		var host := host_of(key)
		var u := host.state.unit(str(e.get("unit", "")))
		if u == null or u.destroyed or not seats.has(u.controller) or u.controller == NetHost.GM_SEAT:
			continue  # only the squad walks between areas
		if host.state.phase == GameState.PHASE_COMBAT and not bool(u.counters.get("exploring", false)):
			continue  # in a fight: no walking out of it
		var edge := _edge_of(areas[key]["area"], host.state.map, u.cell)
		if edge != "":
			_cross(u, key, edge)


## The edge `cell` lies on ("" if none): compared in world space with the area's entry cells,
## so this works on any grid.
static func _edge_of(a: Dictionary, map: BattleMap, cell: Vector2i) -> String:
	var p := map.grid.to_world(cell)
	var ent: Dictionary = a.get("entries", {})
	var g := map.grid
	if ent.has("west") and absf(p.x - g.to_world(_cell_of(a, ent["west"])).x) < 0.5:
		return "west"
	if ent.has("east") and absf(p.x - g.to_world(_cell_of(a, ent["east"])).x) < 0.5:
		return "east"
	if ent.has("north") and absf(p.z - g.to_world(_cell_of(a, ent["north"])).z) < 0.5:
		return "north"
	if ent.has("south") and absf(p.z - g.to_world(_cell_of(a, ent["south"])).z) < 0.5:
		return "south"
	return ""


func _cross(u: Unit, from_key: String, edge: String) -> void:
	var at: Vector2i = areas[from_key]["at"] + EDGES[edge]
	area_at(at)
	var to_key := key_of(at)
	var a: Dictionary = areas[to_key]["area"]
	var entry := _cell_of(a, a["entries"][OPPOSITE[edge]])
	# A couple of steps in from the edge, so the next step doesn't walk straight back out.
	var inward := host_of(to_key).state.map.grid.line(entry, _cell_of(a, a.get("center", [0, 0])))
	entry = inward[mini(2, inward.size() - 1)]
	_move(u, from_key, to_key, entry)
	# Its AI squadmates come along.
	for f: Unit in host_of(from_key).state.units.values().duplicate():
		if str(f.counters.get("leader", "")) == u.id:
			_move(f, from_key, to_key, entry)


func _move(u: Unit, from_key: String, to_key: String, near: Vector2i) -> void:
	var from := host_of(from_key)
	var to := host_of(to_key)
	from.state.units.erase(u.id)
	from.send_updates([{"type": "unit_left", "unit": u.id, "to": to_key}])
	u.counters.erase("exploring")
	_put(to.state, u, near)
	if to.state.phase == GameState.PHASE_COMBAT:
		u.counters["exploring"] = true  # a fight is on there: walking up joins it (join_combat)
	to.send_updates([{"type": "unit_arrived", "unit": u.id, "from": from_key}])
	crossed.emit(u.id, from_key, to_key)
	_note_seat(u.controller, to_key)


func _note_seat(seat: String, key: String) -> void:
	if seat == "" or seat == NetHost.GM_SEAT or str(_seat_area.get(seat, "")) == key:
		return
	# The seat moves once none of its units are left where it was.
	var old := str(_seat_area.get(seat, ""))
	if old != "" and host_of(old) != null and host_of(old).state.units.values().any(func(o: Unit) -> bool: return o.controller == seat and not o.destroyed):
		return
	_seat_area[seat] = key
	if _open:
		room.move_seat(seat, key)
	seat_moved.emit(seat, key)


## Puts a unit on a free cell as near `want` as possible.
static func _put(state: GameState, u: Unit, want: Vector2i) -> bool:
	var taken := {}
	for o: Unit in state.units.values():
		taken[o.cell] = true
	for r in range(0, 8):
		for c: Vector2i in state.map.grid.cells_within(want, r):
			if state.map.has_cell(c) and not taken.has(c) and not state.map.column(c).has_tag(BattleMap.TAG_IMPASSABLE):
				u.cell = c
				u.level = state.map.ground_height(c)
				state.add_unit(u)
				return true
	return false


static func _cell_of(_a: Dictionary, v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	return Vector2i(int(v[0]), int(v[1]))
