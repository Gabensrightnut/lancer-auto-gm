extends TestCase
## Human seats are never played by the AI: the game waits on them (no timeouts), shows who
## it's waiting for, and the players choose who goes next ("I'll go"). Humans are scripted.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var host: NetHost
var director: AiDirector
var mission: Mission


## p1 is a human at this screen, p2 an AI squadmate, the GM plays the enemies.
func _setup(mission_seed: int = 21, sitrep: String = "sitrep_standardcombat") -> void:
	var g := MissionGenerator.generate(mission_seed, {"players": 2, "sitrep": sitrep, "size": 20, "db": MissionTest.db()})
	mission = g["mission"]
	host = NetHost.new(g["state"], RulesEngine.new())
	host.add_local_seat("p1")
	host.set_seat_ai("p2", true)
	director = AiDirector.new(host, GmSettings.from_preset("Standard"), mission)


func test_ai_never_acts_for_a_human_seat() -> void:
	_setup()
	director.run(500)
	var w := host.waiting_on()
	expect_eq(w["state"], "pick", "squad's pick to start")
	expect_eq(w["seats"], ["p1"], "waiting on the human")
	expect(not w["ai"])
	expect(w["text"].contains(host.state.seats["p1"]["name"]), w["text"])
	expect_eq(director.run(500), 0, "nothing happens however long we wait")
	expect(not "p1" in host.state.acted and not "p2" in host.state.acted)
	expect(host.waiting_on("p1")["you"])


func test_ill_go_with_an_ai_squadmate() -> void:
	_setup()
	director.run(500)
	var out := host.submit("p1", {"type": "start_turn", "actor": "p2"})
	expect((out["result"] as RuleResult).ok, "a player can send the AI squadmate in first")
	director.run(500)
	expect("p2" in host.state.acted, "the AI played p2's turn")
	var w := host.waiting_on()
	if host.state.phase == GameState.PHASE_COMBAT:
		expect_eq(w["seats"], ["p1"], "back to waiting on the human")


func test_a_human_turn_waits_for_its_player() -> void:
	_setup()
	director.run(500)
	expect((host.submit("p1", {"type": "start_turn", "actor": "p1"})["result"] as RuleResult).ok, "I'll go")
	var w := host.waiting_on("p1")
	expect_eq(w["state"], "turn")
	expect_eq(w["unit"], "p1")
	expect(w["you"])
	expect(not w["ai"])
	expect_eq(director.run(500), 0, "no auto-resolve")
	expect_eq(host.state.active_unit, "p1")
	# Scripted input: one move, then End Turn.
	var spaces: Array = RulesQueries.reachable(host.state, "p1")["spaces"]
	var to: Array = spaces[0]["cell"]
	expect((host.submit("p1", {"type": "move", "actor": "p1", "params": {"to": to}})["result"] as RuleResult).ok)
	expect((host.submit("p1", {"type": "end_turn", "actor": "p1"})["result"] as RuleResult).ok)
	expect("p1" in host.state.acted)


func test_players_only_pick_for_themselves_or_ai_squadmates() -> void:
	_setup()
	host.set_seat_ai("p2", false)  # p2 is now a person too, on another computer.
	director.run(500)
	var out := host.submit("p1", {"type": "start_turn", "actor": "p2"})
	expect(not (out["result"] as RuleResult).ok, "can't send another player's mech in")
	expect(out["result"].rule_ref != "")
	expect_eq(host.waiting_on()["seats"], ["p1", "p2"], "either player may say I'll go")
	host.add_local_seat("p2")
	expect((host.submit("p1", {"type": "start_turn", "actor": "p2"})["result"] as RuleResult).ok, "sharing a screen, they decide together")
	var enemy := host.state.units_on_side("enemies")[0]
	expect(not (host.submit("p1", {"type": "start_turn", "actor": enemy.id})["result"] as RuleResult).ok)


func test_remote_player_sees_waiting_and_picks() -> void:
	_setup()
	host.set_seat_ai("p2", false)
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "TURNS1")
	var c := NetClient.new(LoopbackTransport.new(hub))
	c.join("TURNS1", "Friend", "p2")
	for i in range(6):
		host.poll()
		c.poll()
	director.run(500)
	for i in range(6):
		host.poll()
		c.poll()
	expect_eq(c.waiting.get("state"), "pick")
	expect(c.waiting.get("you", false), "the client is told it may pick")
	c.pick_next("p2")
	for i in range(6):
		host.poll()
		c.poll()
	expect_eq(host.state.active_unit, "p2")
	expect_eq(c.waiting.get("state"), "turn")
	expect(c.waiting.get("you", false))


func test_hidden_enemy_turn_is_anonymous_to_players() -> void:
	_setup()
	director.run(500)
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	host.submit("p1", {"type": "end_turn", "actor": "p1"})
	var s := host.state
	expect_eq(s.turn_side, "enemies", "enemies pick after the squad")
	var e := s.units_on_side("enemies")[0]
	expect((host.submit("gm", {"type": "start_turn", "actor": e.id})["result"] as RuleResult).ok)
	e.statuses["Hidden"] = {}
	var w := host.waiting_on("p1")
	expect_eq(w["unit"], "", "players aren't told which Hidden enemy is acting")
	expect(not w["text"].contains(e.name), w["text"])
	expect_eq(host.waiting_on("gm")["unit"], e.id)


## A scripted human plays p1 through a whole mission (choosing "I'll go", moving, attacking,
## ending turns); everything else is AI. The game only advances on the human's inputs.
func test_scripted_human_plays_a_whole_mission() -> void:
	_setup(33)
	var me := TacticsAi.new(GmSettings.from_preset("Standard"))
	var guard := 0
	while host.state.phase != GameState.PHASE_ENDED and guard < 2000:
		guard += 1
		if director.step():
			continue
		var w := host.waiting_on("p1")
		if not w["you"]:
			if mission.outcome != "":
				continue
			fail("stuck: waiting on %s" % str(w))
			return
		if w["state"] == "pick":
			var pick: String = "p1" if "p1" in w["units"] else w["units"][0]
			expect((host.submit("p1", {"type": "start_turn", "actor": pick})["result"] as RuleResult).ok)
		elif w["state"] == "turn":
			var plan := me.plan_turn(AiKnowledge.for_side(host.state, host.view_filter, "players"), "p1")
			for a: Dictionary in plan["steps"]:
				host.submit("p1", a)
			if host.state.active_unit == "p1":
				host.submit("p1", {"type": "end_turn", "actor": "p1"})
	expect_eq(host.state.phase, GameState.PHASE_ENDED, "the mission finished: %s" % mission.outcome_reason)
	expect(mission.outcome != "")


func fail(msg: String) -> void:
	expect(false, msg)
