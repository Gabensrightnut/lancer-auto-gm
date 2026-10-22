extends TestCase
## Real-time exploring (WorldSession): walking over the ground, followers, different players
## in different places, being called to a story event, fights and step mode.


func _world() -> WorldSession:
	var w := WorldSession.new()
	var town := BattleMap.flat(GridLayout.Shape.SQUARE, 20, 20)
	town.set_column(Vector2i(10, 5), 0, PackedStringArray([BattleMap.TAG_IMPASSABLE]))
	town.set_column(Vector2i(5, 10), 3)
	w.add_area("town", town, "Redwater")
	w.add_area("saltpan", BattleMap.flat(GridLayout.Shape.SQUARE, 20, 20), "the Saltpan")
	w.add_actor({"id": "ama", "kind": "pilot", "seat": "p1", "area": "town", "pos": Vector2(2, 5)})
	w.add_actor({"id": "rin", "kind": "pilot", "seat": "p2", "area": "town", "pos": Vector2(2, 8)})
	w.add_actor({"id": "kettle", "kind": "pilot", "seat": "p3", "area": "town", "pos": Vector2(1, 5), "ai": true, "leader": "ama"})
	return w


func _run(w: WorldSession, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		w.tick(0.1)


func test_walking_in_real_time_over_the_ground() -> void:
	var w := _world()
	expect_eq(w.move("p1", "ama", Vector2(8, 5)), "")
	_run(w, 1.0)
	var p: Vector2 = w.actors["ama"]["pos"]
	expect(p.x > 4.5 and p.x < 5.5, "about 3 spaces in a second on foot: %s" % p)
	_run(w, 3.0)
	expect(w.actors["ama"]["pos"].distance_to(Vector2(8, 5)) < 0.01, "arrived")
	expect(w.move("p1", "rin", Vector2(3, 3)) != "", "can't move someone else's pilot")
	expect(w.move("p1", "ama", Vector2(10, 5)) != "", "impassable ground")
	w.move("p1", "ama", Vector2(12, 5))
	_run(w, 3.0)
	expect(w.actors["ama"]["pos"].x < 9.6, "stopped at the wall: %s" % w.actors["ama"]["pos"])
	w.move("p2", "rin", Vector2(5, 8))
	w.actors["rin"]["target"] = Vector2(5, 11)
	_run(w, 2.0)
	expect(WorldSession.cell_at(w.areas["town"], w.actors["rin"]["pos"]) != Vector2i(5, 10), "too high a step to walk up")


func test_ai_squadmates_follow_or_stay() -> void:
	var w := _world()
	w.move("p1", "ama", Vector2(9, 5))
	_run(w, 4.0)
	var gap: float = w.actors["kettle"]["pos"].distance_to(w.actors["ama"]["pos"])
	expect(gap < 2.0, "the AI squadmate followed its human: %s" % gap)
	expect_eq(w.set_order("p1", "kettle", "stay"), "")
	w.move("p1", "ama", Vector2(2, 15))
	_run(w, 5.0)
	expect(w.actors["kettle"]["pos"].distance_to(Vector2(7.4, 5)) < 1.0, "told to stay, it stays")
	expect(w.set_order("p2", "kettle", "follow") != "", "only its human orders it")
	w.set_order("p1", "kettle", "follow")
	w.travel("ama", "saltpan", Vector2(4, 4))
	expect_eq(w.actors["kettle"]["area"], "saltpan", "followers travel with their human")


func test_players_in_different_places_see_only_their_own() -> void:
	var w := _world()
	w.travel("rin", "saltpan", Vector2(10, 10))
	var v1 := w.view_for("p1")
	var v2 := w.view_for("p2")
	expect_eq(v1["area"], "town")
	expect_eq(v2["area"], "saltpan")
	expect(not v1["actors"].any(func(a: Dictionary) -> bool: return a["id"] == "rin"), "p1 doesn't see where rin is standing")
	expect_eq(int(v1["squad_elsewhere"].get("the Saltpan", 0)), 1, "only that a squadmate is in the Saltpan")
	expect_eq(w.seats_in("town"), ["p1"])
	var e := w.call_to("saltpan", Vector2(5, 5), "the lander is opening")
	expect(str(e["text"]).contains("the Saltpan"), e["text"])
	expect_eq(w.actors["ama"]["area"], "town", "a prompt first, not a teleport")
	w.call_to("saltpan", Vector2(5, 5), "now", true)
	expect_eq(w.actors["ama"]["area"], "saltpan", "forced: everyone is pulled to it")


func test_fights_and_step_mode() -> void:
	var w := _world()
	w.set_mode("town", "combat", "enc1")
	expect(w.move("p1", "ama", Vector2(4, 5)) != "", "in a fight, moves take turns")
	w.set_mode("town", "step")
	expect_eq(w.move("p1", "ama", Vector2(4, 5)), "")
	expect_eq(w.actors["ama"]["pos"], Vector2(4, 5), "turn-based exploring: the move is taken at once")
	w.set_mode("town", "explore")
	var back := WorldSession.from_dict(w.to_dict())
	expect_eq(back.actors["ama"]["pos"], Vector2(4, 5), "saved")
	expect_eq(back.areas["town"]["name"], "Redwater")
