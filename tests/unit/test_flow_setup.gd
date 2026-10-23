extends TestCase
## The pre-battle setup (Total War style): everyone places their own units inside their side's
## deployment zone (the rules engine's deploy action) until everyone is Ready or the host's
## timer runs out; the other side's placement stays hidden; then round 1 starts.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _battle(seed_value: int, cfg: Dictionary) -> Dictionary:
	var gen := MissionGenerator.generate(seed_value, {"db": MissionTest.db(), "size": 24, "players": 2, "sitrep": "sitrep_standardcombat", "environments": []})
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	mission.flavor["setup"] = cfg
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
	host.set_seat_ai("p2", true)
	var s := BattleSession.for_host(host, director, mission, ["p1"])
	s.start()
	var me := ""
	for u: Unit in state.units_on_side(Mission.PLAYERS):
		if u.controller == "p1":
			me = u.id
	return {"state": state, "session": s, "host": host, "me": me}


## A space in the side's zone the unit can be deployed to (not where it stands).
static func _free_zone_cell(state: GameState, u: Unit) -> Variant:
	for c: Variant in state.objectives["deployment"][u.side]:
		var cell := Vector2i(int(c[0]), int(c[1]))
		if cell != u.cell and Deployment.check(state, u, cell, state.map.ground_height(cell)).ok:
			return cell
	return null


func test_place_inside_your_zone_then_ready_starts_the_fight() -> void:
	var b := _battle(901, {"mode": "ready", "seconds": 90})
	var state: GameState = b["state"]
	var s: BattleSession = b["session"]
	for i in range(8):
		s.poll(0.5)
	expect_eq(state.phase, GameState.PHASE_SETUP, "no fight while setting up")
	expect(s.setup_open())
	expect(not s.exploring(), "setup places units, it doesn't walk them")
	var u := state.unit(b["me"])
	var to: Variant = _free_zone_cell(state, u)
	expect(to != null, "a free space in the zone")
	expect_eq(s.deploy(u.id, to), "")
	expect_eq(u.cell, to as Vector2i, "placed")
	# Outside the zone: refused with the sitrep's deployment rule.
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	expect(s.deploy(u.id, foe.cell) != "", "outside your zone is refused")
	s.set_ready()
	for i in range(6):
		s.poll(0.5)
	expect_eq(state.phase, GameState.PHASE_COMBAT, "everyone's ready: round 1")
	expect(not s.setup_open())
	expect(s.deploy(u.id, to) != "", "no deploying once the fight has started")


func test_timer_runs_out_and_the_fight_starts() -> void:
	var b := _battle(902, {"mode": "timer", "seconds": 60})
	var state: GameState = b["state"]
	var s: BattleSession = b["session"]
	for i in range(10):
		s.poll(5.0)
	expect_eq(state.phase, GameState.PHASE_SETUP, "50 s in: still setting up")
	for i in range(6):
		s.poll(5.0)
	expect_eq(state.phase, GameState.PHASE_COMBAT, "time's up: the fight starts")


func test_enemy_placement_is_hidden_during_setup() -> void:
	var b := _battle(903, {"mode": "ready", "seconds": 90})
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	var v := ViewFilter.new().view_for(state, "p1")
	expect(bool(v["units"][foe.id].get("hidden", false)), "the other side's units are hidden")
	expect(not (v["units"][foe.id] as Dictionary).has("cell"), "no position")
	expect((v["units"][b["me"]] as Dictionary).has("cell"), "your own units are shown")
	var ev := ViewFilter.new().events_for(state, "p1", [{"type": "unit_deployed", "unit": foe.id, "cell": [1, 1, 0]}])
	expect(ev.is_empty(), "where they deploy isn't sent")
	(b["session"] as BattleSession).set_ready()
	for i in range(4):
		(b["session"] as BattleSession).poll(0.5)
	expect_eq(state.phase, GameState.PHASE_COMBAT)
	var after := ViewFilter.new().view_for(state, "p1")
	expect((after["units"][foe.id] as Dictionary).has("cell") or foe.has_status("Hidden"), "seen once the fight starts")
	expect(host != null)


func test_a_friend_says_ready_over_the_network() -> void:
	var b := _battle(904, {"mode": "ready", "seconds": 90})
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	host.lobby_message.emit("p9", {"setup_ready": true})  # not a seat in this battle: ignored
	expect(not ((state.objectives["setup"] as Dictionary)["ready"] as Array).has("p9"))
	expect_eq(state.phase, GameState.PHASE_SETUP)
	host.lobby_message.emit("p1", {"setup_ready": true})
	for i in range(4):
		(b["session"] as BattleSession).poll(0.5)
	expect_eq(state.phase, GameState.PHASE_COMBAT, "the last person ready: round 1")


func test_exploring_missions_have_no_setup() -> void:
	var gen := MissionGenerator.generate(905, {"db": MissionTest.db(), "size": 24, "players": 1, "sitrep": "sitrep_standardcombat", "environments": []})
	var mission: Mission = gen["mission"]
	mission.flavor["explore_first"] = true
	mission.flavor["setup"] = {"mode": "ready", "seconds": 90}
	var host := NetHost.new(gen["state"], RulesEngine.new())
	var s := BattleSession.for_host(host, AiDirector.new(host, GmSettings.from_preset("Standard"), mission), mission, ["p1"])
	s.start()
	s.poll(0.1)
	expect(not s.setup_open(), "fights start where people are")
	expect(s.exploring())
