class_name PvpBattle
extends RefCounted
## Player against player (DESIGN.md; story raises it when a story-changing choice splits the
## squad, e.g. a mutiny): two groups of the squad's players fight each other, each with
## optional AI/NPC allies. AI squadmates always side with their human (the user: "AI players
## follow whatever choices you make"), so the groups only ever come from people disagreeing;
## story builds them.
##
## Group "a" stays on the squad's side (Mission.PLAYERS); group "b" takes the other side
## (Mission.ENEMIES). Everything else follows from that: the rules engine treats the two sides
## as hostile, turns alternate between them (Core p.60), each seat's view is filtered for its
## own side (ViewFilter: no peeking at the other group's stats or Hidden units), hot-seat hands
## the screen over between people, and online each friend plays their own seat.
##
##   var gen := MissionGenerator.generate(seed, {...the whole squad...})
##   PvpBattle.split(gen, {"a": ["p1", "p3"], "b": ["p2"]}, {"b": [{"template": ..., "count": 2}]})
##   ... the mission ends when one side is left: PvpBattle.winner(mission) -> "a" / "b" / ""

const ALLY_SEAT_A := "allies"
const KEY := "pvp"


## Turns a generated mission (MissionGenerator.generate's {state, mission}) into a fight
## between the squad's groups: `groups` {key: [seats]} in order (a split vote: {option id:
## [seats]}). The first group stays on the squad's side, the second takes the other side and
## deploys in the other zone, any further group gets its own side (all hostile to each other)
## and deploys as far from both zones as the map allows. The generated NPC enemies leave. The
## first two groups can have allies (`allies` {key: [{template, count, name}]}: the first's flown
## by the "allies" AI seat, the second's by the AI GM). Returns "" or why not.
static func split(gen: Dictionary, groups: Dictionary, allies: Dictionary = {}, id: String = "", ai_seats: Array = []) -> String:
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var keys: Array = groups.keys().filter(func(k: Variant) -> bool: return not (groups[k] as Array).is_empty())
	if keys.size() < 2:
		return "Both sides need at least one player."
	var seen := {}
	for k: Variant in keys:
		for seat: Variant in groups[k]:
			if not state.seats.has(str(seat)):
				return "No seat %s in this battle." % seat
			if seen.has(seat):
				return "%s can't be on two sides." % seat
			seen[seat] = true
	# No generated enemies: the fight is between the squad's groups.
	for u: Unit in state.units.values().duplicate():
		if u.side == Mission.ENEMIES:
			state.units.erase(u.id)
	mission.reinforcement_pool = []
	mission.allow_reinforcements = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.game_seed, "pvp"])
	var side_of := {}
	for i in range(keys.size()):
		side_of[str(keys[i])] = Mission.PLAYERS if i == 0 else (Mission.ENEMIES if i == 1 else "side_%s" % keys[i])
	for i in range(1, keys.size()):
		var side: String = side_of[str(keys[i])]
		var free := MissionGenerator._free_cells(mission.deployment.get(Mission.ENEMIES, []), rng) if i == 1 else _far_cells(state, mission)
		for seat: Variant in groups[keys[i]]:
			state.seats[str(seat)]["side"] = side
		for u: Unit in state.units.values().duplicate():
			if (groups[keys[i]] as Array).has(u.controller):
				u.side = side
				state.units.erase(u.id)
				if not MissionGenerator._place(state, u, free):  # into that side's ground
					state.add_unit(u)  # no room there: it stays where it was
	_add_allies(state, mission, allies.get(keys[0], []), Mission.PLAYERS, ALLY_SEAT_A, "pa", rng)
	_add_allies(state, mission, allies.get(keys[1], []), Mission.ENEMIES, NetHost.GM_SEAT, "pb", rng)
	var ai := {}
	for seat: Variant in ai_seats:
		ai[str(seat)] = true
	var p := {"id": id, "groups": {}, "side_of": side_of, "ai": ai, "out": []}
	for k: Variant in keys:
		p["groups"][str(k)] = (groups[k] as Array).duplicate()
		p[str(k)] = (groups[k] as Array).duplicate()  # also by key (pvp_requested's "a" / "b")
	mission.flavor[KEY] = p
	mission.briefing = "The squad is split. %s: the last side standing decides it." % " against ".join(PackedStringArray(keys.map(func(k: Variant) -> String: return _names(state, groups[k]))))
	return ""


## Cells as far as the map allows from both deployment zones (a third side's ground).
static func _far_cells(state: GameState, mission: Mission) -> Array:
	var anchors: Array = []
	for side: String in [Mission.PLAYERS, Mission.ENEMIES]:
		var cells: Array = mission.deployment.get(side, [])
		if not cells.is_empty():
			anchors.append(Vector2i(int(cells[0][0]), int(cells[0][1])))
	var all: Array = state.map.cells()
	all.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := 999
		var db := 999
		for x: Vector2i in anchors:
			da = mini(da, state.map.grid.distance(a, x))
			db = mini(db, state.map.grid.distance(b, x))
		return da > db)
	return all.slice(0, 24)


## The winning group once it's decided (its key: a split vote's option id), or "".
static func winner(mission: Mission) -> String:
	if not mission.flavor.has(KEY) or mission.outcome == "":
		return ""
	var side_of: Dictionary = mission.flavor[KEY].get("side_of", {})
	for k: String in side_of:
		if side_of[k] == mission.outcome:
			return k
	return ""


## What story gets when it's over: {id, winner, reason, groups: {key: [seats]}} (and each group
## by its key).
static func result(mission: Mission) -> Dictionary:
	var p: Dictionary = mission.flavor.get(KEY, {})
	var r := {"id": str(p.get("id", "")), "winner": winner(mission), "reason": mission.outcome_reason, "groups": p.get("groups", {})}
	for k: String in p.get("groups", {}):
		r[k] = p["groups"][k]
	return r


## Last side standing (Mission.observe): a side is out when all its units are down (destroyed,
## or knocked out in a non-lethal fight) or its people have yielded. Returns the winning side or "".
static func last_side(mission: Mission, state: GameState) -> String:
	var p: Dictionary = mission.flavor.get(KEY, {})
	var standing: Array = []
	for k: String in p.get("groups", {}):
		if (p.get("out", []) as Array).has(k):
			continue
		var side: String = p["side_of"][k]
		if state.units.values().any(func(u: Unit) -> bool: return u.side == side and Mission._counts(u)):
			standing.append(side)
	return standing[0] if standing.size() == 1 else ""


## A side gives up (a "Yield" button; every person on that side has to). When only one side is
## left, returns {outcome: its side, reason}, else {}.
static func yield_side(mission: Mission, state: GameState, seat: String) -> Dictionary:
	var p: Dictionary = mission.flavor.get(KEY, {})
	var group := ""
	for k: String in p.get("groups", {}):
		if (p["groups"][k] as Array).has(seat):
			group = k
	if group == "" or mission.outcome != "":
		return {}
	var yielded: Array = p.get("yielded", [])
	if not yielded.has(seat):
		yielded.append(seat)
	p["yielded"] = yielded
	var people: Array = (p["groups"][group] as Array).filter(func(s: Variant) -> bool: return not bool(p.get("ai", {}).get(str(s), false)))
	if not people.all(func(s: Variant) -> bool: return yielded.has(s)):
		return {}
	if not (p["out"] as Array).has(group):
		(p["out"] as Array).append(group)
	var left := last_side(mission, state)
	if left == "":
		return {}
	return {"outcome": left, "reason": "%s yield." % _names(state, p["groups"][group])}


## A compact arena around where the squad is (MissionGenerator.area, the hub's town at mech
## scale), with the two deployment zones close together: {state, mission} ready for split().
## The fight is non-lethal (state.objectives["nonlethal"]: the rules knock mechs out instead of
## destroying them or letting a reactor melt down).
static func arena(campaign: Campaign, story: StoryState, db: ContentDB, seed_value: int, fight: Dictionary = {}) -> Dictionary:
	var size := 30
	var area := MissionGenerator.area(seed_value, {"hub": story.hub, "size": size, "place": str(fight.get("place", "town"))})
	var doc := MapDoc.new()
	doc.map = area["map"]
	doc.w = size
	doc.h = size
	doc.name = str(area.get("name", "Arena"))
	var kit := str(area.get("kit", ""))
	doc.landscape = kit.get_slice("+", 0).get_slice("/", 0)
	doc.culture = kit.get_slice("+", 0).get_slice("/", 1) if "/" in kit else ""
	doc.sitrep = "sitrep_standardcombat"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	doc.deployment = SitrepLayout.layout("sitrep_standardcombat", size, size, doc.map.grid.shape, rng, 8)["deployment"]
	var gen := MissionGenerator.generate(seed_value, {"squad": CampaignLoop.squad(campaign, story), "db": db, "map_doc": doc, "sitrep": "sitrep_standardcombat",
		"environments": [], "settings": GmSettings.from_preset("Standard")})
	(gen["state"] as GameState).objectives["nonlethal"] = true
	return gen


static func is_pvp(mission: Mission) -> bool:
	return mission != null and mission.flavor.has(KEY)


static func _add_allies(state: GameState, mission: Mission, list: Array, side: String, seat: String, prefix: String, rng: RandomNumberGenerator) -> void:
	if list.is_empty():
		return
	var templates := UnitFactory.npc_templates()
	var free := MissionGenerator._free_cells(mission.deployment.get(side, []), rng)
	if not state.seats.has(seat):
		state.seats[seat] = {"name": "Allies", "side": side}
	var n := 0
	for a: Dictionary in list:
		if not templates.has(str(a.get("template", ""))):
			continue
		for i in range(int(a.get("count", 1))):
			n += 1
			var u := MissionGenerator.build_enemy({"template": str(a["template"])}, templates, "%s%d" % [prefix, n], n)
			u.name = "%s %d" % [a.get("name", "Ally"), i + 1]
			u.side = side
			u.controller = seat
			MissionGenerator._place(state, u, free)


static func _names(state: GameState, seats: Array) -> String:
	return ", ".join(PackedStringArray(seats.map(func(s: Variant) -> String: return str(state.seats.get(str(s), {}).get("name", s)))))
