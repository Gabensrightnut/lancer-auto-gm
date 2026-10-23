extends TestCase
## Units inside buildings (Garrison): the book's cover rules at windows (Core p.66), and the
## "Garrisoned buildings" house rule (rooms, doors, sharing room spaces, collapses).

const F = preload("res://tests/unit/test_rules_fixtures.gd")
const SoldierTest = preload("res://tests/unit/test_rules_soldiers.gd")


## A two-cell building at (5,5)-(6,5), `height` levels tall, tagged the way the world's
## TerrainGen tags buildings: "interior", a window on every outside face, the door on (5,5)'s
## north face (face 2 in SquareGrid's neighbor order).
static func building(height: int = 2) -> GameState:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 12)
	var cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	for c in cells:
		var tags := PackedStringArray(["building", "interior", "storeys_%d" % height, "destructible", "name:warehouse"])
		var ns := s.map.grid.neighbors(c)
		for i in range(ns.size()):
			if not cells.has(ns[i]):
				tags.append("window_%d" % i)
		if c == Vector2i(5, 5):
			tags.append_array(["entrance", "door_face_2"])
		s.map.set_column(c, height, tags)
	Garrison.sync(s)
	return s


static func soldier(s: GameState, id: String, kind: String, side: String, cell: Vector2i) -> Unit:
	var u := Soldiers.build(SoldierTest.db(), id, kind, side, 1, s)
	u.cell = cell
	s.add_unit(u)
	return u


func test_a_window_is_hard_cover_you_can_shoot_through() -> void:
	var s := building()
	var sq := soldier(s, "sq", "rifle_squad", "players", Vector2i(5, 5))
	var m := F.mech(s, "m", "enemies", Vector2i(5, 9))
	var c := Sight.unit_cover(s, m, sq)
	expect(c["los"], "seen through the window")
	expect_eq(c["cover"], "hard", "at a window in a wall: hard cover (Core p.66)")
	var out := Sight.unit_cover(s, sq, m)
	expect(out["los"] and out["cover"] == "none", "it shoots out without its own window obscuring the shot: %s" % out)
	# Through the open door the line is totally clear of hard cover: flanked, no cover.
	m.cell = Vector2i(5, 2)
	expect_eq(Sight.unit_cover(s, m, sq)["cover"], "none", "flanked through the door")
	# No window on that face: no line of sight at all.
	var col := s.map.column(Vector2i(5, 5))
	var tags := col.tags
	tags.remove_at(tags.find("window_6"))
	col.tags = tags
	m.cell = Vector2i(5, 9)
	expect(not Sight.unit_cover(s, m, sq)["los"], "walls block sight")
	# House rule off: a building is solid, as in the book; nobody is inside.
	s.house_rules[Garrison.HOUSE_RULE] = false
	Garrison.sync(s)
	expect(not Movement.placement(s, 0.5, Vector2i(5, 5), 0)["ok"], "off: no room inside")


func test_room_spaces_hold_two_people_and_a_squad() -> void:
	var s := building()
	var e := RulesEngine.new()
	var sq := soldier(s, "sq", "guard_squad", "players", Vector2i(5, 5))
	var s1 := soldier(s, "s1", "soldier", "players", Vector2i(5, 2))
	var m := F.mech(s, "m", "players", Vector2i(6, 2))
	F.mech(s, "foe", "enemies", Vector2i(11, 11))
	expect(Garrison.fits([sq, s1]) and not Garrison.fits([sq, m]), "the capacity rule")
	var s2 := soldier(s, "s2", "soldier", "players", Vector2i(0, 0))
	var s3 := soldier(s, "s3", "soldier", "players", Vector2i(0, 1))
	expect(not Garrison.fits([sq, s1, s2, s3]), "no more than two people and a squad")
	expect(Garrison.step_ok(s.map, Vector2i(5, 4), 0, Vector2i(5, 5), 0), "in through the door")
	expect(not Garrison.step_ok(s.map, Vector2i(5, 6), 0, Vector2i(5, 5), 0), "not through a window")
	expect(Garrison.step_ok(s.map, Vector2i(5, 5), 0, Vector2i(6, 5), 0), "between the building's own rooms")
	F.begin(e, s, s1)
	var out := F.act(e, s, "move", "s1", {"to": [5, 5]})
	expect(F.ok(out), "in through the door to share the room: " + F.reason(out))
	expect(Garrison.inside(s, s1), "inside")
	F.act(e, s, "end_turn", "s1")
	s.turn_side = "players"
	F.act(e, s, "start_turn", "m")
	out = F.act(e, s, "move", "m", {"to": [5, 5]})
	expect(not F.ok(out), "a Size 1 mech can't share with a squad")


func test_a_collapse_lands_on_everyone_inside() -> void:
	var s := building(6)
	var sq := soldier(s, "sq", "rifle_squad", "players", Vector2i(5, 5))
	var s1 := soldier(s, "s1", "soldier", "players", Vector2i(5, 5))
	var ev := TerrainDamage.destroy_sections(s, Vector2i(5, 5), 6, "test")
	var col: Array = ev.filter(func(x: Dictionary) -> bool: return x["type"] == "building_collapsed")
	expect(not col.is_empty(), "the building came down")
	if col.is_empty():
		return
	var caught: Array = col[0]["caught"]
	expect_eq(caught.size(), 2)
	expect_eq(caught[0]["text"], "The warehouse came down on Rifle Squad: 6 kinetic, like a 6-space fall.")
	expect_eq(sq.hp, 4, "6 armor-piercing kinetic, the book's damage for a 6-space fall")
	expect(s1.destroyed, "a single soldier doesn't survive it")
	expect_eq([sq.cell, sq.level], [Vector2i(5, 5), 0], "the rubble is free ground now: it stays put")
	expect(not s.map.column(Vector2i(5, 5)).has_tag("interior"), "no room left")


func test_standing_on_a_destroyed_building_falls_by_the_book() -> void:
	var s := building(6)
	var m := F.mech(s, "m", "players", Vector2i(6, 5))
	m.level = 6
	TerrainDamage.destroy_sections(s, Vector2i(6, 5), 6, "test")
	expect(m.counters.get("falling", false), "nothing under it: it falls (Core p.63)")


func test_ai_seeks_windows_by_role() -> void:
	var ai := TacticsAi.new()
	expect(float(TacticsAi.priority(ai.priorities, "defender", "sitrep_holdout").get("garrison", 0)) > 1.0, "defenders hold buildings")
	expect_eq(float(TacticsAi.priority(ai.priorities, "striker", "").get("garrison", 0)), 0.0, "strikers don't")
