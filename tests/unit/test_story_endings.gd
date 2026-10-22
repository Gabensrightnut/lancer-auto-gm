extends TestCase
## Portraits for every speaker, squad bonds, campaign endings with epilogues, and a new
## campaign with the same pilots.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const Squad := preload("res://tests/unit/test_story_squad.gd")


func _full(spec: Dictionary) -> bool:
	if int(spec.get("version", 1)) < 2:
		return false
	for p: Dictionary in PortraitSpec.parts():
		if not spec.get("parts", {}).has(p["id"]):
			return false
	return true


func test_every_speaker_has_a_portrait() -> void:
	var r := Squad.run_story(2, 515)
	var t := Setup.setup(140)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	for id: String in s.npcs:
		expect(_full(s.npcs[id].get("portrait", {})), "NPC %s has a full portrait" % id)
	for pid: String in c.pilots:
		expect(_full(c.pilots[pid].get("portrait", {})), "pilot %s has a full portrait" % pid)
	var bar := Setup.npc_with_role(s, "bartender")
	var ev: Array = t["engine"].submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": bar}})["events"]
	for e: Dictionary in ev:
		if e["type"] == "dialogue_line" and e["speaker"] != "narrator":
			expect(_full(e["face"].get("portrait", {})), "dialogue lines carry the speaker's portrait")
			expect(PortraitSpec.expression_ids().has(str(e["face"]["expression"])))
	var bark := Squadmate.barks_for(s, c, {"type": "combat_started"}, {"p2": t["b"]}, {"p2": "p2"})
	for b: Dictionary in bark:
		expect(_full(b["face"]["portrait"]), "barks carry a portrait")
	expect(r["total"] > 0)


func test_bonds_grow_from_shared_history() -> void:
	var t := Setup.setup(141)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	expect_eq(Bonds.get_bond(s, t["a"], t["b"])["label"], "Squadmates")
	var ev: Array = []
	for i in range(3):
		ev.append_array(Bonds.observe(s, c, [{"type": "debrief", "outcome": "victory"}]))
	expect_eq(Bonds.get_bond(s, t["a"], t["b"])["label"], "Friends", "three missions survived together")
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "bond_changed"), "the debrief says so")
	var r := Bonds.observe(s, c, [{"type": "downtime_ended", "recap": []}])
	expect(r.any(func(x: Dictionary) -> bool: return x["type"] == "bond_reward"), "friends get the GM's bond reward (Core p.50)")
	expect_eq(Bonds.reward_between(s, t["a"], [t["b"]]), t["b"])
	s.dialogue = {"ctx": {"speaker": t["a"]}, "helpers": {}}
	var chk := Dialogue._roll_choice(s, c, {"skills": [], "teamwork": true, "fail_effects": []}, {"text": "x"}, {"speaker": t["a"]})
	var rec: Dictionary = (chk["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "narrative_check")[0]["check"]
	expect((rec["sources"] as Array).any(func(x: Dictionary) -> bool: return str(x["label"]).begins_with("Bond with")), "+1 Accuracy helping each other")
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	s.phase = "mission"
	e.submit(s, c, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory"}})
	expect(not s.flags.has(Bonds.REWARDS), "the reward lasts one mission")


func test_drinking_together_bonds_them() -> void:
	var t := Setup.setup(142)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var r := Bonds.observe(s, c, [{"type": "downtime_ended", "recap": [{"pilot": t["a"], "action": "dt_get_a_damn_drink"}, {"pilot": t["b"], "action": "dt_get_a_damn_drink"}]}])
	expect(int(Bonds.get_bond(s, t["a"], t["b"])["score"]) >= 2)
	expect(r.any(func(x: Dictionary) -> bool: return x["type"] == "bond_reward"), "the book's own example: drinking together")


func test_bonded_talent_bondmate_rules() -> void:
	var t := Setup.setup(143)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var third := c.new_pilot("Lin", "Wren")
	var no := e.submit(s, c, {"type": "set_bondmate", "seat": "p1", "params": {"pilot": t["a"], "mate": t["b"]}})
	expect(not no["ok"], "needs the Bonded talent")
	c.pilots[t["a"]]["talents"] = {"t_bonded": 1}
	expect(e.submit(s, c, {"type": "set_bondmate", "seat": "p1", "params": {"pilot": t["a"], "mate": t["b"]}})["ok"])
	var stuck := e.submit(s, c, {"type": "set_bondmate", "seat": "p1", "params": {"pilot": t["a"], "mate": third["id"]}})
	expect(not stuck["ok"] and "hasn't changed" in str(stuck["reason"]), "Core p.90: only if the relationship changed")
	for i in range(3):
		Bonds.observe(s, c, [{"type": "debrief"}])
	expect(e.submit(s, c, {"type": "set_bondmate", "seat": "p1", "params": {"pilot": t["a"], "mate": third["id"]}})["ok"], "the bond changed: now they can")


func test_campaign_ends_with_epilogues_and_a_sequel() -> void:
	var t := Setup.setup(144)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	c.options["campaign_arcs"] = 1
	s.flags["arc_done:escalation:%s" % s.hub["id"]] = "won"
	expect_eq(Ending.due(s, c), "arcs")
	expect_eq(Ending.kind_for(s, c), "triumph")
	s.phase = "mission"
	s.current_hook = {"place": "the ridge road", "title": "x"}
	e.submit(s, c, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory"}})
	Dialogue.close(s)
	var r := e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
	var ended: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "campaign_ended")
	expect_eq(ended.size(), 1, "the campaign ends after the last level up")
	expect_eq(s.phase, "ending")
	var ending: Dictionary = ended[0]["ending"]
	expect_eq((ending["epilogues"] as Array).size(), c.pilots.size(), "an epilogue per pilot")
	for ep: Dictionary in ending["epilogues"]:
		expect(str(ep["text"]).contains(str(ep["callsign"])), "epilogues name the pilot: %s" % ep["text"])
		expect(not str(ep["text"]).contains("{"), ep["text"])
	var next := CampaignLoop.sequel(c, s, e)
	var c2: Campaign = next["campaign"]
	var s2: StoryState = next["story"]
	expect_eq(c2.pilots.size(), c.pilots.size(), "the same pilots")
	expect_eq(int(c2.pilots[t["a"]]["ll"]), int(c.pilots[t["a"]]["ll"]), "they keep their License Level")
	expect(c2.story_flags.has("_legacy"))
	expect_eq(s2.phase, "briefing")
	expect(not s2.hooks.is_empty() and s2.hub["id"] != "" , "a new hub with work")
	var b: Dictionary = e.submit(s2, c2, {"type": "choose_hook", "seat": "gm", "params": {"hook": s2.hooks[0]["id"]}})
	var said := ""
	for x: Dictionary in b["events"]:
		if x["type"] == "dialogue_line":
			said += str(x["text"])
	expect(said.contains(c.name), "the new campaign's first briefing remembers the old one: %s" % said)


func test_endings_by_record() -> void:
	var t := Setup.setup(145)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	s.flags["arc_done:a:h"] = "won"
	s.flags["arc_done:b:h"] = "lost"
	expect_eq(Ending.kind_for(s, c), "bittersweet", "one each way")
	s.flags["arc_done:c:h"] = "lost"
	expect_eq(Ending.kind_for(s, c), "defeat")
	var t2 := Setup.setup(146)
	t2["story"].flags["arc_done:a:h"] = "won"
	StoryEffects.kill(t2["story"], t2["b"], "test")
	expect_eq(Ending.kind_for(t2["story"], t2["campaign"]), "bittersweet", "won, but someone died")
	StoryEffects.kill(t2["story"], t2["a"], "test")
	expect_eq(Ending.due(t2["story"], t2["campaign"]), "fallen")
