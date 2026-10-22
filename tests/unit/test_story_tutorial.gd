extends TestCase
## The guided first opening, culture kits at hubs, and the portrait builder's data hooks.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _tutorial() -> Dictionary:
	var c := Campaign.create("Tutorial test")
	c.id = "c_tut"
	var a := c.new_pilot("Ama Okafor", "Bluebird")
	a["skills"] = {"sk_charm": 1, "sk_get_somewhere_quickly": 1}
	var s := StoryState.new(9)
	s.flags = c.story_flags
	var e := StoryEngine.new(MissionTest.db())
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	var events := CampaignLoop.start_tutorial(c, s, e)
	return {"campaign": c, "story": s, "engine": e, "a": a["id"], "events": events}


static func _prompts(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == "tutorial_prompt")


func _submit(t: Dictionary, type: String, params: Dictionary = {}, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func test_tutorial_opens_with_a_briefing_at_a_training_base() -> void:
	var t := _tutorial()
	var s: StoryState = t["story"]
	expect(Tutorial.active(s))
	expect_eq(s.phase, "briefing", "the first session starts with the mission brief (Core p.40)")
	expect_eq(s.hooks.size(), 1)
	expect(bool(s.hooks[0].get("tutorial", false)))
	expect_eq(s.hub["culture"], "union_core")
	var first := _prompts(t["events"])
	expect(not first.is_empty() and first[0]["id"] == "welcome", "lesson 1 shows right away")
	var r := _submit(t, "choose_hook", {"hook": s.hooks[0]["id"]})
	expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "dialogue_started" and e["scene"] == "tutorial_briefing"))
	var p := _prompts(r["events"])
	expect(not p.is_empty() and p[0]["id"] == "reserves", "next lesson: reserves")


func test_battle_lessons_follow_what_the_pilot_does() -> void:
	var t := _tutorial()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_submit(t, "choose_hook", {"hook": s.hooks[0]["id"]})
	while Dialogue.is_open(s):
		var o := Dialogue.offered(s)
		_submit(t, "dialogue_next" if o.is_empty() else "dialogue_choose", {} if o.is_empty() else {"choice": "ready"}, "p1")
	_submit(t, "confirm_reserves")
	expect_eq(Tutorial.current(s)["id"], "turns")
	var mine := ["p1"]
	var shown := _prompts(Tutorial.observe_battle(s, c, [{"type": "combat_started"}], mine))
	expect(not shown.is_empty() and shown[0]["id"] == "turns", "turns explained when combat starts")
	Tutorial.observe_battle(s, c, [{"type": "turn_started", "unit": "p1"}], mine)
	expect_eq(Tutorial.current(s)["id"], "move")
	Tutorial.observe_battle(s, c, [{"type": "moved", "unit": "e1"}], mine)
	expect_eq(Tutorial.current(s)["id"], "move", "an enemy moving doesn't count")
	Tutorial.observe_battle(s, c, [{"type": "moved", "unit": "p1"}], mine)
	expect_eq(Tutorial.current(s)["id"], "attack")
	var miss := Tutorial.observe_battle(s, c, [{"type": "attack_rolled", "attacker": "p1", "result": "miss", "cover": "none"}], mine)
	expect_eq(Tutorial.current(s)["id"], "cover")
	expect(_prompts(miss).any(func(p: Dictionary) -> bool: return p["id"] == "miss"), "first miss: a tip about Accuracy")
	Tutorial.observe_battle(s, c, [{"type": "attack_rolled", "attacker": "e1", "target": "p1", "result": "hit", "cover": "soft"}], mine)
	expect_eq(Tutorial.current(s)["id"], "heat", "cover came up")
	Tutorial.observe_battle(s, c, [{"type": "heat_changed", "unit": "p1", "amount": 2}], mine)
	expect_eq(Tutorial.current(s)["id"], "tech")
	Tutorial.observe_battle(s, c, [{"type": "tech_action", "unit": "p1", "action": "lock_on"}], mine)
	expect_eq(Tutorial.current(s)["id"], "damage")
	Tutorial.observe_battle(s, c, [{"type": "damage_dealt", "target": "p1", "amount": 3}], mine)
	expect_eq(Tutorial.current(s)["id"], "fight")
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var st: GameState = gen["state"]
	for u: Unit in st.units.values():
		if u.side == Mission.ENEMIES:
			expect(u.name.begins_with("Training Drone"), "the drill only fields training drones: %s" % u.name)
	var r := _submit(t, "mission_finished", {"outcome": "victory", "reason": "drill"})
	expect_eq(Tutorial.current(s)["id"], "level_up", "the debrief finishes the fight lesson")
	expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "tutorial_lesson_done"))


func test_hub_lessons_and_end() -> void:
	var t := _tutorial()
	var s: StoryState = t["story"]
	s.tutorial["step"] = 10  # level_up
	s.tutorial["shown"] = false
	s.phase = "debrief"
	var r := _submit(t, "level_up")
	expect(_prompts(r["events"]).any(func(p: Dictionary) -> bool: return p["id"] == "level_up"))
	_submit(t, "level_picks", {"pilot": t["a"], "trigger": "sk_charm", "mech_skill": "hull"})
	_submit(t, "start_downtime")
	expect_eq(Tutorial.current(s)["id"], "people")
	_submit(t, "talk", {"npc": "tutorial_instructor"}, "p1")
	expect_eq(Tutorial.current(s)["id"], "downtime_action")
	Dialogue.close(s)
	_submit(t, "downtime_action", {"pilot": t["a"], "action": "dt_get_focused", "trigger": "sk_spot"}, "p1")
	expect_eq(Tutorial.current(s)["id"], "next")
	_submit(t, "end_downtime")
	r = _submit(t, "choose_hook", {"hook": s.hooks[0]["id"]})
	expect(not Tutorial.active(s), "tutorial finished")
	expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "tutorial_finished"))


func test_tips_only_with_hints_on() -> void:
	var t := Setup.setup(90)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var ev := Tutorial.observe_battle(s, c, [{"type": "structure_lost", "unit": "p1"}], ["p1"])
	expect(_prompts(ev).size() == 1, "a first-time tip, even outside the tutorial")
	expect(_prompts(Tutorial.observe_battle(s, c, [{"type": "structure_lost", "unit": "p1"}], ["p1"])).is_empty(), "only once")
	c.options["teaching_hints"] = false
	expect(_prompts(Tutorial.observe_battle(s, c, [{"type": "reaction_offered", "unit": "p1"}], ["p1"])).is_empty(), "hints off: quiet")


func test_tutorial_text_cites_the_book() -> void:
	for l: Dictionary in Tutorial.lessons():
		expect(str(l.get("rule_ref", "")).begins_with("Core p."), "%s cites a page" % l["id"])
		expect(not (l.get("done_on", []) as Array).is_empty(), "%s can be finished" % l["id"])
	for tp: Dictionary in Tutorial.data()["tips"]:
		expect(str(tp.get("rule_ref", "")).begins_with("Core p."), tp["id"])


func test_culture_kits_flavor_the_hub() -> void:
	var c := Campaign.create("Culture test")
	var a := c.new_pilot("A", "Alpha")
	var s := StoryState.new(4)
	s.flags = c.story_flags
	var e := StoryEngine.new()
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	e.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": 5, "culture": "old_west"}})
	expect_eq(s.hub["culture"], "old_west")
	var kit: Dictionary = NpcGen.cultures()["old_west"]
	var names: Array = []
	for spot: Dictionary in s.hub["spots"]:
		names.append(spot["name"])
	expect(names.any(func(n: String) -> bool: return (kit["spots"]["bar"] as Array).has(n) or (kit["spots"]["office"] as Array).has(n) or (kit["spots"]["market"] as Array).has(n) or (kit["spots"].get("workshop", []) as Array).has(n)), "kit building names: %s" % [names])
	for h: Dictionary in s.hooks:
		expect_eq(h["culture"], "old_west", "jobs carry the kit for the map")
		var t: Dictionary = MissionHooks.data()["templates"][h["template"]]
		if t.has("cultures"):
			expect((t["cultures"] as Array).has("old_west"))
	var lines := StoryText.pools()
	expect(lines.has("rumor_old_west") and lines.has("greet_bartender_medieval_tech"))
	# Culture-only jobs never show up elsewhere.
	var s2 := StoryState.new(4)
	s2.flags = {}
	e.submit(s2, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	for i in range(6):
		s2.hooks.clear()
		e.submit(s2, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "station", "seed": 20 + i, "culture": "cyberpunk"}})
		for h: Dictionary in s2.hooks:
			expect(str(h["template"]) not in ["train_job", "champion_duel", "shrine_guard"], "no %s at a cyberpunk station" % h["template"])


func test_every_kit_is_picked_somewhere() -> void:
	var seen := {}
	for i in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		seen[NpcGen.pick_culture(rng, "town")] = true
	for k in ["frontier_colony", "old_west", "medieval_tech", "cyberpunk", "retrofuturistic", "east_asian"]:
		expect(seen.has(k), "%s picked for towns" % k)


func test_portrait_spec_round_trip_and_locks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spec := PortraitSpec.randomize(rng)
	expect_eq(int(spec["version"]), 2)
	for p: Dictionary in PortraitSpec.parts():
		expect(spec["parts"].has(p["id"]), "has %s" % p["id"])
	var flat := PortraitSpec.flatten(spec)
	expect_eq(flat["hair_style"], spec["parts"]["hair"]["option"])
	expect_eq(flat["skin"], spec["parts"]["face"]["primary"])
	var again := PortraitSpec.randomize(rng, spec, {"hair": true})
	expect_eq(again["parts"]["hair"], spec["parts"]["hair"], "locked part kept")
	var old := {"skin": "#a16a45", "hair": "#d8b46a", "hair_style": "bun", "extra": "glasses"}
	var up := PortraitSpec.normalize(old)
	expect_eq(PortraitSpec.flatten(up)["hair_style"], "bun", "old flat looks still work")
	expect_eq(PortraitSpec.flatten(up)["extra"], "glasses")


func test_expressions_are_known_and_drawable() -> void:
	var ids := PortraitSpec.expression_ids()
	for e in ["neutral", "smiling", "angry", "worried", "shouting", "sad", "surprised", "determined", "smug", "hurt"]:
		expect(ids.has(e), e)
		expect(Portrait.EXPRESSIONS.has(PortraitSpec.draw_as(e)), "%s has a placeholder face" % e)
	expect_eq(PortraitSpec.pilot_expression(["aggressive"]), "angry")
	expect_eq(PortraitSpec.check_expression("fail"), "angry")
	var t := Setup.setup(91)
	var s: StoryState = t["story"]
	var npc: Dictionary = s.npcs[s.hub["npcs"][0]]
	s.standing[npc["faction"]] = -2
	expect_eq(PortraitSpec.npc_expression(s, npc), "angry", "an unfriendly NPC looks it")


func test_jobs_name_the_world_maps_kit() -> void:
	var expect_map := {"frontier_colony": "", "old_west": "old_west", "medieval_tech": "medieval", "cyberpunk": "cyberpunk",
		"retrofuturistic": "retro", "east_asian": "east_asian", "union_core": "union"}
	var landscapes := ["grassy_hills", "desert_mesas", "tundra", "volcanic", "alien_wilds", "crystal_fields", "toxic_marsh", "city"]
	for kit: String in expect_map:
		var t := Setup.setup(95)
		var s: StoryState = t["story"]
		s.hub["culture"] = kit
		var hook := MissionHooks.make(s, t["campaign"], "clear_raiders", {})
		expect_eq(hook["map_culture"], expect_map[kit], kit)
		expect(landscapes.has(hook["landscape"]), "%s -> %s" % [kit, hook["landscape"]])
