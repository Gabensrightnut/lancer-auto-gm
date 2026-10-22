extends TestCase
## The GM's mid-mission twist (GmTwist): when it's revealed, that it goes through the rules
## engine, who sees it, and how the squad's arrival (late / spent) is told.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const TWIST := {"id": "third_party", "reveal": "New transponders on the scope. Someone else wants this too.",
	"question": "Who sent them?", "effects": [{"set_flag": "third_party_seen"}]}


func _mission(sitrep: String, rounds: int = 0) -> Mission:
	var m := Mission.new()
	m.sitrep_id = sitrep
	m.rounds = rounds
	m.flavor["twist"] = TWIST.duplicate(true)
	return m


func test_the_gm_picks_its_moment() -> void:
	expect_eq(GmTwist.plan(Mission.new()), {}, "no twist, nothing to plan")
	expect_eq(GmTwist.plan(_mission("sitrep_standardcombat")), {"round": 3, "on": "first_destroyed"})
	expect_eq(GmTwist.plan(_mission("sitrep_control", 6)), {"round": 3, "on": "first_score"}, "halfway through a timed mission")
	expect_eq(GmTwist.plan(_mission("sitrep_holdout", 8))["round"], 4)
	var late := _mission("sitrep_standardcombat")
	late.flavor["arrived_late"] = true
	expect_eq(GmTwist.plan(late)["round"], 2, "a late squad meets the twist a round sooner")


func test_objective_or_round_triggers_it() -> void:
	var state := GameState.new(1, GridLayout.Shape.HEX)
	var foe := Unit.new()
	foe.id = "e1"
	foe.kind = Unit.KIND_NPC
	state.units["e1"] = foe
	var m := _mission("sitrep_standardcombat")
	GmTwist.observe(m, state, [{"type": "round_started", "round": 2}])
	expect(not m.flavor.get("twist_due", false), "round 2 is too early")
	GmTwist.observe(m, state, [{"type": "unit_destroyed", "unit": "e1"}])
	expect(m.flavor.get("twist_due", false), "the first mech or NPC down brings it on")
	var m2 := _mission("sitrep_standardcombat")
	GmTwist.observe(m2, state, [{"type": "round_started", "round": 3}])
	expect(m2.flavor.get("twist_due", false), "or round 3 starts")
	var m3 := _mission("sitrep_control", 6)
	GmTwist.observe(m3, state, [{"type": "round_started", "round": 2}])
	expect(not m3.flavor.get("twist_due", false))
	m3.scores[Mission.PLAYERS] = 1
	GmTwist.observe(m3, state, [])
	expect(m3.flavor.get("twist_due", false), "Control: the first zone scored")


func test_the_ai_gm_reveals_it_to_the_squad_only() -> void:
	var gen := MissionGenerator.generate(4321, {"db": MissionTest.db(), "sitrep": "sitrep_standardcombat", "size": 22})
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	mission.flavor["twist"] = TWIST.duplicate(true)
	mission.flavor["arrived_late"] = true
	mission.flavor["arrived_spent"] = true
	mission.flavor["hook"] = {"patron": "Commander Vey"}
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
	host.set_fill_empty_with_ai(true)
	var narration: Array = []
	var before_reveal: Array = []  # (an Array: lambdas capture locals by value)
	host.action_resolved.connect(func(_s: String, a: Dictionary, r: RuleResult, e: Array) -> void:
		if a.get("type", "") == "gm_narrate":
			expect(r.ok, "narration goes through the rules engine: %s" % r.reason)
			narration.append_array(e)
		elif before_reveal.is_empty() and state.round_number >= 1 and not mission.flavor.get("twist_revealed", false):
			before_reveal.append(JSON.stringify(host.view_filter.view_for(state, "p1"))))
	director.run(4000)
	expect_eq(narration.size(), 2, "the arrival, then the twist: %s" % str(narration))
	if narration.size() < 2:
		return
	var arrival: Dictionary = narration[0]
	expect_eq(arrival["type"], "gm_narration")
	expect(str(arrival["text"]).contains("late") and str(arrival["text"]).contains("1 damage"), arrival["text"])
	var twist: Dictionary = narration[1]
	expect_eq(twist["type"], "twist_revealed")
	expect_eq(twist["twist"], {"id": "third_party", "reveal": TWIST["reveal"], "question": TWIST["question"]}, "the effects stay with the story")
	expect_eq(twist["speaker"], "Commander Vey")
	expect_eq(twist["rule_ref"], GmTwist.REF)
	expect(mission.flavor["twist_revealed"])
	expect(not before_reveal.is_empty() and not str(before_reveal[0]).contains("transponders"), "nothing of the twist is in a player's view before it's revealed")
	# Who sees it: the squad's seats and the GM, not the other side.
	state.seats["rival"] = {"side": Mission.ENEMIES}
	var players_seat := ""
	for seat: String in state.seats:
		if str(state.seats[seat].get("side", "")) == Mission.PLAYERS:
			players_seat = seat
	expect_eq(host.view_filter.events_for(state, players_seat, [twist]).size(), 1, "the squad sees it")
	expect_eq(host.view_filter.events_for(state, "gm", [twist]).size(), 1, "the GM sees it")
	expect_eq(host.view_filter.events_for(state, "rival", [twist]).size(), 0, "the other side doesn't")


func test_only_the_gm_may_narrate() -> void:
	var gen := MissionGenerator.generate(99, {"db": MissionTest.db(), "size": 20})
	var host := NetHost.new(gen["state"], RulesEngine.new())
	AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])
	var a := {"type": "gm_narrate", "params": {"kind": "twist", "text": "A lie."}}
	expect(not (host.submit("p1", a)["result"] as RuleResult).ok, "a player can't narrate as the GM")
	expect(not (host.submit(NetHost.GM_SEAT, {"type": "gm_narrate", "params": {"kind": "twist", "text": " "}})["result"] as RuleResult).ok, "needs text")
	expect((host.submit(NetHost.GM_SEAT, a)["result"] as RuleResult).ok)
