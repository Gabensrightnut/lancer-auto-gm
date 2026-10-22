extends TestCase
## AIs (Core p.107): handing over control, cascades, and the NHP systems.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(systems: Array, talents: Dictionary = {}, t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_tactical_knife"]}], "systems": systems}, {"ll": 6, "talents": talents})
	a.side = "players"
	a.controller = "seat1"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _act(name: String, params: Dictionary = {}) -> Dictionary:
	var p := params.duplicate()
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			p["ability"] = x["key"]
	return F.act(e, s, "activate", "a", p)


func _next_turn(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_hand_over_and_take_back() -> void:
	_setup(["ms_comp_con_class_assistant_unit"], {"t_brutal": 3})
	expect(Effects.has(a, "relentless"))
	var out := _act("Engage COMP/CON")
	expect(F.ok(out), F.reason(out))
	expect(AISystems.controlled(a))
	expect(not Effects.has(a, "relentless"), "the AI doesn't benefit from the pilot's talents")
	expect(not F.ok(F.act(e, s, "ai_control", "a", {"take_back": true})), "not on the same turn")
	_next_turn(a)
	out = F.act(e, s, "ai_control", "a", {"take_back": true})
	expect(F.ok(out), F.reason(out))
	expect(not AISystems.controlled(a))


func test_cascade_and_shut_down() -> void:
	_setup(["ms_sekhmet_class_nhp"])
	F.load_dice(s, [6, 1])  # the structure check (6), then the cascade d20 = 1
	Combat.structure_check(s, a)
	expect(AISystems.cascading(a), "a 1 on the d20: cascade")
	expect_eq(a.controller, "gm", "the NHP becomes a GM-controlled NPC")
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "the pilot can only Shut Down")
	var out := F.act(e, s, "shut_down", "a")
	expect(F.ok(out), F.reason(out))
	expect(not AISystems.cascading(a))
	expect_eq(a.controller, "seat1")
	_setup(["ms_comp_con_class_assistant_unit"])
	Combat.structure_check(s, a)
	expect(not AISystems.cascading(a), "COMP/CONs can't cascade")


func test_sekhmet() -> void:
	_setup(["ms_sekhmet_class_nhp"], {}, Vector2i(1, 0))
	expect(F.ok(_act("SEKHMET Protocol")))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "no ranged attacks")
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t", "free_via": "sekhmet"})
	expect(F.ok(out), F.reason(out))
	_next_turn(a)
	out = _act("Take Back Control")
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Stunned"), "taking back control Stuns you until your next turn")


func test_tlaloc_retargets_a_miss() -> void:
	_setup(["ms_tlaloc_class_nhp"])
	var t2 := F.mech(s, "t2", "enemies", Vector2i(5, 2))
	expect(F.ok(_act("TLALOC Protocol")))
	expect(a.has_status("Immobilized"))
	F.load_dice(s, [1, 15, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_retargeted").size(), 1)
	expect(t2.hp < 10, "the reroll hit a new target")


func test_athena_osiris() -> void:
	_setup(["ms_athena_class_nhp"])
	t.statuses["Invisible"] = {"source": "t"}
	expect(F.ok(_act("Simulacrum", {"aim": [4, 0]})))
	F.load_dice(s, [15, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "invisible_roll").is_empty(), "no Invisible inside the model")
	expect(not Combat.can_hide(s, t).ok)
	_setup(["ms_osiris_class_nhp"])
	for gate in range(1, 5):
		F.load_dice(s, [19])
		out = _act("Hurl Into the Duat", {"target": "t"})
		expect(F.ok(out), "gate %d: %s" % [gate, F.reason(out)])
		_next_turn(a)
	expect_eq(t.side, "players", "the Fourth Gate: it changes sides")
	_next_turn(t)
	F.act(e, s, "end_turn", "t")
	expect_eq(t.side, "enemies", "until the end of its next turn")


func test_scylla_and_noah() -> void:
	_setup(["ms_scylla_class_nhp"])
	a.counters["reaction_policy"] = {"scylla": "auto"}
	expect(F.ok(_act("Unleash SCYLLA")))
	_next_turn(t)
	F.load_dice(s, [1, 15, 4])
	var out := F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	var r := F.events_of(out, "reaction").filter(func(x: Dictionary) -> bool: return x["reaction"] == "scylla")
	expect_eq(r.size(), 1, "Skirmish back at the attacker")
	expect_eq(t.hp, 38, "half damage (4 halved)")
	_setup(["ms_noah_class_nhp"])
	a.counters["reaction_policy"] = {"diluvian_ark": "auto"}
	expect(F.ok(_act("Diluvian Ark")))
	_next_turn(t)
	F.load_dice(s, [5])
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "miss", "4+: the attack misses")
	expect_eq(t.hp, 36, "and the attacker takes 4 kinetic")
	expect_eq(a.heat, 2)
