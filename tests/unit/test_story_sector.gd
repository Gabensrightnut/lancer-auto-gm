extends TestCase
## The sector map: systems, worlds with their own kits, narrative travel (Core p.10).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func test_the_sector_around_the_first_hub() -> void:
	var t := Setup.setup(190)
	var s: StoryState = t["story"]
	var sec := Sector.get_sector(s)
	expect_eq((sec["systems"] as Array).size(), 3)
	var names := {}
	for sys: Dictionary in sec["systems"]:
		expect((sys["worlds"] as Array).size() >= 2 and (sys["worlds"] as Array).size() <= 3, "2-3 worlds per system")
	for w: Dictionary in sec["worlds"]:
		expect(not names.has(w["name"]), "world names are distinct: %s" % w["name"])
		names[w["name"]] = true
		expect(NpcGen.cultures().has(str(w["culture"])), "a real culture kit: %s" % w["culture"])
		expect(str(w["landscape"]) != "", "a landscape")
	var here := Sector.current(s)
	expect_eq(str(here["hub_id"]), str(s.hub["id"]), "the squad starts at the first hub")
	expect_eq(str(here["name"]), str(s.hub["planet"]))
	for h: Dictionary in s.hooks:
		expect_eq(str(h["landscape"]), str(here["landscape"]), "jobs are on this world's ground")


func test_travel_between_worlds_keeps_each_hub() -> void:
	var t := Setup.setup(191)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	StoryArc.ensure(s, c)
	var first_hub := str(s.hub["id"])
	var first_npcs: Array = (s.hub["npcs"] as Array).duplicate()
	var arc_id := str(s.arc.get("id", ""))
	var far: Dictionary = {}
	for w: Dictionary in Sector.get_sector(s)["worlds"]:
		if str(w["system"]) == "sys_1":
			far = w
	expect(not e.submit(s, c, {"type": "travel", "seat": "p1", "params": {"world": far["id"]}})["ok"], "the host moves the squad")
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": s.hooks[0]["id"]}})
	var r: Dictionary = e.submit(s, c, {"type": "travel", "seat": "gm", "params": {"world": far["id"]}})
	expect(not r["ok"], "not while a job is under way")
	s.current_hook = {}
	Dialogue.close(s)
	s.phase = "downtime"
	var first_hooks: Array = s.hooks.map(func(h: Dictionary) -> String: return h["id"])
	r = e.submit(s, c, {"type": "travel", "seat": "gm", "params": {"world": far["id"]}})
	expect(r["ok"], str(r["reason"]))
	var tr: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "travelled")
	expect(not tr.is_empty() and str(tr[0]["via"]) == "blink gate" and str(tr[0]["rule_ref"]).contains("p.10"), "another system: through the blink gate")
	expect(not str(tr[0]["text"]).contains("{"), str(tr[0]["text"]))
	expect_eq(str(s.hub["culture"]), str(far["culture"]), "the new hub has the world's culture")
	expect_eq(str(s.hub["planet"]), str(far["name"]))
	expect(not s.hooks.is_empty(), "work waiting there")
	expect(bool(Sector.world(s, far["id"])["visited"]))
	expect(not Sector.factions_of(s, Sector.world(s, "w_0_0")).is_empty(), "the map remembers who you dealt with")
	r = e.submit(s, c, {"type": "travel", "seat": "gm", "params": {"world": "w_0_0"}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(str(s.hub["id"]), first_hub, "back where you started")
	expect_eq(s.hub["npcs"], first_npcs, "the same people")
	var now: Array = s.hooks.map(func(h: Dictionary) -> String: return h["id"])
	expect(first_hooks.all(func(id: String) -> bool: return now.has(id)), "the same job board (topped up): %s vs %s" % [first_hooks, now])
	expect_eq(str(s.arc.get("id", "")), arc_id, "and the same situation")


## A whole campaign, results simulated: three situations on different worlds, then the ending.
func test_a_three_arc_campaign_travels_and_ends() -> void:
	var t := Setup.setup(192)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var worlds := {}
	var broken: Array = []
	var guard := 0
	while s.phase != "ending" and guard < 30:
		guard += 1
		if s.phase == "downtime":
			if s.arc.is_empty() and int(s.hub.get("arc_ended", -99)) >= 0:
				for w: Dictionary in Sector.get_sector(s)["worlds"]:
					if not bool(w["visited"]):
						expect(e.submit(s, c, {"type": "travel", "seat": "gm", "params": {"world": w["id"]}})["ok"])
						break
			e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
			Dialogue.close(s)
		StoryArc.ensure(s, c)
		worlds[str(Sector.current(s)["id"])] = true
		var hook: Dictionary = s.hooks[0]
		for h: Dictionary in s.hooks:
			if h.has("arc"):
				hook = h
		e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
		Dialogue.close(s)
		e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
		var r := e.submit(s, c, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory" if guard % 3 != 0 else "defeat", "reason": "sim",
			"summary": {"rounds": 4, "kills": 3, "lost": [], "ejected": [], "mvp": ""}}})
		for x: Dictionary in r["events"]:
			if str(x.get("text", "")).contains("{"):
				broken.append(x["text"])
		Dialogue.close(s)
		if s.phase == "ending":
			break
		e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
		if s.phase == "ending":
			break
		for pid: String in s.pending_picks.keys():
			var lp := e.submit(s, c, {"type": "level_picks", "seat": "gm", "params": pick_for(c.pilots[pid])})
			expect(lp["ok"] or str(lp["reason"]).contains("already picked"), str(lp["reason"]))
		var sd := e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
		expect(sd["ok"], str(sd["reason"]))
		while not s.all_choices().is_empty():
			var pc: Dictionary = s.all_choices()[0]
			e.submit(s, c, {"type": "downtime_choose", "seat": "gm", "params": {"pilot": pc["pilot"], "picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])}})
	expect_eq(s.phase, "ending", "the campaign reaches its ending (%d missions)" % (s.mission_number - 1))
	expect(worlds.size() >= 3, "three situations on three worlds: %s" % [worlds.keys()])
	expect(broken.is_empty(), "no broken text: %s" % [broken])


## A legal level-up pick: a trigger and a mech skill that aren't at their cap yet.
static func pick_for(p: Dictionary) -> Dictionary:
	var trig := "sk_spot"
	for t: String in ["sk_spot", "sk_survive", "sk_patch", "sk_stay_cool", "sk_read_a_situation", "sk_assault", "sk_charm", "sk_investigate"]:
		if int(p.get("skills", {}).get(t, 0)) < 3:  # ranks: +2 each, +6 at most
			trig = t
			break
	var ms := "hull"
	for m: String in ["hull", "agility", "systems", "engineering"]:
		if int(p.get(m, 0)) < 6:
			ms = m
			break
	return {"pilot": p["id"], "trigger": trig, "mech_skill": ms}
