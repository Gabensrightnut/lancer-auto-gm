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
		var s: GameState = _gen(mission_seed)["state"]
		var n := s.map.cells().size()
		expect(n >= 20 * 20 * 0.75 and n <= 40 * 40, "size %d" % n)
		var heights := {}
		var soft := 0
		var difficult := 0
		for c in s.map.cells():
			heights[s.map.ground_height(c)] = true
			soft += 1 if s.map.column(c).has_tag(Sight.TAG_SOFT_COVER) else 0
			difficult += 1 if s.map.column(c).has_tag(BattleMap.TAG_DIFFICULT) else 0
		expect(heights.size() >= 3, "rolling hills: several heights")
		expect(soft > 0 and difficult > 0, "woods and difficult ground")


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
