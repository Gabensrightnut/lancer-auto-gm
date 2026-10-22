extends TestCase
## Enemy commanders as characters: taunts, parley (Core p.60), and coming back for revenge.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _ready_battle(seed_value: int, personality: String) -> Dictionary:
	var t := Setup.setup(seed_value)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.db = MissionTest.db()
	StoryArc.ensure(s, c)
	var hook: Dictionary = s.hooks[s.hooks.size() - 1]
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	_close(t)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm"})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	t["gen"] = gen
	var b := Rivals.battle(s)
	s.npcs[b["rival"]]["personality"] = personality
	return t


## Reads through a conversation, taking the first reply whenever one is offered.
func _close(t: Dictionary) -> void:
	var s: StoryState = t["story"]
	var guard := 0
	while Dialogue.is_open(s) and guard < 60:
		guard += 1
		var offered := Dialogue.offered(s)
		if offered.is_empty():
			t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
		else:
			t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": offered[offered.size() - 1]["id"]}})


func _down(t: Dictionary, ids: Array) -> Array:
	var evs: Array = [{"type": "round_started", "round": 2}]
	for id: String in ids:
		evs.append({"type": "unit_destroyed", "unit": id})
	return t["engine"].submit(t["story"], t["campaign"], {"type": "battle_events", "seat": "gm", "params": {"events": evs}})["events"]


func _until_choices(t: Dictionary) -> void:
	var s: StoryState = t["story"]
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 10:
		guard += 1
		t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})


func test_every_enemy_force_has_a_commander() -> void:
	var t := _ready_battle(160, "honorable")
	var s: StoryState = t["story"]
	var b := Rivals.battle(s)
	expect(not b.is_empty(), "the battle is tracked")
	var r: Dictionary = s.npcs[b["rival"]]
	expect_eq(r["role"], "enemy_commander")
	expect(not (r["portrait"] as Dictionary).is_empty(), "a portrait")
	var lead: Unit = (t["gen"]["state"] as GameState).unit(str(b["unit"]))
	expect(lead.name.begins_with(str(r["callsign"])), "the strongest enemy is the commander: %s" % lead.name)
	expect_eq(str(t["gen"]["mission"].flavor["commander"]["id"]), str(b["rival"]))
	var arc_cmd := str(s.arc.get("commander", ""))
	expect(arc_cmd != "" and s.npcs.has(arc_cmd), "the arc's other side has a commander")
	var barks := Rivals.barks_for(s, {"type": "combat_started"})
	expect_eq(barks.size(), 1, "the commander says hello")
	expect_eq(str(barks[0]["who"]), str(r["callsign"]))
	expect(not str(barks[0]["text"]).contains("{"), str(barks[0]["text"]))


func test_talking_terms_only_once_the_outcome_is_clear() -> void:
	var t := _ready_battle(161, "zealous")
	var s: StoryState = t["story"]
	var b0 := Rivals.battle(s)
	t["engine"].submit(s, t["campaign"], {"type": "battle_events", "seat": "gm", "params": {"events": [{"type": "unit_destroyed", "unit": (b0["enemy_ids"] as Array).filter(func(x: String) -> bool: return x != str(b0["unit"])).slice(0, ceili((b0["enemy_ids"] as Array).size() / 2.0))[0]}]}})
	var r: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "parley", "seat": "p1", "params": {}})
	expect(not r["ok"], "not while the fight is in question")
	expect(str(r["rule_ref"]).contains("p.60"))
	var b := Rivals.battle(s)
	var others: Array = (b["enemy_ids"] as Array).filter(func(id: String) -> bool: return id != str(b["unit"]))
	var evs := _down(t, others.slice(0, ceili((b["enemy_ids"] as Array).size() / 2.0)))
	expect(evs.any(func(x: Dictionary) -> bool: return x["type"] == "rival_defiant"), "a zealot won't offer terms")
	r = t["engine"].submit(s, t["campaign"], {"type": "parley", "seat": "p1", "params": {}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(str(s.dialogue.get("scene", "")), "parley")
	_until_choices(t)
	var ids: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return o["id"])
	expect(ids.has("fight") and ids.has("reason"), "defiant: reason with them or fight on: %s" % [ids])
	r = t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "fight"}})
	_close(t)
	expect(bool(Rivals.battle(s)["refused"]), "the fight goes on")
	expect(str(Rivals.battle(s)["ended"]) == "", "nothing ended")


func test_a_commander_surrenders_and_is_remembered() -> void:
	var t := _ready_battle(162, "honorable")
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var b := Rivals.battle(s)
	var id := str(b["rival"])
	var others: Array = (b["enemy_ids"] as Array).filter(func(x: String) -> bool: return x != str(b["unit"]))
	var evs := _down(t, others.slice(0, ceili((b["enemy_ids"] as Array).size() / 2.0)))
	expect(evs.any(func(x: Dictionary) -> bool: return x["type"] == "parley_offered" and x["kind"] == "yield"), "an honorable commander offers to yield")
	_until_choices(t)
	var r: Dictionary = t["engine"].submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "accept"}})
	expect(r["ok"], str(r["reason"]))
	var end: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "battle_end_requested")
	expect_eq(end.size(), 1, "the parley ends the fight")
	expect_eq(str(end[0]["outcome"]), "players")
	_close(t)
	var mission: Mission = t["gen"]["mission"]
	var act := CampaignLoop.end_by_parley(mission, end[0])
	expect_eq(str(act["type"]), "gm_end_mission")
	expect_eq(str(act["params"]["outcome"]), "players")
	var fin := CampaignLoop.finish_mission(c, s, t["engine"], t["gen"]["state"], mission, [])
	expect(fin["ok"], str(fin.get("reason", "")))
	expect_eq(str(s.npcs[id]["status"]), "captured")
	var said := ""
	var batch: Array = fin["events"]
	var guard := 0
	while guard < 40:
		guard += 1
		for x: Dictionary in batch:
			if x["type"] == "dialogue_line":
				said += str(x["text"]) + " "
		if not Dialogue.is_open(s):
			break
		var offered := Dialogue.offered(s)
		var act2 := {"type": "dialogue_next", "seat": "p1", "params": {}} if offered.is_empty() else {"type": "dialogue_choose", "seat": "p1", "params": {"choice": offered[0]["id"]}}
		batch = t["engine"].submit(s, c, act2)["events"]
	expect(said.contains(Rivals.call_name(s.npcs[id])), "the debrief mentions them: %s" % said)
	expect(Rivals.battle(s).is_empty(), "the battle is over")


func test_the_squad_can_walk_away_under_a_truce() -> void:
	var t := _ready_battle(163, "weary")
	var s: StoryState = t["story"]
	var b := Rivals.battle(s)
	var evs := _down(t, b["squad_ids"])
	expect(evs.any(func(x: Dictionary) -> bool: return x["type"] == "parley_offered" and x["kind"] == "offer_retreat"), "a weary commander lets the squad go")
	_until_choices(t)
	var r: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "withdraw_squad"}})
	var end: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "battle_end_requested")
	expect(not end.is_empty() and str(end[0]["outcome"]) == "enemies", "withdrawing loses the mission, but everyone lives")


func test_commanders_who_got_away_come_back() -> void:
	var t := Setup.setup(164)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var id := Rivals.make(s, c, "the Iron Tithe")
	s.npcs[id]["grudge"] = 2
	s.npcs[id]["met"] = 1
	s.npcs[id]["last"] = "escaped"
	var back := 0
	for i in range(40):
		var h := MissionHooks.make(s, c, "clear_raiders", {})
		if str(h.get("commander", {}).get("id", "")) == id:
			back += 1
			expect(bool(h["commander"]["returning"]))
			expect(str(h["stakes"]).contains(Rivals.call_name(s.npcs[id])), "the briefing warns you: %s" % h["stakes"])
	expect(back >= 3 and back <= 25, "revenge now and then (%d/40)" % back)
	s.npcs[id]["status"] = "captured"
	for i in range(20):
		expect(str(MissionHooks.make(s, c, "clear_raiders", {}).get("commander", {}).get("id", "")) != id, "a captured commander stays captured")
