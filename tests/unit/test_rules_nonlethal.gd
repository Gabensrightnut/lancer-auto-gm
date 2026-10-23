extends TestCase
## The non-lethal match (state.objectives["nonlethal"], the user's PvP mode): knocked out
## instead of destroyed or melting down; the book's combat otherwise.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func test_last_structure_knocks_out_instead_of_destroying() -> void:
	var s := F.state()
	s.objectives["nonlethal"] = true
	var m := F.mech(s, "m", "players", Vector2i(1, 1))
	m.max_structure = 4
	m.structure = 1
	m.max_stress = 4
	m.stress = 4
	var ev := Combat.deal_damage(s, m, [{"type": "Kinetic", "amount": 20}])
	expect(not m.destroyed and m.counters.get("knocked_out", false), "knocked out, not destroyed")
	expect_eq([m.hp, m.structure, m.stress], [0, 1, 4])
	expect(not Combat.is_present(m), "out of the fight for the rest of the match")
	expect(ev.any(func(e: Dictionary) -> bool: return e["type"] == "knocked_out"), "a knocked_out event")
	expect(Combat.deal_damage(s, m, [{"type": "Kinetic", "amount": 5}]).is_empty(), "no more damage")
	# A normal fight: the same hit destroys it.
	var t := F.state()
	var n := F.mech(t, "n", "players", Vector2i(1, 1))
	n.max_structure = 4
	n.structure = 1
	Combat.deal_damage(t, n, [{"type": "Kinetic", "amount": 20}])
	expect(n.destroyed, "the book: destroyed")


func test_last_stress_knocks_out_instead_of_melting_down() -> void:
	var s := F.state()
	s.objectives["nonlethal"] = true
	var m := F.mech(s, "m", "players", Vector2i(1, 1))
	m.max_structure = 4
	m.structure = 4
	m.max_stress = 4
	m.stress = 1
	Combat.apply_heat(s, m, 10, "test")
	expect(m.counters.get("knocked_out", false) and not m.counters.has("meltdown"), "no meltdown")
	expect_eq([m.stress, m.hp], [1, 0])


func test_no_self_destruct_in_a_non_lethal_match() -> void:
	var s := F.state()
	s.objectives["nonlethal"] = true
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(1, 1))
	F.mech(s, "foe", "enemies", Vector2i(8, 8))
	F.begin(e, s, m)
	var out := F.act(e, s, "self_destruct", "m", {"delay": 1})
	expect(not F.ok(out) and F.reason(out).contains("non-lethal"), F.reason(out))
