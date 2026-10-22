extends TestCase
## Player-vs-player: two player sides, hostile to each other, in one GameState.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func test_two_player_sides_fight() -> void:
	var s := F.state()
	s.player_sides = ["red", "blue"]
	var e := RulesEngine.new()
	var r := F.mech(s, "r", "red", Vector2i(0, 0))
	var b := F.mech(s, "b", "blue", Vector2i(1, 0))
	expect(F.ok(e.submit(s, {"type": "start_combat", "params": {"first_side": "blue"}})), "either player side may go first")
	expect(r.has_status("Engaged") and b.has_status("Engaged"), "different sides are hostile: Engaged")
	F.act(e, s, "start_turn", "b")
	F.load_dice(s, [15, 1, 3])  # Engaged: a Difficulty die before the damage
	var out := F.act(e, s, "skirmish", "b", {"weapon": "0:0", "target": "r"})
	expect(F.ok(out), F.reason(out))
	expect_eq(r.hp, 7)
	var s2 := F.state()
	F.mech(s2, "p", "players", Vector2i(0, 0))
	F.mech(s2, "n", "enemies", Vector2i(5, 0))
	expect(not F.ok(RulesEngine.new().submit(s2, {"type": "start_combat", "params": {"first_side": "enemies"}})), "against the GM, players still go first")
	expect(GameState.from_dict(s.to_dict()).player_sides == ["red", "blue"], "saved")
