extends TestCase
## The user's own ideas as house rules (StoryHouseRules / Economy): off by default, nothing
## shows while off, and switching one on mid-campaign starts it cleanly.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _sub(t: Dictionary, type: String, params: Dictionary, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func _rule(t: Dictionary, id: String, on: bool = true) -> Dictionary:
	return _sub(t, "house_rule", {"id": id, "on": on})


func _finish(t: Dictionary, hook: Dictionary, won: bool, summary: Dictionary) -> Dictionary:
	var s: StoryState = t["story"]
	s.phase = "briefing"
	s.current_hook = {}
	if not s.hooks.has(hook):
		s.hooks.append(hook)
	_sub(t, "choose_hook", {"hook": hook["id"]})
	Dialogue.close(s)
	_sub(t, "confirm_reserves", {})
	var r := _sub(t, "mission_finished", {"outcome": "victory" if won else "defeat", "reason": "test", "summary": summary})
	Dialogue.close(s)
	return r


func test_all_off_by_default_and_nothing_shows() -> void:
	var t := Setup.setup(220)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var defs := StoryHouseRules.definitions()
	expect_eq(defs.size(), 5)
	for r: Dictionary in defs:
		expect(not StoryHouseRules.on(c, str(r["id"])), "%s is off" % r["id"])
		expect_eq(str(r["label"]), "Your idea, not a book rule")
	expect(not MarketPanel.available(c), "no market")
	expect(Economy.offers(s, c).is_empty())
	expect(not _sub(t, "buy", {"item": "drink", "pilot": t["a"]})["ok"], "nothing to buy")
	var r := _finish(t, s.hooks[0], true, {"rounds": 3, "kills": 4, "lost": [str(c.pilots[t["b"]]["callsign"])]})
	expect(not s.flags.has(Economy.WALLET) and not s.flags.has(Economy.SURVIVAL), "no wallet, no rations")
	expect(Economy.wrecked(s, c).is_empty(), "wrecked mechs reprint as the book says")
	expect(not (r["events"] as Array).any(func(x: Dictionary) -> bool: return str(x.get("label", "")) == Economy.LABEL), "no house-rule events at all")
	expect(not _rule(t, "hr_wallet", true)["ok"] == false, "the host can switch one on")
	expect(not _sub(t, "house_rule", {"id": "hr_wallet", "on": true}, "p1")["ok"], "players can't")
	var house: Array = Codex.search("", "House rules", 99)
	expect_eq(house.size(), 5, "the codex lists them")
	expect(house.all(func(e: Dictionary) -> bool: return str(e["source"]) == "Your idea, not a book rule"))


func test_the_wallet_starts_cleanly_and_pays_its_way() -> void:
	var t := Setup.setup(221)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var r := _rule(t, "hr_wallet")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "house_rule_changed" and bool(x["on"])), "announced")
	expect_eq(int(Economy.wallet(s)["manna"]), 600, "a sensible start")
	var before := Economy.local(s)
	expect(_sub(t, "buy", {"item": "drink", "pilot": t["a"]})["ok"])
	expect(Economy.local(s) < before, "paid in this world's money (%s)" % Economy.currency(s))
	r = _finish(t, s.hooks[0], true, {"rounds": 3, "kills": 2, "lost": []})
	expect(int(Economy.wallet(s)["manna"]) > 600, "the patron pays")
	expect(int(Economy.wallet(s)["salvage"]) == 80, "salvage from the wrecks")
	expect(_sub(t, "sell_salvage", {})["ok"] and int(Economy.wallet(s)["salvage"]) == 0)
	var m := int(Economy.wallet(s)["manna"])
	_rule(t, "hr_wallet", false)
	expect(Economy.offers(s, c).is_empty() and not MarketPanel.available(c), "off: hidden again")
	_rule(t, "hr_wallet", true)
	expect_eq(int(Economy.wallet(s)["manna"]), m, "on again: the same wallet, no second handout")


func test_printers_and_paid_travel() -> void:
	var t := Setup.setup(222)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_rule(t, "hr_printers")
	var kettle := str(c.pilots[t["b"]]["callsign"])
	_finish(t, s.hooks[0], true, {"rounds": 3, "kills": 2, "lost": [kettle]})
	expect(Economy.wrecked(s, c).has(t["b"]), "the wrecked mech stays wrecked")
	expect(not CampaignLoop.squad(c, s).any(func(e: Dictionary) -> bool: return str(e["pilot"]["id"]) == t["b"]), "Kettle sits the next one out")
	Sector.current(s)["culture"] = "union_core"
	expect(Economy.has_printer(s), "Union worlds always have one")
	var r := _sub(t, "use_printer", {"pilot": t["b"]})
	expect(r["ok"], str(r["reason"]))
	expect(not Economy.wrecked(s, c).has(t["b"]), "reprinted")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "obligation_added"), "without money tracked, printer time is a favor owed")
	_rule(t, "hr_paid_travel")
	_rule(t, "hr_wallet")
	c.options["patron"] = "pay"
	s.phase = "downtime"
	var far: Dictionary = {}
	for w: Dictionary in Sector.get_sector(s)["worlds"]:
		if str(w["system"]) == "sys_1":
			far = w
	expect(not Economy.passage(s, c, far).is_empty(), "independents buy passage")
	Economy.wallet(s)["manna"] = 0
	Economy.wallet(s)["local"] = {}
	expect(not _sub(t, "travel", {"world": far["id"]})["ok"], "and can't go broke")
	c.options["patron"] = "company"
	expect(Economy.passage(s, c, far).is_empty(), "company squads ride free")
	expect(_sub(t, "travel", {"world": far["id"]})["ok"])


func test_fight_for_it_and_food_and_water() -> void:
	var t := Setup.setup(223)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_rule(t, "hr_wallet")
	_rule(t, "hr_fight_for_it")
	Economy.wallet(s)["manna"] = 0
	Economy.wallet(s)["local"] = {}
	var r := _sub(t, "buy", {"item": "supplies", "pilot": t["a"]})
	expect(not r["ok"] and str(r["reason"]).contains("work it off"), str(r["reason"]))
	r = _sub(t, "fight_for_it", {"item": "supplies", "pilot": t["a"]})
	expect(r["ok"], str(r["reason"]))
	var job: Dictionary = r["events"][0]["hook"]
	r = _finish(t, job, true, {"rounds": 3, "kills": 0, "lost": []})
	expect((s.reserves.get(t["a"], []) as Array).any(func(x: Dictionary) -> bool: return str(x["id"]) == "reserve_supplies"), "won it: the supplies are yours")
	_rule(t, "hr_survival")
	_rule(t, "hr_wallet", false)
	expect_eq(Economy.rations(s), 6, "three days each to start")
	s.flags[Economy.SURVIVAL]["rations"] = 0
	r = _finish(t, s.hooks[0], true, {"rounds": 3, "kills": 0, "lost": []})
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "hungry"), "no food: hungry")
	var opts := Economy.check_opts(s, c, t["a"], {})
	expect_eq(int(opts["difficulty"]), 1, "+1 Difficulty while hungry")
	s.phase = "downtime"
	r = _sub(t, "restock", {})
	expect(r["ok"], str(r["reason"]))
	expect(not Economy.hungry(s, c, t["a"]) and Economy.rations(s) == 4, "a friendly hub feeds the squad")
	expect(not _sub(t, "restock", {})["ok"], "once per visit")


func test_every_world_has_its_own_money() -> void:
	var t := Setup.setup(224)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_rule(t, "hr_wallet")
	var here := Economy.currency(s)
	var start_local := Economy.local(s)
	expect(start_local > 0 and here.begins_with(str(Sector.current(s)["name"])), "named after this world: %s" % here)
	expect(Economy.price(s, c, "drink")["text"].contains("manna"), "prices show both: %s" % Economy.price(s, c, "drink")["text"])
	s.phase = "downtime"
	var far: Dictionary = {}
	for w: Dictionary in Sector.get_sector(s)["worlds"]:
		if str(w["system"]) == "sys_1" and str(w["culture"]) != "union_core":
			far = w
	if far.is_empty():
		return
	expect(_sub(t, "travel", {"world": far["id"]})["ok"])
	expect(Economy.currency(s) != here, "another world, another money: %s" % Economy.currency(s))
	expect_eq(Economy.local(s), 0, "%s is no good here" % here)
	expect(Economy.describe(s).contains("other world"), Economy.describe(s))
	var m := int(Economy.wallet(s)["manna"])
	expect(_sub(t, "exchange", {"to_manna": false, "amount": 10})["ok"], "change manna at the hub")
	expect(Economy.local(s) == 10 * Economy.rate(s) and int(Economy.wallet(s)["manna"]) == m - 10)
	Sector.current(s)["culture"] = "union_core"
	expect(Economy.communal(s) and int(Economy.price(s, c, "food")["manna"]) == 0, "basics are free in the communal Union Core (Core p.10)")
	Sector.current(s)["culture"] = "frontier_colony"
	var poor := Economy.rate(s)
	Sector.current(s)["culture"] = "cyberpunk"
	expect(Economy.rate(s) < poor, "manna buys less on a rich world (%d vs %d a manna)" % [Economy.rate(s), poor])
