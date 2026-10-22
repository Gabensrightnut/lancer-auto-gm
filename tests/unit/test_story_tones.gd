extends TestCase
## Replies have tones; temper and patience decide how a conversation ends (DESIGN section 11).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _talk(t: Dictionary, npc: String) -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": "talk", "seat": "p1", "params": {"npc": npc}})


func _say(t: Dictionary, id: String) -> Dictionary:
	var s: StoryState = t["story"]
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 6:
		guard += 1
		t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
	if not Dialogue.offered(s).any(func(o: Dictionary) -> bool: return str(o["id"]) == id):
		return {"ok": false, "events": []}
	return t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": id}})


func test_insults_build_until_someone_draws() -> void:
	var t := Setup.setup(240)
	var s: StoryState = t["story"]
	var bar := Setup.npc_with_role(s, "bartender")
	var warned := false
	var drew := false
	for i in range(6):
		if not _talk(t, bar)["ok"]:
			break
		var r := _say(t, "insult")
		for x: Dictionary in r.get("events", []):
			warned = warned or x["type"] == "tension"
			drew = drew or x["type"] == "npc_draws"
		if drew:
			break
		Dialogue.close(s)
	expect(warned, "a warning before it gets ugly")
	expect(drew, "push far enough and the bartender draws")
	expect_eq(s.phase, "mission", "the fight starts right there")
	expect(bool(s.current_hook.get("in_town", false)) and str(s.current_hook.get("town_spot", "")) == "bar", "outside the bar")


func test_walking_away_and_patience() -> void:
	var t := Setup.setup(241)
	var s: StoryState = t["story"]
	var rep := Setup.npc_with_role(s, "company_rep")
	_talk(t, rep)
	var r := _say(t, "leave")
	expect(r["ok"] and not Dialogue.is_open(s) or Dialogue.current_node(s).get("end", false), "walking away ends it")
	expect_eq(Tones.temper(s, rep), 0, "and costs nothing")
	Dialogue.close(s)
	_talk(t, rep)
	s.dialogue["patience"] = 2
	r = _say(t, "push")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "patience_out"), "out of patience")
	expect(not Dialogue.is_open(s), "they end it")


func test_too_angry_to_talk_and_cooling_off() -> void:
	var t := Setup.setup(242)
	var s: StoryState = t["story"]
	var mech := Setup.npc_with_role(s, "mechanic")
	s.npcs[mech]["temper"] = 10
	var r := _talk(t, mech)
	expect(not r["ok"], "they won't talk to you")
	for i in range(4):
		t["engine"].submit(s, t["campaign"], {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	expect_eq(Tones.temper(s, mech), 9, "a day later they've cooled a little")
	expect(_talk(t, mech)["ok"])
	s.npcs[mech]["temper"] = 10
	Dialogue.close(s)
	t["engine"].submit(s, t["campaign"], {"type": "talk", "seat": "gm", "params": {"npc": mech}})
	expect(not Dialogue.is_open(s))
	s.npcs[mech]["temper"] = 8
	_talk(t, mech)
	r = _say(t, "insult")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "thrown_out"), "someone unarmed throws you out instead")
	expect_eq(s.phase != "mission", true)
