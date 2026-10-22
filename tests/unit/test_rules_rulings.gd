extends TestCase
## Table rulings: every open question has the canon readings as options; nothing is picked
## silently; each reading changes the outcome as described.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(t_cell := Vector2i(11, 11)) -> void:
	s = F.state()
	s.rulings.clear()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", t_cell)
	F.begin(e, s, a)


func _rule(id: String, choice: String) -> void:
	expect(F.ok(e.submit(s, {"type": "set_ruling", "params": {"id": id, "choice": choice}})))


func test_catalog_offers_canon_readings() -> void:
	for r: Dictionary in Rulings.catalog():
		expect((r["options"] as Dictionary).size() >= 2, r["id"])
		expect(String(r["rule_ref"]).begins_with("Core"), r["id"] + " cites the book")
		expect((r["options"] as Dictionary).has(r["suggested"]), r["id"])
	_setup()
	expect(not F.ok(e.submit(s, {"type": "set_ruling", "params": {"id": "climb_cost", "choice": "free"}})), "only canon options")


func test_climb_cost_readings() -> void:
	_setup()
	s.map.set_column(Vector2i(1, 0), 1)
	var out := F.act(e, s, "move", "a", {"to": [1, 0]})
	expect_eq((out["result"] as RuleResult).grey_area, "climb_cost", "asked, not guessed")
	expect(out["events"].is_empty())
	_rule("climb_cost", "climb_only")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(1, 0))["cost"], 2, "2 per level, step included")
	_rule("climb_cost", "step_plus_climb")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(1, 0))["cost"], 3, "1 + 2 per level")


func test_flight_over_difficult_terrain() -> void:
	_setup()
	a.flight = "hover"
	for y in range(12):
		s.map.set_column(Vector2i(1, y), 0, PackedStringArray([BattleMap.TAG_DIFFICULT]))
	_rule("flight_difficult", "pay")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(2, 0), 1, "move", true)["cost"], 3)
	_rule("flight_difficult", "ignore")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(2, 0), 1, "move", true)["cost"], 2)


func test_range_up_and_down() -> void:
	_setup(Vector2i(1, 0))
	t.level = 4  # floating 4 up, 1 across
	t.flying = true
	a.loadout["weapons"].append(F.weapon("1:0", "Short Gun", "Main", "CQB", "1d6", 2))
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	expect_eq((out["result"] as RuleResult).grey_area, "distance_3d")
	_rule("distance_3d", "ground_only")
	expect(RulesQueries.attack_preview(s, "a", "1:0", "t")["ok"], "1 space along the ground")
	_rule("distance_3d", "spaces_3d")
	expect(not RulesQueries.attack_preview(s, "a", "1:0", "t")["ok"], "4 spaces up")


func test_heat_overflow_pauses_and_replays() -> void:
	_setup()
	a.heat = 6
	var out := F.act(e, s, "overcharge", "a")
	expect_eq(out["events"][0]["type"], "ruling_needed", "asked mid-action")
	expect_eq(a.heat, 6, "nothing applied yet")
	out = e.submit(s, {"type": "set_ruling", "params": {"id": "heat_overflow", "choice": "beyond_cap"}})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "ruling_made").size(), 1)
	expect_eq(a.stress, 3)
	expect_eq(a.heat, 1, "everything past the cap carries over")


func test_explosion_and_unforced_save_targets() -> void:
	_setup(Vector2i(2, 0))
	a.save_target = 14
	_rule("explosion_save_target", "ten")
	F.load_dice(s, [3, 3, 3, 3, 10])
	var ev := Pilots.explode(s, a, "test")
	var checks := ev.filter(func(x: Dictionary) -> bool: return x["type"] == "skill_check")
	expect_eq(checks[0]["check"]["target"], 10)
	_rule("unforced_save_target", "attacker")
	t.flying = true
	t.level = 3
	t.hp = 1
	F.load_dice(s, [6, 10])
	var out := Combat.deal_damage(s, t, [{"type": "Kinetic", "amount": 3}], {"source": "a"})
	var saves := out.filter(func(x: Dictionary) -> bool: return x["type"] == "skill_check")
	expect_eq(saves[0]["check"]["target"], 14, "the attacker's Save Target")


func test_npc_brace_ruling() -> void:
	_setup()
	var n := UnitFactory.build_npc("n", UnitFactory.npc_templates()["training_drone"])
	s.add_unit(n)
	_rule("npc_brace", "no")
	expect(not Reactions.can_react(n, "brace", s).ok)
	_rule("npc_brace", "yes")
	expect(Reactions.can_react(n, "brace", s).ok)


func test_overwatch_with_area_weapons() -> void:
	_setup(Vector2i(1, 0))
	var w := F.weapon("1:0", "Flamer", "Main", "CQB", "1d6", 0)
	w["range"] = [{"type": "Cone", "val": 3}]
	t.loadout["weapons"] = [w]
	t.counters["reaction_policy"] = {"overwatch": "auto"}
	a.counters["reaction_policy"] = {"brace": "never"}
	Combat.refresh_engagement(s)
	_rule("overwatch_area_weapons", "no")
	var out := F.act(e, s, "move", "a", {"to": [0, 3]})
	expect_eq(F.events_of(out, "reaction").size(), 0, "no area Overwatch")
	_setup(Vector2i(1, 0))
	t.loadout["weapons"] = [w]
	t.counters["reaction_policy"] = {"overwatch": "auto"}
	a.counters["reaction_policy"] = {"brace": "never"}
	Combat.refresh_engagement(s)
	_rule("overwatch_area_weapons", "yes")
	out = F.act(e, s, "move", "a", {"to": [0, 3]})
	expect_eq(F.events_of(out, "area_attack").size(), 1, "aimed at the mover")


func test_slowed_jump_ruling() -> void:
	_setup()
	a.statuses["Slowed"] = {"source": "x"}
	expect_eq((F.act(e, s, "jump", "a", {"to": [0, 2]})["result"] as RuleResult).grey_area, "slowed_jump")
	_rule("slowed_jump", "no")
	expect(not F.ok(F.act(e, s, "jump", "a", {"to": [0, 2]})))
	_rule("slowed_jump", "yes")
	expect(F.ok(F.act(e, s, "jump", "a", {"to": [0, 2]})))


func test_teleport_move_cost_readings() -> void:
	_setup()
	a.loadout["effects"] = [{"kind": "teleport_moves", "label": "Slipstream"}]
	_rule("teleport_move_cost", "one_space")
	expect(F.ok(F.act(e, s, "move", "a", {"to": [3, 0]})))
	expect_eq(a.turn["move_spent"], 1, "counts as moving 1 space")
	expect(F.ok(F.act(e, s, "move", "a", {"to": [6, 0]})), "and teleports again with movement left")


func test_prone_and_ignore_difficult() -> void:
	_setup()
	a.loadout["effects"] = [{"kind": "ignore_difficult", "label": "Bulwark Mods"}]
	a.statuses["Prone"] = {"source": "x"}
	_rule("prone_ignore_difficult", "still_double")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(2, 0))["cost"], 4)
	_rule("prone_ignore_difficult", "cancels")
	expect_eq(RulesQueries.preview_move(s, "a", Vector2i(2, 0))["cost"], 2)


func test_rulings_query_and_view() -> void:
	_setup()
	_rule("climb_cost", "climb_only")
	var list := RulesQueries.rulings(s)
	var climb: Dictionary = list.filter(func(r: Dictionary) -> bool: return r["id"] == "climb_cost")[0]
	expect_eq(climb["choice"], "climb_only")
	a.heat = 6
	F.act(e, s, "overcharge", "a")
	var view := ViewFilter.new().view_for(s, "x")
	expect_eq(view["pending"]["ruling"], "heat_overflow", "clients see the open question")
	expect(not F.ok(F.act(e, s, "end_turn", "a")), "everything waits for the ruling")
