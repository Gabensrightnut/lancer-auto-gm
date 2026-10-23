extends TestCase
## The compact arena for split-vote fights.


func test_arena_is_small_mirrored_and_ready() -> void:
	var a := PocketArena.build(3, {"landscape": "desert_mesas", "culture": "old_west", "shape": "square"})
	var map: BattleMap = a["map"]
	expect_eq(a["w"], 10, "about 10x10")
	expect_eq(PocketArena.build(3, {"mechs": 4})["w"], 12, "12x12 for four or more mechs")
	var cover := 0
	for c in map.cells():
		var m := Vector2i(9 - c.x, 9 - c.y)
		expect_eq(map.ground_height(c), map.ground_height(m), "mirrored at %s" % c)
		cover += 1 if map.ground_height(c) > 0 else 0
	expect(cover >= 2, "a little cover: %d" % cover)
	expect(not (a["deployment"][Mission.PLAYERS] as Array).is_empty() and not (a["deployment"][Mission.ENEMIES] as Array).is_empty(), "both sides deploy")
	expect(str(a["kit"]).begins_with("desert_mesas/old_west"), "in the local look")
