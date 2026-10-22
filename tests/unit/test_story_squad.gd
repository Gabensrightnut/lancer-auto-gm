extends TestCase
## AI squadmates as characters, background-driven options and hooks, the new arcs, and how
## often lines repeat over a five-mission run.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_persona_follows_triggers_and_background() -> void:
	expect_eq(Squadmate.suggest({"skills": {"sk_apply_fists_to_faces": 2, "sk_assault": 1}, "background": "pbg_mercenary"}), "bold")
	expect_eq(Squadmate.suggest({"skills": {"sk_patch": 1, "sk_charm": 1}, "background": "pbg_medic"}), "kind")
	expect_eq(Squadmate.suggest({"skills": {"sk_hack_or_fix": 1, "sk_investigate": 1}, "background": "pbg_scientist"}), "curious")
	var t := Setup.setup(130)
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var s: StoryState = t["story"]
	var p := c.new_pilot("Grey", "Ash")
	p["skills"] = {"sk_survive": 2, "sk_take_someone_out": 1}
	p["background"] = "pbg_spec_ops"
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p3", "pilot": p["id"], "ai": true}})
	expect_eq(s.seats["p3"]["persona"], "grim", "no persona given: the build decides")


func test_role_comes_from_the_frame_or_persona() -> void:
	var db := MissionTest.db()
	var p := {"mechs": [{"id": "m", "frame": "mf_standard_pattern_i_everest"}], "active_mech": "m"}
	expect_eq(Squadmate.role(p, "kind", db)["role"], "Support", "the all-rounder Everest takes the persona's role")
	expect_eq(Squadmate.role(p, "kind", db)["stance"], "support")
	var drake := ""
	for f: Dictionary in db.all("frames"):
		if f.get("name", "") == "Drake":
			drake = f["id"]
	var p2 := {"mechs": [{"id": "m", "frame": drake}], "active_mech": "m"}
	expect_eq(Squadmate.role(p2, "bold", db)["role"], "Defender", "a Drake defends, whatever its pilot is like")


func test_memory_and_banter() -> void:
	var t := Setup.setup(131)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var third := c.new_pilot("Lin", "Wren")
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p3", "pilot": third["id"], "ai": true, "persona": "kind"}})
	Squadmate.observe(s, c, StoryEffects.harm(s, c, t["b"], 2))
	expect_eq(int(Squadmate.memory(s, t["b"])["wounds"]), 2)
	Squadmate.observe(s, c, StoryEffects.kill(s, third["id"], "test"))
	expect((Squadmate.memory(s, t["b"])["lost"] as Array).has("Wren"), "Kettle remembers Wren")
	expect_eq(Squadmate.topic(s, t["b"]), "lost_friend")
	var lines := Squadmate.banter(s, c, 2)
	expect(not lines.is_empty() and str(lines[0]["text"]).contains("Wren"), "banter mentions the fallen: %s" % [lines])
	expect_eq(Squadmate.topic(s, t["b"]), "arc" if not s.arc.is_empty() else "idle", "recent memories are spent once talked about")
	var persona: Dictionary = Dialogue.personas()["bold"]
	var shifted := Squadmate.likes(s, t["b"], persona)
	expect(float(shifted.get("kind", 0)) > float(persona["likes"].get("kind", 0)), "losing a friend softens them")
	var prefs := Squadmate.downtime_prefs(s, t["b"], persona)
	expect(str(prefs[0]) != "dt_get_a_damn_drink:Forget the last mission", "talked out: back to their usual downtime")


func test_grief_sends_them_to_the_bar() -> void:
	var t := Setup.setup(132)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var third := c.new_pilot("Lin", "Wren")
	Squadmate.observe(s, c, StoryEffects.kill(s, third["id"], "test"))
	var prefs := Squadmate.downtime_prefs(s, t["b"], Dialogue.personas()["steady"])
	expect_eq(str(prefs[0]), "dt_get_a_damn_drink:Forget the last mission")


func test_barks_are_in_character_and_cosmetic() -> void:
	var t := Setup.setup(133)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var dice_before := s.dice.get_state()
	var said: Array = []
	for i in range(30):
		said.append_array(Squadmate.barks_for(s, c, {"type": "attack_rolled", "attacker": "p2", "result": "crit", "n": i}, {"p2": t["b"]}, {"p2": "p2"}))
	expect(not said.is_empty(), "AI squadmates bark")
	var crit_lines: Array = Squadmate._json(Squadmate.BARKS)["personas"]["bold"]["crit"]
	for b: Dictionary in said:
		expect(crit_lines.has(b["text"]), "a bold pilot's crit line: %s" % b["text"])
	expect(Squadmate.barks_for(s, c, {"type": "attack_rolled", "attacker": "p1", "result": "hit"}, {"p1": t["a"]}, {"p1": "p1"}).is_empty(), "humans speak for themselves")
	expect_eq(s.dice.get_state(), dice_before, "barks never touch the story dice")


func test_background_options_and_personal_hooks() -> void:
	var t := Setup.setup(134)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	c.pilots[t["a"]]["background"] = "pbg_colonist"
	var local := Setup.npc_with_role(s, "local")
	if local != "":
		e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": local}})
		var guard := 0
		while Dialogue.offered(s).is_empty() and Dialogue.is_open(s) and guard < 4:
			e.submit(s, c, {"type": "dialogue_next", "seat": "p1"})
			guard += 1
		var ids: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return o["id"])
		expect(ids.has("bg_colonist_0"), "a colonist pilot gets the colonist option with a local: %s" % [ids])
		var r := e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "bg_colonist_0"}})
		expect(r["ok"], str(r["reason"]))
		expect(s.flags.has("bg_used:bg_colonist_0:" + local), "once per person")
		Dialogue.close(s)
	var personal := 0
	for i in range(20):
		var h := MissionHooks.make(s, c, "rescue", {})
		if h.has("personal"):
			personal += 1
			expect(str(h["stakes"]).contains("Bluebird"), "the stakes name the pilot: %s" % h["stakes"])
	expect(personal > 0, "rescues get personal for a colonist")


func test_new_arcs_and_twists_exist() -> void:
	var ids: Array = (StoryArc.data()["arcs"] as Array).map(func(a: Dictionary) -> String: return a["id"])
	for a in ["betrayal", "manhunt", "gold_rush"]:
		expect(ids.has(a), a)
	var tw: Array = (MissionHooks.pick_twist(RandomNumberGenerator.new(), "turncoat") as Dictionary).keys()
	expect(tw.has("reveal"))


## Five missions of story (briefing, debrief, banter, downtime, hub talk) with simulated
## results: the share of repeated lines stays low.
func test_five_missions_rarely_repeat_lines() -> void:
	var r := run_story(5, 909)
	print("        5-mission story: %d lines, %d unique, repeated %.1f%%" % [r["total"], r["unique"], r["rate"] * 100.0])
	expect(r["total"] > 60, "plenty was said")
	expect(r["rate"] < 0.25, "repeated-line rate %.2f" % r["rate"])


## Plays `missions` missions of story with AI on every seat. With `battles` the fights are
## real (AiDirector); otherwise results alternate. Returns line statistics.
static func run_story(missions: int, seed_value: int, battles: bool = false) -> Dictionary:
	var c := Campaign.create("Repeat test")
	c.id = "c_rep_%d" % seed_value
	var s := StoryState.new(seed_value)
	s.flags = c.story_flags
	var e := StoryEngine.new(MissionTest.db())
	var crew := [["Bluebird", {"sk_charm": 1, "sk_patch": 1}, "pbg_colonist"], ["Kettle", {"sk_assault": 2}, "pbg_soldier"], ["Halo", {"sk_hack_or_fix": 1, "sk_investigate": 1}, "pbg_hacker"]]
	for i in range(crew.size()):
		var p := c.new_pilot("Pilot %d" % i, crew[i][0])
		p["skills"] = crew[i][1]
		p["background"] = crew[i][2]
		e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p%d" % (i + 1), "pilot": p["id"], "ai": true}})
	e.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": seed_value}})
	var lines: Array = []
	var take := func(evs: Array) -> void:
		for x: Dictionary in evs:
			if str(x.get("type", "")) in ["dialogue_line", "banter"]:
				lines.append(str(x["text"]))
	for m in range(missions):
		var hook: Dictionary = s.hooks[0]
		for h: Dictionary in s.hooks:
			if h.has("arc"):
				hook = h
		take.call(_drive(e, s, c, e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})["events"]))
		e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
		var fin: Dictionary
		if battles:
			var gen := CampaignLoop.build_mission(c, s, MissionTest.db(), {"size": 20})
			var host := NetHost.new(gen["state"], RulesEngine.new())
			var director := AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])
			for seat: String in Squadmate.orders(s, c, MissionTest.db()):
				director.set_orders(seat, Squadmate.orders(s, c, MissionTest.db())[seat])
			host.set_fill_empty_with_ai(true)
			var evs: Array = []
			host.action_resolved.connect(func(_s: String, _a: Dictionary, _r: RuleResult, ev: Array) -> void: evs.append_array(ev))
			director.run(4000)
			fin = CampaignLoop.finish_mission(c, s, e, gen["state"], gen["mission"], evs)
		else:
			fin = e.submit(s, c, {"type": "mission_finished", "seat": "gm", "params": {"outcome": "victory" if m % 2 == 0 else "defeat", "reason": "sim",
				"summary": {"rounds": 4 + m, "kills": 3, "lost": [], "ejected": [], "mvp": crew[m % 3][0]}}})
		take.call(_drive(e, s, c, fin["events"]))
		e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
		take.call(e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})["events"])
		# Some hub talk each downtime: one person per mission, in turn.
		var npcs: Array = s.hub["npcs"]
		var npc: String = npcs[m % npcs.size()]
		var tr := e.submit(s, c, {"type": "talk", "seat": "p%d" % (m % 3 + 1), "params": {"npc": npc}})
		if tr["ok"]:
			take.call(_drive(e, s, c, tr["events"]))
		while not s.all_choices().is_empty():
			var pc: Dictionary = s.all_choices()[0]
			e.submit(s, c, {"type": "downtime_choose", "seat": "gm", "params": {"pilot": pc["pilot"], "picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])}})
		e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	var seen := {}
	var repeats := 0
	for l: String in lines:
		if seen.has(l):
			repeats += 1
		seen[l] = true
	return {"total": lines.size(), "unique": seen.size(), "repeats": repeats, "rate": float(repeats) / maxf(lines.size(), 1.0), "lines": lines}


static func _drive(e: StoryEngine, s: StoryState, c: Campaign, first: Array) -> Array:
	var out: Array = first.duplicate()
	var guard := 0
	while Dialogue.is_open(s) and guard < 25:
		guard += 1
		var o := Dialogue.offered(s)
		var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[mini(guard, o.size() - 1)]["id"]}}
		var r := e.submit(s, c, a)
		if not r["ok"]:
			Dialogue.close(s)
			break
		out.append_array(r["events"])
	if Dialogue.is_open(s):
		Dialogue.close(s)
	return out
