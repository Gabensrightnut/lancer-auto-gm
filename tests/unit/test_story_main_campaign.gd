extends TestCase
## The authored main campaign, "The Long Arrival" (CampaignScript, DESIGN.md section 11).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Picks := preload("res://tests/unit/test_story_sector.gd")


static func fresh(seed_value: int) -> Dictionary:
	var c := Campaign.create("The Long Arrival")
	c.id = "c_main_%d" % seed_value
	var a := c.new_pilot("Ama Okafor", "Bluebird")
	var b := c.new_pilot("Rin Sato", "Kettle")
	a["skills"] = {"sk_charm": 2, "sk_hack_or_fix": 3, "sk_act_unseen_or_unheard": 2}
	b["skills"] = {"sk_threaten": 2, "sk_assault": 2}
	var s := StoryState.new(seed_value)
	s.flags = c.story_flags
	var e := StoryEngine.new(MissionTest.db())
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": b["id"], "ai": true, "persona": "bold"}})
	var ev := CampaignScript.begin(s, c, e)
	return {"campaign": c, "story": s, "engine": e, "a": a["id"], "b": b["id"], "events": ev}


## Plays one chapter: its mission (won or lost, a real battle setup), the debrief, the
## conversation after it (reply number `pick`), and the end of downtime.
static func play_chapter(t: Dictionary, pick: int, won: bool = true, town: Callable = Callable()) -> void:
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var hook: Dictionary = {}
	for h: Dictionary in s.hooks:
		if h.has("chapter"):
			hook = h
	if hook.is_empty():
		return
	if town.is_valid():
		town.call(t)
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	Dialogue.close(s)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var mission: Mission = gen["mission"]
	t["last_mission"] = mission
	mission.outcome = Mission.PLAYERS if won else Mission.ENEMIES
	CampaignLoop.finish_mission(c, s, e, gen["state"], mission, [])
	Dialogue.close(s)
	if s.phase == "ending":
		return
	e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
	if s.phase == "ending":
		return
	for pid: String in s.pending_picks.keys():
		e.submit(s, c, {"type": "level_picks", "seat": "gm", "params": Picks.pick_for(c.pilots[pid])})
	e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	var guard := 0
	while Dialogue.is_open(s) and guard < 20:
		guard += 1
		var o := Dialogue.offered(s)
		if o.is_empty():
			e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
		else:
			var plain: Array = o.filter(func(x: Dictionary) -> bool: return not bool(x.get("extra", false)))
			e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": plain[mini(pick, plain.size() - 1)]["id"]}})
	Dialogue.close(s)
	while not s.all_choices().is_empty():
		var pc: Dictionary = s.all_choices()[0]
		e.submit(s, c, {"type": "downtime_choose", "seat": "gm", "params": {"pilot": pc["pilot"], "picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(x: Dictionary) -> String: return x["id"])}})
	e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	Dialogue.close(s)


## A whole run: `picks` is the reply for each chapter's conversation, in order.
static func run(seed_value: int, picks: Array, final_won: bool = true, find_plot: bool = false) -> Dictionary:
	var t := fresh(seed_value)
	var s: StoryState = t["story"]
	var i := 0
	var site := ""
	while s.phase != "ending" and i < 16:
		var ch := CampaignScript.chapter(s, t["campaign"])
		var final := bool(ch.get("final", false))
		if final:
			site = str(CampaignScript.state(s).get("chapter", ""))
		# Finding the militia's plans is something you do in town (follow Cass, break into the
		# storeroom); here it's simply done for the paths that need it.
		var town := func(tt: Dictionary) -> void:
			if find_plot and str(CampaignScript.state(tt["story"]).get("chapter", "")) == "c5_plot":
				(tt["story"] as StoryState).flags["la_plot_found"] = true
		play_chapter(t, int(picks[i % picks.size()]), final_won if final else true, town)
		i += 1
	var st := CampaignScript.state(s)
	var flav: Dictionary = (t["last_mission"] as Mission).flavor if t.has("last_mission") else {}
	return {"t": t, "ending": str(st.get("ending", "")), "chain": (st.get("branches", {}) as Dictionary).duplicate(), "site": site,
		"allies": flav.get("allies", []), "foe": str(flav.get("commander", {}).get("name", "")), "chapters": i}


func test_the_campaign_starts_in_redwater() -> void:
	var t := fresh(300)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	expect(CampaignScript.active(c))
	expect_eq(str(s.hub["planet"]), "Calder's Reach")
	expect_eq(str(s.hub["name"]), "Redwater")
	expect(s.npcs.has("cs_ione") and (s.hub["npcs"] as Array).has("cs_ione"), "Ione Sarkis runs the bar")
	expect(not (s.hub["npcs"] as Array).any(func(n: String) -> bool: return s.npcs[n]["role"] == "bartender" and n != "cs_ione"), "instead of a generated bartender")
	var codes := TownLife.item(s, "la_codes")
	expect(str(codes["spot"]) == "bar" and str(codes["room"]) == "upstairs" and int(codes["lock"]) == 2, "the key-codes are in her safe upstairs")
	var jobs: Array = s.hooks.filter(func(h: Dictionary) -> bool: return h.has("chapter"))
	expect_eq(jobs.size(), 1, "one authored job")
	expect_eq(s.hooks.size(), 1, "and no procedural plot")
	expect_eq(str(jobs[0]["title"]), "Fire in the Sky")
	expect(str(jobs[0].get("commander", {}).get("name", "")).contains("Rook"), "Boss Rook leads the raiders")
	expect((t["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "chapter_started"))


func test_the_key_codes_can_be_taken_at_night() -> void:
	var t := fresh(301)
	var s: StoryState = t["story"]
	play_chapter(t, 0)
	expect_eq(str(CampaignScript.state(s)["chapter"]), "c2_codes")
	var e: StoryEngine = t["engine"]
	var c: Campaign = t["campaign"]
	for i in range(3):
		if TownLife.period(s) == "night":
			break
		e.submit(s, c, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	expect(bool(TownLife.where_npc(s, "cs_ione")["asleep"]), "Ione's asleep upstairs at night")
	var open := false
	for i in range(12):
		e.submit(s, c, {"type": "pick_lock", "seat": "gm", "params": {"pilot": t["a"], "spot": "bar", "room": "upstairs"}})
		if TownLife.is_open(s, "bar", "upstairs"):
			open = true
			break
	expect(open)
	e.submit(s, c, {"type": "go", "seat": "gm", "params": {"pilot": t["a"], "spot": "bar", "room": "upstairs"}})
	var r := e.submit(s, c, {"type": "take", "seat": "gm", "params": {"pilot": t["a"], "item": "la_codes"}})
	expect(r["ok"], str(r["reason"]))
	expect(bool(s.flags.get("la_codes_stolen", false)), "nobody offered 'steal': you just did it")
	play_chapter(t, 0)
	expect_eq(str(CampaignScript.state(s)["branches"].get("b2", "")), "stolen")


func test_eighteen_paths_really_differ() -> void:
	var paths := [[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
		[0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0], [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1], [2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
		[0, 2, 1, 0, 2, 1, 0, 2, 1, 0, 2], [1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2], [0, 0, 1, 1, 2, 2, 0, 0, 1, 1, 2],
		[2, 1, 0, 0, 1, 2, 2, 1, 0, 0, 1], [1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 0], [0, 1, 2, 2, 1, 0, 0, 1, 2, 2, 1],
		[2, 2, 0, 1, 1, 0, 2, 2, 0, 1, 1], [1, 0, 0, 2, 2, 1, 1, 0, 0, 2, 2], [0, 2, 2, 1, 0, 0, 2, 1, 1, 0, 2],
		[2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2], [1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1], [0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1]]
	var chains := {}
	var endings := {}
	var sites := {}
	var foes := {}
	var ally_sets := {}
	for i in range(paths.size()):
		var r := run(310 + i, paths[i], i % 7 != 6)
		expect(r["ending"] != "", "path %d reaches an ending (%d chapters)" % [i, r["chapters"]])
		chains[JSON.stringify(r["chain"])] = true
		endings[r["ending"]] = true
		sites[r["site"]] = true
		foes[r["foe"]] = true
		ally_sets[JSON.stringify(r["allies"])] = true
	print("        main campaign: %d chains, endings %s, sites %s, foes %s, ally sets %d" % [chains.size(), endings.keys(), sites.keys(), foes.keys(), ally_sets.size()])
	expect(chains.size() >= 16, "at least 16 different chains of events (%d)" % chains.size())
	expect(endings.size() >= 5, "many endings reached: %s" % [endings.keys()])
	expect(sites.size() >= 2, "the final battle isn't always in the same place: %s" % [sites.keys()])
	expect(foes.size() >= 2, "nor against the same people: %s" % [foes.keys()])
	expect(ally_sets.size() >= 4, "and who's at your side changes (%d sets)" % ally_sets.size())


func test_redwater_holds_is_reachable() -> void:
	# Seal the crates for the town, speak for Redwater at the meeting, warn the marshal about
	# the plot, refuse the company, open the vault.
	var r := run(360, [2, 0, 1, 0, 0, 2, 1, 0, 0, 0, 0, 0], true, true)
	expect_eq(r["ending"], "town_holds", "Redwater holds: %s" % [r["chain"]])


func test_finding_the_plot_opens_other_endings() -> void:
	var endings := {}
	var paths := [[2, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1], [0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0], [0, 0, 0, 0, 0, 0, 2, 1, 0, 0, 1], [2, 1, 0, 2, 1, 2, 1, 1, 0, 1, 1]]
	for i in range(paths.size()):
		var r := run(340 + i, paths[i], true, true)
		expect(r["ending"] != "", "an ending")
		endings[r["ending"]] = true
	print("        with the plot found: %s" % [endings.keys()])
	expect(endings.size() >= 2, "more endings open up: %s" % [endings.keys()])
	expect(not endings.has("pyrrhic_peace"), "the vault bay wasn't bombed")
