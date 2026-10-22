extends TestCase
## The campaign loop in the book's order: briefing -> reserves -> mission -> debrief ->
## level up -> downtime -> next briefing, with consequences carried forward.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _submit(t: Dictionary, type: String, params: Dictionary = {}, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func _finish_dialogue(t: Dictionary) -> void:
	var s: StoryState = t["story"]
	var guard := 0
	while Dialogue.is_open(s) and guard < 30:
		guard += 1
		var offered := Dialogue.offered(s)
		if offered.is_empty():
			_submit(t, "dialogue_next", {}, "p1")
		else:
			_submit(t, "dialogue_choose", {"choice": offered[0]["id"]}, "p1")


func test_full_loop() -> void:
	var t := Setup.setup(42)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	t["engine"].db = MissionTest.db()
	expect_eq(s.phase, "briefing")
	expect(s.hooks.size() >= 3, "the job board has work")
	expect(not _submit(t, "level_up")["ok"], "can't level up before a mission")
	expect(not _submit(t, "downtime_action", {"pilot": t["a"], "action": "dt_get_focused", "trigger": "sk_charm"})["ok"])

	# Briefing: pick a job; the patron sets the goal and the stakes.
	var hook: Dictionary = s.hooks[0]
	var r := _submit(t, "choose_hook", {"hook": hook["id"]})
	expect(r["ok"], str(r["reason"]))
	expect_eq(s.phase, "reserves")
	expect(r["events"].any(func(e: Dictionary) -> bool: return e["type"] == "dialogue_started" and e["scene"] == "briefing"))
	var said := ""
	for e: Dictionary in r["events"]:
		if e["type"] == "dialogue_line":
			said += str(e["text"]) + "
"
	for i in range(3):
		if Dialogue.offered(s).is_empty() and Dialogue.is_open(s):
			for e: Dictionary in _submit(t, "dialogue_next", {}, "p1")["events"]:
				if e["type"] == "dialogue_line":
					said += str(e["text"]) + "
"
	expect(str(hook["objective"]) in said, "briefing states the objective: %s" % said)
	expect(str(hook["question"]) in said or bool(hook.get("hazardous", false)), "and the stakes as a question")
	_finish_dialogue(t)

	# Reserves, then boots on the ground.
	StoryEffects.apply({"reserve": "reserve_extra_repairs"}, s, c, {"speaker": t["a"]})
	r = _submit(t, "confirm_reserves")
	expect(r["ok"])
	expect_eq(s.phase, "mission")
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var p1 := state.unit("p1")
	expect(p1 != null, "squad pilot's mech is on the field")
	var base := UnitFactory.build_mech(MissionTest.db(), "x", Campaign.STARTER_FRAME, c.pilots[t["a"]]["mechs"][0]["loadout"], c.pilots[t["a"]])
	expect_eq(p1.repairs, base.repairs + 2, "Extra repairs reserve: +2 Repair Cap")
	var pilot_unit := Pilots.pilot_of(state, p1)
	expect(pilot_unit != null and pilot_unit.kind == Unit.KIND_PILOT, "the pilot rides inside as a pilot unit")
	expect_eq(mission.flavor["hook"]["id"], hook["id"])

	# Mission ends (pretend the squad won and Kettle's pilot died).
	mission.outcome = Mission.PLAYERS
	mission.outcome_reason = "All enemy forces have been defeated."
	var kettle := state.unit("p2_pilot")
	if kettle != null:
		kettle.destroyed = true
	r = CampaignLoop.finish_mission(c, s, t["engine"], state, mission)
	expect(r["ok"], str(r["reason"]))
	expect_eq(s.phase, "debrief")
	expect_eq(c.history.size(), 1, "recorded in the campaign")
	expect_eq(s.flags["mission_1_outcome"], "victory")
	expect(s.reserves.is_empty(), "reserves last one mission")
	expect(not c.pilots[t["a"]]["reserves"].has("reserve_extra_repairs"))
	expect(s.dead.has(t["b"]), "pilot death carries over")
	expect_eq(s.mission_number, 2)
	_finish_dialogue(t)

	# Level up: everyone alive, win or lose.
	r = _submit(t, "level_up")
	expect(r["ok"], str(r["reason"]))
	expect_eq(c.pilots[t["a"]]["ll"], 1)
	expect_eq(c.pilots[t["b"]]["ll"], 0, "the dead don't level up")
	expect(not _submit(t, "start_downtime")["ok"], "pick the new trigger and mech skill first")
	expect(not _submit(t, "level_picks", {"pilot": t["a"], "mech_skill": "luck"}, "p1")["ok"])
	r = _submit(t, "level_picks", {"pilot": t["a"], "trigger": "sk_charm", "mech_skill": "hull"}, "p1")
	expect(r["ok"], str(r["reason"]))
	expect_eq(c.pilots[t["a"]]["skills"]["sk_charm"], 2)
	expect_eq(c.pilots[t["a"]]["hull"], 1)
	expect_eq(s.pending_picks[t["a"]]["talent"], 1, "talent and license picks wait for the builder")

	# Downtime, then the next briefing.
	r = _submit(t, "start_downtime")
	expect(r["ok"], str(r["reason"]))
	expect(not s.downtime["actions_left"].has(t["b"]), "the dead get no downtime")
	r = _submit(t, "downtime_action", {"pilot": t["a"], "action": "dt_get_focused", "trigger": "sk_patch"}, "p1")
	expect(r["ok"], str(r["reason"]))
	r = _submit(t, "end_downtime")
	expect(r["ok"])
	expect_eq(s.phase, "briefing")
	expect(s.hooks.size() >= 3)


func test_consequences_reach_later_scenes() -> void:
	var t := Setup.setup(43)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook: Dictionary = s.hooks[0]
	_submit(t, "choose_hook", {"hook": hook["id"]})
	_finish_dialogue(t)
	_submit(t, "confirm_reserves")
	var fac := str(hook["faction"])
	var before := s.get_standing(fac)
	_submit(t, "mission_finished", {"outcome": "defeat", "reason": "test"})
	expect_eq(s.last_mission["outcome"], "defeat")
	var fx: Array = hook["failure"]
	var touches_standing := fx.any(func(e: Dictionary) -> bool: return e.has("standing"))
	if touches_standing:
		expect(s.get_standing(fac) < before or s.get_standing(str(s.hub["faction"])) < 0, "failure costs standing")
	expect(StoryConditions.check({"last_outcome": "defeat"}, s, c, {}))


func test_combat_from_a_scene() -> void:
	var t := Setup.setup(44)
	var s: StoryState = t["story"]
	s.phase = "downtime"
	var ev := StoryEffects.apply({"start_combat": {"hook": "trouble_followed", "on_foot": true, "reason": "The ambush is sprung."}}, s, t["campaign"], {"speaker": t["a"]})
	expect_eq(ev[0]["type"], "combat_requested")
	var out := t["engine"]._combat_from_scene(s, t["campaign"], ev[0]["spec"]) as Array
	expect_eq(s.phase, "mission")
	expect(bool(s.current_hook["on_foot"]))
	var gen := CampaignLoop.build_mission(t["campaign"], s, MissionTest.db())
	var p := (gen["state"] as GameState).unit("p1_pilot")
	expect(p != null and not p.counters.has("mounted_in"), "on_foot: pilots start beside their mechs")
	expect(not out.is_empty())


func test_pilot_gear_limits() -> void:
	var t := Setup.setup(45)
	t["engine"].db = MissionTest.db()
	var ok := _submit(t, "set_pilot_gear", {"pilot": t["a"], "gear": ["pg_light_hardsuit", "pg_corrective"]}, "p1")
	expect(ok["ok"], str(ok["reason"]))
	var two_armor := _submit(t, "set_pilot_gear", {"pilot": t["a"], "gear": ["pg_light_hardsuit", "pg_heavy_hardsuit"]}, "p1")
	expect(not two_armor["ok"] and "one set" in str(two_armor["reason"]))
	var not_mine := _submit(t, "set_pilot_gear", {"pilot": t["b"], "gear": []}, "p1")
	expect(not not_mine["ok"])


func test_story_saves_with_the_campaign() -> void:
	var t := Setup.setup(46)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	s.standing["Test Faction"] = 2
	s.flags["met_someone"] = true
	StoryEffects.apply({"reserve": "reserve_access"}, s, c, {"speaker": t["a"]})
	var roll_before := s.dice.die(20)
	s.dice.set_state(s.dice.get_state())
	s.save_to(c)
	var json := JSON.stringify(c.to_dict())
	var back: Campaign = Campaign.from_dict(JSON.parse_string(json))["campaign"]
	var s2 := StoryState.of(back)
	expect_eq(s2.get_standing("Test Faction"), 2)
	expect(bool(s2.flags.get("met_someone", false)))
	expect(s2.has_reserve(t["a"], "reserve_access"))
	expect_eq(s2.hub["name"], s.hub["name"])
	expect_eq(s2.dice.die(20), s.dice.die(20), "story dice continue where they left off")
	expect(roll_before > 0)


func test_hub_generation_is_seeded_and_varied() -> void:
	var a := Setup.setup(50)
	var b := Setup.setup(50)
	expect_eq(a["story"].hub["name"], b["story"].hub["name"], "same seed, same hub")
	var names := {}
	var roles := {}
	for id: String in a["story"].hub["npcs"]:
		var n: Dictionary = a["story"].npcs[id]
		names[n["name"]] = true
		roles[n["role"]] = true
	expect(roles.has("company_rep") and roles.has("quartermaster") and roles.has("bartender"))
	expect(names.size() >= 5, "different people")
	var hubs := {}
	for i in range(8):
		hubs[Setup.setup(60 + i)["story"].hub["name"]] = true
	expect(hubs.size() >= 5, "hubs vary: %s" % [hubs.keys()])


func test_hostile_faction_can_start_a_fight_from_dialogue() -> void:
	var t := Setup.setup(47)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var agent := Setup.npc_with_role(s, "faction_agent")
	if agent == "":
		agent = NpcGen.make_contact(s, c, "faction_agent")["id"]
		(s.hub["npcs"] as Array).append(agent)
	s.phase = "downtime"
	s.standing[s.npcs[agent]["faction"]] = -2
	var r := _submit(t, "talk", {"npc": agent}, "p1")
	expect(r["ok"], str(r["reason"]))
	var ids: Array = Dialogue.offered(s).map(func(o: Dictionary) -> String: return o["id"])
	expect(ids.has("stand_ground") and ids.has("back_off"), "an Unfriendly faction threatens you: %s" % [ids])
	r = _submit(t, "dialogue_choose", {"choice": "stand_ground"}, "p1")
	expect(r["ok"], str(r["reason"]))
	expect(not Dialogue.is_open(s), "the conversation ends")
	expect_eq(s.phase, "mission", "straight to boots on the ground")
	expect(bool(s.current_hook.get("on_foot", false)), "the fight starts with pilots out of their mechs")
	expect((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "boots_on_the_ground"))
