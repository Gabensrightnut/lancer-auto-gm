extends TestCase
## Dialogue scenes as data: conditions on flags, standing, who's alive and skill triggers;
## effects; the 6-choice cap; narrative skill checks by the book; who chooses (speaker, vote,
## AI squadmates in character).


## A two-pilot campaign at a generated town, with seats p1 (human) and p2 (AI).
static func setup(seed_value: int = 7) -> Dictionary:
	var c := Campaign.create("Story test")
	c.id = "c_test_%d" % seed_value
	var a := c.new_pilot("Ama Okafor", "Bluebird")
	var b := c.new_pilot("Rin Sato", "Kettle")
	a["skills"] = {"sk_charm": 1, "sk_patch": 1, "sk_word_on_the_street": 2, "sk_investigate": 1}
	a["background"] = "pbg_colonist"
	b["skills"] = {"sk_apply_fists_to_faces": 2, "sk_threaten": 1}
	var s := StoryState.new(seed_value)
	s.flags = c.story_flags
	var e := StoryEngine.new()
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": b["id"], "ai": true, "persona": "bold"}})
	e.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": 1}})
	return {"campaign": c, "story": s, "engine": e, "a": a["id"], "b": b["id"]}


static func npc_with_role(story: StoryState, role: String) -> String:
	for id: String in story.hub["npcs"]:
		if story.npcs[id]["role"] == role:
			return id
	return ""


func test_all_story_data_is_valid() -> void:
	var problems := StoryData.lint()
	expect(problems.is_empty(), "\n".join(PackedStringArray(problems)))


func test_conditions() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var ctx := {"speaker": t["a"], "npc": npc_with_role(s, "company_rep")}
	expect(not StoryConditions.check({"flag": "met"}, s, c, ctx))
	s.flags["met"] = true
	expect(StoryConditions.check({"flag": "met"}, s, c, ctx))
	expect(StoryConditions.check({"not": {"flag": "nope"}}, s, c, ctx))
	s.flags["favors"] = 2
	expect(StoryConditions.check({"flag": "favors", "min": 2}, s, c, ctx))
	expect(not StoryConditions.check({"flag": "favors", "min": 3}, s, c, ctx))
	expect(StoryConditions.check({"trigger": "sk_charm"}, s, c, ctx), "speaker has Charm")
	expect(not StoryConditions.check({"trigger": "sk_threaten"}, s, c, ctx), "speaker lacks Threaten")
	expect(StoryConditions.check({"squad_trigger": "sk_threaten"}, s, c, ctx), "squadmate has Threaten")
	expect(StoryConditions.check({"trigger": "sk_word_on_the_street", "min_rank": 2}, s, c, ctx))
	expect(StoryConditions.check({"background": "pbg_colonist"}, s, c, ctx))
	var fac := str(s.npcs[ctx["npc"]]["faction"])
	expect(StoryConditions.check({"standing": "$npc.faction", "min": 0, "max": 0}, s, c, ctx), "neutral to start")
	StoryEffects.apply({"standing": "$npc.faction", "add": 2}, s, c, ctx)
	expect_eq(s.get_standing(fac), 2)
	expect(StoryConditions.check({"standing": "$npc.faction", "min": 2}, s, c, ctx))
	StoryEffects.apply({"standing": "$npc.faction", "add": 9}, s, c, ctx)
	expect_eq(s.get_standing(fac), 3, "standing is clamped to +3")
	expect(StoryConditions.check({"alive": "speaker"}, s, c, ctx))
	StoryEffects.kill(s, t["b"], "test")
	expect(StoryConditions.check({"dead": t["b"]}, s, c, ctx))
	expect(not StoryConditions.check({"squad_trigger": "sk_threaten"}, s, c, ctx), "dead pilots' triggers don't count")
	expect(StoryConditions.check({"any": [{"flag": "nope"}, {"flag": "met"}]}, s, c, ctx))
	expect(not StoryConditions.check({"all": [{"flag": "nope"}, {"flag": "met"}]}, s, c, ctx))
	expect(StoryConditions.check({"hub_has": "bar"}, s, c, ctx))
	s.flags["met:" + str(ctx["npc"])] = true
	expect(StoryConditions.check({"flag": "met:{npc_id}"}, s, c, ctx), "flag keys take placeholders")


func test_effects_reserves_and_contacts() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var ctx := {"speaker": t["a"], "npc": npc_with_role(s, "company_rep")}
	var ev := StoryEffects.apply({"reserve": "reserve_extra_repairs"}, s, c, ctx)
	expect_eq(ev[0]["type"], "reserve_gained")
	expect(s.has_reserve(t["a"], "reserve_extra_repairs"))
	expect(c.pilots[t["a"]]["reserves"].has("reserve_extra_repairs"), "mirrored on the pilot record")
	expect_eq(s.reserves[t["a"]][0]["name"], "Extra repairs")
	StoryEffects.apply({"reserve": "reserve_scouting", "to": "squad"}, s, c, ctx)
	expect(s.has_reserve(t["b"], "reserve_scouting"))
	var tab := StoryEffects.apply({"reserve_table": "Tactical"}, s, c, ctx)
	expect(tab[0].has("table_roll"), "book table rolled with 1d20")
	expect(str(tab[0]["reserve"]["id"]).begins_with("reserve_"))
	StoryEffects.apply({"set_flag": "x", "value": 3}, s, c, ctx)
	StoryEffects.apply({"add_flag": "x", "amount": 2}, s, c, ctx)
	expect_eq(s.flags["x"], 5)


func test_narrative_check_by_the_book() -> void:
	var pilot := {"id": "p", "skills": {"sk_charm": 1, "sk_threaten": 2}, "background": "pbg_noble"}
	var dice := Dice.new(3)
	var r := NarrativeCheck.roll(dice, pilot, {"skills": ["sk_charm", "sk_threaten"]})
	expect_eq(r["trigger"]["id"], "sk_threaten", "best relevant trigger")
	expect_eq(r["bonus"], 4, "+4 at rank 2, only one trigger counts")
	r = NarrativeCheck.roll(dice, pilot, {"skills": ["sk_charm", "sk_threaten"], "use_trigger": "sk_charm"})
	expect_eq(r["bonus"], 2, "the trigger the player picked")
	r = NarrativeCheck.roll(dice, pilot, {"skills": ["sk_patch"]})
	expect_eq(r["bonus"], 0, "no fitting trigger: plain d20")
	r = NarrativeCheck.roll(dice, pilot, {"skills": ["sk_charm"], "tags": ["etiquette"]})
	expect_eq(r["accuracy_roll"]["accuracy"], 1, "noble background fits etiquette: +1 Accuracy")
	r = NarrativeCheck.roll(dice, pilot, {"skills": ["sk_charm"], "against_tags": ["nobles"], "difficult": true})
	expect_eq(r["accuracy_roll"]["difficulty"], 2, "GM invokes the background against + Difficult")
	r = NarrativeCheck.roll(dice, pilot, {"skills": ["sk_charm"], "helpers": 3})
	expect_eq(r["bonus"], 3, "teamwork is +1 however many help")
	# Outcome bands.
	for i in range(200):
		var x := NarrativeCheck.roll(dice, pilot, {"skills": [], "risky": true})
		var tot := int(x["total"])
		expect_eq(x["outcome"], "success" if tot >= 20 else ("success_cost" if tot >= 10 else "fail"), "risky band at %d" % tot)
		var h := NarrativeCheck.roll(dice, pilot, {"heroic": true})
		expect_eq(h["success"], int(h["total"]) >= 20, "heroic needs 20+")
		var n := NarrativeCheck.roll(dice, pilot, {})
		expect_eq(n["success"], int(n["total"]) >= 10)
	expect(NarrativeCheck.push_level("normal")["level"] == "risky")
	expect(NarrativeCheck.push_level("risky", true)["level"] == "heroic")
	expect(not NarrativeCheck.push_level("risky", false)["ok"])
	expect(not NarrativeCheck.push_level("heroic")["ok"], "HEROIC can never be pushed")


func test_skill_challenge_majority() -> void:
	var dice := Dice.new(11)
	var pilots := [{"id": "a", "skills": {}}, {"id": "b", "skills": {}}, {"id": "c", "skills": {}}]
	for i in range(40):
		var r := NarrativeCheck.challenge(dice, pilots, {})
		expect_eq(r["success"], int(r["successes"]) > int(r["failures"]), "3 rollers: majority decides")


func test_talking_offers_at_most_six_choices_and_respects_triggers() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	s.phase = "downtime"
	Downtime.start(s, c)
	var rep := npc_with_role(s, "company_rep")
	var r := e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": rep}})
	expect(r["ok"], str(r["reason"]))
	expect(s.contacts.has(rep), "you've met them: they're a contact now")
	var guard := 0
	while Dialogue.offered(s).is_empty() and Dialogue.is_open(s) and guard < 5:
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1"})
		guard += 1
	var ids: Array = Dialogue.offered(s).filter(func(o: Dictionary) -> bool: return not bool(o.get("extra", false))).map(func(o: Dictionary) -> String: return o["id"])
	expect(ids.size() >= 4 and ids.size() <= Dialogue.MAX_CHOICES, "4-6 choices (plus the tone replies), got %s" % [ids])
	expect(ids.has("charm"), "Ama has Charm, so the Charm option shows")
	expect(not ids.has("pull_rank"), "no Pull Rank trigger, no Pull Rank option")
	expect(ids.has("leave"), "leaving is always offered")
	expect(ids.has("favor"), "downtime with an action left: Get Connected offered")
	# p2 isn't the speaker, so they can't choose (speaker mode is the default).
	var refused := e.submit(s, c, {"type": "dialogue_choose", "seat": "p2", "params": {"choice": "licenses"}})
	expect(not refused["ok"])
	var lic := e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "licenses"}})
	expect(lic["ok"])
	var said: Array = (lic["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "dialogue_line")
	expect(not said.is_empty() and "License" in str(said[0]["text"]), "the rep explains License Levels")


func test_cap_keeps_pinned_and_trigger_choices() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var raw: Array = []
	for i in range(8):
		raw.append({"id": "plain%d" % i, "text": "x"})
	raw.append({"id": "trig", "text": "t", "trigger": "sk_charm"})
	raw.append({"id": "bye", "text": "b", "pinned": true})
	var got: Array = Dialogue._build_choices(s, c, raw, {"speaker": t["a"]}).map(func(o: Dictionary) -> String: return o["id"])
	expect_eq(got.size(), 6)
	expect(got.has("trig") and got.has("bye"), "trigger and pinned options survive the cap: %s" % [got])
	expect_eq(got[0], "plain0", "shown in written order")


func test_failed_check_can_only_be_pushed() -> void:
	var t := setup(21)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var raw := [{"id": "x", "text": "Try it", "check": {"skills": [], "goal": "door"}}]
	s.failed_goals["door"] = "normal"
	var got: Array = Dialogue._build_choices(s, c, raw, {"speaker": t["a"]})
	expect_eq(got[0]["check"]["level"], "risky", "pushing makes it RISKY")
	expect(str(got[0]["text"]).begins_with("[Push it]"))
	s.failed_goals["door"] = "heroic"
	expect(Dialogue._build_choices(s, c, raw, {"speaker": t["a"]}).is_empty(), "HEROIC failures can't be pushed")


func test_vote_mode_and_ai_votes() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	c.options["dialogue_choice"] = "vote"
	var local := npc_with_role(s, "local")
	if local == "":
		local = npc_with_role(s, "bartender")
	e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": local}})
	var guard := 0
	while Dialogue.offered(s).is_empty() and Dialogue.is_open(s) and guard < 5:
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1"})
		guard += 1
	expect(s.dialogue["votes"].has("p2"), "the AI squadmate voted as soon as the choice opened")
	var vote := e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "leave"}})
	expect(vote["ok"])
	var types: Array = vote["events"].map(func(x: Dictionary) -> String: return x["type"])
	expect(types.has("dialogue_choice"), "all seats voted, so it resolved")


func test_ai_speaker_picks_in_character() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var bar := npc_with_role(s, "bartender")
	var r := e.submit(s, c, {"type": "talk", "seat": "p2", "params": {"npc": bar}})
	expect(r["ok"])
	var all_events: Array = r["events"]
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 5:
		all_events.append_array(e.submit(s, c, {"type": "dialogue_next", "seat": "p1"})["events"])
		guard += 1
	var ai := all_events.filter(func(x: Dictionary) -> bool: return x["type"] == "ai_chose")
	expect(not ai.is_empty(), "AI squadmate chose for themselves")
	if not ai.is_empty():
		expect(str(ai[0]["why"]).contains("Kettle"), "explains the choice in character: %s" % ai[0]["why"])
		expect(ai[0]["choice"] != "leave", "a bold squadmate doesn't walk away first")


func test_brawl_harm_and_down_and_out() -> void:
	var t := setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var pid: String = t["a"]
	var mx := StoryEffects.max_hp(c.pilots[pid])
	expect_eq(mx, 6, "LL0 pilots have 6 HP")
	StoryEffects.harm(s, c, pid, 2)
	expect_eq(StoryEffects.current_hp(s, c, pid), 4)
	c.pilots[pid]["pilot_gear"] = ["pg_heavy_hardsuit"]
	expect_eq(StoryEffects.max_hp(c.pilots[pid]), 9, "hardsuit HP")
	StoryEffects.harm(s, c, pid, 2)
	expect_eq(StoryEffects.current_hp(s, c, pid), 4, "Armor 2 stops 2 damage")
	var ev := StoryEffects.harm(s, c, pid, 20, true)
	var roll := ev.filter(func(x: Dictionary) -> bool: return x["type"] == "down_and_out_roll")
	expect_eq(roll.size(), 1, "0 HP: roll 1d6")
	var res := str(roll[0]["result"])
	expect(res in ["close_call", "down_and_out", "dead"])
	if res == "down_and_out":
		var r := t["engine"].submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": s.hub["npcs"][0]}}) as Dictionary
		expect(not r["ok"] and "Down and Out" in str(r["reason"]), "Down and Out pilots can't act")
		StoryEffects.rest(s, c, pid)
		expect(not s.down_and_out.has(pid), "an hour's rest wakes them")
		expect_eq(StoryEffects.current_hp(s, c, pid), 5, "half of 9, rounded up")


func test_random_conversations_never_leak_templates_or_get_stuck() -> void:
	var leaks: Array = []
	var stuck: Array = []
	var bad := RegEx.create_from_string(r"\{[a-z_]+\}|\[[a-z_]+\]")
	for seed_value in range(1, 13):
		var t := setup(seed_value)
		var s: StoryState = t["story"]
		var c: Campaign = t["campaign"]
		var e: StoryEngine = t["engine"]
		s.phase = "downtime" if seed_value % 2 == 0 else "briefing"
		if s.phase == "downtime":
			Downtime.start(s, c)
		for npc: String in s.hub["npcs"]:
			var r := e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": npc}})
			var texts: Array = []
			var steps := 0
			while Dialogue.is_open(s) and steps < 40:
				steps += 1
				for ev: Dictionary in r["events"]:
					if ev["type"] == "dialogue_line":
						texts.append(str(ev["text"]))
						for o: Dictionary in ev["choices"]:
							texts.append(str(o["text"]))
				if not s.pending_choice.is_empty():
					var pc := s.pending_choice
					var picks: Array = (pc["options"] as Array).slice(0, int(pc["count"])).map(func(o: Dictionary) -> String: return o["id"])
					e.submit(s, c, {"type": "downtime_choose", "seat": "gm", "params": {"picks": picks}})
				var offered := Dialogue.offered(s)
				if offered.is_empty():
					r = e.submit(s, c, {"type": "dialogue_next", "seat": "p1"})
				else:
					# Prefer not leaving until a few steps in, so more of each scene gets visited.
					var pick: Dictionary = offered[s.dice.die(offered.size()) - 1]
					if steps < 12 and pick["tags"].has("leave") and offered.size() > 1:
						pick = offered[0] if offered[0]["id"] != pick["id"] else offered[1]
					r = e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": pick["id"]}})
				if not r["ok"]:
					stuck.append("%s: %s" % [s.npcs[npc]["role"], r["reason"]])
					break
			if Dialogue.is_open(s):
				Dialogue.close(s)
			for tx: String in texts:
				if bad.search(tx) != null:
					leaks.append("%s: %s" % [s.npcs[npc]["role"], tx])
	expect(leaks.is_empty(), "\n".join(PackedStringArray(leaks.slice(0, 10))))
	expect(stuck.is_empty(), "\n".join(PackedStringArray(stuck.slice(0, 10))))
