extends TestCase
## Cascading NHPs (Core p.107) as story beats: barks, the debrief, the squad's banter.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _mission_with_cascade(seed_value: int, nhp_off: bool) -> Dictionary:
	var t := Setup.setup(seed_value)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.db = MissionTest.db()
	if nhp_off:
		c.options["content_off"] = ["nhp_themes"]
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": s.hooks[0]["id"]}})
	Dialogue.close(s)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm"})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var events: Array = [{"type": "cascade_check", "unit": "p2", "roll": 1, "cascade": true}, {"type": "cascade_check", "unit": "p1", "roll": 12, "cascade": false}]
	t["summary"] = CampaignLoop.battle_summary(state, s, events)
	t["barks"] = Squadmate.barks_for(s, c, events[0], {"p1": t["a"], "p2": t["b"]}, {"p1": "p1", "p2": "p2"})
	mission.outcome = Mission.PLAYERS
	var fin := CampaignLoop.finish_mission(c, s, e, state, mission, events)
	var said := ""
	var topics: Array = []
	var batch: Array = fin["events"]
	for i in range(30):
		for x: Dictionary in batch:
			if x["type"] == "dialogue_line":
				said += str(x["text"]) + " "
			if x["type"] == "banter":
				topics.append(str(x["topic"]))
				said += str(x["text"]) + " "
		if not Dialogue.is_open(s):
			break
		var o := Dialogue.offered(s)
		batch = e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "p1", "params": {"choice": o[0]["id"]}})["events"]
	t["said"] = said
	t["topics"] = topics
	return t


func test_a_cascade_is_remembered_and_talked_about() -> void:
	var t := _mission_with_cascade(180, false)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var kettle := str(c.pilots[t["b"]]["callsign"])
	expect_eq(t["summary"]["cascades"], [kettle], "only the mech that rolled a 1 cascaded")
	expect(str(t["said"]).contains(kettle) and str(t["said"]).contains("NHP"), "the debrief mentions it: %s" % t["said"])
	expect_eq(int(Squadmate.memory(s, t["b"]).get("cascades", 0)), 1)
	expect((t["topics"] as Array).has("cascade"), "it's what the squad talks about after the debrief: %s" % [t["topics"]])


func test_nhp_themes_switched_off_stay_off() -> void:
	var t := _mission_with_cascade(181, true)
	expect(not str(t["said"]).contains("cascade"), "no cascade talk when the table left NHP themes out")
	expect(not (t["topics"] as Array).has("cascade"), "no banter about it either")
	expect(t["barks"].is_empty() or not t["barks"].any(func(l: Dictionary) -> bool: return str(l["text"]).contains("NHP")))
