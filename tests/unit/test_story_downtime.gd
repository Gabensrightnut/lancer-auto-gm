extends TestCase
## Downtime by the book (Core p.50-55): one action per pilot, full repair, results by band,
## choices from the book's lists, "next time treat it as..." memory, organizations.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _downtime(seed_value: int = 5) -> Dictionary:
	var t := Setup.setup(seed_value)
	var s: StoryState = t["story"]
	s.phase = "level_up"
	t["engine"].submit(s, t["campaign"], {"type": "start_downtime", "seat": "gm", "params": {}})
	return t


func _act(t: Dictionary, action: String, params: Dictionary, seat: String = "p1") -> Dictionary:
	var p := params.duplicate()
	p["action"] = action
	return t["engine"].submit(t["story"], t["campaign"], {"type": "downtime_action", "seat": seat, "params": p})


func _result(r: Dictionary) -> Dictionary:
	for e: Dictionary in r["events"]:
		if e["type"] == "downtime_result":
			return e
	return {}


func test_start_gives_one_action_and_a_full_repair() -> void:
	var t := Setup.setup()
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	StoryEffects.harm(s, c, t["a"], 3)
	s.down_and_out[t["b"]] = true
	s.phase = "level_up"
	var r: Dictionary = t["engine"].submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(s.phase, "downtime")
	expect_eq(s.downtime["actions_left"][t["a"]], 1, "one downtime action (Core p.53)")
	expect_eq(StoryEffects.current_hp(s, c, t["a"]), 6, "full repair restores HP")
	expect(not s.down_and_out.has(t["b"]), "full repair clears Down and Out")
	var long := Setup.setup(9)
	long["story"].phase = "level_up"
	long["engine"].submit(long["story"], long["campaign"], {"type": "start_downtime", "seat": "gm", "params": {"long": true}})
	expect_eq(long["story"].downtime["actions_left"][long["a"]], 2, "a long downtime gives two")


func test_one_action_per_downtime_and_only_in_downtime() -> void:
	var t := _downtime()
	var r := _act(t, "dt_buy_some_time", {"subject": "The people hunting us"})
	expect(r["ok"], str(r["reason"]))
	var again := _act(t, "dt_buy_some_time", {"subject": "Something else"})
	expect(not again["ok"] and "already used" in str(again["reason"]))
	var t2 := Setup.setup(3)
	t2["story"].phase = "briefing"
	var early := _act(t2, "dt_get_focused", {"trigger": "sk_charm"})
	expect(not early["ok"], "not in downtime")


func test_result_bands_follow_the_roll() -> void:
	for i in range(30):
		var t := _downtime(100 + i)
		var r := _act(t, "dt_scrounge_and_barter", {"subject": "A vehicle", "use_trigger": "sk_word_on_the_street"})
		expect(r["ok"], str(r["reason"]))
		var res := _result(r)
		var total := int(res["check"]["total"])
		expect_eq(res["band"], Downtime.band_of(total))
		expect_eq(res["check"]["trigger"]["bonus"], 4, "the trigger counts (Core p.53)")
		var s: StoryState = t["story"]
		expect(s.has_reserve(t["a"], "reserve_vehicle"), "you always get the item as a reserve (a vehicle is the book's Vehicle reserve)")
		if res["band"] == "high":
			expect(s.pending_choice.is_empty(), "20+: no problem")
		else:
			expect_eq(s.pending_choice["count"], 1, "choose one complication or price")


func test_gm_refuses_irrelevant_trigger() -> void:
	var t := _downtime()
	var r := _act(t, "dt_get_a_damn_drink", {"subject": "Collect gossip", "use_trigger": "sk_patch"})
	expect(not r["ok"] and "doesn't see how" in str(r["reason"]))


func test_get_a_damn_drink_gain_and_lose() -> void:
	var found_mid := false
	for i in range(40):
		var t := _downtime(200 + i)
		var s: StoryState = t["story"]
		var r := _act(t, "dt_get_a_damn_drink", {"subject": "Make some connections"})
		var res := _result(r)
		if res["band"] != "mid":
			continue
		found_mid = true
		expect_eq(s.pending_choice["step"], "gain")
		var ch: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["reputation"]}})
		expect(ch["ok"], str(ch["reason"]))
		expect(s.has_reserve(t["a"], "reserve_reputation"))
		expect_eq(s.pending_choice["step"], "lose", "then lose one")
		var opts: Array = s.pending_choice["options"].map(func(o: Dictionary) -> String: return o["id"])
		expect(not opts.has("reputation"), "can't lose the thing you just gained")
		var bad: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["reputation"]}})
		expect(not bad["ok"])
		t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["opportunity"]}})
		expect(s.pending_choice.is_empty())
		break
	expect(found_mid, "some seed rolled 10-19")


func test_get_a_damn_drink_needs_a_bar() -> void:
	var t := _downtime()
	var s: StoryState = t["story"]
	s.hub["spots"] = (s.hub["spots"] as Array).filter(func(sp: Dictionary) -> bool: return sp["kind"] != "bar")
	var r := _act(t, "dt_get_a_damn_drink", {"subject": "Forget the last mission"})
	expect(not r["ok"] and "drink" in str(r["reason"]))


func test_buy_some_time_memory() -> void:
	# Force results by checking every seed until the same situation gets 10-19 twice.
	var t := Setup.setup(1)
	var s: StoryState = t["story"]
	var cfg := Downtime.action_cfg("dt_buy_some_time")
	var ctx := {"speaker": t["a"]}
	var params := {"subject": "The Baron"}
	expect_eq(Downtime._apply_memory(s, cfg, "dt_buy_some_time", params, ctx, "mid"), "mid")
	expect_eq(Downtime._apply_memory(s, cfg, "dt_buy_some_time", params, ctx, "mid"), "low", "second 10-19 for the same situation counts as 9 or less")
	expect_eq(Downtime._apply_memory(s, cfg, "dt_buy_some_time", {"subject": "Other"}, ctx, "mid"), "mid", "different situation")
	expect_eq(Downtime._apply_memory(s, cfg, "dt_buy_some_time", params, ctx, "high"), "high")
	expect_eq(Downtime._apply_memory(s, cfg, "dt_buy_some_time", params, ctx, "high"), "mid", "second 20+ counts as 10-19")


func test_get_connected_needs_a_contact_and_gives_their_help() -> void:
	var t := _downtime(31)
	var s: StoryState = t["story"]
	var rep := Setup.npc_with_role(s, "company_rep")
	var no := _act(t, "dt_get_connected", {"subject": "x", "npc": rep})
	expect(not no["ok"], "haven't met them yet")
	s.contacts.append(rep)
	var r := _act(t, "dt_get_connected", {"subject": rep, "npc": rep})
	expect(r["ok"], str(r["reason"]))
	var res := _result(r)
	# 9 or less asks first whether you do the favor now; otherwise they help straight away.
	if res["band"] == "low":
		t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["favor_now"]}})
	expect_eq(s.pending_choice.get("step", ""), "help")
	var offers: Array = s.pending_choice["options"].map(func(o: Dictionary) -> String: return o["id"])
	expect(offers.has("reserve_extra_repairs"), "a company rep can get you extra repairs")
	expect(not offers.has("reserve_jump_jets"), "trusted offers need Trusted standing")
	t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["reserve_extra_repairs"]}})
	expect(s.has_reserve(t["a"], "reserve_extra_repairs"))
	if res["band"] == "mid":
		expect(StoryConditions.check({"obligation": "$npc.faction"}, s, t["campaign"], {"npc": rep}), "10-19: you owe them a favor")


func test_get_connected_trusted_offers() -> void:
	var t := _downtime(31)
	var s: StoryState = t["story"]
	var rep := Setup.npc_with_role(s, "company_rep")
	s.contacts.append(rep)
	s.standing[s.npcs[rep]["faction"]] = 2
	Downtime._help(s, t["campaign"], {"speaker": t["a"], "npc": rep})
	var offers: Array = s.pending_choice["options"].map(func(o: Dictionary) -> String: return o["id"])
	expect(offers.has("reserve_jump_jets"), "Trusted standing opens better help")


func test_get_focused_improves_a_trigger() -> void:
	var t := _downtime()
	var c: Campaign = t["campaign"]
	var r := _act(t, "dt_get_focused", {"trigger": "sk_charm"})
	expect(r["ok"], str(r["reason"]))
	expect_eq(c.pilots[t["a"]]["skills"]["sk_charm"], 2, "+2 -> +4")
	var t2 := _downtime(8)
	_act(t2, "dt_get_focused", {"trigger": "custom:Playing Chess"})
	expect_eq(t2["campaign"].pilots[t2["a"]]["skills"]["custom:Playing Chess"], 1, "a new +2 trigger")
	expect_eq(NarrativeCheck.trigger_name("custom:Playing Chess"), "Playing Chess")
	t2["campaign"].pilots[t2["a"]]["skills"]["sk_charm"] = 3
	t2["story"].downtime["actions_left"][t2["a"]] = 1
	expect(not _act(t2, "dt_get_focused", {"trigger": "sk_charm"})["ok"], "+6 is the cap")


func test_power_at_a_cost_gm_picks_costs() -> void:
	var t := _downtime()
	var r := _act(t, "dt_power_at_a_cost", {"subject": "A dropship", "scale": "outlandish"})
	expect(r["ok"], str(r["reason"]))
	var res := _result(r)
	expect_eq((res["costs"] as Array).size(), 2, "outlandish: the GM picks two costs")
	expect(t["story"].has_reserve(t["a"], "custom"), "you can definitely get it")


func test_get_creative_progress_then_finish() -> void:
	var finished := false
	for i in range(40):
		var t := _downtime(300 + i)
		var s: StoryState = t["story"]
		var r := _act(t, "dt_get_creative", {"subject": "A decoy beacon"})
		var res := _result(r)
		if res["band"] != "mid":
			continue
		expect_eq(s.pending_choice["count"], 2, "choose the two things you'll need")
		t["engine"].submit(s, t["campaign"], {"type": "downtime_choose", "seat": "p1", "params": {"picks": ["need0", "need2"]}})
		var key := "dt_get_creative:a decoy beacon"
		expect_eq(s.downtime["projects"][key]["state"], "in_progress")
		# Next downtime: finish without rolling.
		s.mission_number += 1
		s.phase = "level_up"
		t["engine"].submit(s, t["campaign"], {"type": "start_downtime", "seat": "gm", "params": {}})
		var fin := _act(t, "dt_get_creative", {"finish": key})
		expect(fin["ok"], str(fin["reason"]))
		expect(not _result(fin).has("check"), "no roll")
		expect_eq(s.downtime["projects"][key]["state"], "done")
		finished = true
		break
	expect(finished)


func test_organization_rolls_after_first_downtime() -> void:
	var t := _downtime()
	var s: StoryState = t["story"]
	var r := _act(t, "dt_get_organized", {"subject": "The Night Shift", "focus": "humanitarian", "start_stat": "influence"})
	expect(r["ok"], str(r["reason"]))
	var org: Dictionary = s.downtime["orgs"][t["a"]][0]
	expect_eq(org["influence"], 2)
	expect_eq(org["efficiency"], 0)
	s.phase = "level_up"
	var again: Dictionary = t["engine"].submit(s, t["campaign"], {"type": "start_downtime", "seat": "gm", "params": {}})
	expect(not again["events"].any(func(e: Dictionary) -> bool: return e["type"] == "org_roll"), "not in the same downtime")
	s.mission_number += 1
	s.phase = "level_up"
	again = t["engine"].submit(s, t["campaign"], {"type": "start_downtime", "seat": "gm", "params": {}})
	expect(again["events"].any(func(e: Dictionary) -> bool: return e["type"] == "org_roll"), "rolls each later downtime")
	expect_eq(s.downtime["actions_left"][t["a"]], 1, "the organization roll isn't the downtime action")


func test_ai_squadmates_take_their_own_downtime() -> void:
	for i in range(20):
		var t := _downtime(400 + i)
		var s: StoryState = t["story"]
		expect_eq(s.downtime["actions_left"][t["b"]], 0, "the AI squadmate spent its downtime action")
		expect_eq(s.downtime["actions_left"][t["a"]], 1, "the human's action is left for them")
		expect(s.pending_choice.is_empty() or str(s.pending_choice["pilot"]) != t["b"], "AI picked its own options")
