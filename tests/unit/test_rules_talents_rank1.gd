extends TestCase
## Rank 1 talents automated in batch 9: Bonded, Executioner, Walking Armory, Exemplar, Heavy
## Gunner, Hunter, Infiltrator.

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


func _setup(talents: Dictionary, mounts: Array, t_cell: Vector2i = Vector2i(4, 0), pilot_extra: Dictionary = {}) -> void:
	s = F.state()
	e = RulesEngine.new()
	var pilot := {"ll": 6, "talents": talents}
	pilot.merge(pilot_extra)
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": []}, pilot)
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _key(name: String) -> String:
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			return x["key"]
	return ""


func test_bonded() -> void:
	_setup({"t_bonded": 1}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(4, 0), {"bondmate": "b"})
	var b := F.mech(s, "b", "players", Vector2i(1, 0))
	var check := Combat.skill_check(s, a, "hull", "test", 10, 0, 0, [], true)
	expect_eq((check["sources"] as Array).filter(func(x: Dictionary) -> bool: return x["label"] == "Bondmate")[0]["value"], 1, "+1 next to the bondmate")
	check = Combat.skill_check(s, b, "agility", "test", 10)
	expect_eq((check["sources"] as Array).filter(func(x: Dictionary) -> bool: return x["label"] == "Bondmate").size(), 1, "the bondmate gets it too")
	b.cell = Vector2i(5, 5)
	check = Combat.skill_check(s, a, "hull", "test", 10)
	expect((check["sources"] as Array).filter(func(x: Dictionary) -> bool: return x["label"] == "Bondmate").is_empty(), "only while adjacent")


func test_executioner_backswing() -> void:
	_setup({"t_executioner": 1}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_tactical_knife"]}, {"weapons": ["mw_heavy_melee_weapon"]}], Vector2i(1, 0))
	var other := F.mech(s, "o", "enemies", Vector2i(0, 1))
	other.max_hp = 30
	other.hp = 30
	F.load_dice(s, [15, 4, 4])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "2:0", "target": "t"})
	expect_eq(F.events_of(out, "follow_up_available").size(), 1)
	expect(not F.ok(F.act(e, s, "backswing", "a", {"target": "t"})), "a different character")
	F.load_dice(s, [15, 4, 4])
	out = F.act(e, s, "backswing", "a", {"target": "o"})
	expect(F.ok(out), F.reason(out))
	expect_eq(other.hp, 25, "half damage: 2d6+1 = 9, halved and rounded up (Core p.12) = 5")
	expect(not F.ok(F.act(e, s, "backswing", "a", {"target": "o"})), "once")


func test_walking_armory_ammo() -> void:
	_setup({"t_walking_armory": 1}, [{"weapons": ["mw_assault_rifle"]}])
	var near := F.mech(s, "n", "enemies", Vector2i(5, 0))
	F.load_dice(s, [15, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "ammo": "shock"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "damage_dealt")[0]["damage_type"], "Energy", "Shock: energy damage")
	expect_eq(near.hp, 9, "1 AP energy next to the target")
	expect_eq(TalentRules.ammo_left(a), 5)
	_next(a)
	expect(F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "ammo": "thumper"})), "once per turn, again next turn")
	_next(a)
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "ammo": "laser"})))


func test_exemplar_mark_and_valiant_aid() -> void:
	_setup({"t_exemplar": 1}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(3, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(0, 2))
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(String(t.counters.get("exemplar_mark", "")), "a", "marked, hit or miss, within 3")
	F.act(e, s, "end_turn", "a")
	s.turn_side = "players"
	F.act(e, s, "start_turn", "ally")
	F.load_dice(s, [2, 15, 3])
	var out := F.act(e, s, "skirmish", "ally", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_rerolled").size(), 1, "Valiant Aid: reroll the miss")
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "hit")


func test_heavy_gunner_covering_fire() -> void:
	_setup({"t_heavy_gunner": 1}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": []}, {"weapons": ["mw_heavy_machine_gun"]}])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Covering Fire"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Impaired"))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 6, 6, 6])
	out = F.act(e, s, "move", "t", {"to": [6, 0]})
	expect(not t.has_status("Impaired"), "moving more than 1 space clears it")
	expect_eq(F.events_of(out, "attack_rolled").size(), 1, "the reaction shot")


func test_hunter_lunge() -> void:
	_setup({"t_hunter": 1}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_tactical_knife"]}], Vector2i(4, 0))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})), "out of Threat without lunging")
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t", "lunge": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.cell, Vector2i(3, 0), "flew 3 spaces at the target")
	expect_eq(F.events_of(out, "attack_rolled").size(), 1)


func test_infiltrator_prowl() -> void:
	_setup({"t_infiltrator": 1}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(6, 0))
	var out := F.act(e, s, "hide", "a")
	expect(F.ok(out), "Hide in plain sight on its turn: " + F.reason(out))
	F.act(e, s, "move", "a", {"to": [2, 0]})
	expect(a.has_status("Hidden"), "line of sight doesn't reveal it during its turn")
	F.act(e, s, "end_turn", "a")
	expect(not a.has_status("Hidden"), "at the end of its turn, still in sight: revealed")


func _next(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_heavy_gunner_two_targets_and_pin() -> void:
	_setup({"t_heavy_gunner": 3}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": []}, {"weapons": ["mw_heavy_machine_gun"]}])
	var t2 := F.mech(s, "t2", "enemies", Vector2i(4, 2))
	var out := F.act(e, s, "activate", "a", {"ability": _key("Covering Fire"), "targets": ["t", "t2"]})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Impaired") and t2.has_status("Impaired"), "two targets")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 6, 6, 6])
	F.act(e, s, "move", "t", {"to": [6, 0]})
	expect(t.has_status("Immobilized"), "Heavy Gunner 2: pinned by the hit")


func test_walking_armory_rank_2_and_3() -> void:
	_setup({"t_walking_armory": 3}, [{"weapons": ["mw_assault_rifle"]}])
	t.armor = 2
	F.load_dice(s, [20, 3, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "ammo": "sabot"})
	expect(F.ok(out), F.reason(out))
	expect_eq(TalentRules.ammo_left(a), 6, "a crit spends no charges (rank 3)")
	expect_eq(t.hp, 37, "Sabot: AP ignores Armor 2")


func test_gunslinger_die() -> void:
	_setup({"t_gunslinger": 3}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}], Vector2i(3, 0))
	a.counters["gunslinger_die"] = 1
	F.load_dice(s, [15, 2, 3, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "bonus_damage").size() + F.events_of(out, "effect_triggered").filter(func(x: Dictionary) -> bool: return x["effect"] == "Gunslinger Die").size() >= 1, true)
	expect_eq(int(a.counters["gunslinger_die"]), 6, "reset after the charged shot")


func test_hacker_invade_options() -> void:
	_setup({"t_hacker": 2}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(3, 0))
	F.load_dice(s, [19])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Hack./Slash"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	expect(not F.ok(F.act(e, s, "scan", "t", {"target": "a"})), "no tech actions")
	F.load_dice(s, [15])
	F.act(e, s, "fix_hack", "t", {"what": "hack_slash"})
	expect(F.ok(F.act(e, s, "scan", "t", {"target": "a"})), "rebooted")


func test_return_fire() -> void:
	_setup({"t_gunslinger": 2}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}], Vector2i(3, 0))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 2, 15, 2])
	var out := F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	var rolls := F.events_of(out, "attack_rolled")
	expect_eq(rolls.size(), 2, "shot back")
	expect_eq(rolls[1]["attacker"], "a")


func test_intercede() -> void:
	_setup({"t_bonded": 2}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(5, 0), {"bondmate": "b"})
	var b := F.mech(s, "b", "players", Vector2i(1, 0))
	b.hp = 3
	Combat.deal_damage(s, b, [{"type": "Kinetic", "amount": 5}], {"source": "t"})
	expect_eq(b.hp, 3, "the Bonded mech took it")
	expect(a.hp < a.max_hp)


func test_flank() -> void:
	_setup({"t_tactician": 3}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(4, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(0, 2))
	F.act(e, s, "end_turn", "a")
	s.turn_side = "players"
	F.act(e, s, "start_turn", "ally")
	F.load_dice(s, [15, 2, 15, 4])
	var out := F.act(e, s, "skirmish", "ally", {"weapon": "0:0", "target": "t"})
	var rolls := F.events_of(out, "attack_rolled")
	expect_eq(rolls.size(), 2, "Flank: the Tactician joins in")
	expect_eq(t.hp, 40 - 2 - 2, "half of 4")


func test_executioner_reroll() -> void:
	_setup({"t_executioner": 3}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_tactical_knife"]}, {"weapons": ["mw_heavy_melee_weapon"]}], Vector2i(1, 0))
	var other := F.mech(s, "o", "enemies", Vector2i(0, 1))
	F.load_dice(s, [2, 15, 3, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_rerolled")[0]["target"], "o", "rerolled against the other character")
	expect(other.hp < 10)


func test_hunter_throw() -> void:
	_setup({"t_hunter": 3}, [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_tactical_knife"]}], Vector2i(1, 0))
	var far := F.mech(s, "far", "enemies", Vector2i(4, 2))
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	expect_eq(F.events_of(out, "follow_up_available").size(), 1)
	F.load_dice(s, [15, 2])
	out = F.act(e, s, "hunter_throw", "a", {"weapon": "1:0", "target": "far"})
	expect(F.ok(out), F.reason(out))
	expect(far.hp < 10, "thrown with Thrown 5 (Hunter 2)")


func test_exemplar_overwatch() -> void:
	_setup({"t_exemplar": 2}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(3, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(2, 2))
	F.load_dice(s, [15, 2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 2, 15, 2])
	var out := F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "ally"})
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "the mark attacked someone near the Exemplar: Overwatch")


func test_spotter_free_lock_on() -> void:
	_setup({"t_spotter": 2}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(3, 0))
	F.act(e, s, "lock_on", "a", {"target": "t"})
	t.statuses.erase("Lock On")
	F.act(e, s, "end_turn", "a")
	expect(t.has_status("Lock On"), "a free Lock On at the end of a still turn")
