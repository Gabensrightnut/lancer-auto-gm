extends TestCase
## Area attacks: templates on hex and square, one damage roll, cover from the origin.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _cells(shape: GridLayout.Shape, pattern: String, size: int, aim: Vector2i) -> Array[Vector2i]:
	var grid := GridLayout.create(shape)
	var origin: Array[Vector2i] = [Vector2i(0, 0)]
	return Areas.template(grid, pattern, size, origin, aim)


func test_blast_and_burst_sizes() -> void:
	expect_eq(_cells(GridLayout.Shape.SQUARE, "Blast", 1, Vector2i(5, 5)).size(), 9)
	expect_eq(_cells(GridLayout.Shape.HEX, "Blast", 1, Vector2i(5, 5)).size(), 7)
	expect_eq(_cells(GridLayout.Shape.HEX, "Blast", 2, Vector2i(5, 5)).size(), 19)
	expect_eq(_cells(GridLayout.Shape.SQUARE, "Burst", 1, Vector2i.ZERO).size(), 9, "includes the user's space")


func test_line_is_straight_and_x_long() -> void:
	for shape in [GridLayout.Shape.SQUARE, GridLayout.Shape.HEX]:
		var line := _cells(shape, "Line", 3, Vector2i(5, 0))
		expect_eq(line, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i], "shape %d" % shape)


func test_cone_starts_one_wide_and_ends_x_wide() -> void:
	var cone := _cells(GridLayout.Shape.SQUARE, "Cone", 3, Vector2i(6, 0))
	expect_eq(cone.size(), 7)
	for c in [Vector2i(1, 0), Vector2i(2, -1), Vector2i(2, 1), Vector2i(3, -1), Vector2i(3, 0), Vector2i(3, 1)]:
		expect(cone.has(c), str(c))
	expect(not cone.has(Vector2i(1, 1)), "1 wide at the start")
	var hex := _cells(GridLayout.Shape.HEX, "Cone", 3, Vector2i(6, 0))
	expect(hex.has(Vector2i(1, 0)) and hex.has(Vector2i(3, 0)))
	var far := 0
	var grid := GridLayout.create(GridLayout.Shape.HEX)
	for c in hex:
		if grid.distance(Vector2i.ZERO, c) == 3:
			far += 1
	expect(far >= 3, "at least 3 wide at the far end on hex (%d)" % far)


func _blast_setup() -> Array:
	var s := F.state()
	var e := RulesEngine.new()
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	var w := F.weapon("1:0", "Grenade Launcher", "Main", "Launcher", "1d6", 0)
	w["range"] = [{"type": "Blast", "val": 1}, {"type": "Range", "val": 8}]
	a.loadout["weapons"].append(w)
	F.begin(e, s, a)
	return [s, e, a]


func test_blast_rolls_damage_once_and_attacks_each_target() -> void:
	var t := _blast_setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	var x := F.mech(s, "x", "enemies", Vector2i(5, 5))
	var y := F.mech(s, "y", "enemies", Vector2i(6, 5))
	var ally := F.mech(s, "z_ally", "players", Vector2i(5, 6))
	y.statuses["Hidden"] = {"source": "y"}
	F.load_dice(s, [15, 4, 12, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0", "aim": [5, 5]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "area_attack")[0]["targets"], ["x", "y", "z_ally"], "everyone in the area, Hidden and allies too")
	var rolls := F.events_of(out, "damage_rolled")
	expect_eq(rolls.size(), 2, "one per target hit")
	expect_eq(rolls[0]["roll"], rolls[1]["roll"], "but the same single roll")
	expect_eq(x.hp, 6)
	expect_eq(y.hp, 6, "same damage roll")
	expect_eq(ally.hp, 10, "missed")


func test_blast_center_must_be_in_range_and_sight() -> void:
	var t := _blast_setup()
	var s: GameState = t[0]
	var e: RulesEngine = t[1]
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "1:0", "aim": [10, 0]})), "out of Range 8")
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "a"})), "area weapons aim at a space")


func test_blast_cover_comes_from_the_center() -> void:
	var t := _blast_setup()
	var s: GameState = t[0]
	F.mech(s, "x", "enemies", Vector2i(5, 0))
	# A low wall between the attacker and x, but the blast lands on x's side of it.
	s.map.set_column(Vector2i(4, 0), 1)
	expect_eq(RulesQueries.cover(s, "a", "x")["cover"], "hard", "against the attacker it's hard cover")
	var p := RulesQueries.area_preview(s, "a", "1:0", Vector2i(6, 0))
	expect(p["ok"], p["reason"])
	expect_eq(p["targets"].size(), 1)
	expect_eq(p["targets"][0]["preview"]["difficulty"], 0, "no cover from the blast center")


func test_burst_does_not_hit_the_user() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var a := F.mech(s, "a", "players", Vector2i(3, 3))
	var w := F.weapon("1:0", "Shockwave", "Main", "Special", "2", 0)
	w["range"] = [{"type": "Burst", "val": 1}]
	a.loadout["weapons"].append(w)
	var x := F.mech(s, "x", "enemies", Vector2i(4, 4))
	F.begin(e, s, a)
	F.load_dice(s, [15])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "1:0"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "area_attack")[0]["targets"], ["x"])
	expect_eq(x.hp, 8)
	expect_eq(a.hp, 10)
