extends TestCase
## Frame traits and core systems that deal or change damage: bonus damage (Core p.67),
## integrated weapons (Core p.32), Neurolink, Mark for Death, Seeking Payload, Avenger Silos,
## the Pegasus omnigun and average damage, Raleigh Thunder God, Tokugawa Limit Break.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _frame(id: String, frame: String, side: String, cell: Vector2i, weapons: Array = ["mw_assault_rifle"]) -> Unit:
	var u := UnitFactory.build_mech(db(), id, frame, {"mounts": [{"weapons": weapons}], "systems": []})
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


func _ability(u: Unit, name: String) -> String:
	for a: Dictionary in Abilities.all(u):
		if a["name"] == name:
			return a["key"]
	return ""


func _melee(u: Unit) -> void:
	u.loadout["weapons"] = [F.weapon("0:0", "Blade", "Main", "Melee", "1d6", 1)]


func test_nelson_momentum_after_boost() -> void:
	_setup()
	var nel := _frame("nel", "mf_nelson", "players", Vector2i(0, 0))
	_melee(nel)
	var t := F.mech(s, "t", "enemies", Vector2i(3, 0))
	t.max_hp = 30
	t.hp = 30
	_turn(nel)
	F.act(e, s, "boost", "nel", {"to": [2, 0]})
	F.load_dice(s, [15, 3, 4])
	var out := F.act(e, s, "skirmish", "nel", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "bonus_damage").size(), 1, "the melee attack after a Boost gains +1d6")
	expect_eq(t.hp, 30 - 3 - 4)
	_turn(t, true)
	_turn(nel)
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "skirmish", "nel", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "bonus_damage").is_empty(), "no Boost first: no bonus")


func test_mourning_cloak_hunter_needs_an_isolated_target() -> void:
	_setup()
	var mc := _frame("mc", "mf_mourning_cloak", "players", Vector2i(2, 0))
	_melee(mc)
	var t := F.mech(s, "t", "enemies", Vector2i(3, 0))
	t.max_hp = 30
	t.hp = 30
	var ally := F.mech(s, "ally", "enemies", Vector2i(4, 0))
	_turn(mc)
	F.load_dice(s, [15, 3])
	var out := F.act(e, s, "skirmish", "mc", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "bonus_damage").is_empty(), "another character next to the target")
	ally.cell = Vector2i(8, 8)
	_turn(t, true)
	_turn(mc)
	F.load_dice(s, [15, 3, 5, 15, 3])
	out = F.act(e, s, "skirmish", "mc", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "bonus_damage").size(), 1, "alone with the Mourning Cloak: +1d6")
	F.act(e, s, "overcharge", "mc")
	out = F.act(e, s, "skirmish", "mc", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "bonus_damage").is_empty(), "1/round")


func test_tokugawa_limit_break_and_plasma_sheath() -> void:
	_setup()
	var tok := _frame("tok", "mf_tokugawa", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(13, 0))
	t.max_hp = 40
	t.hp = 40
	_turn(tok)
	var out := F.act(e, s, "skirmish", "tok", {"weapon": "0:0", "target": "t"})
	expect(not F.ok(out), "Range 10 assault rifle can't reach 13 spaces")
	out = F.act(e, s, "activate", "tok", {"ability": _ability(tok, "Overclock")})
	expect(F.ok(out), F.reason(out))
	expect(tok.has_status("Exposed"))
	F.load_dice(s, [15, 4])
	out = F.act(e, s, "skirmish", "tok", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), "Exposed: +5 range")
	expect_eq(F.events_of(out, "damage_rolled")[0]["damage_type"], "Energy", "kinetic becomes energy")
	var bonus: Dictionary = F.events_of(out, "bonus_damage")[0]
	expect_eq([bonus["damage_type"], bonus["amount"]], ["Energy", 3])
	expect_eq(t.hp, 40 - 4 - 3)
	tok.heat = 3
	tok.statuses["Danger Zone"] = {"source": "heat"}
	F.act(e, s, "overcharge", "tok")
	F.load_dice(s, [15, 4])
	out = F.act(e, s, "skirmish", "tok", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "bonus_damage")[0]["damage_type"], "Burn", "Danger Zone + energy weapon: bonus becomes burn")
	expect_eq(t.burn, 3)


func test_deaths_head_neurolink_rerolls_the_first_miss() -> void:
	_setup()
	var dh := _frame("dh", "mf_deaths_head", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(6, 0))
	t.max_hp = 30
	t.hp = 30
	_turn(dh)
	F.load_dice(s, [2, 15, 3])
	var out := F.act(e, s, "skirmish", "dh", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_rerolled").size(), 1)
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "hit", "the second result stands")
	F.act(e, s, "overcharge", "dh")
	F.load_dice(s, [1, 2, 15])
	out = F.act(e, s, "skirmish", "dh", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "attack_rerolled").is_empty(), "only the first ranged attack each round")


func test_deaths_head_mark_for_death() -> void:
	_setup()
	var dh := _frame("dh", "mf_deaths_head", "players", Vector2i(0, 0))
	var near := F.mech(s, "near", "enemies", Vector2i(3, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(8, 0))
	t.max_hp = 50
	t.hp = 50
	_turn(dh)
	expect(F.ok(F.act(e, s, "core_power", "dh")))
	var key := _ability(dh, "Mark for Death")
	expect(not F.ok(F.act(e, s, "activate", "dh", {"ability": key, "target": "near"})), "must be further than range 5")
	var out := F.act(e, s, "activate", "dh", {"ability": key, "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(dh.has_status("Immobilized"))
	expect(not Reactions.can_react(dh, "overwatch", s).ok, "no reactions while focusing")
	_turn(near, true)
	_turn(dh)
	# Crit: 1d6 rolled twice (keep 1), bonus 2d6 (Main) rolled twice (keep 2).
	F.load_dice(s, [20, 2, 5, 6, 6, 1, 1])
	out = F.act(e, s, "skirmish", "dh", {"weapon": "0:0", "target": "t"})
	var bonus: Array = F.events_of(out, "bonus_damage")
	expect_eq(bonus.size(), 1)
	expect_eq(bonus[0]["amount"], 12)
	expect_eq(t.hp, 50 - 5 - 12)
	_turn(near, true)
	_turn(dh)
	expect(F.ok(F.act(e, s, "activate", "dh", {"ability": _ability(dh, "Cease Focus")})))
	expect(not dh.has_status("Immobilized"))
	expect(not dh.counters.has("focus"))


func test_monarch_seeking_payload_ignores_cover_and_reduction() -> void:
	_setup()
	var mon := _frame("mon", "mf_monarch", "players", Vector2i(0, 0))
	mon.loadout["weapons"] = [F.weapon("0:0", "Rack", "Main", "Launcher", "1d6", 10)]
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	t.armor = 2
	t.statuses["Lock On"] = {"source": "test"}
	s.map.set_column(Vector2i(4, 0), 2)  # a wall between them
	_turn(mon)
	var p := RulesQueries.attack_preview(s, "mon", "0:0", "t")
	expect(p["ok"], p["reason"])
	expect(p.get("seeking_payload", false))
	F.load_dice(s, [15, 1, 5])
	var out := F.act(e, s, "skirmish", "mon", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 5, "Armor doesn't reduce it")
	expect(not t.has_status("Lock On"), "Lock On consumed")


func test_monarch_avenger_silos_asks_for_a_target() -> void:
	_setup()
	var mon := _frame("mon", "mf_monarch", "players", Vector2i(0, 0))
	mon.controller = "seat1"
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	t.max_hp = 30
	t.hp = 30
	var other := F.mech(s, "o", "enemies", Vector2i(5, 3))
	_turn(mon)
	F.load_dice(s, [20, 3, 4])
	var out := F.act(e, s, "skirmish", "mon", {"weapon": "0:0", "target": "t"})
	var asked: Array = F.events_of(out, "reaction_offered")
	expect_eq(asked.size(), 1)
	expect_eq(asked[0]["reaction"], "avenger_silos")
	expect(asked[0]["context"]["targets"].has("o"))
	out = F.act(e, s, "react", "mon", {"take": true, "target": "o"})
	expect(F.ok(out), F.reason(out))
	expect_eq(other.hp, 7, "3 explosive to a different character")


func test_pegasus_omnigun_and_average_damage() -> void:
	_setup()
	var peg := _frame("peg", "mf_pegasus", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(6, 0))
	t.armor = 3
	t.resistances = ["Kinetic"]
	_turn(peg)
	var key := _ability(peg, "Fire Omnigun")
	var out := F.act(e, s, "activate", "peg", {"ability": key, "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 9, "1 damage, ignoring Armor and Resistance")
	expect(not F.ok(F.act(e, s, "activate", "peg", {"ability": key, "target": "t"})), "1/round")
	t.armor = 0
	t.resistances = []
	F.load_dice(s, [15])
	out = F.act(e, s, "skirmish", "peg", {"weapon": "0:0", "target": "t", "average_damage": true})
	expect_eq(F.events_of(out, "damage_rolled")[0]["roll"]["total"], 4, "1d6 averages to 4")
	_turn(t, true)
	_turn(peg)
	expect(F.ok(F.act(e, s, "core_power", "peg")))
	for i in range(3):
		expect(F.ok(F.act(e, s, "activate", "peg", {"ability": key, "target": "t"})), "3/round with the core")
	expect(not F.ok(F.act(e, s, "activate", "peg", {"ability": key, "target": "t"})))


func test_raleigh_thunder_god_chambers() -> void:
	_setup()
	var ral := _frame("ral", "mf_raleigh", "players", Vector2i(0, 0))
	var mj := Weapons.find(ral, "int:0")
	expect_eq(mj.get("name", ""), "M35 Mjolnir", "integrated weapon (Core p.32)")
	var t := F.mech(s, "t", "enemies", Vector2i(3, 0))
	t.max_hp = 40
	t.hp = 40
	t.armor = 2
	_turn(ral)
	expect(F.ok(F.act(e, s, "core_power", "ral")))
	_turn(t, true)
	expect_eq(int(ral.counters.get("chambers", 0)), 2, "two rounds after a turn it didn't fire")
	_turn(ral)
	_turn(t, true)
	expect_eq(int(ral.counters["chambers"]), 4)
	_turn(ral)
	F.load_dice(s, [15])
	var out := F.act(e, s, "skirmish", "ral", {"weapon": "int:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 40 - 16, "4 rounds: 16 kinetic, AP")
	expect(t.has_status("Shredded"))
	expect_eq(int(ral.counters["chambers"]), 0)
	_turn(t, true)
	expect_eq(int(ral.counters["chambers"]), 0, "fired this turn: nothing loaded")


func test_integrated_weapons_that_cant_attack_normally() -> void:
	_setup()
	var bar := _frame("bar", "mf_barbarossa", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(8, 0))
	var rail := Weapons.find(bar, "int:0")
	expect(rail.get("integrated", false))
	expect(rail.get("no_attack", false))
	_turn(bar)
	expect(not F.ok(F.act(e, s, "barrage", "bar", {"attacks": [{"weapon": "int:0", "target": "t"}]})))
