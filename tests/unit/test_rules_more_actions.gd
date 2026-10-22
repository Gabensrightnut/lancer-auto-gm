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
	expect_eq(t.hp, 10, "12 explosive damage: structure lost, HP reset to full")
	expect_eq(t.structure, 3)
