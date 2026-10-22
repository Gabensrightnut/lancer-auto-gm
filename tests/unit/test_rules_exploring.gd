extends TestCase
## Exploring vs. fighting (DESIGN.md): a fight starts with whoever is there, latecomers join from
## the next round, combat ends while others explore, and turn-based exploring.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine


func _units() -> void:
	s = F.state()
	e = RulesEngine.new()
	F.mech(s, "a", "players", Vector2i(0, 0))
	F.mech(s, "far", "players", Vector2i(11, 11))
	F.mech(s, "foe", "enemies", Vector2i(3, 0))


func test_fight_starts_with_whoever_is_there() -> void:
	_units()
	var out := e.submit(s, {"type": "start_combat", "params": {"first_side": "players", "center": [1, 0], "radius": 5}})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "combat_started")[0]["exploring"], ["far"])
	expect(not TurnRules.takes_turns(s.unit("far")), "the far teammate isn't in the fight")
	expect(F.ok(e.submit(s, {"type": "explore_move", "actor": "far", "params": {"to": [11, 8]}})), "it keeps exploring")
	expect(not F.ok(e.submit(s, {"type": "explore_move", "actor": "a", "params": {"to": [0, 1]}})), "fighters move on their turn")


func test_latecomer_joins_from_the_next_round() -> void:
	_units()
	e.submit(s, {"type": "start_combat", "params": {"first_side": "players", "units": ["a", "foe"]}})
	var out := e.submit(s, {"type": "join_combat", "actor": "far", "params": {"to": [4, 0]}})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.unit("far").cell, Vector2i(4, 0), "arrives behind the enemy")
	expect(s.unit("far").has_status("Engaged"), "next to the enemy: Engaged, nothing provoked")
	expect(not TurnRules.takes_turns(s.unit("far")), "not this round")
	F.act(e, s, "start_turn", "a")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "foe")
	F.act(e, s, "end_turn", "foe")
	expect_eq(s.round_number, 2)
	expect(TurnRules.takes_turns(s.unit("far")), "from the next round it takes turns")
	expect(not F.ok(e.submit(s, {"type": "join_combat", "actor": "a", "params": {"to": [5, 5]}})), "already in the fight")


func test_combat_ends_while_others_explore() -> void:
	_units()
	e.submit(s, {"type": "start_combat", "params": {"first_side": "players", "units": ["a", "foe"]}})
	expect(not RulesQueries.combat_over(s))
	s.unit("foe").destroyed = true
	expect(RulesQueries.combat_over(s), "only one side left fighting")
	var out := e.submit(s, {"type": "end_combat"})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.phase, GameState.PHASE_SETUP)
	expect(not s.unit("far").counters.has("exploring"))
	expect(F.ok(e.submit(s, {"type": "explore_move", "actor": "a", "params": {"to": [0, 2]}})), "everyone explores again")


func test_turn_based_exploring() -> void:
	_units()
	s.units.erase("foe")
	var out := e.submit(s, {"type": "start_combat", "params": {"first_side": "players", "mode": "explore"}})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.turn_mode, "explore")
	expect(F.ok(F.act(e, s, "start_turn", "a")), "turns, for stealth")
	expect(not RulesQueries.combat_over(s), "explore mode doesn't end by itself")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "far")
	F.act(e, s, "end_turn", "far")
	expect(F.ok(e.submit(s, {"type": "end_combat"})))
	expect_eq(s.turn_mode, "combat")
