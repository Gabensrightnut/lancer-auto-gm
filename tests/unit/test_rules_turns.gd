extends TestCase
## Turn order and the action economy.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _setup() -> Array:
	var s := F.state()
	var e := RulesEngine.new()
	var p1 := F.mech(s, "p1", "players", Vector2i(0, 0))
	var p2 := F.mech(s, "p2", "players", Vector2i(0, 2))
	var n1 := F.mech(s, "n1", "enemies", Vector2i(9, 9))
	return [s, e, p1, p2, n1]


func test_sides_alternate_and_rounds_advance() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	expect(not F.ok(F.act(e, s, "start_turn", "p1")), "no turns before combat starts")
	expect(not F.ok(e.submit(s, {"type": "start_combat", "params": {"first_side": "enemies"}})), "players always act first (Core p.60)")
	expect(F.ok(e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})))
	expect_eq(s.round_number, 1)
	expect(not F.ok(F.act(e, s, "start_turn", "n1")), "players pick first")
	expect(F.ok(F.act(e, s, "start_turn", "p1")))
	expect(not F.ok(F.act(e, s, "start_turn", "p2")), "one unit at a time")
	expect(not F.ok(F.act(e, s, "end_turn", "p2")), "only the active unit ends its turn")
	F.act(e, s, "end_turn", "p1")
	expect_eq(s.turn_side, "enemies", "then the other side picks")
	expect(not F.ok(F.act(e, s, "start_turn", "p2")))
	F.act(e, s, "start_turn", "n1")
	F.act(e, s, "end_turn", "n1")
	expect_eq(s.turn_side, "players", "enemies are out of units, players continue")
	F.act(e, s, "start_turn", "p2")
	var out := F.act(e, s, "end_turn", "p2")
	expect_eq(s.round_number, 2, "everyone acted: new round")
	expect_eq(F.events_of(out, "round_started").size(), 1)
	expect_eq(s.turn_side, "enemies", "the players took the last turn, so the enemies start round 2 (Core p.60)")
	expect(not F.ok(F.act(e, s, "start_turn", "p1")))
	expect(F.ok(F.act(e, s, "start_turn", "n1")))


func test_two_quick_actions_or_one_full() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	var p1: Unit = t[2]
	F.begin(e, s, p1)
	expect(F.ok(F.act(e, s, "lock_on", "p1", {"target": "n1"})))
	var again := F.act(e, s, "lock_on", "p1", {"target": "n1"})
	expect(not F.ok(again), "can't repeat the same Quick Tech option")
	expect(F.ok(F.act(e, s, "boost", "p1", {"to": [2, 0]})))
	var third := F.act(e, s, "skirmish", "p1", {"weapon": "0:0", "target": "n1"})
	expect(not F.ok(third), "only two quick actions")
	expect(not F.ok(F.act(e, s, "stabilize", "p1", {"main": "cool", "extra": "reload"})), "full action after quick actions")


func test_full_action_uses_the_turn() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	F.begin(e, s, t[2])
	expect(F.ok(F.act(e, s, "stabilize", "p1", {"main": "cool", "extra": "reload"})))
	expect(not F.ok(F.act(e, s, "lock_on", "p1", {"target": "n1"})))
	expect(F.ok(F.act(e, s, "move", "p1", {"to": [1, 0]})), "standard move is separate from actions")


func test_overcharge_allows_repeating_a_quick_action_for_heat() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	var p1: Unit = t[2]
	F.begin(e, s, p1)
	F.act(e, s, "boost", "p1", {"to": [1, 0]})
	F.act(e, s, "lock_on", "p1", {"target": "n1"})
	var oc := F.act(e, s, "overcharge", "p1")
	expect(F.ok(oc))
	expect_eq(p1.heat, 1, "first Overcharge: 1 heat")
	expect(not F.ok(F.act(e, s, "overcharge", "p1")), "once per turn")
	expect(F.ok(F.act(e, s, "boost", "p1", {"to": [2, 0]})), "repeat Boost via Overcharge")
	expect(not F.ok(F.act(e, s, "boost", "p1", {"to": [3, 0]})))
	F.act(e, s, "end_turn", "p1")
	# Second overcharge costs 1d3.
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "p1")
	F.load_dice(s, [3])
	F.act(e, s, "overcharge", "p1")
	expect_eq(p1.heat, 4, "second Overcharge: 1d3 heat")
	expect_eq(p1.overcharge_count, 2)


func test_stunned_mech_cannot_act() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	var p1: Unit = t[2]
	F.begin(e, s, p1)
	p1.statuses["Stunned"] = {"source": "test"}
	var out := F.act(e, s, "move", "p1", {"to": [1, 0]})
	expect(not F.ok(out))
	expect(not F.ok(F.act(e, s, "overcharge", "p1")))
	expect(F.ok(F.act(e, s, "end_turn", "p1")), "a stunned unit can still end its turn")


func test_status_until_end_of_next_turn() -> void:
	var t := _setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	var p1: Unit = t[2]
	var n1: Unit = t[4]
	F.begin(e, s, p1)
	Combat.add_status(s, n1, "Impaired", "test", "n1")
	F.act(e, s, "end_turn", "p1")
	expect(n1.has_status("Impaired"), "still there after someone else's turn")
	F.act(e, s, "start_turn", "n1")
	F.act(e, s, "end_turn", "n1")
	expect(not n1.has_status("Impaired"), "gone at the end of its next turn")
	# Applied during its own turn: lasts through the following turn too.
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "p1")
	Combat.add_status(s, p1, "Impaired", "test", "p1")
	F.act(e, s, "end_turn", "p1")
	expect(p1.has_status("Impaired"))
