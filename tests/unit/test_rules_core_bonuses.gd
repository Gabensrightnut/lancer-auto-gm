extends TestCase
## Core bonuses (GMS Core p.118, IPS-N p.127, SSC p.158, HORUS p.191, HA p.225).

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


func _build(cbs: Array, choices: Dictionary = {}, loadout: Dictionary = {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []}) -> Unit:
	return UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", loadout, {"ll": 9, "core_bonuses": cbs, "core_bonus_choices": choices})


func _setup(cbs: Array, choices: Dictionary = {}, loadout: Dictionary = {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []}, t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = _build(cbs, choices, loadout)
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _next_turn(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_stat_bonuses() -> void:
	var plain := _build([])
	var b := _build(["cb_reinforced_frame", "cb_sloped_plating", "cb_full_subjectivity_sync", "cb_the_lesson_of_disbelief", "cb_superior_by_design"])
	expect_eq(b.max_hp, plain.max_hp + 5)
	expect_eq(b.armor, plain.armor + 1)
	expect_eq(b.evasion, plain.evasion + 2)
	expect_eq(b.edef, plain.edef + 2)
	expect_eq(b.heat_cap, plain.heat_cap + 2)
	expect(Effects.immune_to_status(b, "Impaired"))
	var open := _build(["cb_the_lesson_of_the_open_door"])
	expect_eq(open.save_target, plain.save_target + 2)
	var ranged := _build(["cb_neurolink_targeting"])
	expect_eq(Weapons.range_for(ranged, Weapons.find(ranged, "0:0")), 13, "+3 Range")


func test_mount_bonuses() -> void:
	var b := _build(["cb_improved_armament"])
	expect_eq((b.loadout["mounts"] as Array).size(), 3, "Everest already has 3 mounts: no extra")
	expect_eq(UnitFactory.mounts_for({"mounts": ["Main", "Heavy"]}, {"core_bonuses": ["cb_improved_armament"]}), ["Main", "Heavy", "Flex"], "fewer than 3: a Flex mount")
	var frame := db().frame("mf_standard_pattern_i_everest")
	expect_eq(UnitFactory.mounts_for(frame, {"core_bonuses": ["cb_mount_retrofitting"], "core_bonus_choices": {"cb_mount_retrofitting": 0}})[0], "Main/Aux")
	var iw := _build(["cb_integrated_weapon"], {}, {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": [], "integrated_weapon": "mw_pistol"})
	expect(not Weapons.find(iw, "cbi:0").is_empty(), "an integrated Auxiliary mount")
	expect(UnitFactory.check_loadout(db(), "mf_standard_pattern_i_everest", {"mounts": [], "integrated_weapon": "mw_pistol"}, {"ll": 9, "core_bonuses": ["cb_integrated_weapon"]}).ok)


func test_auto_stabilizing_and_overpower_and_integrated_weapon() -> void:
	_setup(["cb_auto_stabilizing_hardpoints", "cb_overpower_caliber", "cb_integrated_weapon"], {"cb_auto_stabilizing_hardpoints": 0, "cb_overpower_caliber": "0:0"},
		{"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": [], "integrated_weapon": "mw_pistol"})
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["accuracy"], 1, "+1 Accuracy on the chosen mount")
	var key := ""
	for x: Dictionary in Abilities.all(a):
		if x["name"] == "Integrated Weapon":
			key = x["key"]
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key, "target": "t"})), "only after firing another weapon")
	F.load_dice(s, [15, 1, 2, 4])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "bonus_damage").size(), 1, "Overpower Caliber +1d6")
	F.load_dice(s, [15, 2])
	out = F.act(e, s, "activate", "a", {"ability": key, "target": "t"})
	expect(F.ok(out), F.reason(out))


func test_briareos() -> void:
	_setup(["cb_briareos_frame"])
	a.structure = 1
	var hp := a.hp
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 6}], {"ap": true})
	expect_eq(a.hp, hp - 3, "Resistance at 1 Structure")
	a.hp = 1
	F.load_dice(s, [6, 6, 6, 6, 6])
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 10}], {"ap": true})
	expect(not a.destroyed, "0 HP and 0 Structure: not destroyed")
	expect(a.counters.get("briareos_down", false))
	expect(not F.ok(F.act(e, s, "stabilize", "a", {"main": "repair", "extra": "reload"})), "no HP back until a rest")


func test_titanomachy_heatfall_ammo_feeds() -> void:
	_setup(["cb_titanomachy_mesh", "cb_heatfall_coolant_system", "cb_integrated_ammo_feeds"], {}, {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": ["ms_pattern_b_hex_charges"]}, Vector2i(1, 0))
	var limited := -1
	for x: Dictionary in RulesQueries.available_actions(s, "a"):
		if x.get("name", "") == "Frag Grenade":
			limited = int(x["uses_left"])
	expect_eq(limited, 5, "Limited 3 + 2")
	F.load_dice(s, [15])
	F.act(e, s, "ram", "a", {"target": "t"})
	t.statuses.erase("Prone")
	F.load_dice(s, [15])
	var out := F.act(e, s, "grapple", "a", {"target": "t", "free_via": "titanomachy"})
	expect(F.ok(out), "a free Grapple after a successful Ram: " + F.reason(out))
	a.overcharge_count = 3
	F.load_dice(s, [6])
	F.act(e, s, "overcharge", "a")
	expect(a.heat <= 6, "Heatfall: never more than 1d6")


func test_horus_lessons() -> void:
	_setup(["cb_the_lesson_of_thinking_tomorrows_thought", "cb_the_lesson_of_transubstantiation"], {}, {"mounts": [{"weapons": ["mw_tactical_knife"]}], "systems": []}, Vector2i(1, 0))
	F.load_dice(s, [19])
	F.act(e, s, "lock_on", "a", {"target": "t"})
	F.load_dice(s, [19, 1])
	F.act(e, s, "invade", "a", {"target": "t"})
	expect_eq(String(a.counters.get("tomorrow", "")), "t")
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["accuracy"], 1, "+1 from the Lesson (the Invade used up the Lock On)")
	a.hp = 1
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 3}], {"ap": true})
	expect(a.counters.has("folded"), "structure damage: it slips into non-space")


func test_held_image_and_stasis_shielding() -> void:
	_setup(["cb_the_lesson_of_the_held_image", "cb_stasis_shielding"])
	a.controller = "gm"
	var ally := F.mech(s, "ally", "players", Vector2i(0, 2))
	_next_turn(ally)
	expect(t.has_status("Lock On"), "Lock On at the start of an ally's turn")
	a.heat = a.heat_cap
	F.load_dice(s, [6])
	Combat.apply_heat(s, a, 2, "test")
	expect(Effects.resists(a, "Kinetic", false, -1), "Stasis Shielding after stress damage")
