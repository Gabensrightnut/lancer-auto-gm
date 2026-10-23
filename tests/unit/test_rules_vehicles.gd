extends TestCase
## Parked vehicles (Sight.TAG_VEHICLE): objects whose Size is the table's "vehicle_size"
## ruling; cover by Size (Core p.66) and obstruction by Size (Core p.62).

const F = preload("res://tests/unit/test_rules_fixtures.gd")
const SoldierTest = preload("res://tests/unit/test_rules_soldiers.gd")


static func street() -> GameState:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 12)
	s.map.set_column(Vector2i(5, 5), 0, PackedStringArray(["road", "vehicle", Sight.TAG_SOFT_COVER, BattleMap.TAG_DESTRUCTIBLE]))
	return s


func test_cover_behind_a_car_goes_by_size() -> void:
	var s := street()
	var shooter := F.mech(s, "m", "enemies", Vector2i(5, 1))
	var guard := Soldiers.build(SoldierTest.db(), "g", "soldier", "players", 1, s)
	guard.cell = Vector2i(5, 6)
	s.add_unit(guard)
	var c := Sight.unit_cover(s, shooter, guard)
	expect(c["los"], "a car doesn't block sight")
	expect_eq(c["cover"], "hard", "a person on foot next to a Size 1/2 car: hard cover")
	guard.cell = Vector2i(0, 0)
	var mech := F.mech(s, "t", "players", Vector2i(5, 6))
	expect_eq(Sight.unit_cover(s, shooter, mech)["cover"], "soft", "a mech behind a car: soft cover, like a low wall")
	s.rulings["vehicle_size"] = {"choice": "one"}
	expect_eq(Sight.unit_cover(s, shooter, mech)["cover"], "hard", "the table's other reading: a Size 1 car covers a Size 1 mech")
	s.rulings["vehicle_size"] = {"choice": "half"}
	# Shooting over your own car: no cover for the target out in the open.
	shooter.cell = Vector2i(5, 4)
	mech.cell = Vector2i(5, 10)
	expect_eq(Sight.unit_cover(s, shooter, mech)["cover"], "none", "it shoots over a car smaller than itself")


func test_cars_obstruct_by_size() -> void:
	var s := street()
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(5, 3))
	var guard := Soldiers.build(SoldierTest.db(), "g", "soldier", "players", 1, s)
	guard.cell = Vector2i(5, 7)
	s.add_unit(guard)
	F.mech(s, "foe", "enemies", Vector2i(11, 11))
	expect_eq(Movement._car(s, guard, Vector2i(5, 5), 0), Movement.CAR_BLOCKS, "a person on foot can't pass a car")
	expect_eq(Movement._car(s, m, Vector2i(5, 5), 0), Movement.CAR_PASS, "a mech passes over a smaller car")
	F.begin(e, s, m)
	var out := F.act(e, s, "move", "m", {"to": [5, 5]})
	expect(not F.ok(out) and F.reason(out).contains("parked vehicle"), F.reason(out))
	out = F.act(e, s, "move", "m", {"to": [5, 6]})
	expect(F.ok(out), "straight through to the far side: " + F.reason(out))
