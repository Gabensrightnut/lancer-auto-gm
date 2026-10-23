extends TestCase
## Units inside buildings (Garrison): the book's cover rules at windows (Core p.66), and the
## "Garrisoned buildings" house rule (sharing room spaces, being caught in a collapse).

const F = preload("res://tests/unit/test_rules_fixtures.gd")
const SoldierTest = preload("res://tests/unit/test_rules_soldiers.gd")


## A one-room building at (5,5): a room with a roof `height` levels up, walls around it, a
## window on the south side (5,6) and a door on the north side (5,4).
static func building(height: int = 2) -> GameState:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 12)
	for c: Vector2i in [Vector2i(4, 4), Vector2i(6, 4), Vector2i(4, 5), Vector2i(6, 5), Vector2i(4, 6), Vector2i(6, 6)]:
		s.map.set_column(c, height, PackedStringArray(["building", "wall"]))
	s.map.set_column(Vector2i(5, 6), height, PackedStringArray(["building", "window"]))
	var door := s.map.set_column(Vector2i(5, 4), height, PackedStringArray(["building", "door"]))
	door.gap_bottom = 0
	door.gap_top = 1
	var room := s.map.set_column(Vector2i(5, 5), height, PackedStringArray(["building", "interior", "destructible", "name:warehouse"]))
	room.gap_bottom = 0
	room.gap_top = 1
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
	expect_eq(c["cover"], "hard", "next to the wall it shoots through: hard cover (Core p.66)")
	var out := Sight.unit_cover(s, sq, m)
	expect(out["los"] and out["cover"] == "none", "it shoots out without its own window obscuring the shot: %s" % out)
	# From the doorway the line to it is totally clear of hard cover: flanked, no cover.
	m.cell = Vector2i(5, 4)
	expect_eq(Sight.unit_cover(s, m, sq)["cover"], "none", "flanked from the door")
	# A plain wall instead of the window: no line of sight at all.
	s.map.column(Vector2i(5, 6)).tags = PackedStringArray(["building", "wall"])
	m.cell = Vector2i(5, 9)
	expect(not Sight.unit_cover(s, m, sq)["los"], "walls block sight")
	expect(not Movement.placement(s, 1.0, Vector2i(5, 6), 0)["ok"], "nobody walks through a window")


func test_room_spaces_hold_two_people_and_a_squad() -> void:
	var s := building()
	var e := RulesEngine.new()
	var sq := soldier(s, "sq", "guard_squad", "players", Vector2i(5, 5))
	var s1 := soldier(s, "s1", "soldier", "players", Vector2i(5, 2))
	soldier(s, "s2", "soldier", "players", Vector2i(4, 2))
	var m := F.mech(s, "m", "players", Vector2i(6, 2))
	F.mech(s, "foe", "enemies", Vector2i(11, 11))
	expect(Garrison.fits([sq, s1]) and not Garrison.fits([sq, m]), "the capacity rule")
	expect(not Garrison.fits([sq, s1, s.unit("s2"), soldier(s, "s3", "soldier", "players", Vector2i(0, 0))]), "no more than two people and a squad")
	F.begin(e, s, s1)
	var out := F.act(e, s, "move", "s1", {"to": [5, 5]})
	expect(F.ok(out), "in through the door to share the room: " + F.reason(out))
	expect(Garrison.inside(s, s1), "inside")
	F.act(e, s, "end_turn", "s1")
	s.turn_side = "players"
	F.act(e, s, "start_turn", "m")
	out = F.act(e, s, "move", "m", {"to": [5, 5]})
	expect(not F.ok(out), "a Size 1 mech can't share with a squad")
	# House rule off: the book's rule, nobody ends a move in an occupied space (Core p.62).
	s.house_rules[Garrison.HOUSE_RULE] = false
	expect(not Garrison.may_share(s, m, Sight.make_body(s, Vector2i(5, 5), 0, 0.5), []), "off: no sharing")


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


func test_standing_on_a_destroyed_building_falls_by_the_book() -> void:
	var s := building(6)
	var m := F.mech(s, "m", "players", Vector2i(5, 5))
	m.level = 6
	TerrainDamage.destroy_sections(s, Vector2i(5, 5), 6, "test")
	expect(m.counters.get("falling", false), "nothing under it: it falls (Core p.63)")


func test_ai_seeks_windows_by_role() -> void:
	var ai := TacticsAi.new()
	expect(float(TacticsAi.priority(ai.priorities, "defender", "sitrep_holdout").get("garrison", 0)) > 1.0, "defenders hold buildings")
	expect_eq(float(TacticsAi.priority(ai.priorities, "striker", "").get("garrison", 0)), 0.0, "strikers don't")
