extends TestCase
## MULE Harness riders, Expanded Compartment passengers, Cable Winch.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var m: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(systems: Array, frame: String = "mf_standard_pattern_i_everest") -> void:
	s = F.state()
	e = RulesEngine.new()
	m = UnitFactory.build_mech(db(), "m", frame, {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": systems})
	m.side = "players"
	s.add_unit(m)


func _turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	if s.phase != GameState.PHASE_COMBAT:
		e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_mule_harness() -> void:
	_setup(["ms_mule_harness"])
	var p := Pilots.make_pilot("p", "P", "players", "seat1")
	p.cell = Vector2i(1, 0)
	s.add_unit(p)
	var big := F.mech(s, "big", "enemies", Vector2i(0, 7))
	_turn(p)
	var out := F.act(e, s, "climb_on", "p", {"host": "m"})
	expect(F.ok(out), F.reason(out))
	expect_eq(p.cell, m.cell, "shares the mech's space")
	expect_eq(RulesQueries.attack_preview(s, "big", "0:0", "p")["cover"]["cover"], "soft", "riders have soft cover")
	_turn(m)
	F.act(e, s, "move", "m", {"to": [3, 3]})
	expect_eq(p.cell, m.cell, "moves with the mech")
	Combat.add_status(s, m, "Prone", "x")
	expect(not p.counters.has("riding"), "the mount knocked Prone: riders fall off")
	expect(p.has_status("Prone"))


func test_expanded_compartment() -> void:
	_setup(["ms_expanded_compartment"])
	m.controller = "seat1"
	var p := Pilots.make_pilot("p", "P", "players", "seat2")
	p.cell = Vector2i(1, 0)
	s.add_unit(p)
	_turn(p)
	var out := F.act(e, s, "board", "p", {"mech": "m"})
	expect(F.ok(out), F.reason(out))
	expect(not Combat.is_present(p), "can't be targeted inside")
	_turn(m)
	var key := ""
	for x: Dictionary in Abilities.all(m):
		if x["name"] == "Transfer Control":
			key = x["key"]
	out = F.act(e, s, "activate", "m", {"ability": key})
	expect(F.ok(out), F.reason(out))
	expect_eq(m.controller, "seat2")
	expect(m.has_status("Impaired") and m.has_status("Slowed"))


func test_cable_winch() -> void:
	_setup(["ms_cable_winch_system"])
	var t := F.mech(s, "t", "enemies", Vector2i(1, 0))
	_turn(m)
	F.load_dice(s, [3])
	var key := ""
	for x: Dictionary in Abilities.all(m):
		if x["name"] == "Cable Winch System":
			key = x["key"]
	var out := F.act(e, s, "activate", "m", {"ability": key, "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.counters.has("cable"))
	_turn(t)
	expect(not F.ok(F.act(e, s, "move", "t", {"to": [7, 0]})), "can't get more than 5 away")
	F.load_dice(s, [15])
	out = F.act(e, s, "cut_cable", "t", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(not t.counters.has("cable"))
