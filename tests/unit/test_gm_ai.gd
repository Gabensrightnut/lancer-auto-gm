extends TestCase
## The tactics AI: plays by what its side knows, follows roles, stances and dials, explains.


func _state() -> GameState:
	var s := RulesFixtures.state(GridLayout.Shape.SQUARE, 16, 16)
	s.seats = {"p1": {"name": "P1", "side": "players"}, "gm": {"name": "GM", "side": "enemies", "gm": true}}
	return s


func _start(s: GameState, u: Unit) -> RulesEngine:
	var engine := RulesEngine.new()
	RulesFixtures.begin(engine, s, u)
	return engine


func _plan(s: GameState, unit_id: String, orders: Dictionary = {}, preset: String = "Standard") -> Dictionary:
	var ai := TacticsAi.new(GmSettings.from_preset(preset))
	ai.settings.randomness = 0.0
	var u := s.unit(unit_id)
	return ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), u.side), unit_id, orders)


static func _types(plan: Dictionary) -> Array:
	return plan["steps"].map(func(a: Dictionary) -> String: return a["type"])


static func _targets(plan: Dictionary) -> Array:
	var out: Array = []
	for a: Dictionary in plan["steps"]:
		var p: Dictionary = a.get("params", {})
		if p.has("target"):
			out.append(p["target"])
		for x: Dictionary in p.get("attacks", []):
			out.append(x["target"])
	return out


func test_attacks_a_target_in_range() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	e.controller = "gm"
	RulesFixtures.mech(s, "p1", "players", Vector2i(3, 9))
	_start(s, e)
	var plan := _plan(s, "e1")
	expect("skirmish" in _types(plan) or "barrage" in _types(plan), "attacks: %s" % str(_types(plan)))
	expect_eq(_targets(plan).back(), "p1")
	expect(plan["log"].begins_with("e1 "), "log names the unit: " + plan["log"])
	expect("%" in plan["log"], "log gives the hit chance")


func test_never_targets_or_knows_about_hidden_enemies() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	e.controller = "gm"
	var sneaky := RulesFixtures.mech(s, "p1", "players", Vector2i(3, 6))
	sneaky.statuses = {"Hidden": {}}
	RulesFixtures.mech(s, "p2", "players", Vector2i(12, 12))
	_start(s, e)
	var know := AiKnowledge.for_side(s, ViewFilter.new(), "enemies")
	expect(know.state.unit("p1") == null, "a Hidden enemy isn't in this side's picture at all")
	expect(not "p1" in _targets(_plan(s, "e1")))


func test_unscanned_stats_are_unknown_to_the_ai() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	var p := RulesFixtures.mech(s, "p1", "players", Vector2i(3, 9))
	p.hp = 3
	p.evasion = 15
	var know := AiKnowledge.for_side(s, ViewFilter.new(), "enemies")
	expect(not know.knows_stats("p1"))
	expect(know.state.unit("p1").hp != 3, "HP of an unscanned enemy isn't copied")
	expect(know.state.unit("p1").evasion != 15)
	expect(know.state.unit("p1").loadout.is_empty(), "its weapons are unknown too")
	ViewFilter.reveal_in_state(s, "enemies", "p1")
	know = AiKnowledge.for_side(s, ViewFilter.new(), "enemies")
	expect_eq(know.state.unit("p1").hp, 3, "after a Scan the side knows")
	expect(know.state.unit(e.id).hp == e.hp)


func test_planning_never_changes_the_real_state() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	RulesFixtures.mech(s, "p1", "players", Vector2i(4, 9))
	_start(s, e)
	var before := JSON.stringify(s.to_dict())
	_plan(s, "e1")
	expect_eq(JSON.stringify(s.to_dict()), before)


func test_hold_stance_stays_put() -> void:
	var s := _state()
	var p := RulesFixtures.mech(s, "p1", "players", Vector2i(3, 12))
	p.controller = "p1"
	RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 2))
	_start(s, p)
	var plan := _plan(s, "p1", {"stance": "hold"})
	expect(not "move" in _types(plan) and not "boost" in _types(plan), str(_types(plan)))
	expect("hold" in plan["log"], plan["log"])


func test_focus_target_order_is_followed() -> void:
	var s := _state()
	var p := RulesFixtures.mech(s, "p1", "players", Vector2i(6, 8))
	RulesFixtures.mech(s, "e1", "enemies", Vector2i(4, 4))
	RulesFixtures.mech(s, "e2", "enemies", Vector2i(8, 4))
	_start(s, p)
	expect_eq(_targets(_plan(s, "p1", {"focus": "e2", "stance": "hold"})).back(), "e2")
	expect_eq(_targets(_plan(s, "p1", {"focus": "e1", "stance": "hold"})).back(), "e1")


func test_ruthless_finishes_the_wounded() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(6, 3))
	var a := RulesFixtures.mech(s, "p1", "players", Vector2i(4, 8))
	var b := RulesFixtures.mech(s, "p2", "players", Vector2i(8, 8))
	b.hp = 2
	for id in ["p1", "p2"]:
		ViewFilter.reveal_in_state(s, "enemies", id)
	_start(s, e)
	expect_eq(_targets(_plan(s, "e1", {"stance": "hold"}, "Ruthless")).back(), "p2", "focus fire picks the hurt mech")
	expect(a.hp == 10)


func test_artillery_keeps_its_distance_and_striker_closes_in() -> void:
	var s := _state()
	var arty := RulesFixtures.mech(s, "e1", "enemies", Vector2i(7, 7))
	arty.loadout["weapons"] = [RulesFixtures.weapon("0:0", "Long Gun", "Main", "Rifle", "1d6", 15)]
	arty.loadout["ai_role"] = "artillery"
	RulesFixtures.mech(s, "p1", "players", Vector2i(7, 9))
	_start(s, arty)
	var plan := _plan(s, "e1")
	var moves: Array = plan["steps"].filter(func(a: Dictionary) -> bool: return a["type"] == "move")
	expect(not moves.is_empty(), "artillery backs away from an enemy 2 spaces off")
	if not moves.is_empty():
		var to := Vector2i(moves[0]["params"]["to"][0], moves[0]["params"]["to"][1])
		expect(s.map.grid.distance(to, Vector2i(7, 9)) > 2, "ends further away")
	var s2 := _state()
	var brute := RulesFixtures.mech(s2, "e1", "enemies", Vector2i(7, 2))
	brute.loadout["weapons"] = [RulesFixtures.weapon("0:0", "Club", "Main", "Melee", "1d6+2", 1)]
	RulesFixtures.mech(s2, "p1", "players", Vector2i(7, 7))
	_start(s2, brute)
	var plan2 := _plan(s2, "e1", {}, "Ruthless")
	var to2: Array = plan2["steps"][0]["params"].get("to", [7, 2]) if not plan2["steps"].is_empty() else [7, 2]
	expect(s2.map.grid.distance(Vector2i(to2[0], to2[1]), Vector2i(7, 7)) <= 2, "melee striker closes in: %s" % plan2["log"])


func test_vents_heat_when_hot() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	e.heat = 5
	RulesFixtures.mech(s, "p1", "players", Vector2i(14, 14))
	_start(s, e)
	var plan := _plan(s, "e1", {}, "Cautious")
	expect("stabilize" in _types(plan), plan["log"])


func test_seeded_noise_is_repeatable() -> void:
	var s := _state()
	var e := RulesFixtures.mech(s, "e1", "enemies", Vector2i(3, 3))
	RulesFixtures.mech(s, "p1", "players", Vector2i(8, 10))
	_start(s, e)
	var ai := TacticsAi.new(GmSettings.from_preset("Chaotic"))
	var a := ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "enemies"), "e1")
	var b := ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "enemies"), "e1")
	expect_eq(JSON.stringify(a["steps"]), JSON.stringify(b["steps"]), "same state, same choice")


func test_presets_load() -> void:
	for name in ["Standard", "Ruthless", "Cautious", "Chaotic", "Teaching"]:
		expect(name in GmSettings.preset_names(), name)
	var r := GmSettings.from_preset("Ruthless")
	var c := GmSettings.from_preset("Cautious")
	expect(r.aggression > c.aggression and r.caution < c.caution and r.focus_fire > c.focus_fire)
	expect(GmSettings.from_preset("Chaotic").randomness > r.randomness)
	var t := GmSettings.from_preset("Teaching")
	expect(t.explain and t.difficulty < 1.0 and t.reinforcements == 0.0)
	expect_eq(GmSettings.from_dict(r.to_dict()).to_dict(), r.to_dict())
