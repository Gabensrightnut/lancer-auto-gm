class_name RulesFixtures
extends RefCounted
## Helpers for the rules scenario tests (no tests in this file).


## Dice that return queued values first, then fall back to the seeded RNG.
class LoadedDice:
	extends Dice
	var queue: Array[int] = []
	var used := 0

	func die(sides: int) -> int:
		if used < queue.size():
			used += 1
			return queue[used - 1]
		return super(sides)

	## The engine rewinds dice when it pauses for a reaction (RulesEngine._snapshot).
	func checkpoint() -> int:
		return used

	func rewind(to: int) -> void:
		used = to


static func state(shape: GridLayout.Shape = GridLayout.Shape.SQUARE, w: int = 12, h: int = 12) -> GameState:
	var s := GameState.new(7, shape)
	s.map = BattleMap.flat(shape, w, h)
	s.dice = LoadedDice.new(7)
	# The table chose the suggested reading for every open rules question (tests that check a
	# ruling clear or change it).
	Rulings.apply_suggested(s)
	# Rules tests run on the book's rules; the Lancer Tactics variants have their own tests.
	for id: String in ["lt_split_barrage", "lt_brace_prompt", "lt_repeat_quick_tech"]:
		s.rulings[id] = {"choice": "book"}
	return s


static func load_dice(s: GameState, values: Array) -> void:
	var d := s.dice as LoadedDice
	d.queue.assign(values)
	d.used = 0


static func weapon(key: String, name: String, size: String = "Main", type: String = "Rifle", damage: String = "1d6", rng: int = 10, tags: Array = [], damage_type: String = "Kinetic") -> Dictionary:
	var range_entry := {"type": "Threat", "val": rng} if type == "Melee" else {"type": "Range", "val": rng}
	return {"key": key, "id": "test_" + key, "name": name, "mount": int(key.split(":")[0]) if ":" in key else -1,
		"size": size, "type": type, "damage": [{"type": damage_type, "val": damage}], "range": [range_entry], "tags": tags}


## A plain Size 1 mech: HP 10, Evasion 8, E-Def 8, Heat Cap 6, Speed 4, Sensors 10, Grit 0,
## armed with a 1d6 Rifle (key "0:0", range 10).
static func mech(s: GameState, id: String, side: String, cell: Vector2i, size: float = 1.0) -> Unit:
	var u := Unit.new()
	u.id = id
	u.name = id
	u.side = side
	u.kind = Unit.KIND_MECH
	u.cell = cell
	u.size = size
	u.level = s.map.ground_height(cell)
	u.max_hp = 10
	u.hp = 10
	u.heat_cap = 6
	u.evasion = 8
	u.edef = 8
	u.speed = 4
	u.sensors = 10
	u.repairs = 4
	u.loadout = {"weapons": [weapon("0:0", "Rifle")], "systems": []}
	s.add_unit(u)
	return u


static func act(engine: RulesEngine, s: GameState, type: String, actor: String, params: Dictionary = {}) -> Dictionary:
	return engine.submit(s, {"type": type, "actor": actor, "params": params})


## Starts combat with `u`'s side first and gives `u` its turn.
static func begin(engine: RulesEngine, s: GameState, u: Unit) -> void:
	if s.phase != GameState.PHASE_COMBAT:
		# Players always act first (Core p.60); tests then hand the pick to u's side.
		var first := u.side
		for o: Unit in s.units.values():
			if o.side == "players":
				first = "players"
		engine.submit(s, {"type": "start_combat", "params": {"first_side": first}})
	s.turn_side = u.side
	engine.submit(s, {"type": "start_turn", "actor": u.id})


static func events_of(out: Dictionary, type: String) -> Array:
	var found: Array = []
	for e: Dictionary in out["events"]:
		if e["type"] == type:
			found.append(e)
	return found


static func ok(out: Dictionary) -> bool:
	return (out["result"] as RuleResult).ok


static func reason(out: Dictionary) -> String:
	return (out["result"] as RuleResult).reason
