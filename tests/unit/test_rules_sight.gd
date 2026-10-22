extends TestCase
## Line of sight and cover in 3D, with Size.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _pair(s: GameState, target_size := 1.0, target_cell := Vector2i(4, 0)) -> Array:
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", target_cell, target_size)
	return [a, t]


func test_tall_wall_blocks_line_of_sight() -> void:
	for shape in [GridLayout.Shape.SQUARE, GridLayout.Shape.HEX]:
		var s := F.state(shape)
		s.map.set_column(Vector2i(2, 0), 2)
		_pair(s)
		expect(not RulesQueries.line_of_sight(s, "a", "t"), "shape %d" % shape)
		expect(not RulesQueries.cover(s, "a", "t")["los"])


func test_low_wall_next_to_target_is_hard_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(3, 0), 1)
	_pair(s)
	var c := RulesQueries.cover(s, "a", "t")
	expect(c["los"], "the top of the mech shows over the wall")
	expect_eq(c["cover"], "hard")
	expect_eq(c["difficulty"], 2)
	expect_eq(c["cover_cells"], [[3, 0]])


func test_low_wall_does_not_cover_a_size_three() -> void:
	var s := F.state()
	for y in range(12):
		s.map.set_column(Vector2i(3, y), 1)
	_pair(s, 3.0)
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "none")


func test_cover_must_be_at_least_the_targets_size() -> void:
	var s := F.state()
	for y in range(12):
		s.map.set_column(Vector2i(3, y), 2)
	_pair(s, 3.0)
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "soft", "a Size 2 wall only obscures a Size 3 (Core p.66)")
	for y in range(12):
		s.map.set_column(Vector2i(3, y), 3)
	expect(not RulesQueries.cover(s, "a", "t")["los"], "a full-height wall hides it from a small attacker")
	s.unit("a").size = 3.0
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "hard", "a Size 3 attacker sees its top over a Size 3 wall")


func test_high_attacker_sees_over_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(3, 0), 1)
	s.map.set_column(Vector2i(0, 0), 3)
	_pair(s)
	var c := RulesQueries.cover(s, "a", "t")
	expect(c["flanked"], "from up high a line clears the wall")
	expect_eq(c["cover"], "soft", "not hard cover; the center line still clips the wall (PROVISIONAL 3D reading)")


func test_attacker_shoots_over_its_own_low_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(1, 0), 1)
	_pair(s)
	var c := RulesQueries.cover(s, "a", "t")
	expect(c["los"])
	expect_eq(c["cover"], "none", "a wall no taller than the attacker, next to it (Core p.66)")


func test_hard_cover_away_from_the_target_is_soft_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(2, 0), 1)
	_pair(s)
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "soft", "obscured by hard cover it isn't adjacent to (Core p.66)")


func test_flanking_ignores_hard_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(3, 0), 1)
	var t := _pair(s)
	var a: Unit = t[0]
	a.cell = Vector2i(4, 4)
	var c := RulesQueries.cover(s, "a", "t")
	expect(c["flanked"], "a clear line from the side")
	expect_eq(c["cover"], "none")


func test_wrecks_give_hard_cover() -> void:
	var s := F.state()
	_pair(s)
	var wreck := F.mech(s, "w", "enemies", Vector2i(3, 0))
	wreck.destroyed = true
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "hard", "destroyed mechs become hard cover (Core p.82)")
	wreck.counters["vaporized"] = true
	expect_eq(RulesQueries.cover(s, "a", "t")["cover"], "none", "a reactor meltdown leaves no wreck")


func test_smoke_is_soft_cover() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(2, 0), 0, PackedStringArray([Sight.TAG_SOFT_COVER]))
	_pair(s)
	var c := RulesQueries.cover(s, "a", "t")
	expect_eq(c["cover"], "soft")
	expect_eq(c["difficulty"], 1)


func test_cover_shows_in_attack_breakdown_but_not_for_melee() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(3, 0), 1)
	var t := _pair(s)
	var a: Unit = t[0]
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect(p["ok"], p["reason"])
	expect_eq(p["difficulty"], 2)
	expect_eq(p["sources"][0]["label"], "Hard cover")
	expect(p["hit_chance"] < RulesQueries.hit_chance(0, 0, 8))
	a.loadout["weapons"].append(F.weapon("1:0", "Sword", "Main", "Melee", "1d6", 1))
	a.cell = Vector2i(5, 0)
	var m := RulesQueries.attack_preview(s, "a", "1:0", "t")
	expect(m["ok"], m["reason"])
	expect_eq(m["difficulty"], 0, "cover only affects ranged attacks")


func test_cover_at_destination() -> void:
	var s := F.state()
	s.map.set_column(Vector2i(3, 0), 1)
	var t := _pair(s)
	var c := RulesQueries.cover_at(s, "t", Vector2i(5, 0), 0)
	expect_eq(c["a"]["cover"], "soft", "away from the wall it only obscures: soft cover (Core p.66)")
	expect_eq(RulesQueries.cover_at(s, "t", Vector2i(4, 0), 0)["a"]["cover"], "hard")


func test_hit_chance_math() -> void:
	expect(is_equal_approx(RulesQueries.hit_chance(0, 0, 11), 0.5))
	expect(is_equal_approx(RulesQueries.hit_chance(0, 0, 1), 1.0))
	expect(RulesQueries.hit_chance(0, 1, 11) > 0.5)
	expect(RulesQueries.hit_chance(0, -1, 11) < 0.5)
