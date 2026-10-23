extends TestCase
## Ambushes on the world map (Ambushes, WorldMapSession): only in a region at war, hidden in real
## cover until spotted or sprung, a window to run, otherwise the fight starts where you're caught.


func _region(war: bool) -> Dictionary:
	var tiles := {}
	for x in range(20):
		for y in range(20):
			tiles["%d,%d" % [x, y]] = {"terrain": "plains", "cost": 4.0, "mech": true, "foot": true}
	var spots: Array = []
	for i in range(30):
		spots.append({"id": "s%d" % i, "at": [i % 20, 10], "cover": "tree line", "faction": "Dawn", "force": [{"template": "ph_grunt", "count": 2}]})
	return {"id": "front", "size": [20, 20], "tiles": tiles, "war": {"factions": ["STX", "Dawn"]} if war else null, "ambush_spots": spots}


func _one(m: WorldMapSession, at: Vector2) -> void:
	m.ambushes.list = [{"id": "a1", "at": at, "home": at, "cover": "tree line", "faction": "Dawn", "state": "hidden", "target": "", "enemies": [{"template": "ph_grunt", "count": 2}]}]


func _run(m: WorldMapSession, seconds: float) -> void:
	for i in range(int(seconds * 20)):
		m.tick(0.05)


func test_only_at_war_and_only_some_spots() -> void:
	expect(WorldMapSession.new(_region(false)).ambushes.list.is_empty(), "no war: no ambushes")
	var n := WorldMapSession.new(_region(true)).ambushes.list.size()
	expect(n > 2 and n < 20, "a few of the spots are manned: %d / 30" % n)


func test_spotted_before_they_spring() -> void:
	var m := WorldMapSession.new(_region(false))
	_one(m, Vector2(10, 10))
	m.add_seat("p1", Vector2(10, 4), 4, "mech", 30)  # a sharp-eyed pilot
	m.add_seat("p2", Vector2(1, 1), 4)
	var told: Array = []
	m.ambushes.spotted.connect(func(seat: String, _a: Dictionary, text: String) -> void: told.append([seat, text]))
	expect(m.view_for("p1")["ambushers"].is_empty(), "hidden at first")
	m.walk_to("p1", Vector2i(10, 7))
	_run(m, 2.0)
	expect(told.size() == 1 and told[0][1] == "Movement in the tree line ahead.", str(told))
	expect_eq(m.view_for("p1")["ambushers"].size(), 1, "the spotter sees them")
	expect(m.view_for("p2")["ambushers"].is_empty(), "not someone far away")


func test_caught_or_escaped() -> void:
	var m := WorldMapSession.new(_region(false))
	_one(m, Vector2(10, 10))
	m.add_seat("p1", Vector2(10, 8.5), 4)
	var caught: Array = []
	m.ambushes.caught.connect(func(seat: String, _a: Dictionary, at: Vector2) -> void: caught.append([seat, at]))
	_run(m, 2.0)
	expect(caught.size() == 1 and caught[0][0] == "p1", "standing still: caught, the fight starts there")
	expect((caught[0][1] as Vector2).distance_to(m.seats["p1"]["at"]) < 1.0, "with them where they caught you")
	expect(not m.view_for("p1")["ambushers"].is_empty(), "sprung: everyone sees them")

	var m2 := WorldMapSession.new(_region(false))
	_one(m2, Vector2(10, 10))
	m2.add_seat("p1", Vector2(10, 8.5), 4)
	m2.move("p1", Vector2(0, -1))  # WASD: run for it
	var got_away: Array = []
	var caught2: Array = []
	m2.ambushes.escaped.connect(func(seat: String, _a: Dictionary, _t: String) -> void: got_away.append(seat))
	m2.ambushes.caught.connect(func(seat: String, _a: Dictionary, _at: Vector2) -> void: caught2.append(seat))
	_run(m2, 3.0)
	expect(got_away == ["p1"] and caught2.is_empty(), "ran at once: got away, no fight")


func test_no_ambush_right_after_a_fight() -> void:
	var m := WorldMapSession.new(_region(false))
	_one(m, Vector2(10, 10))
	m.ambushes.fight_over()
	m.add_seat("p1", Vector2(10, 8.5), 4)
	_run(m, 2.0)
	expect(str(m.ambushes.list[0]["state"]) in ["hidden", "spotted"], "they let you pass right after a fight (you may still spot them)")
