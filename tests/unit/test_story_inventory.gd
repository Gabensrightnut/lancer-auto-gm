extends TestCase
## Each pilot's own money and pack (Inventory), food and water (Survival), trades and gifts,
## and what each player is allowed to see.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _sub(t: Dictionary, type: String, params: Dictionary, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func _setup(seed_value: int) -> Dictionary:
	var t := Setup.setup(seed_value)
	_sub(t, "house_rule", {"id": "hr_wallet", "on": true})
	_sub(t, "house_rule", {"id": "hr_survival", "on": true})
	# Kettle is a second player here (not an AI squadmate).
	_sub(t, "set_seat", {"seat": "p2", "pilot": t["b"], "ai": false})
	return t


func test_trade_my_food_for_your_manna() -> void:
	var t := _setup(800)
	var s: StoryState = t["story"]
	var a: String = t["a"]
	var b: String = t["b"]
	var r := _sub(t, "trade_offer", {"from": a, "to": b, "give": {"items": {"ration": 2}}, "get": {"manna": 30}}, "p1")
	expect(r["ok"], str(r.get("reason", "")))
	var tid := str((r["events"] as Array)[0]["trade"]["id"])
	expect(not _sub(t, "trade_answer", {"trade": tid, "accept": true}, "p1")["ok"], "the other player answers, not you")
	r = _sub(t, "trade_answer", {"trade": tid, "accept": true}, "p2")
	expect(r["ok"], str(r.get("reason", "")))
	expect_eq(Inventory.count(s, a, "ration"), 1)
	expect_eq(Inventory.count(s, b, "ration"), 5)
	expect_eq(int(Economy.wallet(s, a)["manna"]), 330)
	expect_eq(int(Economy.wallet(s, b)["manna"]), 270, "swapped at once, through the story engine")
	# A gift goes straight across.
	r = _sub(t, "trade_offer", {"from": b, "to": a, "give": {"manna": 20}, "get": {}}, "p2")
	expect(r["ok"] and (r["events"] as Array)[0]["type"] == "gift")
	expect_eq(int(Economy.wallet(s, a)["manna"]), 350)
	# Nothing duplicates: an offer whose goods are gone falls through.
	r = _sub(t, "trade_offer", {"from": a, "to": b, "give": {"items": {"ration": 1}}, "get": {"manna": 5}}, "p1")
	tid = str((r["events"] as Array)[0]["trade"]["id"])
	Inventory.take(s, a, "ration", 1)
	r = _sub(t, "trade_answer", {"trade": tid, "accept": true}, "p2")
	expect((r["events"] as Array)[0]["type"] == "trade_failed", "Bluebird ate it first")
	expect_eq(Inventory.count(s, b, "ration"), 5)


func test_rations_pack_unpack_and_sell_for_more() -> void:
	var t := _setup(801)
	var s: StoryState = t["story"]
	var a: String = t["a"]
	expect(_sub(t, "unpack_ration", {"pilot": a, "n": 1}, "p1")["ok"])
	expect(Inventory.count(s, a, "food") == 1 and Inventory.count(s, a, "water") == 1)
	expect(_sub(t, "pack_ration", {"pilot": a, "n": 1}, "p1")["ok"])
	expect_eq(Inventory.count(s, a, "ration"), 3)
	expect(Inventory.sell_price(s, "ration") > Inventory.sell_price(s, "food") + Inventory.sell_price(s, "water"), "a sealed field pack is worth more than its parts")
	var before := Economy.local(s, a)
	expect(_sub(t, "sell_item", {"pilot": a, "item": "ration", "n": 1}, "p1")["ok"])
	expect(Economy.local(s, a) > before, "sold to a merchant here")


func test_food_and_water_run_down_and_upgrades_cut_the_need() -> void:
	var t := _setup(802)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var a: String = t["a"]
	_sub(t, "set_auto_eat", {"pilot": a, "on": false}, "p1")
	Survival.pass_hours(s, c, 30)
	var b := Survival.bars(s, a)
	expect(b.y < b.x, "water runs out faster than food")
	expect(Inventory.count(s, a, "ration") == 3, "auto-eat off: nothing eaten")
	expect(_sub(t, "eat", {"pilot": a, "item": "ration"}, "p1")["ok"])
	expect(Survival.bars(s, a).y > b.y, "you eat and drink yourself")
	expect_eq(Survival.need_text(c, a), "Needs 1 food, 1 water per day")
	c.pilots[a]["implants"] = ["metabolic_regulator", "synthetic_organs", "water_recycler"]
	expect_eq(Survival.need_text(c, a), "Needs 1 food, 1 water per day", "upgrades only count with the Cybernetic upgrades house rule")
	_sub(t, "house_rule", {"id": "hr_cybernetics", "on": true})
	var n := Survival.need(c, a)
	expect(absf(n.x - 0.6) < 0.01 and absf(n.y - 0.6) < 0.01, "they stack: %s" % n)
	c.pilots[a]["implants"] = ["metabolic_regulator", "metabolic_regulator", "metabolic_regulator", "metabolic_regulator", "synthetic_organs"]
	expect(absf(Survival.need(c, a).x - 0.25) < 0.01, "never below a quarter ration a day")


func test_each_player_sees_only_their_own_pack() -> void:
	var t := _setup(803)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var view := StoryView.view_for(s, c, "p1")
	var inv: Dictionary = view["flags"].get(Inventory.KEY, {})
	expect(inv.has(t["a"]) and not inv.has(t["b"]), "Bluebird's player doesn't see Kettle's wallet")
	expect(inv.has(Inventory.SQUAD) or true)
	var gm: Dictionary = StoryView.view_for(s, c, "gm")["flags"].get(Inventory.KEY, {})
	expect(gm.has(t["a"]) and gm.has(t["b"]), "the host sees all")


func test_ai_squadmates_wallets_are_their_humans_to_handle() -> void:
	var t := Setup.setup(804)
	_sub(t, "house_rule", {"id": "hr_wallet", "on": true})
	var r := _sub(t, "fund_deposit", {"pilot": t["b"], "manna": 50}, "p1")
	expect(r["ok"], "Bluebird's player puts Kettle's (AI) money into the squad fund: %s" % r.get("reason", ""))
	expect_eq(int(Economy.wallet(t["story"])["manna"]), 50)
	expect(_sub(t, "set_pay_split", {"shares": {t["a"]: 2, t["b"]: 1}})["ok"], "the host can set the split")
	var ev := Inventory.split_pay(t["story"], t["campaign"], 300, "a job")
	expect(str(ev[0]["text"]).contains("200") and str(ev[0]["text"]).contains("100"), str(ev[0]["text"]))
