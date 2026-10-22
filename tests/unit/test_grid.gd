extends TestCase


func test_hex_distance_and_neighbors() -> void:
	var g := GridLayout.create(GridLayout.Shape.HEX)
	expect_eq(g.neighbors(Vector2i(0, 0)).size(), 6)
	for n in g.neighbors(Vector2i(3, -2)):
		expect_eq(g.distance(Vector2i(3, -2), n), 1)
	expect_eq(g.distance(Vector2i(0, 0), Vector2i(3, -1)), 3)
	expect_eq(g.distance(Vector2i(-2, 4), Vector2i(2, 0)), 4)


func test_square_distance_counts_diagonals_as_one() -> void:
	var g := GridLayout.create(GridLayout.Shape.SQUARE)
	expect_eq(g.neighbors(Vector2i(0, 0)).size(), 8)
	expect_eq(g.distance(Vector2i(0, 0), Vector2i(3, 3)), 3)
	expect_eq(g.distance(Vector2i(0, 0), Vector2i(5, 2)), 5)


func test_lines_are_contiguous_on_both_grids() -> void:
	for shape in [GridLayout.Shape.HEX, GridLayout.Shape.SQUARE]:
		var g := GridLayout.create(shape)
		var path := g.line(Vector2i(0, 0), Vector2i(5, -2))
		expect_eq(path[0], Vector2i(0, 0))
		expect_eq(path[-1], Vector2i(5, -2))
		expect_eq(path.size(), g.distance(Vector2i(0, 0), Vector2i(5, -2)) + 1)
		for i in range(1, path.size()):
			expect_eq(g.distance(path[i - 1], path[i]), 1, "gap in line on %s" % shape)


func test_world_round_trip() -> void:
	for shape in [GridLayout.Shape.HEX, GridLayout.Shape.SQUARE]:
		var g := GridLayout.create(shape)
		for cell in [Vector2i(0, 0), Vector2i(4, -3), Vector2i(-5, 7)]:
			expect_eq(g.from_world(g.to_world(cell, 2)), cell)
		# Adjacent centers are one space apart.
		var a := g.to_world(Vector2i(0, 0))
		var b := g.to_world(Vector2i(1, 0))
		expect(absf(a.distance_to(b) - GridLayout.SPACE) < 0.001)


func test_footprints_by_size() -> void:
	var hex := GridLayout.create(GridLayout.Shape.HEX)
	var sq := GridLayout.create(GridLayout.Shape.SQUARE)
	expect_eq(hex.footprint(Vector2i.ZERO, 0.5).size(), 1, "Size 1/2 uses one space")
	expect_eq(hex.footprint(Vector2i.ZERO, 1).size(), 1)
	expect_eq(sq.footprint(Vector2i.ZERO, 2).size(), 4)
	expect_eq(sq.footprint(Vector2i.ZERO, 3).size(), 9)
	expect_eq(hex.footprint(Vector2i.ZERO, 2).size(), 3)
	expect_eq(hex.footprint(Vector2i.ZERO, 3).size(), 7)


func test_size_three_cannot_fit_on_one_space_hilltop() -> void:
	var m := BattleMap.flat(GridLayout.Shape.SQUARE, 6, 6)
	m.set_column(Vector2i(2, 2), 3)  # a 1-space pillar, 3 levels tall
	var under_small := m.footprint_ground(Vector2i(2, 2), 1)
	expect_eq(under_small, [3] as Array[int])
	var under_big := m.footprint_ground(Vector2i(2, 2), 3)
	expect(under_big.min() != under_big.max(), "a Size 3 on the pillar would stand on uneven ground")
	expect(m.footprint_ground(Vector2i(5, 5), 2).is_empty(), "footprint off the map edge")


func test_map_round_trip() -> void:
	var m := BattleMap.flat(GridLayout.Shape.HEX, 5, 4)
	m.set_column(Vector2i(1, 1), 2, PackedStringArray(["difficult"]))
	var copy := BattleMap.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	expect_eq(copy.grid.shape, GridLayout.Shape.HEX)
	expect_eq(copy.cells().size(), 20)
	expect_eq(copy.ground_height(Vector2i(1, 1)), 2)
	expect(copy.column(Vector2i(1, 1)).has_tag("difficult"))
