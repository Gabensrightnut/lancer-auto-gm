extends TestCase
## The procedural GM's story tables: deals (a job for a reserve), hidden twists, arcs, the
## hub's two-sided conflict, and supplies the book's way.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _submit(t: Dictionary, type: String, params: Dictionary = {}, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func _run_dialogue(t: Dictionary, prefer: String = "") -> Array:
	var s: StoryState = t["story"]
	var all: Array = []
	var guard := 0
	while Dialogue.is_open(s) and guard < 30:
		guard += 1
		var offered := Dialogue.offered(s)
		var r: Dictionary
		if offered.is_empty():
			r = _submit(t, "dialogue_next", {}, "p1")
		else:
			var pick: Dictionary = offered[0]
			for o: Dictionary in offered:
				if o["id"] == prefer:
					pick = o
			r = _submit(t, "dialogue_choose", {"choice": pick["id"]}, "p1")
		all.append_array(r["events"])
	return all


func _play(t: Dictionary, hook_id: String, outcome: String) -> Dictionary:
	_submit(t, "choose_hook", {"hook": hook_id})
	_run_dialogue(t, "ready")
	_submit(t, "confirm_reserves")
	var r := _submit(t, "mission_finished", {"outcome": outcome, "reason": "test"})
	_run_dialogue(t)
	return r


func _lines(events: Array) -> String:
	var out := ""
	for e: Dictionary in events:
		if e["type"] == "dialogue_line":
			out += str(e["text"]) + " "
	return out


func test_hub_has_a_two_sided_conflict() -> void:
	var t := Setup.setup(80)
	var s: StoryState = t["story"]
	var c: Dictionary = s.hub["conflict"]
	expect(not c.is_empty(), "every hub has a situation")
	expect(c["a"] == s.hub["faction"] and c["b"] != c["a"])
	expect(not str(c["summary"]).contains("{"), str(c["summary"]))


func test_helping_one_side_costs_with_the_other() -> void:
	var t := Setup.setup(81)
	var s: StoryState = t["story"]
	var hook: Dictionary = {}
	for h: Dictionary in s.hooks:
		if str(h.get("rival", "")) != "":
			hook = h
	expect(not hook.is_empty(), "some job is for one side of the conflict")
	if hook.is_empty():
		return
	var rival := str(hook["rival"])
	_play(t, hook["id"], "victory")
	expect(s.get_standing(rival) < 0, "the other side noticed")


func test_deal_pays_a_reserve_for_the_next_mission() -> void:
	var t := Setup.setup(82)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var npc := Setup.npc_with_role(s, "bartender")
	expect(StoryConditions.check({"deal": "$npc", "state": "none"}, s, c, {"npc": npc}))
	var ev := StoryEffects.apply({"deal": {"template": "$npc.want_hook", "fallback": "clear_raiders"}}, s, c, {"npc": npc, "speaker": t["a"]})
	expect_eq(ev[0]["type"], "deal_made")
	expect_eq(s.deals[npc]["state"], "accepted")
	var hook: Dictionary = ev[0]["hook"]
	var reward := str(s.npcs[npc]["deal_reward"])
	_play(t, hook["id"], "victory")
	expect_eq(s.deals[npc]["state"], "won")
	expect(s.has_reserve(t["a"], reward), "the reward is a reserve, kept for the next mission")


func test_lost_deal_is_withdrawn() -> void:
	var t := Setup.setup(83)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var npc := Setup.npc_with_role(s, "company_rep")
	var ev := StoryEffects.apply({"deal": {"template": "clear_raiders"}}, s, c, {"npc": npc, "speaker": t["a"]})
	_play(t, ev[0]["hook"]["id"], "defeat")
	expect_eq(s.deals[npc]["state"], "lost")
	expect(not s.has_reserve(t["a"], str(s.npcs[npc]["deal_reward"])))
	s.phase = "downtime"
	Downtime.start(s, c)
	var r := _submit(t, "talk", {"npc": npc}, "p1")
	var said := _lines(r["events"]).to_lower()
	expect("deal" in said or "offer" in said, "they tell you the deal is off: %s" % said)
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 4:
		_submit(t, "dialogue_next", {}, "p1")
		guard += 1
	var ids: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return o["id"])
	expect(not ids.has("deal"), "no new deal with them")
	expect(ids.has("favor"), "but you can still Get Connected another way: %s" % [ids])


func test_twist_is_revealed_at_the_debrief() -> void:
	var t := Setup.setup(84)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook := MissionHooks.make(s, c, "recover_cargo", {"twist": "patron_lied"})
	expect_eq(hook["twist"]["id"], "patron_lied")
	s.hooks.append(hook)
	var r := _play(t, hook["id"], "victory")
	expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "twist_revealed"))
	expect(bool(s.flags.get("patron_lied:" + str(hook["patron"]), false)), "its consequence sticks")


func test_arc_moves_on_every_mission_and_ends() -> void:
	var t := Setup.setup(85)
	var s: StoryState = t["story"]
	expect(not s.arc.is_empty(), "an arc starts at the hub")
	if s.arc.is_empty():
		return
	var stages := (StoryArc.arc_def(str(s.arc["id"]))["stages"] as Array).size()
	var arc_id := str(s.arc["id"])
	for i in range(stages):
		var hook: Dictionary = {}
		for h: Dictionary in s.hooks:
			if h.get("arc", {}).get("id", "") == arc_id:
				hook = h
		expect(not hook.is_empty(), "stage %d is on the board" % i)
		if hook.is_empty():
			return
		expect_eq(int(hook["arc"]["stage"]), i)
		_play(t, hook["id"], "victory" if i % 2 == 0 else "defeat")
		_submit(t, "level_up")
		for pid: String in s.pending_picks:
			_submit(t, "level_picks", {"pilot": pid, "trigger": "sk_spot", "mech_skill": "hull"})
		_submit(t, "start_downtime")
		while not s.pending_choice.is_empty():
			var pc := s.pending_choice
			_submit(t, "downtime_choose", {"picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])})
		_submit(t, "end_downtime")
	expect(s.flags.has("arc_done:%s:%s" % [arc_id, s.hub["id"]]), "the arc finished and was remembered")
	expect(s.arc.is_empty(), "the world stays quiet for a while: time for side jobs, or to travel on")
	s.mission_number += StoryArc.QUIET
	StoryArc.ensure(s, t["campaign"])
	expect(not s.arc.is_empty() and int(s.arc["stage"]) == 0, "then a new situation begins")


func test_hazardous_crossing_without_supplies_is_a_challenge() -> void:
	var t := Setup.setup(86)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook := MissionHooks.make(s, c, "rescue", {})
	expect(bool(hook["hazardous"]))
	s.hooks.append(hook)
	_submit(t, "choose_hook", {"hook": hook["id"]})
	var guard := 0
	var seen_journey := false
	while Dialogue.is_open(s) and guard < 10:
		guard += 1
		var ids: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return o["id"])
		if ids.has("cross"):
			seen_journey = true
			var r := _submit(t, "dialogue_choose", {"choice": "cross"}, "p1")
			expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "skill_challenge"), "everyone rolls")
			break
		if ids.is_empty():
			_submit(t, "dialogue_next", {}, "p1")
		else:
			_submit(t, "dialogue_choose", {"choice": ids[0]}, "p1")
	expect(seen_journey, "no Supplies: the crossing is a skill challenge (Core p.47)")
	var t2 := Setup.setup(86)
	var s2: StoryState = t2["story"]
	StoryEffects.apply({"reserve": "reserve_supplies"}, s2, t2["campaign"], {"speaker": t2["b"]})
	var h2 := MissionHooks.make(s2, t2["campaign"], "rescue", {})
	s2.hooks.append(h2)
	_submit(t2, "choose_hook", {"hook": h2["id"]})
	var crossed := false
	guard = 0
	while Dialogue.is_open(s2) and guard < 10:
		guard += 1
		var ids: Array = Dialogue.offered(s2).map(func(o: Dictionary) -> String: return o["id"])
		crossed = crossed or ids.has("cross")
		if ids.is_empty():
			_submit(t2, "dialogue_next", {}, "p1")
		else:
			_submit(t2, "dialogue_choose", {"choice": "ready" if ids.has("ready") else ids[0]}, "p1")
	expect(not crossed, "Supplies: gear for crossing a hazardous area (reserves table)")


func test_scrounge_for_supplies_gives_the_book_reserve() -> void:
	var t := Setup.setup(87)
	var s: StoryState = t["story"]
	s.phase = "level_up"
	_submit(t, "start_downtime")
	var r := _submit(t, "downtime_action", {"pilot": t["a"], "action": "dt_scrounge_and_barter", "subject": "Supplies for crossing hostile ground"}, "p1")
	expect(r["ok"], str(r["reason"]))
	expect(s.has_reserve(t["a"], "reserve_supplies"))
	var t2 := Setup.setup(88)
	t2["story"].phase = "level_up"
	_submit(t2, "start_downtime")
	_submit(t2, "downtime_action", {"pilot": t2["a"], "action": "dt_scrounge_and_barter", "subject": "Spare repair materials for the mech"}, "p1")
	expect(t2["story"].has_reserve(t2["a"], "reserve_extra_repairs"), "+2 Repair Cap reserve")


func test_reading_someone_reveals_their_secret() -> void:
	var t := Setup.setup(89)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	for id: String in s.hub["npcs"]:
		expect(str(s.npcs[id].get("secret", "")) != "", "everyone has a secret")
		expect(str(s.npcs[id].get("deal_reward", "")).begins_with("reserve_"))
	c.pilots[t["a"]]["skills"]["sk_read_a_situation"] = 3
	var local := Setup.npc_with_role(s, "local")
	if local == "":
		return
	var found := false
	for attempt in range(8):
		s.failed_goals.clear()
		s.flags.erase("read:" + local)
		var evs: Array = _submit(t, "talk", {"npc": local}, "p1")["events"]
		var guard := 0
		while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 4:
			evs.append_array(_submit(t, "dialogue_next", {}, "p1")["events"])
			guard += 1
		if Dialogue.offered(s).any(func(o: Dictionary) -> bool: return o["id"] == "read"):
			evs.append_array(_submit(t, "dialogue_choose", {"choice": "read"}, "p1")["events"])
			found = str(s.npcs[local]["secret"]) in _lines(evs)
		if Dialogue.is_open(s):
			Dialogue.close(s)
		if found:
			break
	expect(found, "Read a Situation shows what they're hiding")
