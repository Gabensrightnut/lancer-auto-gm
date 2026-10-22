extends TestCase
## Reactions and checks from frame traits and core systems around attacks (TraitReactions).

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _frame(id: String, frame: String, side: String, cell: Vector2i) -> Unit:
	var u := UnitFactory.build_mech(db(), id, frame, {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []})
	u.side = side
	u.cell = cell
	s.add_unit(u)
	return u


func _setup() -> void:
	s = F.state()
	e = RulesEngine.new()


func _turn(u: Unit, new_round: bool = false) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	if s.phase != GameState.PHASE_COMBAT:
		e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	if new_round:
		s.round_number += 1
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func _reactions(out: Dictionary, kind: String) -> Array:
	return F.events_of(out, "reaction").filter(func(x: Dictionary) -> bool: return x["reaction"] == kind)


func test_black_witch_mag_parry() -> void:
	_setup()
	_frame("bw", "mf_black_witch", "enemies", Vector2i(5, 1))
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(a)
	F.load_dice(s, [15, 5])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(_reactions(out, "mag_parry").size(), 1, "an adjacent ally's kinetic hit")
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "miss", "5+: the attack misses")
	expect_eq(t.hp, 10)
	F.act(e, s, "overcharge", "a")
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(_reactions(out, "mag_parry").is_empty(), "1/round")
	expect_eq(t.hp, 7)


func test_saladin_warp_shield_and_defensive_pulse() -> void:
	_setup()
	var sal := _frame("sal", "mf_saladin", "enemies", Vector2i(6, 3))
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(a)
	F.load_dice(s, [15, 6, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(_reactions(out, "warp_shield").size(), 1)
	var srcs: Array = F.events_of(out, "attack_rolled")[0]["check"]["sources"]
	expect(srcs.any(func(x: Dictionary) -> bool: return x["label"] == "Warp Shield"), "+1 Difficulty from Warp Shield")
	_turn(sal, true)
	expect(not F.ok(F.act(e, s, "core_power", "sal")), "needs a target to shield")
	var core := F.act(e, s, "core_power", "sal", {"target": "t"})
	expect(F.ok(core), F.reason(core))
	sal.counters["reaction_policy"] = {"warp_shield": "never"}
	_turn(a)
	F.load_dice(s, [15, 6])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(_reactions(out, "defensive_pulse").size(), 1)
	expect_eq(t.hp, 7 - 3, "Resistance to the attack's damage: 6 halved")


func test_goblin_reactive_code_invades_back() -> void:
	_setup()
	var gob := _frame("gob", "mf_goblin", "enemies", Vector2i(3, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(a)
	F.load_dice(s, [19, 19])
	var out := F.act(e, s, "invade", "a", {"target": "gob"})
	expect(F.ok(out), F.reason(out))
	var r := _reactions(out, "reactive_code")
	expect_eq(r.size(), 1)
	expect_eq(r[0]["action"], "invade")
	expect(a.has_status("Impaired"), "the Goblin's Invade hit back")
	expect_eq(a.heat, 2)
	expect(gob.has_status("Impaired"))


func test_swallowtail_tactical_simulation() -> void:
	_setup()
	var sw := _frame("sw", "mf_swallowtail", "enemies", Vector2i(6, 4))
	var t := F.mech(s, "t", "enemies", Vector2i(6, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(sw)
	expect(F.ok(F.act(e, s, "core_power", "sw")))
	_turn(a, true)
	F.load_dice(s, [15, 6, 5])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var r := _reactions(out, "tactical_simulation")
	expect_eq(r.size(), 1)
	expect(r[0]["resist"], "4+: Resistance")
	expect_eq(t.hp, 10 - 3)


func test_tactical_simulation_teleport_when_asked() -> void:
	_setup()
	var sw := _frame("sw", "mf_swallowtail", "players", Vector2i(6, 4))
	sw.controller = "seat1"
	var t := F.mech(s, "t", "players", Vector2i(6, 0))
	var a := F.mech(s, "a", "enemies", Vector2i(0, 0))
	t.counters["reaction_policy"] = {"brace": "never"}
	_turn(sw)
	expect(F.ok(F.act(e, s, "core_power", "sw")))
	_turn(a, true)
	F.load_dice(s, [15, 6, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "reaction_offered")[0]["reaction"], "tactical_simulation")
	out = F.act(e, s, "react", "sw", {"take": true, "to": [6, 6]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 4, "3 or less: no Resistance")
	expect_eq(t.cell, Vector2i(6, 6), "but it may teleport up to 6")


func test_gorgon_basilisk_stuns_before_the_attack() -> void:
	_setup()
	var gor := _frame("gor", "mf_gorgon", "enemies", Vector2i(6, 2))
	var t := F.mech(s, "t", "enemies", Vector2i(6, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(gor)
	expect(F.ok(F.act(e, s, "core_power", "gor")))
	_turn(a, true)
	F.load_dice(s, [3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(a.has_status("Stunned"), "failed the Systems save")
	expect(F.events_of(out, "attack_rolled").is_empty(), "no attack (suggested ruling)")
	expect_eq(F.events_of(out, "attack_cancelled").size(), 1)
	expect_eq(t.hp, 10)
	expect((a.counters["basilisk_stunned"] as Array).has("gor"), "once per scene")


func test_metalmark_flash_cloak_invisible_against_overwatch() -> void:
	_setup()
	var mm := _frame("mm", "mf_metalmark", "players", Vector2i(0, 0))
	F.mech(s, "h", "enemies", Vector2i(1, 1))
	_turn(mm)
	F.load_dice(s, [1])
	var out := F.act(e, s, "move", "mm", {"to": [0, 3]})
	expect_eq(F.events_of(out, "invisible_roll").size(), 1, "Overwatch against a moving Metalmark")
