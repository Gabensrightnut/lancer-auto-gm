extends TestCase
## The rules codex and session zero.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func test_codex_covers_the_rules_and_finds_them() -> void:
	var cats := Codex.categories()
	for c in ["Rules", "Statuses and conditions", "Actions", "Tags", "Frames", "Manufacturers", "Skill triggers", "Downtime actions", "Reserves", "Pilot gear", "Talents", "This game"]:
		expect(cats.has(c), "codex has %s" % c)
	var frames := Codex.search("", "Frames", 999)
	expect_eq(frames.size(), 29, "every core frame")
	var r := Codex.search("engaged")
	expect(not r.is_empty() and r[0]["title"] == "Engaged", "exact title first: %s" % [r.slice(0, 3).map(func(e: Dictionary) -> String: return e["title"])])
	var ev := Codex.search("everest")
	expect(not ev.is_empty() and str(ev[0]["title"]).contains("Everest"))
	expect(str(ev[0]["text"]).contains("HP"), "frame stats included")
	expect(not Codex.search("lock on").is_empty(), "two-word search")
	expect(Codex.search("zzzxqq").is_empty())
	for e: Dictionary in Codex.entries():
		expect(not str(e["text"]).contains("<"), "plain text, no HTML: %s" % e["title"])
	expect_eq(str(Codex.find("Standing")["source"]), "Game feature (not a book rule)", "our own features are marked")


func test_session_zero_sets_up_the_squad() -> void:
	var t := Setup.setup(150)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var r := e.submit(s, c, {"type": "session_zero", "seat": "gm", "params": {"identity": "Rebels who need the frontier on their side", "patron": "company",
		"history": [{"question": "stranded", "a": t["a"], "b": t["b"]}], "tone": "gritty", "focus": "story", "content_off": ["civilian_harm"]}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(c.options["tone"], "gritty")
	expect(bool(c.options["long_downtime"]), "story focus: long downtimes (two actions, Core p.50)")
	expect_eq(int(Bonds.get_bond(s, t["a"], t["b"])["score"]), 3, "stranded together: a bond to start")
	expect(not e.submit(s, c, {"type": "session_zero", "seat": "p1", "params": {}})["ok"], "the host enters it")
	var rng := RandomNumberGenerator.new()
	for i in range(200):
		rng.seed = i
		var tw := MissionHooks.pick_twist(rng, "", c)
		expect(tw.is_empty() or str(tw["id"]) != "civilians", "switched-off content never comes up")
	var company := 0
	for i in range(20):
		var h := MissionHooks.make(s, c, "clear_raiders", {})
		if str(s.npcs.get(str(h["patron_id"]), {}).get("role", "")) == "company_rep":
			company += 1
	expect(company >= 8, "a corporate sponsor brings most of the work (%d/20)" % company)
	var b: Dictionary = e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": s.hooks[0]["id"]}})
	var said := ""
	for x: Dictionary in b["events"]:
		if x["type"] == "dialogue_line":
			said += str(x["text"])
	expect(said.contains("Rebels who need the frontier"), "the first briefing says who you are: %s" % said)


func test_session_zero_only_before_the_first_mission() -> void:
	var t := Setup.setup(151)
	var s: StoryState = t["story"]
	s.mission_number = 2
	var r: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "session_zero", "seat": "gm", "params": {"tone": "hopeful"}})
	expect(not r["ok"])


func test_gritty_tone_brings_more_twists() -> void:
	var c := Campaign.create("Tone")
	var rng := RandomNumberGenerator.new()
	var count := func(tone: String) -> int:
		c.options["tone"] = tone
		var n := 0
		for i in range(400):
			rng.seed = i
			if not MissionHooks.pick_twist(rng, "", c).is_empty():
				n += 1
		return n
	expect(int(count.call("gritty")) > int(count.call("hopeful")), "gritty > hopeful")
