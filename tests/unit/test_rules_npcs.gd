extends TestCase
## NPCs from NPC class data (lancer-data / COMP/CON format): the placeholder pack, a content
## pack, templates, multiple activations and Recharge.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _db(with_pack: bool) -> ContentDB:
	var db := ContentDB.new()
	db.load_all()
	if with_pack:
		var p := ContentPack.new()
		p.name = "NPC test pack"
		p.author = "tests"
		p.version = "1.0.0"
		p.collections = {
			"npc_classes": [{"id": "npcc_test_ace", "name": "Test Ace", "role": "striker",
				"stats": {"activations": [1, 1, 1], "hp": [10, 12, 14], "armor": [0, 0, 1], "evade": [10, 11, 12], "edef": [8, 9, 10],
					"heatcap": [8, 8, 8], "speed": [6, 6, 7], "sensor": [10, 10, 10], "save": [10, 11, 12], "hull": [0, 0, 1],
					"agility": [2, 2, 3], "systems": [0, 1, 1], "engineering": [0, 0, 1], "size": [[1], [1], [1]]},
				"base_features": ["npcf_test_ace_gun", "npcf_test_ace_hack", "npcf_test_ace_boost", "npcf_test_ace_trait"], "optional_features": []}],
			"npc_features": [
				{"id": "npcf_test_ace_gun", "name": "Ace Rifle", "type": "Weapon", "weapon_type": "Main Rifle",
					"damage": [{"type": "kinetic", "damage": [4, 5, 6]}], "range": [{"type": "Range", "val": 10}],
					"attack_bonus": [1, 2, 3], "accuracy": [0, 0, 1], "tags": [{"id": "tg_recharge", "val": 5}], "on_hit": "The target is Slowed."},
				{"id": "npcf_test_ace_hack", "name": "Ace Hack", "type": "Tech", "tech_type": "Quick", "attack_bonus": [2, 3, 4], "effect": "The target takes 2 heat."},
				{"id": "npcf_test_ace_boost", "name": "Ace Burner", "type": "System", "tags": [{"id": "tg_quick_action"}, {"id": "tg_recharge", "val": 4}], "effect": "Move 3."},
				{"id": "npcf_test_ace_trait", "name": "Ace Instinct", "type": "Trait", "effect": "Gains +1 Accuracy on reactions."},
				{"id": "npcf_test_elite", "name": "Elite", "type": "Trait", "effect": "", "bonus": {"structure": 1, "stress": 1, "activations": 1}},
			],
			"npc_templates": [{"id": "npct_test_elite", "name": "Elite", "base_features": ["npcf_test_elite"], "optional_features": []}],
		}
		expect(db.add_pack(p))
	return db


func test_placeholder_pack_until_a_real_one_is_loaded() -> void:
	var db := _db(false)
	expect(NPCBuilder.source(db)["placeholder"])
	var n := UnitFactory.build_npc_class(db, "e1", "npcc_ph_grunt", 2)
	expect_eq(n.max_hp, 8)
	var w: Dictionary = n.loadout["weapons"][0]
	expect_eq(w["damage"][0]["val"], "1d6+1", "tier 2 damage")
	expect_eq(w["attack_bonus"], 2)
	expect(Effects.has(n, "accuracy"), "encoded placeholder trait")
	var elite := UnitFactory.build_npc_class(db, "e2", "npcc_ph_grunt", 1, {"templates": ["npct_ph_elite"]})
	expect_eq(elite.max_structure, 2)
	expect_eq(int(elite.counters["activations"]), 2)


func test_pack_class_features_and_template() -> void:
	var db := _db(true)
	expect(not NPCBuilder.source(db)["placeholder"])
	var n := UnitFactory.build_npc_class(db, "ace", "npcc_test_ace", 3, {"templates": ["npct_test_elite"]})
	expect_eq([n.max_hp, n.evasion, n.armor, n.speed, n.save_target], [14, 12, 1, 7, 12])
	expect_eq([n.max_structure, n.max_stress, int(n.counters["activations"])], [2, 2, 2], "Elite bonuses")
	var w: Dictionary = n.loadout["weapons"][0]
	expect_eq([w["size"], w["type"], w["damage"][0]["type"], w["damage"][0]["val"], w["attack_bonus"]], ["Main", "Rifle", "Kinetic", 6, 3])
	var names := (n.loadout["abilities"] as Array).map(func(a: Dictionary) -> String: return "%s:%s" % [a["name"], a["activation"]])
	expect(names.has("Ace Hack:Quick Tech") and names.has("Ace Burner:Quick"))
	expect(not (n.loadout["traits"] as Array)[0]["automated"], "an unencoded trait is shown to the table")


func test_multiple_activations_and_recharge() -> void:
	var db := _db(true)
	var s := F.state()
	var e := RulesEngine.new()
	var n := UnitFactory.build_npc_class(db, "ace", "npcc_test_ace", 1, {"templates": ["npct_test_elite"]})
	n.cell = Vector2i(6, 0)
	s.add_unit(n)
	var p := F.mech(s, "p", "players", Vector2i(0, 0))
	p.controller = "seat1"
	e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	F.act(e, s, "start_turn", "p")
	F.act(e, s, "end_turn", "p")
	F.act(e, s, "start_turn", "ace")
	var key := ""
	for a: Dictionary in Abilities.all(n):
		if a["name"] == "Ace Burner":
			key = a["key"]
	expect(F.ok(F.act(e, s, "activate", "ace", {"ability": key})))
	F.act(e, s, "end_turn", "ace")
	expect(not s.acted.has("ace"), "an Elite still has a second activation this round")
	var round := s.round_number
	F.load_dice(s, [1])  # the Recharge roll at the start of its turn fails
	var out := F.act(e, s, "start_turn", "ace")
	expect(F.ok(out), F.reason(out))
	expect(not RulesQueries.available_actions(s, "ace").filter(func(x: Dictionary) -> bool: return x.get("name", "") == "Ace Burner")[0]["available"], "still recharging (Recharge 4+, rolled 1)")
	F.act(e, s, "end_turn", "ace")
	expect_eq(s.round_number, round + 1, "both activations used: the round ends")


func test_npc_tech_uses_its_own_bonus() -> void:
	var db := _db(true)
	var s := F.state()
	var e := RulesEngine.new()
	var n := UnitFactory.build_npc_class(db, "ace", "npcc_test_ace", 2)
	n.cell = Vector2i(4, 0)
	s.add_unit(n)
	var p := F.mech(s, "p", "players", Vector2i(0, 0))
	F.begin(e, s, n)
	var key := ""
	for a: Dictionary in Abilities.all(n):
		if a["name"] == "Ace Hack":
			key = a["key"]
	F.load_dice(s, [10])
	var out := F.act(e, s, "activate", "ace", {"ability": key, "target": "p"})
	expect(F.ok(out), F.reason(out))
	var check: Dictionary = F.events_of(out, "tech_attack")[0]["check"]
	expect_eq(check["bonus"], 3, "the feature's tier 2 attack bonus")
	expect_eq(F.events_of(out, "manual_effect").size(), 1, "its effect text goes to the table on a hit")
