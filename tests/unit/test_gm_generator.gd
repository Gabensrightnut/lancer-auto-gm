extends TestCase
## Mission generation and sitrep scoring.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _gen(mission_seed: int, opts: Dictionary = {}) -> Dictionary:
	opts["db"] = MissionTest.db()
	return MissionGenerator.generate(mission_seed, opts)


func test_same_seed_same_mission() -> void:
	var a := _gen(42)
	var b := _gen(42)
	expect_eq(JSON.stringify(a["state"].to_dict()), JSON.stringify(b["state"].to_dict()))
	expect_eq(JSON.stringify(a["mission"].to_dict()), JSON.stringify(b["mission"].to_dict()))
	var c := _gen(43)
	expect(JSON.stringify(c["state"].map.to_dict()) != JSON.stringify(a["state"].map.to_dict()), "another seed, another map")


func test_map_is_grassy_hills_in_size_range() -> void:
	for mission_seed in [1, 2, 3]:
		var s: GameState = _gen(mission_seed, {"landscape": "grassy_hills"})["state"]
		var n := s.map.cells().size()
		expect(n >= 30 * 30 and n <= 60 * 60, "size %d" % n)
		var heights := {}
		var soft := 0
		var difficult := 0
		for c in s.map.cells():
			heights[s.map.ground_height(c)] = true
			soft += 1 if s.map.column(c).has_tag(Sight.TAG_SOFT_COVER) else 0
			difficult += 1 if s.map.column(c).has_tag(BattleMap.TAG_DIFFICULT) else 0
		expect(heights.size() >= 3, "rolling hills: several heights")
		expect(soft > 0 and difficult > 0, "woods and difficult ground")


func test_every_landscape_has_terrain_to_fight_over() -> void:
	for land: String in TerrainGen.LANDSCAPES:
		for mission_seed in [11, 12]:
			var g := _gen(mission_seed, {"landscape": land})
			var s: GameState = g["state"]
			var m: Mission = g["mission"]
			expect(str(m.flavor.get("kit", "")).begins_with(land), "%s kit %s" % [land, m.flavor.get("kit", "")])
			var cover := 0
			var difficult := 0
			for c in s.map.cells():
				var col := s.map.column(c)
				cover += 1 if col.ground >= 2 or col.has_tag(Sight.TAG_SOFT_COVER) else 0
				difficult += 1 if col.has_tag(BattleMap.TAG_DIFFICULT) else 0
			expect(cover > 10, "%s has cover (%d)" % [land, cover])
			expect(difficult > 0, "%s has difficult ground" % land)
			# Deployment ground stays low and safe.
			for side: String in m.deployment:
				for c: Array in m.deployment[side]:
					var col := s.map.column(Vector2i(c[0], c[1]))
					expect(col.ground <= 1 and not col.has_tag(BattleMap.TAG_DANGEROUS) and not col.has_tag(BattleMap.TAG_IMPASSABLE), "%s deploy %s is safe" % [land, c])


func test_forces_are_legal_and_deployed_in_their_zones() -> void:
	var g := _gen(7, {"players": 3, "sitrep": "sitrep_standardcombat"})
	var s: GameState = g["state"]
	var m: Mission = g["mission"]
	var players := s.units_on_side("players")
	expect_eq(players.size(), 3)
	expect(s.units_on_side("enemies").size() >= 3, "an encounter to fight")
	for side in ["players", "enemies"]:
		var zone := {}
		for c: Array in m.deployment[side]:
			zone[Vector2i(c[0], c[1])] = true
		for u in s.units_on_side(side):
			expect(zone.has(u.cell), "%s deploys in its zone" % u.id)
			expect_eq(u.level, s.map.ground_height(u.cell), "%s stands on the ground" % u.id)
	for u in players:
		expect(s.seats.has(u.controller), "each mech has a seat")
		expect(not u.loadout.get("weapons", []).is_empty())
	expect(s.seats["gm"].get("gm", false))
	expect(m.briefing != "")


func test_difficulty_scales_the_encounter() -> void:
	var easy := _gen(5, {"settings": GmSettings.from_preset("Teaching"), "sitrep": "sitrep_standardcombat"})
	var hard := _gen(5, {"settings": GmSettings.from_preset("Ruthless"), "sitrep": "sitrep_standardcombat"})
	expect(hard["state"].units_on_side("enemies").size() > easy["state"].units_on_side("enemies").size())


func test_sitrep_zones() -> void:
	var c: Mission = _gen(3, {"sitrep": "sitrep_control"})["mission"]
	expect_eq(c.zones.size(), 4, "four control zones")
	expect_eq(c.rounds, 6)
	expect_eq(c.sitrep_name, "Control")
	for z: Array in c.zones.values():
		expect_eq(z.size(), 16, "4x4 spaces")
	var h: Mission = _gen(3, {"sitrep": "sitrep_holdout"})["mission"]
	expect_eq(h.zones["zone"].size(), 50, "10x5 holdout zone")
	expect_eq(h.deployment["players"], h.zones["zone"], "PCs deploy in the zone")
	var gt: Mission = _gen(3, {"sitrep": "sitrep_gauntlet"})["mission"]
	expect_eq(gt.deployment["enemies"], gt.zones["zone"], "the zone is the enemy deployment zone")
	expect_eq(gt.rounds, 8)


# --- Scoring (sitrep text, data/lancer-data/sitreps.json) -------------------------------------

func _scoring_state(m: Mission) -> GameState:
	var s := RulesFixtures.state(GridLayout.Shape.SQUARE, 20, 20)
	m.zones = {"zone_1": [[0, 0]], "zone_2": [[5, 0]], "zone_3": [[10, 0]], "zone_4": [[15, 0]], "zone": [[2, 2], [3, 2], [4, 2]]}
	return s


static func _round_over(m: Mission, s: GameState, r: int) -> void:
	m.observe(s, [{"type": "round_started", "round": r + 1}])


func test_control_scoring() -> void:
	var m := Mission.new()
	m.sitrep_id = "sitrep_control"
	m.rounds = 6
	var s := _scoring_state(m)
	m.zones.erase("zone")
	RulesFixtures.mech(s, "p1", "players", Vector2i(0, 0))
	RulesFixtures.mech(s, "p2", "players", Vector2i(5, 0))
	RulesFixtures.mech(s, "p3", "players", Vector2i(10, 0))
	RulesFixtures.mech(s, "e1", "enemies", Vector2i(10, 0))  # contested
	RulesFixtures.mech(s, "e2", "enemies", Vector2i(15, 0))
	_round_over(m, s, 1)
	expect_eq(m.scores, {"players": 2, "enemies": 1})
	s.unit("e1").destroyed = true
	s.unit("e2").cell = Vector2i(19, 19)
	s.unit("e2").destroyed = false
	RulesFixtures.mech(s, "p4", "players", Vector2i(15, 0))
	_round_over(m, s, 2)
	expect_eq(m.scores["players"], 2 + 4 + 1, "all four zones: +1")
	expect_eq(m.outcome, "")
	for r in range(3, 7):
		_round_over(m, s, r)
	expect_eq(m.outcome, "players")


func test_holdout_scoring() -> void:
	var m := Mission.new()
	m.sitrep_id = "sitrep_holdout"
	m.rounds = 6
	var s := _scoring_state(m)
	RulesFixtures.mech(s, "p1", "players", Vector2i(10, 10))
	for i in range(3):
		RulesFixtures.mech(s, "e%d" % i, "enemies", Vector2i(2 + i, 2))
	_round_over(m, s, 5)
	expect_eq(m.outcome, "", "decided at the end of round 6")
	_round_over(m, s, 6)
	expect_eq(m.scores["players"], 1)
	expect_eq(m.outcome, "players", "4 - 3 enemies = 1: the squad holds")
	var m2 := Mission.new()
	m2.sitrep_id = "sitrep_holdout"
	m2.rounds = 6
	var s2 := _scoring_state(m2)
	RulesFixtures.mech(s2, "p1", "players", Vector2i(10, 10))
	for i in range(3):
		RulesFixtures.mech(s2, "e%d" % i, "enemies", Vector2i(2 + i, 2))
	RulesFixtures.mech(s2, "e9", "enemies", Vector2i(3, 2))
	s2.unit("e9").cell = Vector2i(2, 2)  # Overlap is fine for counting.
	_round_over(m2, s2, 6)
	expect_eq(m2.outcome, "enemies", "4 - 4 = 0")


func test_gauntlet_and_wipeout() -> void:
	var m := Mission.new()
	m.sitrep_id = "sitrep_gauntlet"
	m.rounds = 8
	var s := _scoring_state(m)
	RulesFixtures.mech(s, "p1", "players", Vector2i(2, 2))
	RulesFixtures.mech(s, "p2", "players", Vector2i(3, 2))
	RulesFixtures.mech(s, "e1", "enemies", Vector2i(4, 2))
	_round_over(m, s, 8)
	expect_eq(m.outcome, "players", "2 PCs vs 1 enemy in the zone")
	var m2 := Mission.new()
	m2.sitrep_id = "sitrep_standardcombat"
	var s2 := _scoring_state(m2)
	RulesFixtures.mech(s2, "p1", "players", Vector2i(2, 2))
	var e := RulesFixtures.mech(s2, "e1", "enemies", Vector2i(9, 9))
	m2.observe(s2, [])
	expect_eq(m2.outcome, "")
	e.destroyed = true
	m2.observe(s2, [])
	expect_eq(m2.outcome, "players")
	var m3 := Mission.from_dict(m2.to_dict())
	expect_eq(m3.outcome, "players")


func test_names_and_flavor_come_from_the_compcon_lists() -> void:
	var g := _gen(42)
	var m: Mission = g["mission"]
	var s: GameState = g["state"]
	var names := NameGen.new(RandomNumberGenerator.new())
	expect(m.flavor["operation"].begins_with("OPERATION "), m.flavor["operation"])
	expect(m.flavor["planet"] in names.lines("planets.txt"))
	expect(m.flavor["faction"] in names.lines("factions.txt"))
	expect(m.briefing.contains(m.flavor["operation"]))
	var callsigns := names.lines("callsigns.txt")
	var seen := {}
	for u in s.units_on_side("players"):
		expect(u.name in callsigns, "%s is a callsign" % u.name)
		expect(not seen.has(u.name), "no two pilots share a callsign")
		seen[u.name] = true
		var seat: Dictionary = s.seats[u.controller]
		expect(seat["pilot"].split(" ").size() >= 2, "full pilot name: %s" % seat["pilot"])
		expect(seat["mech"].contains("Everest"), seat["mech"])
	expect_eq(_gen(42)["mission"].flavor, m.flavor, "same seed, same names")


func test_bigger_maps_scale_with_the_squad_and_keep_deployment_close() -> void:
	var cfg := GmSettings.load_json(GmSettings.MISSIONS_FILE)
	var small := MissionGenerator.map_size(RandomNumberGenerator.new(), cfg, 1, "sitrep_standardcombat")
	var big := MissionGenerator.map_size(RandomNumberGenerator.new(), cfg, 4, "sitrep_standardcombat")
	expect(big.x * big.y > small.x * small.y, "4 players get a bigger map than 1 (%s vs %s)" % [big, small])
	for sitrep: String in ["sitrep_standardcombat", "sitrep_escort", "sitrep_control"]:
		for p in range(1, 5):
			var wh := MissionGenerator.map_size(RandomNumberGenerator.new(), cfg, p, sitrep)
			expect(wh.x >= 30 and wh.x <= 60 and wh.y >= 30 and wh.y <= 60, "%s %d players: %s" % [sitrep, p, wh])
	var esc := MissionGenerator.map_size(RandomNumberGenerator.new(), cfg, 4, "sitrep_escort")
	expect(esc.y > esc.x, "an escort map is longer than wide: %s" % esc)
	# The approach dial keeps the zones close on a 60-long map.
	var lay := SitrepLayout.layout("sitrep_standardcombat", 50, 60, GridLayout.Shape.SQUARE, RandomNumberGenerator.new(), 14)
	var rows := func(side: String) -> Array:
		var r: Array = []
		for c: Array in lay["deployment"][side]:
			r.append(int(c[1]))
		return r
	var gap: int = (rows.call("players") as Array).min() - (rows.call("enemies") as Array).max() - 1
	expect(gap <= 14, "deployment zones at most 14 rows apart on a 60-row map (%d)" % gap)


func test_a_fight_in_town_uses_the_hub() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hub := {"kind": "town", "culture": "old_west", "seed": 5, "spots": HubLayout.spots("town", rng)}
	var g := _gen(31, {"hub": hub, "sitrep": "sitrep_standardcombat", "players": 2})
	var s: GameState = g["state"]
	var m: Mission = g["mission"]
	expect(str(m.flavor["kit"]).contains("old_west"), "the hub's culture: %s" % m.flavor["kit"])
	var buildings := 0
	for c in s.map.cells():
		var col := s.map.column(c)
		if col.has_tag("building"):
			buildings += 1
			expect(col.ground >= 1 and col.ground <= 2, "small-town buildings are 1-2 levels")
			expect(col.has_tag(BattleMap.TAG_DESTRUCTIBLE), "and can be knocked down")
			expect(col.has_tag("material_wood") and col.has_tag("armor_0"), "Old West wood: no Armor (Core p.68)")
	expect(buildings > 20, "the town's buildings take up their spaces (%d)" % buildings)


func test_materials_follow_the_culture() -> void:
	var want := {"medieval": ["stone", "armor_1"], "union": ["fortified", "armor_3"], "cyberpunk": ["concrete", "armor_1"]}
	for culture: String in want:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2
		var map := TerrainGen.generate(rng, 30, 30, GridLayout.Shape.SQUARE, {}, "city", culture)
		var seen := false
		for c in map.cells():
			var col := map.column(c)
			if col.has_tag("building"):
				expect(col.has_tag("material_" + want[culture][0]) and col.has_tag(want[culture][1]), "%s building %s: %s" % [culture, c, col.tags])
				seen = true
				break
		expect(seen, "%s has buildings" % culture)
	var rng2 := RandomNumberGenerator.new()
	var ship := TerrainGen.generate(rng2, 30, 30, GridLayout.Shape.SQUARE, {}, "starship", "")
	for c in ship.cells():
		if ship.column(c).has_tag("bulkhead"):
			expect(ship.column(c).has_tag("armor_4"), "starship hull: Armor 4")
			break



func test_story_town_opts_are_understood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var spots := HubLayout.spots("town", rng)
	var town := {"hub_id": "hub_9", "kind": "town", "culture": "medieval_tech", "map_culture": "medieval",
		"landscape": "tundra", "seed": 9, "spots": spots, "at": "bar", "on_foot": true}
	var g := _gen(44, {"town": town, "sitrep": "sitrep_standardcombat", "players": 2})
	var m: Mission = g["mission"]
	expect(str(m.flavor["kit"]).begins_with("tundra/medieval"), "town landscape and culture: %s" % m.flavor["kit"])
	var s: GameState = g["state"]
	var buildings := 0
	for c in s.map.cells():
		if s.map.column(c).has_tag("building"):
			buildings += 1
	expect(buildings > 15, "the town's buildings (%d)" % buildings)


func test_maps_are_built_on_purpose() -> void:
	# A medieval valley: a castle (keep, walls, moat), a village with houses, roads and fields;
	# rocks stay off the roads.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var map := TerrainGen.generate(rng, 40, 34, GridLayout.Shape.SQUARE, {}, "grassy_hills", "medieval")
	var count := {}
	for c in map.cells():
		for tag: String in ["keep", "wall", "water", "house", "road", "farm", "rock"]:
			if map.column(c).has_tag(tag):
				count[tag] = int(count.get(tag, 0)) + 1
	expect(int(count.get("keep", 0)) == 9, "a 3x3 keep: %s" % count)
	expect(int(count.get("wall", 0)) >= 24, "curtain walls and towers: %s" % count)
	expect(int(count.get("water", 0)) >= 20, "a moat: %s" % count)
	expect(int(count.get("house", 0)) >= 8 and int(count.get("road", 0)) >= 20, "a village on its streets: %s" % count)
	expect(int(count.get("farm", 0)) > 0, "fields: %s" % count)
	for c in map.cells():
		if map.column(c).has_tag("rock"):
			for n in map.grid.cells_within(c, 1):
				expect(not (map.has_cell(n) and map.column(n).has_tag("road")), "rock %s next to a road" % c)
	# A city: streets with lanes and crossings, and the rules see roads as open ground.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 22
	var city := TerrainGen.generate(rng2, 40, 40, GridLayout.Shape.SQUARE, {}, "city", "cyberpunk")
	var lanes := 0
	var crossings := 0
	for c in city.cells():
		var col := city.column(c)
		if col.has_tag("road") and col.gap_top == 0:
			expect(not col.has_tag(BattleMap.TAG_DIFFICULT) and not col.has_tag(Sight.TAG_SOFT_COVER), "roads are open ground")
			lanes += 1 if not col.has_tag("crossing") else 0
			crossings += 1 if col.has_tag("crossing") else 0
	expect(lanes > 40 and crossings > 0 and crossings < lanes, "streets %d, crossings %d" % [lanes, crossings])


func test_boarding_maps_dock_two_ships() -> void:
	# Two hulls with open space between (impassable) crossed by tubes; both sides alike.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var map := TerrainGen.generate(rng, 36, 40, GridLayout.Shape.SQUARE, {}, "boarding", "")
	var void_rows := {}
	var tube_cells := 0
	for c in map.cells():
		var col := map.column(c)
		if col.has_tag("void"):
			expect(col.has_tag(BattleMap.TAG_IMPASSABLE), "open space can't be crossed")
			void_rows[c.y] = true
		elif col.has_tag("deck") and col.ground == 0:
			tube_cells += 1
		var m := Vector2i(35 - c.x, 39 - c.y)
		expect(map.ground_height(m) == map.ground_height(c), "mirrored ship at %s" % c)
	expect(void_rows.size() == 4 and tube_cells >= 8, "a gap of 4 rows with tubes: %s, %d" % [void_rows.keys(), tube_cells])
	var hull := 0
	for c in map.cells():
		if map.column(c).has_tag("bulkhead") and map.column(c).has_tag("armor_4"):
			hull += 1
	expect(hull > 20, "hull plating is Armor 4: %d" % hull)


func test_the_next_fight_in_a_region_keeps_its_look() -> void:
	var first: Mission = _gen(11, {"landscape": "desert_mesas", "culture": "old_west"})["mission"]
	var region: Dictionary = first.flavor["region"]
	expect_eq(region["landscape"], "desert_mesas")
	var second: Dictionary = _gen(12, {"region": region})
	var m2: Mission = second["mission"]
	expect_eq(m2.flavor["region"], region, "same landscape, culture, weather and place seed")
	expect_eq(m2.flavor["kit"], first.flavor["kit"], "the same look")
	var s1: GameState = _gen(11, {"landscape": "desert_mesas", "culture": "old_west"})["state"]
	expect(JSON.stringify(s1.map.to_dict()) != JSON.stringify((second["state"] as GameState).map.to_dict()), "new terrain down the road")


func test_boarding_opts_pick_the_ship_map() -> void:
	var want := {"docked": "boarding", "enemy_ship": "boarding_assault", "own_ship": "boarding_defend"}
	for kind: String in want:
		var g := _gen(5, {"landscape": "starship", "boarding": {"kind": "seize", "map": kind}})
		var m: Mission = g["mission"]
		expect(str(m.flavor["kit"]).begins_with(want[kind]), "%s: %s" % [kind, m.flavor["kit"]])
		expect_eq(m.flavor["boarding"]["map"], kind)
		expect(bool(g["fairness"]["ok"]), "%s map is fair: %s" % [kind, g["fairness"]])


func test_ship_interiors_have_hull_rooms_and_a_way_in() -> void:
	for defend: bool in [true, false]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 6
		var map := TerrainGen.generate(rng, 36, 44, GridLayout.Shape.SQUARE, {}, "boarding_defend" if defend else "boarding_assault", "")
		var hull := 0
		var way_in := 0
		var breakable_walls := 0
		for c in map.cells():
			var col := map.column(c)
			if col.has_tag("hull"):
				hull += 1
				expect(col.has_tag("armor_4"), "the outer hull is Armor 4")
			if col.has_tag("torpedo") or col.has_tag("airlock"):
				way_in += 1
			if col.has_tag("bulkhead") and col.has_tag(BattleMap.TAG_DESTRUCTIBLE):
				breakable_walls += 1
		expect(hull > 60, "hull down both sides: %d" % hull)
		expect(way_in >= (2 if defend else 2), "%s: torpedo breaches or an airlock (%d)" % ["defend" if defend else "assault", way_in])
		expect(breakable_walls > 0, "some inner bulkheads can be broken through")


func test_exploring_areas_join_up() -> void:
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 5
	var hub := {"kind": "town", "culture": "old_west", "seed": 5, "spots": HubLayout.spots("town", hrng)}
	var town := MissionGenerator.area(5, {"hub": hub, "shape": "square", "size": 50})
	var map: BattleMap = town["map"]
	var buildings := 0
	for c in map.cells():
		buildings += 1 if map.column(c).has_tag("building") else 0
	expect(buildings > 10, "the town stands in its area: %d" % buildings)
	# The next area down the road: same region, same look, its own ground.
	var next := MissionGenerator.area(6, {"region": town["region"], "shape": "square", "size": 50})
	expect_eq(next["kit"], town["kit"], "the same region looks the same")
	for a: Dictionary in [town, next]:
		var m: BattleMap = a["map"]
		for edge: String in ["west", "east", "north", "south"]:
			var e: Array = a["entries"][edge]
			var col := m.column(Vector2i(e[0], e[1]))
			expect(col.has_tag("road") and m.ground_height(Vector2i(e[0], e[1])) == 0, "%s: a road out at ground level" % edge)
		var rough := 0
		for c in m.cells():
			if c.x < TerrainGen.AREA_EDGE or c.y < TerrainGen.AREA_EDGE or c.x >= 50 - TerrainGen.AREA_EDGE or c.y >= 50 - TerrainGen.AREA_EDGE:
				rough += 1 if m.ground_height(c) != 0 or m.column(c).has_tag(BattleMap.TAG_IMPASSABLE) else 0
		expect_eq(rough, 0, "the seam along the edges is level and open")


func test_no_rock_against_buildings() -> void:
	# User report: a rock ridge ran straight out of a house. Natural rock keeps two spaces from
	# anything built, in every settled landscape, and town ground between buildings is lots.
	var kits := [["salt_flats", "industrial"], ["desert_mesas", "old_west"], ["grassy_hills", "medieval"], ["tundra", "union"],
		["autumn_forest", "east_asian"], ["jungle", "medieval"], ["city", "ruins"]]
	for kit: Array in kits:
		for s in range(1, 9):
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			var map := TerrainGen.generate(rng, 40, 40, GridLayout.Shape.SQUARE, {}, kit[0], kit[1])
			var bad := 0
			var lots := 0
			for c in map.cells():
				var col := map.column(c)
				lots += 1 if col.has_tag("lot") else 0
				if not col.has_tag("rock"):
					continue
				for n in map.grid.neighbors(c):
					if map.has_cell(n) and (map.column(n).has_tag("building") or map.column(n).has_tag("house")):
						bad += 1
			expect_eq(bad, 0, "%s/%s seed %d: rock against a building" % [kit[0], kit[1], s])
			if kit[0] != "city":
				expect(lots > 0, "%s/%s seed %d: yards and lots between the houses" % [kit[0], kit[1], s])
	# Whole missions too: the fairness repair adds cover after the terrain is made.
	for kit: Array in [["salt_flats", "industrial"], ["desert_mesas", "old_west"], ["grassy_hills", "medieval"]]:
		for s in range(1, 4):
			var map: BattleMap = (_gen(s, {"landscape": kit[0], "culture": kit[1], "shape": "square"})["state"] as GameState).map
			var bad := 0
			for c in map.cells():
				if map.column(c).has_tag("rock"):
					for n in map.grid.neighbors(c):
						if map.has_cell(n) and (map.column(n).has_tag("building") or map.column(n).has_tag("house")):
							bad += 1
			expect_eq(bad, 0, "mission %s/%s seed %d: rock against a building" % [kit[0], kit[1], s])


func test_roads_have_a_hierarchy_and_no_bare_city_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var city := TerrainGen.generate(rng, 44, 44, GridLayout.Shape.SQUARE, {}, "city", "cyberpunk")
	var widths := {}
	var deck := 0
	var bare := 0
	for c in city.cells():
		var col := city.column(c)
		for t in col.tags:
			if t.begins_with("lane"):
				widths[int(t.split("_")[1])] = true
		if col.has_tag("highway") and col.gap_top >= 2 and col.ground >= 2:
			deck += 1
		if col.ground == 0 and col.gap_top == 0 and col.tags.is_empty():
			bare += 1
	expect(widths.has(4), "a four-lane boulevard: %s" % widths.keys())
	expect(widths.has(2) or widths.has(3), "streets: %s" % widths.keys())
	expect(deck > 20, "an elevated highway on pillars in the mega-city: %d" % deck)
	expect_eq(bare, 0, "no bare ground in the city")
