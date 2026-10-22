extends TestCase
## Movement: costs, terrain, Size, engagement, Boost, flight and falling.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _one(s: GameState, e: RulesEngine, cell := Vector2i(0, 0), size := 1.0) -> Unit:
	var u := F.mech(s, "p1", "players", cell, size)
	F.mech(s, "far", "enemies", Vector2i(11, 11))
	F.begin(e, s, u)
	return u


func test_standard_move_costs_and_can_be_split() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := _one(s, e)
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(3, 3))
	expect(plan["ok"], plan["reason"])
	expect_eq(plan["cost"], 3, "square diagonals count as 1 (PROVISIONAL)")
	expect_eq(plan["remaining"], 1)
	expect(F.ok(F.act(e, s, "move", "p1", {"to": [3, 0]})))
	expect_eq(u.cell, Vector2i(3, 0))
	expect(F.ok(F.act(e, s, "move", "p1", {"to": [4, 0]})), "rest of the standard move")
	var out := F.act(e, s, "move", "p1", {"to": [5, 0]})
	expect(not F.ok(out), "standard move used up")


func test_preview_does_not_change_state_and_flags_boost() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	_one(s, e)
	var before := JSON.stringify(s.to_dict())
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(6, 0))
	expect(not plan["ok"])
	expect(plan["needs_boost"], "6 spaces with Speed 4 needs a Boost")
	RulesQueries.reachable(s, "p1")
	expect_eq(JSON.stringify(s.to_dict()), before, "queries never change the state")


func test_difficult_terrain_costs_double() -> void:
	var s := F.state()
	for y in range(12):
		s.map.set_column(Vector2i(1, y), 0, PackedStringArray([BattleMap.TAG_DIFFICULT]))
	var e := RulesEngine.new()
	_one(s, e)
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(2, 0))
	expect_eq(plan["cost"], 3)
	var types: Array = []
	for w: Dictionary in plan["warnings"]:
		types.append(w["type"])
	expect(types.has("difficult"))


func test_climbing_costs_two_per_level() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(1, 0), 1)
	var e := RulesEngine.new()
	_one(s, e)
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(1, 0))
	expect(plan["ok"], plan["reason"])
	expect_eq(plan["cost"], 3, "1 step + 2 for one level climbed (PROVISIONAL step cost)")
	expect_eq(plan["path"].back(), [1, 0, 1])
	F.act(e, s, "move", "p1", {"to": [1, 0]})
	expect_eq(s.unit("p1").level, 1)


func test_size_two_cannot_stand_on_a_one_space_pillar() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(5, 5), 1)
	var small := Movement.placement(s, 1.0, Vector2i(5, 5), 1)
	expect(small["ok"] and small["standing"], "a Size 1 fits on top")
	var big := Movement.placement(s, 2.0, Vector2i(5, 5), 1)
	expect(not big["standing"], "a Size 2 has no ground under most of it")
	expect(big["uneven"], "partly supported: the book doesn't say, so it's a table ruling")
	var e := RulesEngine.new()
	var u := _one(s, e, Vector2i(3, 5), 2.0)
	s.rulings[Movement.RULING_UNEVEN] = {"choice": "forbid"}
	for sp: Dictionary in RulesQueries.reachable(s, u.id)["spaces"]:
		expect(not (sp["cell"] == [5, 5] and sp["level"] == 1), "pillar top greyed out for Size 2")


func test_overhang_clearance_depends_on_size() -> void:
	var s := F.state()
	# A bridge: ground 3, open underneath for levels 0..0 (1 level of headroom).
	for y in range(12):
		var c := s.map.set_column(Vector2i(4, y), 3)
		c.gap_bottom = 0
		c.gap_top = 1
	expect(Movement.placement(s, 1.0, Vector2i(4, 0), 0)["ok"], "Size 1 fits under")
	expect(not Movement.placement(s, 2.0, Vector2i(3, 0), 0)["ok"], "Size 2 is too tall")
	expect(Movement.placement(s, 1.0, Vector2i(4, 0), 3)["ok"], "and can stand on top")


func test_allies_can_be_passed_but_not_stopped_on_and_hostiles_block() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 6, 1)
	var e := RulesEngine.new()
	var u := F.mech(s, "p1", "players", Vector2i(0, 0))
	var ally := F.mech(s, "p2", "players", Vector2i(1, 0))
	F.begin(e, s, u)
	expect(RulesQueries.preview_move(s, "p1", Vector2i(2, 0))["ok"], "through an ally")
	expect(not RulesQueries.preview_move(s, "p1", Vector2i(1, 0))["ok"], "not onto an ally")
	ally.side = "enemies"
	expect(not RulesQueries.preview_move(s, "p1", Vector2i(2, 0))["ok"], "hostiles block")


func test_engagement_stops_movement_for_equal_or_larger_size() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := F.mech(s, "p1", "players", Vector2i(0, 0))
	var n1 := F.mech(s, "n1", "enemies", Vector2i(3, 1))
	F.begin(e, s, u)
	expect(not RulesQueries.preview_move(s, "p1", Vector2i(4, 0))["ok"], "can't walk past: the move would stop")
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(2, 0))
	expect_eq(plan["stopped_by"], "n1")
	var out := F.act(e, s, "move", "p1", {"to": [2, 0]})
	expect(F.ok(out))
	expect_eq(F.events_of(out, "movement_stopped").size(), 1)
	expect(u.has_status("Engaged") and n1.has_status("Engaged"))
	expect(not F.ok(F.act(e, s, "move", "p1", {"to": [2, 1]})), "unused movement is lost")


func test_smaller_hostiles_engage_without_stopping() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := F.mech(s, "p1", "players", Vector2i(0, 0))
	F.mech(s, "n1", "enemies", Vector2i(3, 1), 0.5)
	F.begin(e, s, u)
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(4, 0))
	expect(plan["ok"], plan["reason"])
	F.act(e, s, "move", "p1", {"to": [4, 0]})
	expect(u.has_status("Engaged"))


func test_boost_slowed_and_immobilized() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := _one(s, e)
	F.act(e, s, "move", "p1", {"to": [4, 0]})
	expect(F.ok(F.act(e, s, "boost", "p1", {"to": [8, 0]})), "Boost: another Speed of movement")
	expect_eq(u.turn["quick"], 1, "Boost is a quick action")
	u.turn["taken"] = []
	u.statuses["Slowed"] = {"source": "t"}
	expect(not F.ok(F.act(e, s, "boost", "p1", {"to": [9, 0]})), "Slowed can't Boost")
	u.statuses.erase("Slowed")
	u.turn["move_spent"] = 0
	u.statuses["Immobilized"] = {"source": "t"}
	expect(not F.ok(F.act(e, s, "move", "p1", {"to": [9, 0]})), "Immobilized can't move")


func test_prone_stand_up_and_difficult_movement() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := _one(s, e)
	u.statuses["Prone"] = {"source": "t"}
	expect_eq(RulesQueries.preview_move(s, "p1", Vector2i(2, 0))["cost"], 4, "Prone moves as if in difficult terrain")
	expect(F.ok(F.act(e, s, "stand_up", "p1")))
	expect(not u.has_status("Prone"))
	expect(not F.ok(F.act(e, s, "move", "p1", {"to": [1, 0]})), "standing up replaced the standard move")


func test_flying_must_move_or_fall_and_fall_damage() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := _one(s, e)
	u.flight = "flight"
	u.armor = 2
	var out := F.act(e, s, "move", "p1", {"to": [3, 0], "level": 3, "fly": true})
	expect(F.ok(out), F.reason(out))
	expect(u.flying)
	expect_eq(u.level, 3)
	F.act(e, s, "end_turn", "p1")
	expect_eq(u.level, 3, "moved this turn: still flying")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "p1")
	out = F.act(e, s, "end_turn", "p1")
	expect_eq(u.level, 0, "didn't move while flying: falls")
	expect_eq(u.hp, 7, "3 spaces fallen: 3 AP kinetic, Armor ignored")
	expect(not u.flying)


func test_walkers_cannot_fly() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	_one(s, e)
	expect(not F.ok(F.act(e, s, "move", "p1", {"to": [1, 0], "level": 2, "fly": true})))


func test_uneven_ground_for_big_mechs_is_a_ruling() -> void:
	var s := F.state()
	s.rulings.clear()
	s.map.set_column(Vector2i(3, 0), 1)
	var e := RulesEngine.new()
	var u := _one(s, e, Vector2i(0, 0), 2.0)
	var out := F.act(e, s, "move", "p1", {"to": [2, 0], "level": 1})
	var r: RuleResult = out["result"]
	expect_eq(r.grey_area, Movement.RULING_UNEVEN, "the table has to rule")
	expect(out["events"].is_empty(), "nothing happens until it does")
	s.rulings[Movement.RULING_UNEVEN] = {"choice": "allow"}
	expect_eq((F.act(e, s, "move", "p1", {"to": [2, 0], "level": 1})["result"] as RuleResult).grey_area, "climb_cost", "then how climbing costs")
	s.rulings["climb_cost"] = {"choice": "step_plus_climb"}
	expect(F.ok(F.act(e, s, "move", "p1", {"to": [2, 0], "level": 1})))
	expect_eq(u.level, 1)


func test_hex_movement_and_big_footprint() -> void:
	var s := F.state(GridLayout.Shape.HEX)
	var e := RulesEngine.new()
	var u := _one(s, e, Vector2i(2, 2), 3.0)
	var plan := RulesQueries.preview_move(s, "p1", Vector2i(4, 2))
	expect(plan["ok"], plan["reason"])
	expect_eq(plan["cost"], 2)
	F.act(e, s, "move", "p1", {"to": [4, 2]})
	expect_eq(u.cell, Vector2i(4, 2))


func test_stunned_flyer_falls_even_when_hovering() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var u := _one(s, e)
	u.flight = "hover"
	F.act(e, s, "move", "p1", {"to": [1, 0], "level": 3, "fly": true})
	expect(u.flying)
	Combat.add_status(s, u, "Stunned", "test", "p1")
	F.act(e, s, "end_turn", "p1")
	expect_eq(u.level, 0)
