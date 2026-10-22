extends TestCase
## Multiplayer story (host session, remote clients, votes, help offers) and the whole story
## loop over three procedurally generated missions played out by the AI.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


## A host with p1 (on the host), p2 (a remote player) and p3 (AI), wired to a client for p2.
func _net() -> Dictionary:
	var t := Setup.setup(120)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var third := c.new_pilot("Teo Lind", "Halo")
	third["skills"] = {"sk_hack_or_fix": 1}
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p3", "pilot": third["id"], "ai": true, "persona": "kind"}})
	var session := StorySession.new(e, s, c)
	session.local_seats = ["p1"]
	var client := StoryClient.new(null, "p2")
	session.broadcast = func(payload: Dictionary) -> void: client.receive(payload)
	client.send = func(payload: Dictionary) -> void: session.handle_message("p2", payload)
	session.resync()
	return {"t": t, "session": session, "client": client}


func test_clients_never_see_secrets() -> void:
	var n := _net()
	var client: StoryClient = n["client"]
	var s: StoryState = n["t"]["story"]
	expect(client.story != null, "the client has a mirror")
	for id: String in client.story.npcs:
		expect(not client.story.npcs[id].has("secret"), "no NPC secrets on clients")
	var c: Campaign = n["t"]["campaign"]
	var hook := MissionHooks.make(s, c, "recover_cargo", {"twist": "patron_lied"})
	s.hooks.append(hook)
	(n["session"] as StorySession).resync()
	for h: Dictionary in client.story.hooks:
		expect(not h.has("twist"), "hidden twists stay on the host")
	expect(not client.story.to_dict().has("dice_state") or str(client.story.to_dict()["dice_state"]) != str(s.dice.get_state()), "no story dice")


func test_remote_player_acts_only_as_themselves() -> void:
	var n := _net()
	var client: StoryClient = n["client"]
	var s: StoryState = n["t"]["story"]
	var refusals: Array = []
	client.refused.connect(func(reason: String, _ref: String) -> void: refusals.append(reason))
	s.phase = "mission"
	client.send.call({"story_action": {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory"}}})
	expect_eq(s.phase, "mission", "a remote player can't report a mission as the GM")
	expect(not refusals.is_empty(), "and is told why")
	s.phase = "downtime"
	var bar := Setup.npc_with_role(s, "bartender")
	client.submit(client.story, client.campaign, {"type": "talk", "params": {"npc": bar}})
	expect(Dialogue.is_open(s), "p2 started a conversation on the host")
	expect_eq(str(s.dialogue["ctx"]["speaker"]), n["t"]["b"], "p2's pilot is the one talking")
	expect(Dialogue.is_open(client.story), "the client's mirror shows it")


func test_vote_with_remote_and_ai_seats() -> void:
	var n := _net()
	var session: StorySession = n["session"]
	var client: StoryClient = n["client"]
	var s: StoryState = n["t"]["story"]
	var c: Campaign = n["t"]["campaign"]
	c.options["dialogue_choice"] = "vote"
	var local := Setup.npc_with_role(s, "bartender")
	session.submit("p1", {"type": "talk", "params": {"npc": local}})
	var guard := 0
	while Dialogue.offered(s).is_empty() and Dialogue.is_open(s) and guard < 5:
		session.submit("p1", {"type": "dialogue_next", "params": {}})
		guard += 1
	expect(not s.dialogue["votes"].has("p3"), "AI squadmates don't vote: only the humans do")
	var pick := str(Dialogue.offered(s)[0]["id"])
	session.submit("p1", {"type": "dialogue_choose", "params": {"choice": pick}})
	expect(Dialogue.is_open(s) and s.dialogue["votes"].has("p1"), "still waiting on p2")
	client.submit(client.story, client.campaign, {"type": "dialogue_choose", "params": {"choice": pick}})
	expect(not s.dialogue.get("votes", {}).has("p1"), "everyone voted: resolved, and the next node opened")


func test_helpers_can_say_no() -> void:
	var t := Setup.setup(121)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	var bar := Setup.npc_with_role(s, "bartender")
	e.submit(s, c, {"type": "talk", "seat": "p2", "params": {"npc": bar}})
	var r := e.submit(s, c, {"type": "dialogue_help", "seat": "p1", "params": {"on": false}})
	expect(r["ok"], str(r["reason"]))
	expect(not e.submit(s, c, {"type": "dialogue_help", "seat": "p2", "params": {"on": true}})["ok"], "the speaker can't help themself")
	var ev := Dialogue._roll_choice(s, c, {"skills": ["sk_apply_fists_to_faces"], "teamwork": true, "fail_effects": []}, {"text": "x"}, s.dialogue["ctx"])
	var rec: Dictionary = (ev["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "narrative_check")[0]["check"]
	expect(not (rec["bonus_sources"] as Array).any(func(b: Dictionary) -> bool: return b["label"] == "Teamwork"), "p1 said no: no teamwork bonus")
	e.submit(s, c, {"type": "dialogue_help", "seat": "p1", "params": {"on": true}})
	ev = Dialogue._roll_choice(s, c, {"skills": ["sk_apply_fists_to_faces"], "teamwork": true, "fail_effects": []}, {"text": "x"}, s.dialogue["ctx"])
	rec = (ev["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "narrative_check")[0]["check"]
	expect((rec["bonus_sources"] as Array).any(func(b: Dictionary) -> bool: return b["label"] == "Teamwork"), "p1 helps: +1")


func test_downtime_choices_dont_block_other_players() -> void:
	var t := Setup.setup(122)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	s.phase = "level_up"
	e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	e.submit(s, c, {"type": "downtime_action", "seat": "p1", "params": {"action": "dt_get_a_damn_drink", "subject": "Collect gossip"}})
	var r := e.submit(s, c, {"type": "downtime_action", "seat": "p2", "params": {"action": "dt_scrounge_and_barter", "subject": "A vehicle"}})
	expect(r["ok"], "p2 isn't blocked by p1's open choice: %s" % r["reason"])
	for pid: String in [t["a"], t["b"]]:
		var guard := 0
		while not s.first_choice_for(pid).is_empty() and guard < 5:
			guard += 1
			var pc := s.first_choice_for(pid)
			var picks: Array = (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])
			var seat := s.seat_of(pid)
			expect(e.submit(s, c, {"type": "downtime_choose", "seat": seat, "params": {"picks": picks}})["ok"])
	expect(s.all_choices().is_empty())
	expect((s.downtime["log"] as Array).size() >= 2, "both results narrated")
	expect(e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})["ok"])


## Three generated missions in a row, AI on every seat: arcs move, twists come out at the
## debrief, and each briefing and debrief refers back to what happened.
func test_three_generated_missions_in_a_row() -> void:
	var c := Campaign.create("Loop test")
	c.id = "c_loop"
	var s := StoryState.new(2024)
	s.flags = c.story_flags
	var e := StoryEngine.new(MissionTest.db())
	var personas := ["bold", "steady"]
	for i in range(2):
		var p := c.new_pilot("Pilot %d" % i, ["Bluebird", "Kettle"][i])
		p["skills"] = {"sk_charm": 1, "sk_survive": 1, "sk_spot": 1, "sk_assault": 1}
		e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p%d" % (i + 1), "pilot": p["id"], "ai": true, "persona": personas[i]}})
	e.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": 7}})
	var arc_id := str(s.arc.get("id", ""))
	expect(arc_id != "", "an arc is running")
	var said_all := ""
	for m in range(3):
		var hook: Dictionary = s.hooks[0]
		for h: Dictionary in s.hooks:
			if h.has("arc"):
				hook = h
		var r := e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
		var said := _talk(e, s, c, r["events"])
		if m > 0:
			expect("rounds" in said_all or said.contains(str(s.current_hook.get("place", "!"))) or said.length() > 0)
			expect(said.contains(str(s.last_mission.get("hook", "~~"))) or said.contains(str(s.last_mission.get("place", "~~"))) or said.contains("Last time"),
				"briefing %d looks back at the last mission: %s" % [m + 1, said])
		e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
		var gen := CampaignLoop.build_mission(c, s, MissionTest.db(), {"size": 20})
		var state: GameState = gen["state"]
		var mission: Mission = gen["mission"]
		var host := NetHost.new(state, RulesEngine.new())
		var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
		host.set_fill_empty_with_ai(true)
		var events: Array = []
		host.action_resolved.connect(func(_s: String, _a: Dictionary, _r: RuleResult, ev: Array) -> void: events.append_array(ev))
		director.run(4000)
		expect(mission.outcome != "", "mission %d reached an outcome" % (m + 1))
		var fin := CampaignLoop.finish_mission(c, s, e, state, mission, events)
		var debrief := _talk(e, s, c, fin["events"])
		said_all += debrief
		expect(debrief.contains("round"), "debrief %d mentions how the fight went: %s" % [m + 1, debrief])
		if not hook.get("twist", {}).is_empty():
			expect((fin["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "twist_revealed"), "twist revealed at debrief %d" % (m + 1))
		e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
		var dt := e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
		expect(dt["ok"], str(dt["reason"]))
		expect(e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})["ok"])
	expect_eq(c.history.size(), 3)
	expect(s.flags.has("arc_done:%s:%s" % [arc_id, s.hub["id"]]) or int(s.arc.get("stage", 0)) >= 2 or str(s.arc.get("id", "")) != arc_id, "the arc moved on every mission")
	for pid: String in c.pilots:
		if s.is_alive(pid):
			expect_eq(int(c.pilots[pid]["ll"]), 3, "three missions survived, three License Levels")
		else:
			expect_eq(int(c.pilots[pid]["ll"]), int(s.dead[pid]["mission"]) - 1, "the fallen level up for the missions they finished")
			expect(said_all.contains(str(c.pilots[pid]["callsign"])), "the debrief remembers them")


func _talk(e: StoryEngine, s: StoryState, c: Campaign, first: Array) -> String:
	var said := ""
	var evs := first
	var guard := 0
	while guard < 30:
		guard += 1
		for x: Dictionary in evs:
			if x["type"] == "dialogue_line":
				said += str(x["text"]) + " "
		if not Dialogue.is_open(s):
			break
		var o := Dialogue.offered(s)
		var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[o.size() - 1]["id"] if o[0]["id"] != "ready" else "ready"}}
		evs = e.submit(s, c, a)["events"]
	return said
