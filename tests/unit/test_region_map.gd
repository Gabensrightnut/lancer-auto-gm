extends TestCase
## The walkable region map (world map): tiles with travel times, places on roads, each tile
## stepping into its matching area.


func _region() -> Dictionary:
	return {"seed": 41, "landscape": "grassy_hills", "culture": "old_west", "weather": "", "name": "Saltpan"}


func test_same_seed_same_region() -> void:
	var a := RegionMap.build(_region(), {"start": true})
	var b := RegionMap.build(_region(), {"start": true})
	expect_eq(JSON.stringify(a["tiles"]), JSON.stringify(b["tiles"]), "the region seed fixes the map")
	var other := _region()
	other["seed"] = 42
	expect(JSON.stringify(RegionMap.build(other)["tiles"]) != JSON.stringify(a["tiles"]), "another seed, another region")


func test_starting_region_has_first_jobs_close_by() -> void:
	var rm := RegionMap.build(_region(), {"start": true})
	var town := Vector2i(rm["start"][0], rm["start"][1])
	var near := {}
	for p: Dictionary in rm["places"]:
		var at := Vector2i(p["at"][0], p["at"][1])
		if p["kind"] in ["farm", "wreck", "outpost", "landmark"] and maxi(absi(at.x - town.x), absi(at.y - town.y)) <= 3:
			near[p["kind"]] = true
	expect_eq(near.size(), 4, "a farm, a wreck, an outpost and a landmark within walking distance: %s" % [near.keys()])
	for p: Dictionary in rm["places"]:
		if p["id"] == "town":
			continue
		var hours := RegionMap.travel_hours(rm, town, Vector2i(p["at"][0], p["at"][1]))
		expect(hours > 0.0, "%s can be reached on the road" % p["id"])


func test_tiles_step_into_matching_areas() -> void:
	var rm := RegionMap.build(_region(), {"start": true})
	var town := Vector2i(rm["start"][0], rm["start"][1])
	var o := RegionMap.area_opts(rm, town.x, town.y)
	expect_eq(o["place"], "town", "the town tile is the town's area")
	expect_eq(o["at"], [town.x, town.y])
	var road_tile := Vector2i(-1, -1)
	for r: Array in rm["roads"]:
		var is_place := false
		for p: Dictionary in rm["places"]:
			is_place = is_place or (int(p["at"][0]) == int(r[0]) and int(p["at"][1]) == int(r[1]))
		if not is_place:
			road_tile = Vector2i(r[0], r[1])
			break
	expect_eq(RegionMap.area_opts(rm, road_tile.x, road_tile.y)["place"], "road", "a road tile is open road")
	var a := MissionGenerator.area(1, RegionMap.area_opts(rm, road_tile.x, road_tile.y).merged({"shape": "square", "size": 30}))
	expect(a.has("map") and a["at"] == [road_tile.x, road_tile.y], "and it builds")
	expect(rm["mech_blocked"].has("water") and float(rm["travel"]["road"]) < float(rm["travel"]["forest"]), "roads are fastest; mechs can't wade the deep water")


func test_net_shape() -> void:
	var r := WorldMapGen.region(41, {"name": "Saltpan", "culture": "old_west", "landscape": "desert_mesas", "start": true})
	expect(r.has("tiles") and r.has("sites") and r.has("ambush_spots") and r.has("war"), "net's fields")
	var t: Dictionary = r["tiles"]["0,0"]
	expect(t.has("terrain") and t.has("cost") and t.has("mech") and t.has("foot"), "each tile: terrain, cost, mech, foot")
	var kinds := {}
	for s: Dictionary in r["sites"]:
		kinds[s["kind"]] = true
		expect(s["area"].has("place") and s["area"].has("at") and s["area"].has("region"), "a site's area feeds MissionGenerator.area()")
	expect(kinds.has("town") and kinds.has("job") and kinds.has("landmark"), "towns, jobs and landmarks: %s" % [kinds.keys()])


func test_war_regions_have_ambushes_in_cover() -> void:
	var r := WorldMapGen.region(41, {"name": "Saltpan", "culture": "old_west", "landscape": "grassy_hills", "start": true,
		"war": {"factions": ["Harrison Armory", "IPS-Northstar"]}})
	expect(not (r["ambush_spots"] as Array).is_empty(), "ambushes along the routes")
	for a: Dictionary in r["ambush_spots"]:
		expect(a["cover"] in ["forest", "hills", "urban", "mountain", "grass", "jungle", "ruins"] and a["faction"] in ["Harrison Armory", "IPS-Northstar"], "in cover, by a warring faction: %s" % [a])
	var spot: Dictionary = r["ambush_spots"][0]
	var g := MissionGenerator.generate(5, {"ambush": spot, "landscape": "grassy_hills", "players": 2})
	var m: Mission = g["mission"]
	expect(m.first_side == Mission.ENEMIES and not (m.deployment[Mission.ENEMIES] as Array).is_empty(), "the ambushers start in their cover and go first")
	expect(not WorldMapGen.region(41, {"name": "x", "landscape": "grassy_hills"}).has("war") or WorldMapGen.region(41, {"name": "x", "landscape": "grassy_hills"})["ambush_spots"].is_empty(), "no war, no ambushes")
