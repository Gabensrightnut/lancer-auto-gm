extends TestCase
## The region map (WorldMapSession): walking in real time with travel time on the clock (the
## slowest mech while together, each one's own when split), ground mechs can't cross, entering a
## site's area and leaving it, and gathering.


func _region() -> Dictionary:
	var tiles := {}
	for x in range(10):
		for y in range(10):
			tiles["%d,%d" % [x, y]] = {"terrain": "plains", "cost": 4.0, "mech": true, "foot": true}
	tiles["5,5"] = {"terrain": "canyon", "cost": 4.0, "mech": false, "foot": true}
	return {"id": "valley", "size": [10, 10], "tiles": tiles,
		"sites": [{"id": "redwater", "kind": "town", "at": [1, 1], "area": {"place": "town", "at": [0, 0]}, "name": "Redwater"},
			{"id": "saltpan", "kind": "job", "at": [8, 1], "area": {"place": "wilds", "at": [3, 0]}, "name": "The Saltpan"}]}


func _run(m: WorldMapSession, seconds: float) -> void:
	for i in range(int(seconds * 10)):
		m.tick(0.1)


func test_travel_time_follows_the_slowest_mech_together() -> void:
	var m := WorldMapSession.new(_region())
	var hours: Array = []
	m.travelled.connect(func(group: Array, h: float) -> void: hours.append([group.size(), h]))
	m.add_seat("p1", Vector2(1, 1), 4)
	m.add_seat("p2", Vector2(1, 1), 6)
	m.walk_to("p1", Vector2i(5, 1))
	m.walk_to("p2", Vector2i(5, 1))
	_run(m, 3.0)
	var total := 0.0
	for h: Array in hours:
		total += float(h[1])
		expect_eq(int(h[0]), 2, "they travel as one group")
	expect(absf(total - 4.0) < 0.01, "4 tiles at cost 4 over Speed 4 (the slowest): 4 hours, got %s" % total)


func test_split_up_each_travels_at_its_own_speed() -> void:
	var m := WorldMapSession.new(_region())
	var per_seat := {}
	m.travelled.connect(func(group: Array, h: float) -> void:
		for s: String in group:
			per_seat[s] = float(per_seat.get(s, 0.0)) + h)
	m.add_seat("p1", Vector2(1, 1), 4)
	m.add_seat("p2", Vector2(1, 1), 8)
	m.walk_to("p1", Vector2i(1, 5))
	m.walk_to("p2", Vector2i(5, 1))
	_run(m, 3.0)
	expect(absf(float(per_seat.get("p1", 0.0)) - 4.0) < 0.01, "p1 alone: Speed 4")
	expect(absf(float(per_seat.get("p2", 0.0)) - 2.0) < 0.01, "p2 alone: Speed 8")
	expect(m.walk_to("p1", Vector2i(5, 5)) != "", "a mech can't cross the canyon")
	m.seats["p1"]["on"] = "foot"
	expect_eq(m.walk_to("p1", Vector2i(5, 5)), "", "a pilot on foot can")


func test_enter_and_leave_a_site_and_gather() -> void:
	var region := ExploreRegion.new(77, {"p1": {"name": "Ama", "side": Mission.PLAYERS}, "p2": {"name": "Rin", "side": Mission.PLAYERS}}, {"size": 30})
	var m := WorldMapSession.new(_region(), region)
	m.add_seat("p1", Vector2(1, 1), 4)
	m.add_seat("p2", Vector2(7, 7), 4)
	expect_eq(m.enter("p1"), "0,0", "into Redwater's area")
	expect(region.areas.has("0,0"))
	expect(m.walk_to("p1", Vector2i(3, 3)) != "", "inside a site: walk its area, not the map")
	m.leave("p1")
	expect_eq(m.seats["p1"]["in_area"], "")
	expect(m.tile_of(m.seats["p1"]["at"]) != Vector2i(1, 1), "back on the map beside the town")
	expect_eq(m.enter("p2"), "", "no site at 7,7")
	m.seats["p1"]["at"] = Vector2(8, 1)
	expect_eq(m.enter("p1"), "3,0", "the job site's area")
	m.gather("p1")
	expect_eq(m.seats["p2"]["in_area"], "3,0", "a story event pulls p2 to the lead")
	var v := m.view_for("p2")
	expect_eq(v["squad"].size(), 2)
	expect_eq(v["sites"].size(), 2)


## The real region data (WorldMapGen.region): start in town, walk to another site, go into its
## area (its own look from the region), and war regions bring ambushes and faction traffic.
func test_on_a_real_region() -> void:
	var r := WorldMapGen.region(41, {"name": "Saltpan", "culture": "old_west", "landscape": "grassy_hills", "start": true, "war": {"factions": ["STX", "Dawn"]}})
	var region := ExploreRegion.new(41, {"p1": {"name": "Ama", "side": Mission.PLAYERS}})
	var m := WorldMapSession.new(r, region, Dice.new(41))
	var start := Vector2(float(r["start"][0]), float(r["start"][1]))
	m.add_seat("p1", start, 4)
	var town := m.site_at(WorldMapSession.tile_of(start))
	expect(not town.is_empty() and str(town["kind"]) == "town", "the region starts in town: %s" % str(town))
	var other: Dictionary = {}
	for site: Dictionary in r["sites"]:
		if site["id"] != town.get("id", "") and m.walkable(Vector2i(int(site["at"][0]), int(site["at"][1])), "mech"):
			other = site
			break
	expect(not other.is_empty(), "somewhere else to walk to")
	var to := Vector2i(int(other["at"][0]), int(other["at"][1]))
	var hours := [0.0]
	m.travelled.connect(func(_g: Array, h: float) -> void: hours[0] += h)
	expect_eq(m.walk_to("p1", to), "")
	for i in range(400):
		m.tick(0.1)
		if WorldMapSession.tile_of(m.seats["p1"]["at"]) == to:
			break
	expect_eq(WorldMapSession.tile_of(m.seats["p1"]["at"]), to, "walked there")
	expect(hours[0] > 0.0, "the trip took time on the clock")
	var key := m.enter("p1")
	expect(key != "" and region.areas.has(key), "into the site's area")
	var spot_ids: Array = (r["ambush_spots"] as Array).map(func(a: Dictionary) -> String: return str(a["id"]))
	expect(m.ambushes.list.all(func(a: Dictionary) -> bool: return spot_ids.has(str(a["id"]))), "ambushers only where world put cover")
