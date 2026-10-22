extends TestCase
## Doing things yourself in town (TownLife): the clock, schedules, things kept somewhere,
## the book's skill triggers for sneaking and theft, witnesses; and comms (radio, Jammed).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _do(t: Dictionary, type: String, params: Dictionary) -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": "gm", "params": params})


func _wait_until(t: Dictionary, p: String) -> void:
	for i in range(4):
		if TownLife.period(t["story"]) == p:
			return
		_do(t, "wait", {"periods": 1})


func test_the_clock_and_where_people_are() -> void:
	var t := Setup.setup(230)
	var s: StoryState = t["story"]
	expect_eq(TownLife.period(s), "day")
	var bar := Setup.npc_with_role(s, "bartender")
	var w := TownLife.where_npc(s, bar)
	expect(str(w["spot"]) == "bar" and str(w["room"]) == "main" and not bool(w["asleep"]), "the bartender works the bar by day")
	var r := _do(t, "wait", {"periods": 2})
	expect(r["ok"] and TownLife.period(s) == "night" and TownLife.is_dark(s))
	expect(str((r["events"] as Array)[0]["text"]).to_lower().contains("night"), str(r["events"][0]["text"]))
	w = TownLife.where_npc(s, bar)
	expect(bool(w["asleep"]) and str(w["room"]) == "upstairs", "and sleeps upstairs")
	_do(t, "wait", {"periods": 2})
	expect_eq(int(TownLife.clock(s)["day"]), 2, "a new day")


func test_breaking_into_the_office_at_night() -> void:
	var t := Setup.setup(231)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	c.pilots[t["a"]]["skills"]["sk_hack_or_fix"] = 3
	var rep := Setup.npc_with_role(s, "company_rep")
	var papers := "%s_papers" % rep
	expect(not TownLife.item(s, papers).is_empty(), "the company rep keeps papers in the office safe")
	expect(not _do(t, "go", {"pilot": t["a"], "spot": "office", "room": "safe"})["ok"], "the safe is locked")
	expect(not _do(t, "take", {"pilot": t["a"], "item": papers})["ok"], "you can't just take it")
	_wait_until(t, "evening")
	expect_eq(str(TownLife.where_npc(s, rep)["spot"]), "bar", "evenings, the rep drinks at the bar")
	var opened := false
	for i in range(12):
		var r := _do(t, "pick_lock", {"pilot": t["a"], "spot": "office", "room": "safe"})
		expect(r["ok"], str(r["reason"]))
		expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "narrative_check" and str(x["rule_ref"]).contains("Hack or Fix")), "a Hack or Fix check (Core p.26)")
		if TownLife.is_open(s, "office", "safe"):
			opened = true
			break
	expect(opened, "the lock gives eventually")
	_do(t, "go", {"pilot": t["a"], "spot": "office", "room": "front"})
	var r := _do(t, "take", {"pilot": t["a"], "item": papers})
	expect(r["ok"], str(r["reason"]))
	expect_eq(str(TownLife.item(s, papers)["holder"]), t["a"])
	expect(bool(s.flags.get("secret_known:%s" % rep, false)), "reading them tells you their secret")
	var missed := false
	for i in range(4):
		for x: Dictionary in _do(t, "wait", {"periods": 1})["events"]:
			if x["type"] == "item_missed":
				missed = true
	expect(missed, "sooner or later they notice")
	expect(int(s.npcs[rep].get("temper", 0)) > 0, "and they're angry")


func test_pickpocketing_and_following() -> void:
	var t := Setup.setup(232)
	var s: StoryState = t["story"]
	var fixer := ""
	for id: String in s.hub["npcs"]:
		if s.npcs[id]["role"] == "fixer":
			fixer = id
	if fixer == "":
		fixer = Setup.npc_with_role(s, "bartender")
		TownLife.add_item(s, {"id": "%s_ledger" % fixer, "name": "a ledger", "owner": fixer, "kept": "person", "value": 20})
	var w := TownLife.where_npc(s, fixer)
	expect(not _do(t, "pickpocket", {"pilot": t["a"], "npc": fixer, "item": "%s_ledger" % fixer})["ok"], "you have to be where they are")
	_do(t, "go", {"pilot": t["a"], "spot": w["spot"], "room": w["room"]})
	var r := _do(t, "pickpocket", {"pilot": t["a"], "npc": fixer, "item": "%s_ledger" % fixer})
	expect(r["ok"], str(r["reason"]))
	var taken := (r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "item_taken")
	var caught := (r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "seen" and (x["witnesses"] as Array).has(fixer))
	expect(taken != caught, "either you get it, or they catch your hand")
	r = _do(t, "follow", {"pilot": t["b"], "npc": Setup.npc_with_role(s, "mechanic")})
	expect(r["ok"], str(r["reason"]))
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] in ["learned", "noticed"]))


func test_comms_and_jammed() -> void:
	var t := Setup.setup(233)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var bar := Setup.npc_with_role(s, "bartender")
	var scene := {"npc": bar, "lines": [{"who": "npc", "text": "Lancers, do you read?"}], "choices": [{"text": "Loud and clear."}, {"text": "Say again?"}]}
	GmTools.apply(s, c, "gm_scene", scene.merged({"start": false}), t["a"])
	var r: Array = Dialogue.start(s, c, "gm_0", {"speaker": t["a"], "npc": bar, "mode": "radio", "channel": "Squad channel"})
	var line: Dictionary = r.filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line")[0]
	expect(str(line["mode"]) == "radio" and str(line["channel"]) == "Squad channel", "over comms")
	expect_eq(Dialogue.offered(s).size(), 2)
	Dialogue.close(s)
	Rivals._track_jammed(s, [{"type": "status_added", "unit": "p1", "status": "Jammed"}])
	expect(Dialogue.is_jammed(s, t["a"]), "Jammed pilot tracked from battle events")
	var ev: Array = Dialogue.start(s, c, "gm_0", {"speaker": t["a"], "npc": bar, "mode": "radio"})
	line = ev.filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line")[0]
	expect(bool(line["jammed"]) and str(line["text"]).contains("static"), "a Jammed pilot gets static")
	expect(Dialogue.offered(s).is_empty(), "and can't reply")
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
	expect(not Dialogue.is_open(s), "the call drops")
	Rivals._track_jammed(s, [{"type": "status_removed", "unit": "p1", "status": "Jammed"}])
	expect(not Dialogue.is_jammed(s, t["a"]))
	ev = Dialogue.start(s, c, "gm_0", {"speaker": t["a"], "npc": bar})
	expect_eq(str(ev.filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line")[0]["mode"]), "talk", "face to face by default")
