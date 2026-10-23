extends TestCase
## Cloning (Core p.83-84), split decisions, world consequences, personal agendas.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _sub(t: Dictionary, type: String, params: Dictionary, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func test_a_clone_wakes_where_the_template_is() -> void:
	var t := Setup.setup(270)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	c.pilots[t["a"]]["ll"] = 4
	c.pilots[t["a"]]["origin"] = {"homeworld": "city", "upbringing": "street", "specialty": "hacker"}
	expect(not _sub(t, "store_template", {"pilot": t["a"], "kind": "facsimile"})["ok"], "facsimile needs sanctioned facilities")
	c.options["patron"] = "company"
	expect(_sub(t, "store_template", {"pilot": t["a"], "kind": "facsimile"})["ok"])
	var home := str(Sector.get_sector(s)["at"])
	var ev := StoryEffects.kill(s, t["a"], "Killed in action.")
	ev.append_array(Cloning.on_death(s, c, t["a"]))
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "clone_possible" and not bool(x["ready"])), "the clone isn't grown yet")
	for i in range(8):
		Cloning.tick(s)
	s.phase = "downtime"
	var far := ""
	for w: Dictionary in Sector.get_sector(s)["worlds"]:
		if str(w["id"]) != home:
			far = str(w["id"])
	_sub(t, "travel", {"world": far})
	expect(not _sub(t, "wake_clone", {"pilot": t["a"]})["ok"], "you have to go where the template is")
	_sub(t, "travel", {"world": home})
	var r := _sub(t, "wake_clone", {"pilot": t["a"]})
	expect(r["ok"], str(r["reason"]))
	expect(s.is_alive(t["a"]), "back")
	expect_eq(int(c.pilots[t["a"]]["ll"]), 4, "a clone keeps all License Levels (Core p.83)")
	expect(str(c.pilots[t["a"]]["origin"]["upbringing"]) != "street", "a slightly different backstory")
	expect_eq(int(Cloning.template(s, t["a"])["ready_in"]), 8, "the next clone starts growing")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "clone_woke" and str(x["note"]).contains("remember nothing")))


func test_one_extra_pilot_per_player() -> void:
	var t := Setup.setup(271)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	expect(_sub(t, "add_second_pilot", {"seat": "p1", "name": "Ada Okafor", "callsign": "Wren", "relation": "family"}, "p1")["ok"])
	expect(not _sub(t, "add_second_pilot", {"seat": "p1", "name": "Another", "relation": "friend"}, "p1")["ok"], "one extra pilot at most")
	var second := str(s.seats["p1"]["second"])
	expect(_sub(t, "set_active_pilot", {"seat": "p1", "pilot": second}, "p1")["ok"])
	expect_eq(s.pilot_of_seat("p1"), second, "they choose who flies")
	c.pilots[t["b"]]["deaths"] = 1
	expect(not _sub(t, "add_second_pilot", {"seat": "p2", "name": "X", "relation": "friend"})["ok"], "not after dying once")


func test_split_decisions_and_ai_followers() -> void:
	var t := Setup.setup(272)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	StoryEffects.apply({"decision": {"id": "mutiny", "prompt": "Take the ship from the captain", "accept": [{"set_flag": "mutinied"}], "decline": [{"set_flag": "loyal"}]}}, s, c, {})
	var r := _sub(t, "decide", {"accept": true}, "p1")
	expect(r["ok"] and bool(s.flags.get("mutinied", false)), "one human: their call stands, and the AI squadmate goes along")
	expect(not _sub(t, "decide", {"accept": true}, "p2")["ok"], "AI squadmates don't vote")
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	var cpid := str(c.new_pilot("Third", "Dove")["id"])
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p3", "pilot": cpid, "ai": true}})
	StoryEffects.apply({"decision": {"id": "captain", "prompt": "Put Bluebird in command", "accept": [{"set_flag": "new_captain"}], "decline": []}}, s, c, {})
	_sub(t, "decide", {"accept": true}, "p1")
	r = _sub(t, "decide", {"accept": false}, "p2")
	var split: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "party_split")
	expect(not split.is_empty() and bool(split[0]["gather"]), "the humans split: it comes to a fight, and it pulls everyone together")
	expect((split[0]["sides"]["accept"] as Array).has("p3"), "the AI squadmate stands with the lead human")
	r = _sub(t, "split_resolved", {"winner": "decline"})
	expect(r["ok"] and not s.flags.has("new_captain"), "the winners' choice stands")
	expect(not Decisions.gathering([{"type": "chapter_started"}]).is_empty(), "chapter starts gather the squad too")


func test_breaking_the_dam_dries_the_town() -> void:
	var t := Setup.setup(273)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook := {"template": "destroy_infrastructure", "place": "the old dam"}
	WorldState.after_mission(s, c, hook, true)
	expect_eq(str(WorldState.facts(s)["broken"]), "the old dam")
	s.mission_number += 1
	var ev := WorldState.tick(s, c)
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "consequence" and str(x["text"]).contains("the old dam")), "the water runs short")
	expect_eq(str(WorldState.facts(s)["water"]), "short")
	expect(s.hooks.any(func(h: Dictionary) -> bool: return str(h["template"]) == "make_it_right_water"), "a job to make it right")
	expect(StoryConditions.check({"world": "water", "eq": "short"}, s, c, {}), "scenes can ask about it")


func test_short_rations_build_a_grudge() -> void:
	var t := Setup.setup(274)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_sub(t, "house_rule", {"id": "hr_survival", "on": true})
	_sub(t, "house_rule", {"id": "hr_printers", "on": true})
	s.flags[Economy.WRECKED] = [t["b"]]
	Inventory.of(s, t["b"])["items"] = {}  # the supplies stowed in the wrecked mech are gone
	Economy.eat(s, c, 2)
	Economy.eat(s, c, 2)
	expect(Economy.hungry(s, c, t["b"]), "no mech of their own: going hungry")
	expect(int(Agendas.of(s, t["b"]).get("strength", 0)) >= 2, "and a grudge that grows")
	expect(StoryConditions.check({"agenda": "grievance"}, s, c, {}))
