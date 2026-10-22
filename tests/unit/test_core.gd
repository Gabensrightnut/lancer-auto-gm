extends TestCase


func test_dice_replay_from_seed() -> void:
	var a := Dice.new(1234)
	var b := Dice.new(1234)
	for i in range(20):
		expect_eq(a.roll("2d6+3")["total"], b.roll("2d6+3")["total"])


func test_dice_expressions() -> void:
	var d := Dice.new(7)
	for i in range(200):
		var r := d.roll("1d6+4")
		expect(r["total"] >= 5 and r["total"] <= 10)
		var r3 := d.roll("1d3")
		expect(r3["total"] >= 1 and r3["total"] <= 3)
	expect_eq(d.roll("4")["total"], 4)


func test_accuracy_and_difficulty_cancel() -> void:
	var d := Dice.new(99)
	var even := d.accuracy_roll(2, 2)
	expect_eq(even["net"], 0)
	expect_eq(even["dice"].size(), 0)
	expect_eq(even["value"], 0)
	var acc := d.accuracy_roll(3, 1)
	expect_eq(acc["color"], "blue")
	expect_eq(acc["dice"].size(), 2)
	expect_eq(acc["value"], acc["dice"].max(), "keeps the highest d6")
	var diff := d.accuracy_roll(0, 2)
	expect_eq(diff["color"], "red")
	expect_eq(diff["value"], -diff["dice"].max())


func test_state_round_trip_through_json() -> void:
	var s := GameState.new(424242, GridLayout.Shape.SQUARE)
	s.map = BattleMap.flat(GridLayout.Shape.SQUARE, 4, 4)
	var u := Unit.new()
	u.id = "p1_everest"
	u.content_id = "mf_standard_pattern_i_everest"
	u.cell = Vector2i(2, 3)
	u.hp = 10
	u.statuses = {"Lock On": {"source": "e1"}}
	s.add_unit(u)
	s.dice.roll("1d20")
	var next_roll: int = GameState.from_dict(s.to_dict()).dice.die(20)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	expect_eq(copy.game_seed, 424242)
	expect_eq(copy.unit("p1_everest").cell, Vector2i(2, 3))
	expect_eq(copy.unit("p1_everest").hp, 10)
	expect(copy.unit("p1_everest").has_status("Lock On"))
	expect_eq(copy.dice.die(20), next_roll, "dice continue from the saved state")


func test_rules_engine_refuses_out_of_turn_actions() -> void:
	var s := GameState.new(1)
	var u := Unit.new()
	u.id = "a"
	s.add_unit(u)
	var engine := RulesEngine.new()
	var out := engine.submit(s, {"type": "end_turn", "actor": "a"})
	expect(not (out["result"] as RuleResult).ok)
	expect(out["events"].is_empty())
	s.active_unit = "a"
	out = engine.submit(s, {"type": "end_turn", "actor": "a"})
	expect((out["result"] as RuleResult).ok)
	expect_eq(out["events"][0]["type"], "turn_ended")
	expect(not engine.submit(s, {"type": "fly_to_the_moon", "actor": "a"})["result"].ok)


func test_view_filter_hides_enemy_stats_and_hidden_units() -> void:
	var s := GameState.new(1)
	s.seats = {"seat1": {"name": "P1", "side": "players"}}
	var ally := Unit.new()
	ally.id = "ally"
	ally.side = "players"
	ally.hp = 10
	var enemy := Unit.new()
	enemy.id = "enemy"
	enemy.side = "enemies"
	enemy.hp = 15
	var sneaky := Unit.new()
	sneaky.id = "sneaky"
	sneaky.side = "enemies"
	sneaky.statuses = {"Hidden": {}}
	for u in [ally, enemy, sneaky]:
		s.add_unit(u)
	var filter := ViewFilter.new()
	var view := filter.view_for(s, "seat1")
	expect(not view.has("dice_state"), "clients never get the dice state")
	expect_eq(view["units"]["ally"]["hp"], 10)
	expect(not view["units"]["enemy"].has("hp"), "unscanned enemy HP stays unknown")
	expect(not view["units"]["sneaky"].has("cell"), "Hidden enemy position stays unknown")
	filter.reveal_stats("players", "enemy")
	expect_eq(filter.view_for(s, "seat1")["units"]["enemy"]["hp"], 15)
