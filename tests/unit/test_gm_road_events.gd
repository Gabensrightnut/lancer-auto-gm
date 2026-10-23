extends TestCase
## Road events (RoadEvents): rare, seeded on the story's dice, from the GM's tables.


func test_rare_seeded_and_buildable() -> void:
	var hits := 0
	var found := {}
	for seed_value in range(400):
		var d := Dice.new(seed_value)
		var e := RoadEvents.roll(d, 4.0)
		if not e.is_empty():
			hits += 1
			found[e["id"]] = true
	expect(hits > 10 and hits < 120, "a few trips in a hundred meet something: %d / 400" % hits)
	expect(found.size() == 3, "patrols, bandits and convoys all turn up: %s" % str(found.keys()))
	var a := RoadEvents.roll(Dice.new(12345), 30.0)
	var b := RoadEvents.roll(Dice.new(12345), 30.0)
	expect_eq(a, b, "the same dice, the same road")
	expect(RoadEvents.roll(Dice.new(1), 0.5).is_empty(), "less than an hour: nothing")
	var bandits := {}
	for e: Dictionary in RoadEvents.data()["events"]:
		if e["id"] == "bandits":
			bandits = e
	var units := RoadEvents.enemies(bandits, "road1_")
	expect_eq(units.size(), 3)
	expect(units.all(func(u: Unit) -> bool: return u.side == Mission.ENEMIES and u.controller == NetHost.GM_SEAT and u.id.begins_with("road1_")))
