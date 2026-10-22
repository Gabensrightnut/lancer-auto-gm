extends TestCase
## Rooftops on real buildings: standing room by Size, getting up (climb, jump, fly), being
## knocked off an edge and the fall (Core p.62-63 movement and falling; glossary: Falling).

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine


func _building(cells: Array, height: int) -> void:
	for c: Vector2i in cells:
		s.map.set_column(c, height, PackedStringArray(["building"]))


func _setup() -> void:
	s = F.state()
	e = RulesEngine.new()


func test_roof_room_by_size() -> void:
	_setup()
	_building([Vector2i(5, 5)], 2)
	expect(Movement.placement(s, 0.5, Vector2i(5, 5), 2)["ok"], "Size 1/2 fits a 1-wide roof")
	expect(Movement.placement(s, 1.0, Vector2i(5, 5), 2)["ok"], "Size 1 fits a 1-wide roof")
	var big := Movement.placement(s, 2.0, Vector2i(5, 5), 2)
	expect(not big["standing"] and big["uneven"], "Size 2 is only partly on a 1-wide roof")
	var m2 := F.mech(s, "m2", "players", Vector2i(3, 3), 2.0)
	m2.speed = 20
	var land := Movement.plan(s, m2, Vector2i(5, 5), 2)
	expect(not land["ok"], "no partial footprints: it can't climb up and stand there (table ruling, suggested: forbid)")
	_building([Vector2i(8, 1), Vector2i(9, 1), Vector2i(8, 2), Vector2i(9, 2)], 2)
	expect(Movement.placement(s, 2.0, Vector2i(8, 1), 2)["standing"], "Size 2 on a 2-wide roof")
	var three := Movement.placement(s, 3.0, Vector2i(8, 1), 2)
	expect(not three["standing"], "Size 3 needs a 3-wide roof")
	var cells: Array = []
	for x in range(0, 3):
		for y in range(8, 11):
			cells.append(Vector2i(x, y))
	_building(cells, 2)
	expect(Movement.placement(s, 3.0, Vector2i(0, 8), 2)["standing"], "Size 3 on a 3-wide roof")


func test_getting_onto_a_two_tall_building() -> void:
	_setup()
	_building([Vector2i(3, 0)], 2)
	var a := F.mech(s, "a", "players", Vector2i(2, 0))
	a.speed = 5
	F.mech(s, "foe", "enemies", Vector2i(11, 11))
	F.begin(e, s, a)
	var plan := Movement.plan(s, a, Vector2i(3, 0), 2)
	expect(plan["ok"], "climbing works: %s" % plan["reason"])
	expect_eq(plan["cost"], 5, "1 for the step plus 2 per level climbed (climbing is half speed)")
	a.speed = 4
	var short := Movement.plan(s, a, Vector2i(3, 0), 2)
	expect(not short["ok"], "speed 4 can't climb it in one move")
	expect(short.get("unreachable_roof", false) and String(short["reason"]).contains("roof"), "the arrow says why: " + String(short["reason"]))
	var jump := F.act(e, s, "jump", "a", {"to": [3, 0], "vertical": true})
	expect(not F.ok(jump), "a vertical jump only reaches 1 up")
	a.flight = "flight"
	var fp := Movement.plan(s, a, Vector2i(3, 0), 2, Movement.MODE_MOVE, true)
	expect(fp["ok"], "a flyer can land on it: " + String(fp["reason"]))


func test_knocked_off_a_roof_falls() -> void:
	_setup()
	_building([Vector2i(4, 0), Vector2i(5, 0)], 6)
	var a := F.mech(s, "a", "players", Vector2i(4, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	t.max_hp = 20
	t.hp = 20
	F.begin(e, s, a)
	var ev := Attacks.knock_back(s, t, a.cell, 2, a)
	expect_eq(t.cell, Vector2i(7, 0), "pushed straight off the edge")
	expect(F.events_of({"events": ev}, "falling").size() == 1, "it begins falling")
	var out := F.act(e, s, "end_turn", "a")
	expect_eq(t.level, 0, "falls at the end of the turn")
	expect_eq(t.hp, 14, "6 spaces: 6 AP kinetic (3 per 3 spaces, at most 9)")
	expect(not t.has_status("Stunned"), "no Stun from a fall (not in the book)")


func test_flyers_dont_fall() -> void:
	_setup()
	_building([Vector2i(4, 0), Vector2i(5, 0)], 6)
	var a := F.mech(s, "a", "players", Vector2i(4, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	t.flight = "flight"
	t.flying = true
	F.begin(e, s, a)
	Attacks.knock_back(s, t, a.cell, 2, a)
	F.act(e, s, "end_turn", "a")
	expect_eq(t.level, 6, "still flying")
