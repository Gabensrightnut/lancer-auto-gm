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
## between the two groups: the generated NPC enemies leave, group b's seats and units change
## sides and deploy in the other zone, and each group gets its allies (group a's flown by the
## "allies" AI seat, group b's by the AI GM). Returns "" or why not.
static func split(gen: Dictionary, groups: Dictionary, allies: Dictionary = {}, id: String = "") -> String:
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var a: Array = groups.get("a", [])
	var b: Array = groups.get("b", [])
	if a.is_empty() or b.is_empty():
		return "Both sides need at least one player."
	for seat: Variant in a + b:
		if not state.seats.has(str(seat)):
			return "No seat %s in this battle." % seat
	for seat: Variant in a:
		if b.has(seat):
			return "%s can't be on both sides." % seat
	# No generated enemies: the fight is between the squad's two groups.
	for u: Unit in state.units.values().duplicate():
		if u.side == Mission.ENEMIES:
			state.units.erase(u.id)
	mission.reinforcement_pool = []
	mission.allow_reinforcements = false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.game_seed, "pvp"])
	var free := MissionGenerator._free_cells(mission.deployment.get(Mission.ENEMIES, []), rng)
	for seat: Variant in b:
		state.seats[str(seat)]["side"] = Mission.ENEMIES
	for u: Unit in state.units.values().duplicate():
		if b.has(u.controller):
			u.side = Mission.ENEMIES
			state.units.erase(u.id)
			if not MissionGenerator._place(state, u, free):  # into the other deployment zone
				state.add_unit(u)  # no room there: it stays where it was
	_add_allies(state, mission, allies.get("a", []), Mission.PLAYERS, ALLY_SEAT_A, "pa", rng)
	_add_allies(state, mission, allies.get("b", []), Mission.ENEMIES, NetHost.GM_SEAT, "pb", rng)
	mission.flavor[KEY] = {"id": id, "a": a.duplicate(), "b": b.duplicate()}
	mission.briefing = "The squad is split. %s against %s: the last side standing decides it." % [_names(state, a), _names(state, b)]
	return ""


## The winning group once the mission is decided ("a", "b"), or "" (not over, or no winner).
static func winner(mission: Mission) -> String:
	if not mission.flavor.has(KEY):
		return ""
	match mission.outcome:
		Mission.PLAYERS:
			return "a"
		Mission.ENEMIES:
			return "b"
	return ""


## What story gets when it's over: {id, winner: "a"/"b"/"", reason, a: [seats], b: [seats]}.
static func result(mission: Mission) -> Dictionary:
	var p: Dictionary = mission.flavor.get(KEY, {})
	return {"id": str(p.get("id", "")), "winner": winner(mission), "reason": mission.outcome_reason, "a": p.get("a", []), "b": p.get("b", [])}


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
