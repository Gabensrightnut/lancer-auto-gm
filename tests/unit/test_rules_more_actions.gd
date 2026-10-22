extends TestCase
## Ram, Grapple, Jump, Full Tech, Bolster, Prepare, Eject, Mount/Dismount, pilots, Self Destruct.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(t_cell := Vector2i(1, 0), t_size := 1.0) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", t_cell, t_size)
	F.begin(e, s, a)


func _next_turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_ram_knocks_prone_and_back() -> void:
	_setup()
	F.load_dice(s, [15])
	var out := F.act(e, s, "ram", "a", {"target": "t", "knockback": true})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Prone"))
	expect_eq(t.cell, Vector2i(2, 0))
	expect_eq(t.hp, 10, "Ram deals no damage")
	_setup(Vector2i(1, 0), 2.0)
	expect(not F.ok(F.act(e, s, "ram", "a", {"target": "t"})), "only your Size or smaller")


func test_grapple_immobilizes_smaller_drags_and_ends() -> void:
	_setup(Vector2i(1, 0), 0.5)
	F.load_dice(s, [15])
	var out := F.act(e, s, "grapple", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Immobilized"))
	expect(not F.ok(F.act(e, s, "boost", "a", {"to": [0, 2]})), "no Boost while grappling")
	F.act(e, s, "move", "a", {"to": [0, 2]})
	expect_eq(t.cell, Vector2i(1, 2), "dragged along")
	expect(t.counters.has("grapple"))
	_next_turn(t)
	F.load_dice(s, [18, 2])
	out = F.act(e, s, "break_free", "t")
	expect(F.ok(out), F.reason(out))
	expect(not t.counters.has("grapple") and not t.has_status("Immobilized"))


func test_jump_up_and_over() -> void:
	_setup(Vector2i(9, 9))
	s.map.set_column(Vector2i(1, 0), 1)
	var out := F.act(e, s, "jump", "a", {"to": [1, 0], "vertical": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.level, 1)
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [2, 0]})), "jumping used the standard move")
	_setup(Vector2i(9, 9))
	s.map.set_column(Vector2i(1, 0), 4)
	expect(not F.ok(F.act(e, s, "jump", "a", {"to": [2, 0]})), "can't jump through a wall")
	expect(not F.ok(F.act(e, s, "jump", "a", {"to": [0, 3]})), "half of Speed 4 is 2")
	expect(F.ok(F.act(e, s, "jump", "a", {"to": [0, 2]})))


func test_full_tech_and_bolster() -> void:
	_setup(Vector2i(4, 0))
	var ally := F.mech(s, "b", "players", Vector2i(0, 2))
	var out := F.act(e, s, "full_tech", "a", {"options": [{"type": "scan", "target": "t"}, {"type": "bolster", "target": "b"}]})
	expect(F.ok(out), F.reason(out))
	expect(s.intel["players"].has("t"))
	expect(ally.has_status("Bolstered"))
	F.load_dice(s, [5, 6])
	var check := Combat.skill_check(s, ally, "hull", "test")
	expect_eq(check["total"], 11, "5 + Bolster's d6 (6)")
	expect(not ally.has_status("Bolstered"), "used up")
	expect(not F.ok(F.act(e, s, "lock_on", "a", {"target": "t"})), "Full Tech took the turn")


func test_prepared_skirmish_fires_when_a_hostile_moves_adjacent() -> void:
	_setup(Vector2i(4, 0))
	var out := F.act(e, s, "prepare", "a", {"action": {"type": "skirmish", "params": {"weapon": "0:0", "target": "trigger"}},
		"trigger": {"event": "moves_adjacent", "who": "hostile"}, "text": "When a hostile moves next to me, I shoot it"})
	expect(F.ok(out), F.reason(out))
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [0, 1]})), "can't move after preparing")
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "it counts as the Skirmish")
	_next_turn(t)
	F.load_dice(s, [15, 1, 3])  # Engaged once t arrives: +1 Difficulty
	out = F.act(e, s, "move", "t", {"to": [1, 0]})
	expect_eq(F.events_of(out, "prepared_triggered").size(), 1)
	expect_eq(t.hp, 7)
	expect(not a.counters.has("prepared"))


func test_eject_dismount_and_mount() -> void:
	_setup(Vector2i(9, 9))
	var out := F.act(e, s, "eject", "a", {"to": [4, 0]})
	expect(F.ok(out), F.reason(out))
	var pilot := s.unit("a_pilot")
	expect(pilot != null and Combat.is_present(pilot))
	expect_eq(pilot.cell, Vector2i(4, 0))
	expect(a.has_status("Impaired"))
	expect_eq(s.active_unit, "a_pilot", "the pilot carries on the turn")
	expect(not TurnRules.takes_turns(a), "an empty mech takes no turns")
	expect(not F.ok(F.act(e, s, "skirmish", "a_pilot", {"weapon": "0:0", "target": "t"})), "pilots can't Skirmish")
	F.act(e, s, "end_turn", "a_pilot")
	expect(s.acted.has("a") and s.acted.has("a_pilot"))
	pilot.cell = Vector2i(1, 0)
	_next_turn(pilot)
	out = F.act(e, s, "mount", "a_pilot", {"mech": "a"})
	expect(F.ok(out), F.reason(out))
	expect(not Combat.is_present(pilot))
	expect(TurnRules.takes_turns(a))
	expect_eq(s.active_unit, "a")
	_next_turn(a)
	expect(F.ok(F.act(e, s, "dismount", "a")))
	expect(Combat.is_present(pilot))
	expect(not F.ok(F.act(e, s, "eject", "a", {"to": [4, 0]})))


func test_pilot_weapons_and_down_and_out() -> void:
	var db := ContentDB.new()
	db.load_all()
	_setup(Vector2i(9, 9))
	var p := UnitFactory.build_pilot(db, "pp", {"name": "Ace", "ll": 2, "weapons": ["pg_archaic_ranged", "pg_light_a_c"]}, "players")
	expect_eq(p.hp, 7, "6 + Grit 1")
	expect_eq(p.size, 0.5)
	p.cell = Vector2i(2, 2)
	s.add_unit(p)
	t.cell = Vector2i(3, 2)
	_next_turn(p)
	F.load_dice(s, [19])
	var out := F.act(e, s, "fight", "pp", {"weapon": "p0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 10, "Archaic weapons can't harm mechs")
	expect(not F.ok(F.act(e, s, "fight", "pp", {"weapon": "p1", "target": "t"})), "Fight is a full action")
	Combat.deal_damage(s, p, [{"type": "Kinetic", "amount": 9}])
	expect(p.has_status("Down and Out") and p.has_status("Stunned"))
	expect(not p.destroyed)
	Combat.deal_damage(s, p, [{"type": "Kinetic", "amount": 1}])
	expect(p.destroyed, "damage while Down and Out kills")


func test_self_destruct_explodes_at_end_of_next_turn() -> void:
	_setup(Vector2i(2, 0))
	var out := F.act(e, s, "self_destruct", "a", {"delay": 1})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	expect(not a.destroyed, "not this turn")
	_next_turn(a)
	F.load_dice(s, [3, 3, 3, 3, 5])  # 4d6 = 12; t's Agility save 5 fails
	out = F.act(e, s, "end_turn", "a")
	expect(a.destroyed)
	expect_eq(F.events_of(out, "reactor_explosion").size(), 1)
	expect_eq(t.hp, 8, "12 explosive damage: structure lost, HP reset, 2 excess (Core p.80)")
	expect_eq(t.structure, 3)


func test_big_damage_can_cost_several_structure() -> void:
	_setup(Vector2i(9, 9))
	F.load_dice(s, [6, 6])
	Combat.deal_damage(s, t, [{"type": "Kinetic", "amount": 25}])
	expect_eq(t.structure, 2, "10 + 10 + 5: two structure (Core p.80)")
	expect_eq(t.hp, 5)


func test_heat_overflow_and_zero_stress_meltdown() -> void:
	_setup(Vector2i(9, 9))
	F.load_dice(s, [6, 6])
	Combat.apply_heat(s, a, 9, "test")
	expect_eq(a.stress, 3, "9 heat on cap 6: overheat once")
	expect_eq(a.heat, 2, "the 2 beyond what it took to exceed the cap (PROVISIONAL)")
	a.stress = 1
	a.heat = 0
	Combat.apply_heat(s, a, 7, "test")
	expect_eq(a.stress, 0)
	expect(not a.destroyed, "0 Stress: meltdown at the end of its next turn, not at once (Core p.81)")
	expect(a.counters.has("meltdown"))


func test_one_reaction_per_turn() -> void:
	_setup(Vector2i(9, 9))
	Reactions._mark_used(t, "overwatch", s)
	var r := Reactions.can_react(t, "brace", s)
	expect(not r.ok, "already reacted this turn (Core p.73)")
	_next_turn(t)
	expect(Reactions.can_react(t, "brace", s).ok, "a new turn")


func test_pilots_boost_and_are_immune_to_most_tech() -> void:
	_setup(Vector2i(2, 2))
	var p := Pilots.make_pilot("pp", "Ace", "enemies", "gm", 1)
	p.cell = Vector2i(3, 0)
	s.add_unit(p)
	expect(not F.ok(F.act(e, s, "invade", "a", {"target": "pp"})), "BIOLOGICAL: no Invade (Core p.74)")
	expect(F.ok(F.act(e, s, "lock_on", "a", {"target": "pp"})), "Lock On still works")
	Combat.refresh_engagement(s)
	expect(not a.has_status("Engaged"), "pilots don't engage mechs")
	_next_turn(p)
	expect(F.ok(F.act(e, s, "boost", "pp", {"to": [4, 1]})), "pilots can Boost")
	F.load_dice(s, [9])
	var c := Combat.skill_check(s, p, "agility", "test", 10, 0, 0, [], true)
	expect_eq(c["total"], 10, "9 + Grit 1 instead of a mech skill")


func test_mechs_pass_smaller_hostiles_and_pilots() -> void:
	s = F.state(GridLayout.Shape.SQUARE, 6, 1)
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", Vector2i(1, 0), 0.5)
	F.begin(e, s, a)
	expect(RulesQueries.preview_move(s, "a", Vector2i(2, 0))["ok"], "smaller hostiles don't obstruct (Core p.62)")
	t.size = 1.0
	expect(not RulesQueries.preview_move(s, "a", Vector2i(2, 0))["ok"], "same Size does")


func test_falling_ten_spaces_per_round() -> void:
	_setup(Vector2i(9, 9))
	a.level = 14
	a.counters["falling"] = true
	F.act(e, s, "end_turn", "a")
	expect_eq(a.level, 4, "10 spaces this round (Core p.63)")
	expect_eq(a.hp, 10, "still falling: no damage yet")
	_next_turn(t)
	F.act(e, s, "end_turn", "t")
	expect_eq(a.level, 4, "only falls at the end of its own turns")
	_next_turn(a)
	F.act(e, s, "end_turn", "a")
	expect_eq(a.level, 0)
	expect_eq(a.hp, 1, "14 spaces: 9 AP kinetic (the maximum)")


func test_search_ties_go_to_the_searcher() -> void:
	_setup(Vector2i(4, 0))
	t.statuses["Hidden"] = {"source": "t"}
	F.load_dice(s, [10, 10])
	var out := F.act(e, s, "search", "a", {"target": "t"})
	expect(F.events_of(out, "searched")[0]["found"], "a tie: the one who started the contest wins (Core p.13)")
