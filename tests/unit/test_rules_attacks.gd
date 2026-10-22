extends TestCase
## Skirmish, Barrage, Accuracy/Difficulty sources, damage, tags.
## Loaded dice: the d20 comes first, then Accuracy/Difficulty d6s, then damage dice.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(weapon: Dictionary = {}) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", Vector2i(3, 0))
	if not weapon.is_empty():
		a.loadout["weapons"].append(weapon)
	F.begin(e, s, a)


func _shoot(dice: Array, key := "0:0", extra := {}) -> Dictionary:
	F.load_dice(s, dice)
	var params := {"weapon": key, "target": "t"}
	params.merge(extra, true)
	return F.act(e, s, "skirmish", "a", params)


func test_hit_rolls_damage_minus_armor() -> void:
	_setup()
	t.armor = 1
	var out := _shoot([15, 4])
	expect(F.ok(out), F.reason(out))
	var roll: Dictionary = F.events_of(out, "attack_rolled")[0]
	expect_eq(roll["result"], "hit")
	expect_eq(roll["check"]["d20"], 15)
	expect_eq(roll["check"]["target"], 8, "vs Evasion 8")
	var dmg: Dictionary = F.events_of(out, "damage_dealt")[0]
	expect_eq(dmg["armor_reduced"], 1)
	expect_eq(t.hp, 7)


func test_miss_deals_nothing() -> void:
	_setup()
	_shoot([2])
	expect_eq(t.hp, 10)


func test_crit_rolls_damage_dice_twice_keeping_the_best() -> void:
	_setup()
	var out := _shoot([20, 2, 5])
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "crit")
	expect_eq(t.hp, 5, "1d6 on a crit: rolled 2 and 5, kept 5")


func test_reliable_damage_on_a_miss() -> void:
	_setup(F.weapon("1:0", "Reliable Gun", "Main", "Rifle", "1d6", 10, [{"id": "tg_reliable", "val": 2}]))
	var out := _shoot([1], "1:0")
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "miss")
	expect_eq(t.hp, 8)


func test_armor_piercing_ignores_armor() -> void:
	_setup(F.weapon("1:0", "AP Gun", "Main", "Rifle", "1d6", 10, [{"id": "tg_ap"}]))
	t.armor = 3
	_shoot([15, 4], "1:0")
	expect_eq(t.hp, 6)


func test_accurate_inaccurate_and_lock_on_are_listed_with_sources() -> void:
	_setup(F.weapon("1:0", "Odd Gun", "Main", "Rifle", "1d6", 10, [{"id": "tg_accurate"}, {"id": "tg_inaccurate", "val": 2}]))
	t.statuses["Lock On"] = {"source": "x"}
	var p := RulesQueries.attack_preview(s, "a", "1:0", "t")
	var labels: Array = []
	for src: Dictionary in p["sources"]:
		labels.append(src["label"])
	expect(labels.has("Accurate") and labels.has("Inaccurate") and labels.has("Lock On"))
	expect_eq(p["accuracy"], 2)
	expect_eq(p["difficulty"], 2)
	var out := _shoot([10], "1:0")
	expect(F.events_of(out, "attack_rolled")[0]["lock_on_consumed"])
	expect(not t.has_status("Lock On"), "Lock On is consumed")


func test_engaged_attacker_gets_difficulty_on_ranged_only() -> void:
	_setup(F.weapon("1:0", "Sword", "Main", "Melee", "1d6", 1))
	F.mech(s, "adj", "enemies", Vector2i(1, 0))
	Combat.refresh_engagement(s)
	expect(a.has_status("Engaged"))
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["difficulty"], 1)
	expect_eq(RulesQueries.attack_preview(s, "a", "1:0", "adj")["difficulty"], 0)


func test_out_of_range_is_refused() -> void:
	_setup(F.weapon("1:0", "Short Gun", "Main", "CQB", "1d6", 2))
	var out := _shoot([15], "1:0")
	expect(not F.ok(out))
	expect(F.reason(out).contains("Out of Range"), F.reason(out))


func test_loading_weapon_needs_a_reload() -> void:
	_setup(F.weapon("1:0", "Big Gun", "Main", "Cannon", "1d6", 10, [{"id": "tg_loading"}]))
	_shoot([2], "1:0")
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	expect(not F.ok(_shoot([15], "1:0")), "not loaded")
	F.act(e, s, "stabilize", "a", {"main": "cool", "extra": "reload"})
	expect(Weapons.state_of(a, Weapons.find(a, "1:0"))["loaded"])


func test_superheavy_only_in_barrage() -> void:
	_setup(F.weapon("2:0", "Huge Gun", "Superheavy", "Cannon", "1d6", 10))
	expect(not F.ok(_shoot([15], "2:0")))
	F.load_dice(s, [15, 3])
	var out := F.act(e, s, "barrage", "a", {"attacks": [{"weapon": "2:0", "target": "t"}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 7)


func test_barrage_two_weapons() -> void:
	_setup(F.weapon("1:0", "Second Gun", "Main", "Rifle", "1d6", 10))
	F.load_dice(s, [15, 3, 15, 2])
	var out := F.act(e, s, "barrage", "a", {"attacks": [{"weapon": "0:0", "target": "t"}, {"weapon": "1:0", "target": "t"}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 2)
	expect_eq(t.hp, 5)
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "full action used the turn")
	var same := F.act(e, s, "barrage", "a", {"attacks": [{"weapon": "0:0", "target": "t"}, {"weapon": "0:0", "target": "t"}]})
	expect(not F.ok(same))


func test_skirmish_with_auxiliary_on_same_mount() -> void:
	_setup(F.weapon("0:1", "Pistol", "Auxiliary", "CQB", "1d3", 5))
	F.load_dice(s, [15, 3, 15, 1])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "aux": {"weapon": "0:1", "target": "t"}})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 6)


func test_exposed_resistance_and_shredded() -> void:
	_setup()
	t.statuses["Exposed"] = {"source": "x"}
	_shoot([15, 3])
	expect_eq(t.hp, 4, "Exposed doubles kinetic damage")
	t.statuses.erase("Exposed")
	t.hp = 10
	t.resistances = ["Kinetic"]
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	_shoot([15, 5])
	expect_eq(t.hp, 7, "Resistance halves 5 (PROVISIONAL: rounding up, 3 taken)")
	t.hp = 10
	t.armor = 2
	t.statuses["Shredded"] = {"source": "x"}
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	_shoot([15, 5])
	expect_eq(t.hp, 5, "Shredded: no Armor, no Resistance")


func test_knockback_pushes_directly_away() -> void:
	_setup(F.weapon("1:0", "Hammer Gun", "Main", "Rifle", "1d6", 10, [{"id": "tg_knockback", "val": 2}]))
	var out := _shoot([15, 1], "1:0", {"knockback": true})
	expect_eq(t.cell, Vector2i(5, 0))
	expect_eq(F.events_of(out, "moved")[0]["mode"], "involuntary")


func test_invisible_half_miss_before_the_roll() -> void:
	_setup()
	t.statuses["Invisible"] = {"source": "x"}
	var out := _shoot([1])
	expect(F.events_of(out, "attack_rolled")[0]["invisible_miss"])
	expect_eq(t.hp, 10)


func test_hidden_targets_cannot_be_attacked() -> void:
	_setup()
	t.statuses["Hidden"] = {"source": "t"}
	expect(not F.ok(_shoot([15])))


func test_prone_target_and_stunned_evasion() -> void:
	_setup()
	t.statuses["Prone"] = {"source": "x"}
	t.statuses["Stunned"] = {"source": "x"}
	t.evasion = 12
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect_eq(p["accuracy"], 1)
	expect_eq(p["target_number"], 5)


func test_smart_weapons_use_e_defense() -> void:
	_setup(F.weapon("1:0", "Smart Gun", "Main", "Rifle", "1d6", 10, [{"id": "tg_smart"}]))
	t.edef = 12
	var p := RulesQueries.attack_preview(s, "a", "1:0", "t")
	expect_eq(p["defense_name"], "E-Defense")
	expect_eq(p["target_number"], 12)


func test_ordnance_only_before_moving() -> void:
	_setup(F.weapon("2:0", "Siege Gun", "Heavy", "Cannon", "1d6", 10, [{"id": "tg_ordnance"}]))
	F.act(e, s, "move", "a", {"to": [0, 1]})
	var out := _shoot([15], "2:0")
	expect(not F.ok(out))
	expect_eq((out["result"] as RuleResult).rule_ref, "tags: Ordnance")


func test_jammed_only_improvised() -> void:
	_setup()
	t.cell = Vector2i(1, 0)
	a.statuses["Jammed"] = {"source": "x"}
	expect(not F.ok(_shoot([15])))
	F.load_dice(s, [15, 4])
	var out := F.act(e, s, "improvised_attack", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 6)


func test_hp_to_zero_marks_structure_and_checks() -> void:
	_setup()
	t.hp = 3
	var out := _shoot([15, 6, 5])
	expect_eq(t.structure, 3)
	expect_eq(t.hp, 7, "HP resets to full, then takes the 3 excess (Core p.80)")
	var check: Dictionary = F.events_of(out, "structure_check")[0]
	expect_eq(check["outcome"], "Glancing Blow")
	expect(t.has_status("Impaired"))


func test_npc_attack_uses_its_own_bonus() -> void:
	s = F.state()
	e = RulesEngine.new()
	var npc := UnitFactory.build_npc("n", UnitFactory.npc_templates()["training_drone"])
	npc.cell = Vector2i(0, 0)
	s.add_unit(npc)
	t = F.mech(s, "t", "players", Vector2i(3, 0))
	F.begin(e, s, npc)
	var p := RulesQueries.attack_preview(s, "n", "w0", "t")
	expect_eq(p["bonus"], 1)
	expect_eq(p["bonus_sources"][0]["label"], "Attack bonus")
	F.load_dice(s, [7, 2])
	var out := F.act(e, s, "skirmish", "n", {"weapon": "w0", "target": "t"})
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "hit", "7 + 1 = 8 meets Evasion 8")
	expect_eq(t.hp, 8)
