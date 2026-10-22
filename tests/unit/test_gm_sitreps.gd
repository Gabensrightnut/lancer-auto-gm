extends TestCase
## Escort, Extraction and Recon (data/lancer-data/sitreps.json): the Objective, extracting,
## carrying it, the round limits, Recon's secret True Control Zone and surveying it.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _mission(sitrep: String, mission_seed: int = 515) -> Dictionary:
	var gen := MissionGenerator.generate(mission_seed, {"db": MissionTest.db(), "sitrep": sitrep, "size": 20, "players": 2, "environments": [], "weather": "clear"})
	var state: GameState = gen["state"]
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])
	host.add_local_seat("p1")
	host.set_seat_ai("p2", true)
	host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS}})
	return {"state": state, "mission": gen["mission"], "host": host, "director": director}


## Puts `u` on a free standable cell of `cells` (next to `near` if given). Returns the cell.
static func _put(state: GameState, u: Unit, cells: Array, near: Unit = null) -> bool:
	var taken := {}
	for o: Unit in state.units.values():
		if o != u and Combat.is_present(o):
			for c in state.map.grid.footprint(o.cell, o.size):
				taken[c] = true
	for c: Array in cells:
		var cell := Vector2i(int(c[0]), int(c[1]))
		if taken.has(cell) or not state.map.has_cell(cell):
			continue
		if near != null and state.map.grid.distance(cell, near.cell) != 1:
			continue
		u.cell = cell
		u.level = state.map.ground_height(cell)
		return true
	return false


func test_every_book_sitrep_is_generated() -> void:
	var cfg := GmSettings.load_json(GmSettings.MISSIONS_FILE)
	for s: Dictionary in MissionGenerator._sitreps():
		expect(cfg["sitreps"].has(s["id"]), "%s is generated" % s["id"])
	expect_eq(int(cfg["sitreps"]["sitrep_escort"]["rounds"]), 8)
	expect_eq(int(cfg["sitreps"]["sitrep_extraction"]["rounds"]), 10)
	expect_eq(int(cfg["sitreps"]["sitrep_recon"]["rounds"]), 6)


func test_escort_extract_with_the_objective() -> void:
	var b := _mission("sitrep_escort")
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var m: Mission = b["mission"]
	var obj := SitrepActions.objective(state)
	expect(obj != null, "the Objective is on the field")
	expect_eq([obj.max_hp, obj.evasion, obj.edef, obj.armor], [10, 10, 10, 0], "10 HP per Size, Evasion 10, E-Defense 10, no Armor")
	expect(SitrepActions.in_cells(state, obj, m.deployment[Mission.PLAYERS]), "Escort: it starts in the Allied Deployment Zone")
	var p1 := state.unit("p1")
	expect((host.submit("p1", {"type": "start_turn", "actor": "p1"})["result"] as RuleResult).ok)
	expect(not (host.submit("p1", {"type": "extract", "actor": "p1"})["result"] as RuleResult).ok, "only from the Extraction Zone")
	var ext: Array = state.objectives["extraction"]
	expect(_put(state, p1, ext), "p1 in the Extraction Zone")
	expect(_put(state, obj, ext, p1), "the Objective next to it")
	var out := host.submit("p1", {"type": "extract", "actor": "p1"})
	expect((out["result"] as RuleResult).ok, (out["result"] as RuleResult).reason)
	var types: Array = (out["events"] as Array).map(func(e: Dictionary) -> String: return e["type"])
	expect(types.has("unit_extracted") and types.has("objective_extracted"), str(types))
	expect(not Combat.is_present(p1), "extracted: off the battlefield")
	expect_eq(state.active_unit, "", "extracting ends the turn")
	expect_eq(m.outcome, Mission.PLAYERS, m.outcome_reason)


func test_contested_objective_stays_behind() -> void:
	var b := _mission("sitrep_extraction", 616)
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var m: Mission = b["mission"]
	var obj := SitrepActions.objective(state)
	expect(SitrepActions.in_cells(state, obj, m.zones["objective"]), "Extraction: the GM places it in the Objective Zone")
	var p1 := state.unit("p1")
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	var ext: Array = state.objectives["extraction"]
	expect(_put(state, p1, ext))
	expect(_put(state, obj, ext, p1))
	var near_obj: Array = []
	for c: Array in ext:
		near_obj.append(c)
	expect(_put(state, foe, near_obj, obj), "an enemy next to the Objective")
	var out := host.submit("p1", {"type": "extract", "actor": "p1"})
	var types: Array = (out["events"] as Array).map(func(e: Dictionary) -> String: return e["type"])
	expect(types.has("unit_extracted") and not types.has("objective_extracted"), "contested: it stays (%s)" % str(types))
	expect(m.outcome != Mission.PLAYERS)


func test_objective_moves_with_its_carrier() -> void:
	var b := _mission("sitrep_escort", 717)
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var m: Mission = b["mission"]
	var obj := SitrepActions.objective(state)
	var p1 := state.unit("p1")
	var adz: Array = m.deployment[Mission.PLAYERS]
	expect(_put(state, p1, adz, obj), "p1 starts its turn next to the Objective")
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	expect_eq(str(m.flavor.get("carrier", "")), "p1")
	var dest: Dictionary = {}
	for sp: Dictionary in RulesQueries.reachable(state, "p1")["spaces"]:
		if int(sp["cost"]) >= 2 and not sp.get("ruling", false):
			dest = sp
			break
	expect(not dest.is_empty())
	var mv := host.submit("p1", {"type": "move", "actor": "p1", "params": {"to": dest["cell"], "level": dest["level"]}})
	expect((mv["result"] as RuleResult).ok, (mv["result"] as RuleResult).reason)
	expect(b["director"].step(), "the GM moves the Objective along")
	expect_eq(Sight.unit_distance(state, p1, obj), 1, "it's next to its carrier again")


func test_round_limits_and_a_destroyed_objective() -> void:
	var b := _mission("sitrep_extraction", 818)
	var state: GameState = b["state"]
	var m: Mission = b["mission"]
	m.observe(state, [{"type": "unit_destroyed", "unit": "objective"}])
	expect_eq(m.outcome, "none", "the Objective destroyed: no victor")
	var b2 := _mission("sitrep_escort", 919)
	var m2: Mission = b2["mission"]
	m2.observe(b2["state"], [{"type": "round_started", "round": 8}])
	expect_eq(m2.outcome, "", "still time")
	m2.observe(b2["state"], [{"type": "round_started", "round": 9}])
	expect_eq(m2.outcome, Mission.ENEMIES, "not extracted by the end of the eighth round")


func test_recon_true_zone_is_secret_until_surveyed() -> void:
	var b := _mission("sitrep_recon", 321)
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var m: Mission = b["mission"]
	var t := str(state.objectives["true_zone"])
	expect(t.begins_with("zone_"))
	var view := host.view_filter.view_for(state, "p1")
	expect(not view["objectives"].has("true_zone"), "the squad doesn't know which one")
	expect_eq(view["objectives"]["zones"].size(), 4, "they see all four zones")
	expect(view["objectives"]["deployment"].has(Mission.PLAYERS) and view["objectives"]["deployment"].has(Mission.ENEMIES), "deployment zones are in every view")
	expect_eq(host.view_filter.view_for(state, NetHost.GM_SEAT)["objectives"]["true_zone"], t, "the GM knows")
	var wrong := ""
	for z: String in state.objectives["zones"]:
		if z != t:
			wrong = z
	var p1 := state.unit("p1")
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	expect(_put(state, p1, state.objectives["zones"][wrong]))
	var out := host.submit("p1", {"type": "survey_zone", "actor": "p1"})
	expect((out["result"] as RuleResult).ok, (out["result"] as RuleResult).reason)
	expect_eq(out["events"][0]["true"], false)
	expect_eq(host.view_filter.events_for(state, "p1", out["events"]).size(), 1)
	state.seats["rival"] = {"side": Mission.ENEMIES}
	expect_eq(host.view_filter.events_for(state, "rival", out["events"]).size(), 0, "only the surveying side learns the answer")
	expect(not host.view_filter.view_for(state, "p1")["objectives"].has("true_zone"))
	host.submit("p1", {"type": "end_turn", "actor": "p1"})
	# Next round: survey the true one.
	state.acted = PackedStringArray()
	state.active_unit = ""
	state.turn_side = Mission.PLAYERS
	expect(_put(state, p1, state.objectives["zones"][t]))
	p1.turn = {}
	host.submit_ai({"type": "start_turn", "actor": "p1"})
	var hit := host.submit("p1", {"type": "survey_zone", "actor": "p1"})
	expect((hit["result"] as RuleResult).ok, (hit["result"] as RuleResult).reason)
	expect_eq(hit["events"][0]["true"], true)
	expect_eq(host.view_filter.view_for(state, "p1")["objectives"]["true_zone"], t, "found: now the squad knows")
	# Scoring: only PCs in the True Control Zone at the end of round 6.
	for u: Unit in state.units.values():
		if u != p1 and u.side == Mission.ENEMIES and SitrepActions.in_cells(state, u, state.objectives["zones"][t]):
			u.destroyed = true
	m.observe(state, [{"type": "round_started", "round": 7}])
	expect_eq(m.outcome, Mission.PLAYERS, m.outcome_reason)


func test_new_sitreps_play_to_an_end() -> void:
	for id: String in ["sitrep_escort", "sitrep_extraction", "sitrep_recon"]:
		var r := MissionTest.play(4040, {"sitrep": id, "size": 22, "players": 2})
		var m: Mission = r["mission"]
		expect(m.outcome != "", "%s reached an outcome" % id)
		print("        %s: %s after round %d. %s" % [id, m.outcome, r["state"].round_number, m.outcome_reason])
