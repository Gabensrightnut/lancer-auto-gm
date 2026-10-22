extends TestCase
## GMS gear (General Massive Systems, LL0): every weapon fires, and the systems' rules (Core
## p.120-121).

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


func _setup(systems: Array = [], mounts: Array = [{"weapons": ["mw_assault_rifle"]}]) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": systems})
	a.side = "players"
	a.controller = "seat1"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", Vector2i(4, 0))
	t.max_hp = 30
	t.hp = 30
	F.begin(e, s, a)


func _ability(u: Unit, name: String) -> String:
	for x: Dictionary in Abilities.all(u):
		if x["name"] == name:
			return x["key"]
	return ""


func _next_turn() -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")


func test_every_gms_weapon_fires() -> void:
	for w: Dictionary in db().all("weapons"):
		if w.get("source", "") != "GMS" or w.get("mount", "") == "Superheavy":
			continue
		var mount := {"Main": 0, "Auxiliary": 1, "Heavy": 2}.get(w.get("mount", ""), 0) as int
		var mounts: Array = [{}, {}, {}]
		mounts[mount] = {"weapons": [w["id"]]}
		_setup([], mounts)
		var key := "%d:0" % mount
		var weapon := Weapons.find(a, key)
		if Weapons.is_melee(weapon):
			t.cell = Vector2i(1, 0)
		var params := {"weapon": key, "target": "t"}
		if Weapons.area(weapon) != "":
			params = {"weapon": key, "aim": [t.cell.x, t.cell.y]}
		var out := F.act(e, s, "skirmish", "a", params)
		expect(F.ok(out), "%s: %s" % [w["id"], F.reason(out)])
		expect(not F.events_of(out, "attack_rolled").is_empty() or not F.events_of(out, "area_attack").is_empty(), w["id"])


func test_cyclone_pulse_rifle_takes_a_barrage() -> void:
	_setup([], [{}, {}, {"weapons": ["mw_cyclone_pulse_rifle"]}])
	var out := F.act(e, s, "barrage", "a", {"attacks": [{"weapon": "2:0", "target": "t"}]})
	expect(F.ok(out), F.reason(out))


func test_frag_grenade() -> void:
	_setup(["ms_pattern_b_hex_charges"])
	var t2 := F.mech(s, "t2", "enemies", Vector2i(4, 1))
	var key := _ability(a, "Frag Grenade")
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key, "aim": [9, 0]})), "Range 5")
	F.load_dice(s, [4, 3, 15])  # 1d6 = 4; t fails, t2 saves
	var out := F.act(e, s, "activate", "a", {"ability": key, "aim": [4, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 26)
	expect_eq(t2.hp, 8, "half on a success")


func test_smoke_grenade_gives_soft_cover() -> void:
	_setup(["ms_pattern_a_smoke_charges"])
	var out := F.act(e, s, "activate", "a", {"ability": _ability(a, "Smoke Grenade"), "aim": [4, 0]})
	expect(F.ok(out), F.reason(out))
	var foe := F.mech(s, "foe", "enemies", Vector2i(10, 0))
	expect_eq(RulesQueries.attack_preview(s, "foe", "0:0", "t")["cover"]["cover"], "soft")
	_next_turn()
	_next_turn()
	expect(s.zones.is_empty(), "disperses at the end of your next turn")
	expect_eq(foe.hp, 10)


func test_smoke_mine_only_allies_set_it_off() -> void:
	_setup(["ms_pattern_a_smoke_charges"])
	var out := F.act(e, s, "activate", "a", {"ability": _ability(a, "Deploy Smoke Mine"), "to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "enemies"
	t.cell = Vector2i(4, 1)
	F.act(e, s, "start_turn", "t")
	out = F.act(e, s, "move", "t", {"to": [2, 1]})
	expect(F.events_of(out, "mine_triggered").is_empty(), "a hostile doesn't set off a Smoke Mine")
	var ally := F.mech(s, "ally", "players", Vector2i(0, 3))
	F.act(e, s, "end_turn", "t")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "ally")
	out = F.act(e, s, "move", "ally", {"to": [0, 1]})
	expect_eq(F.events_of(out, "mine_triggered").size(), 1)
	expect_eq(Zones.of_kind(s, "smoke").size(), 1, "burst 3 of smoke")


func test_type_3_projected_shield() -> void:
	_setup(["ms_type_3_projected_shield"])
	var out := F.act(e, s, "activate", "a", {"ability": _ability(a, "Project Shield"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.heat, 1, "Heat 1 (Self)")
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect_eq(p["difficulty"], 2, "+2 Difficulty on attacks against them")
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "a")["difficulty"], 2, "and on theirs against you")


func test_turret_drone_joins_a_hit() -> void:
	_setup(["ms_turret_drones"])
	var out := F.act(e, s, "activate", "a", {"ability": _ability(a, "Deploy Turret Drone"), "to": [2, 2]})
	expect(F.ok(out), F.reason(out))
	a.counters["reaction_policy"] = {"turret_attack": "auto"}
	F.act(e, s, "overcharge", "a")
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	var turret := F.events_of(out, "reaction").filter(func(x: Dictionary) -> bool: return x["reaction"] == "turret_attack")
	expect_eq(turret.size(), 1, "the turret adds 3 kinetic")
	expect_eq(t.hp, 30 - 3 - 3)


func test_custom_paint_job_personalizations_stable_structure() -> void:
	_setup(["ms_custom_paint_job", "ms_personalizations", "ms_stable_structure"])
	var plain := UnitFactory.build_mech(db(), "p", "mf_standard_pattern_i_everest", {"mounts": [], "systems": []})
	expect_eq(a.max_hp, plain.max_hp + 2, "Personalizations: +2 HP")
	var st := a.structure
	a.hp = 2
	F.load_dice(s, [6])
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 9}], {"ap": true})
	expect_eq([a.structure, a.hp], [st, 1], "a 6: just scratched the paint")
	F.load_dice(s, [1, 1])
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 9}], {"ap": true})
	expect_eq(a.structure, st - 1, "once per Full Repair")
	var op := {"op": "save_damage", "save": "hull", "damage": "1", "type": "Kinetic", "on_fail": [{"status": "Prone"}]}
	var ev := AbilityActions.apply_target_ops(s, t, [op], ["a"])
	var srcs: Array = F.events_of({"events": ev}, "skill_check")[0]["check"]["sources"]
	expect(srcs.any(func(x: Dictionary) -> bool: return x["label"] == "ms_stable_structure"), "Stable Structure: +1 on saves against Prone")
