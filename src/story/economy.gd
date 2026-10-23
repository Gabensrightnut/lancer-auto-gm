class_name Economy
extends RefCounted
## The money-and-supplies house rules (StoryHouseRules; all "Your idea, not a book rule"):
## a tracked wallet, printer scarcity, paid travel, "can't afford it? fight for it", and food
## and water. Nothing here runs unless its rule is on. Amounts are our own numbers
## (house_rules.json). Kept in story.flags: _wallet, _survival, _wrecked, _fight_for.
##
## StoryEngine actions: buy {item, pilot}, sell_salvage {}, use_printer {pilot},
## restock {} (free food and water at a friendly hub when the wallet is off), fight_for_it {item}.

const WALLET := "_wallet"
const SURVIVAL := "_survival"
const WRECKED := "_wrecked"
const FIGHT := "_fight_for"
const R_WALLET := "hr_wallet"
const R_PRINTERS := "hr_printers"
const R_TRAVEL := "hr_paid_travel"
const R_FIGHT := "hr_fight_for_it"
const R_FOOD := "hr_survival"
## Patrons whose squads ride free with paid travel (session zero's "who gives us orders?").
const MEMBERS := ["company", "union", "officer", "faith", "noble", "elders", "mentor"]
const LABEL := "Your idea, not a book rule"


static func cfg() -> Dictionary:
	return StoryHouseRules.data()


## Sets a rule up from where the campaign is now.
static func start(story: StoryState, campaign: Campaign, id: String) -> Array:
	match id:
		R_WALLET:
			if not story.flags.has(WALLET):
				# Every pilot has their own money (Inventory); the squad fund, for shared things,
				# starts empty and anyone can pay into it.
				story.flags[WALLET] = {"manna": 0, "local": {}, "salvage": 0}
				Inventory.start_wallets(story, campaign)
				var pid := str(_alive(story, campaign)[0]) if not _alive(story, campaign).is_empty() else ""
				return [{"type": "wallet_started", "text": "Each pilot has their own money (%s to start); the squad fund for shared things is empty." % (describe(story, pid) if pid != "" else "some"), "label": LABEL}]
		R_FOOD:
			if not story.flags.has(SURVIVAL):
				story.flags[SURVIVAL] = {"started": true, "hungry": {}}
				Inventory.start_food(story, campaign)
				return [{"type": "rations_started", "text": "Each pilot carries %d field rations (a sealed day of food and water each)." % int(Inventory.data().get("pilot_start", {}).get("items", {}).get("ration", 3)), "label": LABEL}]
	return []


# --- Wallet ------------------------------------------------------------------------------

## The squad fund (no pilot), or one pilot's own money.
static func wallet(story: StoryState, pid: String = "") -> Dictionary:
	if pid != "":
		return Inventory.wallet(story, pid)
	return story.flags.get(WALLET, {})


static func _store(story: StoryState, pid: String, w: Dictionary) -> void:
	if pid == "":
		story.flags[WALLET] = w


## Which world's money this is: each world has its own, good only there (the sector world, or
## the hub when there's no sector).
static func money_key(story: StoryState) -> String:
	var w := Sector.current(story)
	return str(w.get("id", "")) if not w.is_empty() else str(story.hub.get("id", "here"))


static func _world(story: StoryState) -> Dictionary:
	var w := Sector.current(story)
	return w if not w.is_empty() else {"id": story.hub.get("id", "here"), "name": story.hub.get("planet", story.hub.get("name", "")), "culture": story.hub.get("culture", "")}


## In the Union Core there's no money for basics: "communal and post-capital" (Core p.10).
static func communal(story: StoryState) -> bool:
	return str(_world(story).get("culture", "")) == "union_core"


## This world's own money, named after it ("Karrakis dollar"), or manna in the Union Core.
static func currency(story: StoryState) -> String:
	if communal(story):
		return "manna"
	var w := _world(story)
	var names: Dictionary = cfg().get("currency_names", {})
	var list: Array = names.get(str(w.get("culture", "")), names.get("default", ["{world} scrip"]))
	var pick := str(list[absi(hash([story.story_seed, str(w.get("id", "")), "money"])) % list.size()])
	return pick.replace("{world}", str(w.get("name", "local")))


## A short symbol for it: the world's and the unit's first letters.
static func symbol(story: StoryState) -> String:
	if communal(story):
		return "m"
	var parts := currency(story).split(" ", false)
	return (parts[0].left(1) + parts[parts.size() - 1].left(1)).to_upper() if parts.size() > 1 else currency(story).left(2).to_upper()


## How well-off this world is, 1 (poor frontier) to 5 (rich).
static func wealth(story: StoryState) -> int:
	var w := _world(story)
	var r: Array = cfg().get("wealth", {}).get(str(w.get("culture", "")), [2, 3])
	return int(r[0]) + absi(hash([story.story_seed, str(w.get("id", "")), "wealth"])) % (int(r[1]) - int(r[0]) + 1)


## Local money per manna here: manna buys more on poor worlds, less on rich ones.
static func rate(story: StoryState) -> int:
	if communal(story):
		return 1
	return maxi(1, roundi(5.0 * (6 - wealth(story)) / 3.0))


static func local(story: StoryState, pid: String = "") -> int:
	return int(wallet(story, pid).get("local", {}).get(money_key(story), 0))


## Exchanging at a hub: this world's money for manna or back (only here).
static func exchange(story: StoryState, to_manna: bool, amount: int, pid: String = "") -> Array:
	var w: Dictionary = wallet(story, pid)
	var loc: Dictionary = w.get("local", {})
	var key := money_key(story)
	if to_manna:
		var m := amount / rate(story)
		loc[key] = int(loc.get(key, 0)) - m * rate(story)
		w["manna"] = int(w.get("manna", 0)) + m
	else:
		w["manna"] = int(w.get("manna", 0)) - amount
		loc[key] = int(loc.get(key, 0)) + amount * rate(story)
	w["local"] = loc
	_store(story, pid, w)
	return [{"type": "exchanged", "pilot": pid, "text": "Changed money. Now: %s." % describe(story, pid), "label": LABEL}]


static func exchange_refusal(story: StoryState, campaign: Campaign, to_manna: bool, amount: int, pid: String = "") -> String:
	if not StoryHouseRules.on(campaign, R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	if communal(story):
		return "Nobody here deals in anything but manna."
	if amount <= 0:
		return "How much?"
	if to_manna and (local(story, pid) < amount or amount < rate(story)):
		return "You don't have that much %s (it's %d to a manna here)." % [currency(story), rate(story)]
	if not to_manna and int(wallet(story, pid).get("manna", 0)) < amount:
		return "You don't have that much manna."
	return ""


static func describe(story: StoryState, pid: String = "") -> String:
	var w := wallet(story, pid)
	var cur := currency(story)
	var t := "%d manna" % int(w.get("manna", 0))
	if cur != "manna":
		t += " and %d %s" % [local(story, pid), cur]
	var elsewhere := 0
	for k: String in w.get("local", {}):
		if k != money_key(story) and int(w["local"][k]) > 0:
			elsewhere += 1
	if elsewhere > 0:
		t += " (plus money from %d other world%s, good only there)" % [elsewhere, "" if elsewhere == 1 else "s"]
	if int(w.get("salvage", 0)) > 0:
		t += ", salvage worth %d manna" % int(w["salvage"])
	return t


## What `item` costs here: {"manna": n} or {"local": n}, with "text".
static func price(story: StoryState, campaign: Campaign, item: String) -> Dictionary:
	var p: Dictionary = cfg().get("prices", {}).get(item, {})
	if p.is_empty():
		return {}
	var out := {"name": str(p.get("name", item))}
	if communal(story) and (cfg().get("communal_free", []) as Array).has(item):
		out["manna"] = 0
		out["text"] = "free here (the Union Core is communal, Core p.10)"
		return out
	if p.has("local") and not communal(story):
		out["local"] = int(p["local"])
		out["text"] = "%d %s (about %s manna)" % [out["local"], currency(story), _manna_text(float(out["local"]) / rate(story))]
	else:
		var m := int(p.get("manna", ceili(float(p.get("local", 0)) / 4.0)))
		out["manna"] = maxi(0, m / 2) if communal(story) else m
		out["text"] = "%d manna (about %d %s)" % [out["manna"], out["manna"] * rate(story), currency(story)] if not communal(story) else "%d manna" % out["manna"]
	return out


static func _manna_text(v: float) -> String:
	return ("%d" % roundi(v)) if v >= 1.0 else "%.1f" % v


## Manna-equivalent of everything the squad can pay with: local money first, then manna, then
## salvage (with "fight for it": scrap is as good as money).
static func can_pay(story: StoryState, campaign: Campaign, cost: Dictionary, pid: String = "") -> bool:
	if not StoryHouseRules.on(campaign, R_WALLET):
		return false
	var w := wallet(story, pid)
	var salvage := int(w.get("salvage", 0)) if StoryHouseRules.on(campaign, R_FIGHT) else 0
	if cost.has("local"):
		return local(story, pid) + (int(w.get("manna", 0)) + salvage) * rate(story) >= int(cost["local"])
	return int(w.get("manna", 0)) + salvage + local(story, pid) / rate(story) >= int(cost.get("manna", 0))


## Pays from one pilot's money (pid), or the squad fund for shared things.
static func pay(story: StoryState, campaign: Campaign, cost: Dictionary, why: String, pid: String = "") -> Array:
	var w: Dictionary = wallet(story, pid)
	var cur := money_key(story)
	var loc: Dictionary = w.get("local", {})
	if cost.has("local"):
		var need := int(cost["local"])
		var from_local := mini(need, int(loc.get(cur, 0)))
		loc[cur] = int(loc.get(cur, 0)) - from_local
		need -= from_local
		if need > 0:
			var manna := int(ceil(float(need) / rate(story)))
			_take_manna(w, campaign, manna)
			loc[cur] = int(loc.get(cur, 0)) + manna * rate(story) - need
	else:
		var need := int(cost.get("manna", 0))
		var short := need - int(w.get("manna", 0)) - (int(w.get("salvage", 0)) if StoryHouseRules.on(campaign, R_FIGHT) else 0)
		if short > 0:
			var loc_need := short * rate(story)
			loc[cur] = int(loc.get(cur, 0)) - loc_need
			need -= short
		_take_manna(w, campaign, need)
	w["local"] = loc
	_store(story, pid, w)
	return [{"type": "paid", "pilot": pid, "for": why, "cost": cost.duplicate(), "text": "Paid %s for %s. Left: %s." % [cost.get("text", ""), why, describe(story, pid)], "label": LABEL}]


static func _take_manna(w: Dictionary, campaign: Campaign, n: int) -> void:
	var m := int(w.get("manna", 0))
	if m >= n:
		w["manna"] = m - n
		return
	w["manna"] = 0
	if StoryHouseRules.on(campaign, R_FIGHT):
		w["salvage"] = maxi(0, int(w.get("salvage", 0)) - (n - m))


## Money in: to one pilot (pid), or the squad fund.
static func earn(story: StoryState, manna: int, why: String, pid: String = "") -> Array:
	var w: Dictionary = wallet(story, pid)
	w["manna"] = int(w.get("manna", 0)) + manna
	_store(story, pid, w)
	return [{"type": "earned", "pilot": pid, "manna": manna, "for": why, "text": "+%d manna: %s. Now: %s." % [manna, why, describe(story, pid)], "label": LABEL}]


# --- Buying ------------------------------------------------------------------------------

## What the market offers right now, with prices ([] with every money rule off).
static func offers(story: StoryState, campaign: Campaign, pid: String = "") -> Array:
	var out: Array = []
	if not StoryHouseRules.on(campaign, R_WALLET):
		return out
	for item: String in ["drink", "food", "fresh_food", "water", "meal", "street_food", "lodging", "information", "supplies", "repair_kit"]:
		if item in ["food", "fresh_food", "water", "meal", "street_food"] and not StoryHouseRules.on(campaign, R_FOOD):
			continue
		var p := price(story, campaign, item)
		if p.is_empty():
			continue
		p["item"] = item
		p["affordable"] = can_pay(story, campaign, p, pid)
		out.append(p)
	return out


static func buy_refusal(story: StoryState, campaign: Campaign, item: String, pid: String = "") -> String:
	if not StoryHouseRules.on(campaign, R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	var p := price(story, campaign, item)
	if p.is_empty() or item in ["printer", "passage_local", "passage_gate"]:
		return "That isn't for sale here."
	if story.hub.is_empty():
		return "There's nobody to buy from out here."
	if not can_pay(story, campaign, p, pid):
		return ("%s can't afford %s (%s). A squadmate could chip in (trade), or pay from the squad fund." % [campaign.pilots.get(pid, {}).get("callsign", "You"), p["name"], p["text"]] if pid != ""
			else "The squad fund can't afford %s (%s)." % [p["name"], p["text"]]) + (" Ask to work it off instead." if StoryHouseRules.on(campaign, R_FIGHT) else "")
	return ""


## `payer`: the pilot whose own money pays ("" = the squad fund); `pid` gets what's bought.
static func buy(story: StoryState, campaign: Campaign, item: String, pid: String, payer: String = "") -> Array:
	var p := price(story, campaign, item)
	var events := pay(story, campaign, p, str(p["name"]).to_lower(), payer)
	events.append_array(_deliver(story, campaign, item, pid))
	return events


## What a purchase (or a job worked off for it) gives.
static func _deliver(story: StoryState, campaign: Campaign, item: String, pid: String) -> Array:
	var def: Dictionary = cfg().get("prices", {}).get(item, {})
	var events: Array = []
	match item:
		"drink":
			events.append({"type": "bought", "item": item, "text": "Drinks all round at %s." % story.hub.get("name", "the bar")})
		"food":
			start(story, campaign, R_FOOD)
			Inventory.add(story, pid, "ration", int(def.get("rations", 2)))
			events.append({"type": "rations", "pilot": pid, "text": "%s buys %d field rations (a sealed day of food and water each)." % [campaign.pilots.get(pid, {}).get("callsign", ""), int(def.get("rations", 2))], "label": LABEL})
		"fresh_food", "water":
			start(story, campaign, R_FOOD)
			var what := "food" if item == "fresh_food" else "water"
			Inventory.add(story, pid, what, int(def.get("n", 1)))
			events.append({"type": "rations", "pilot": pid, "text": "%s buys %s." % [campaign.pilots.get(pid, {}).get("callsign", ""), str(def.get("name", what)).to_lower()], "label": LABEL})
		"lodging":
			story.flags["lodged:%d" % story.mission_number] = true
			story.flags.erase("_sick")
			for p: String in _alive(story, campaign):
				events.append_array(StoryEffects.rest(story, campaign, p))
		"meal", "street_food":
			events.append_array(meal(story, campaign))
		"information":
			var hk: Dictionary = story.hooks[0] if not story.hooks.is_empty() else {}
			events.append({"type": "bought", "item": item, "text": ("Word is the next job will be against %s, at %s." % [hk.get("enemy", "someone"), hk.get("place", "somewhere")]) if not hk.is_empty() else "Nothing worth hearing right now."})
		"supplies":
			events.append_array(StoryEffects.give_reserve(story, campaign, {"speaker": pid}, {"reserve": str(def.get("reserve", "reserve_supplies")), "to": pid, "source": "Bought (house rule)"}))
		"repair_kit":
			events.append_array(StoryEffects.give_reserve(story, campaign, {"speaker": pid}, {"reserve": "custom", "name": str(def.get("custom", "Repair kit")), "to": pid, "source": "Bought (house rule)"}))
		"printer":
			events.append_array(_reprint(story, campaign, pid))
	return events


## Selling salvage from won fights at a hub.
static func sell_salvage(story: StoryState) -> Array:
	var w: Dictionary = wallet(story)
	var s := int(w.get("salvage", 0))
	w["salvage"] = 0
	w["manna"] = int(w.get("manna", 0)) + s
	story.flags[WALLET] = w
	return [{"type": "earned", "manna": s, "for": "salvage", "text": "Sold the salvage for %d manna. Now: %s." % [s, describe(story)], "label": LABEL}]


# --- After a mission ---------------------------------------------------------------------

## Pay, salvage, rations and wrecked mechs, for the rules that are on.
static func after_mission(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool, summary: Dictionary) -> Array:
	var events: Array = []
	if StoryHouseRules.on(campaign, R_WALLET):
		start(story, campaign, R_WALLET)
		var pays: Dictionary = cfg().get("wallet", {}).get("pay", {})
		var amount := int(pays.get(str(hook.get("template", "")), pays.get("default", 400)))
		if won and amount > 0 and not bool(hook.get("tutorial", false)):
			# The pay is split between the pilots (Inventory; the host can set shares).
			events.append_array(Inventory.split_pay(story, campaign, amount, "%s paid for the job" % hook.get("patron", "the patron")))
		var kills := int(summary.get("kills", 0))
		if won and kills > 0:
			var w: Dictionary = wallet(story)
			var add := kills * int(cfg().get("wallet", {}).get("salvage_per_kill", 40))
			w["salvage"] = int(w.get("salvage", 0)) + add
			story.flags[WALLET] = w
			events.append({"type": "salvage", "value": add, "text": "Salvage from %d wrecks, worth about %d manna." % [kills, add], "label": LABEL})
		# A job worked off: what it was for.
		var ff: Dictionary = story.flags.get(FIGHT, {})
		if ff.has(str(hook.get("id", ""))):
			var deal: Dictionary = ff[str(hook["id"])]
			ff.erase(str(hook["id"]))
			story.flags[FIGHT] = ff
			if won:
				events.append({"type": "bought", "item": deal["item"], "text": "Worked off: %s." % deal["name"]})
				events.append_array(_deliver(story, campaign, str(deal["item"]), str(deal["pilot"])))
			else:
				events.append({"type": "deal_off", "text": "The deal for %s is off. You can still pay for it, in money or salvage." % deal["name"], "label": LABEL})
	if StoryHouseRules.on(campaign, R_FOOD):
		var cut: Array = (summary.get("lost", []) as Array) + (summary.get("ejected", []) as Array)
		events.append_array(eat(story, campaign, maxi(1, int(hook.get("nights", 2 if bool(hook.get("hazardous", false)) else 1))), cut))
	if StoryHouseRules.on(campaign, R_PRINTERS):
		var lost: Array = summary.get("lost", [])
		var wrecked: Array = (story.flags.get(WRECKED, []) as Array).duplicate()
		for pid: String in campaign.pilots:
			if lost.has(str(campaign.pilots[pid].get("callsign", ""))) and not wrecked.has(pid):
				wrecked.append(pid)
				events.append({"type": "mech_wrecked", "pilot": pid, "text": "%s's mech stays wrecked until it can be reprinted at a printer%s." % [campaign.pilots[pid].get("callsign", ""),
					"" if has_printer(story) else " (there's none on this world)"], "label": LABEL})
		story.flags[WRECKED] = wrecked
	return events


# --- Printers ----------------------------------------------------------------------------

## Does this world have a printer? Always, with the rule off (Core p.31, p.82).
static func has_printer(story: StoryState, w: Dictionary = {}) -> bool:
	if w.is_empty():
		w = Sector.current(story)
	if w.is_empty():
		return true
	var chance := int(cfg().get("printers", {}).get("no_printer_chance", {}).get(str(w.get("culture", "")), 0))
	return absi(hash([story.story_seed, str(w.get("id", "")), "printer"])) % 100 >= chance


static func wrecked(story: StoryState, campaign: Campaign) -> Array:
	return (story.flags.get(WRECKED, []) as Array) if StoryHouseRules.on(campaign, R_PRINTERS) else []


static func printer_refusal(story: StoryState, campaign: Campaign, pid: String) -> String:
	if not StoryHouseRules.on(campaign, R_PRINTERS):
		return "Printers are everywhere (the printer scarcity house rule is off)."
	if not wrecked(story, campaign).has(pid):
		return "That pilot's mech isn't wrecked."
	if not has_printer(story) and not Plunder.has_printer(story, campaign):
		return "There's no printer on this world. Travel somewhere with one (the map shows which)."
	if StoryHouseRules.on(campaign, R_WALLET):
		var p := price(story, campaign, "printer")
		if not can_pay(story, campaign, p, pid):
			return "Printer access costs %s." % p["text"] + (" Ask to work it off instead." if StoryHouseRules.on(campaign, R_FIGHT) else "")
	return ""


static func use_printer(story: StoryState, campaign: Campaign, pid: String) -> Array:
	var events: Array = []
	if Plunder.has_printer(story, campaign):
		pass  # The squad's own printer, aboard their ship.
	elif StoryHouseRules.on(campaign, R_WALLET):
		events.append_array(pay(story, campaign, price(story, campaign, "printer"), "printer access", pid))
	else:
		events.append_array(StoryEffects.apply({"obligation": {"to": str(story.hub.get("faction", "")), "what": "Printer time at %s" % story.hub.get("name", "")}}, story, campaign, {}))
	events.append_array(_reprint(story, campaign, pid))
	return events


static func _reprint(story: StoryState, campaign: Campaign, pid: String) -> Array:
	var w: Array = (story.flags.get(WRECKED, []) as Array).duplicate()
	w.erase(pid)
	story.flags[WRECKED] = w
	return [{"type": "mech_reprinted", "pilot": pid, "text": "%s's mech comes off the printer, good as new." % campaign.pilots.get(pid, {}).get("callsign", ""), "rule_ref": "Core p.82: printing a mech"}]


# --- Paid travel -------------------------------------------------------------------------

static func rides_free(campaign: Campaign) -> bool:
	return MEMBERS.has(str(campaign.options.get("patron", "")))


static func passage(story: StoryState, campaign: Campaign, to: Dictionary) -> Dictionary:
	if not StoryHouseRules.on(campaign, R_TRAVEL) or rides_free(campaign):
		return {}
	var gate := str(to.get("system", "")) != str(Sector.current(story).get("system", ""))
	return price(story, campaign, "passage_gate" if gate else "passage_local")


static func travel_refusal(story: StoryState, campaign: Campaign, to: Dictionary) -> String:
	var p := passage(story, campaign, to)
	if p.is_empty() or not StoryHouseRules.on(campaign, R_WALLET):
		return ""
	return "" if can_pay(story, campaign, p) else "The squad can't afford passage (%s)." % p["text"]


static func pay_passage(story: StoryState, campaign: Campaign, to: Dictionary) -> Array:
	var p := passage(story, campaign, to)
	if p.is_empty():
		return []
	if StoryHouseRules.on(campaign, R_WALLET):
		return pay(story, campaign, p, "passage to %s" % to.get("name", ""))
	return StoryEffects.apply({"obligation": {"to": str(story.hub.get("faction", "")), "what": "Passage to %s" % to.get("name", "")}}, story, campaign, {})


# --- Can't afford it? Fight for it -------------------------------------------------------

static func fight_refusal(story: StoryState, campaign: Campaign, item: String) -> String:
	if not StoryHouseRules.on(campaign, R_FIGHT):
		return "There's no working it off (that house rule is off)."
	if cfg().get("prices", {}).get(item, {}).is_empty() or item in ["passage_local", "passage_gate"]:
		return "There's nothing like that to work for."
	if story.hub.is_empty():
		return "There's nobody here to make a deal with."
	if (story.flags.get(FIGHT, {}) as Dictionary).values().any(func(d: Dictionary) -> bool: return str(d["item"]) == item):
		return "You already have a job lined up for that."
	return ""


## The seller offers a job instead of money: it goes on the board; win it to get the thing.
static func fight_for(story: StoryState, campaign: Campaign, item: String, pid: String) -> Array:
	var hook := MissionHooks.make(story, campaign, "clear_raiders", {})
	var def: Dictionary = cfg().get("prices", {}).get(item, {})
	hook["title"] = "Work It Off: %s" % hook["title"]
	hook["stakes"] = "Do this and %s is yours. Fail, and the deal's off." % str(def.get("name", item)).to_lower()
	story.hooks.append(hook)
	var ff: Dictionary = (story.flags.get(FIGHT, {}) as Dictionary).duplicate()
	ff[str(hook["id"])] = {"item": item, "name": str(def.get("name", item)), "pilot": pid}
	story.flags[FIGHT] = ff
	return [{"type": "hook_added", "hook": hook, "label": LABEL}]


# --- Food and water ----------------------------------------------------------------------

## Field rations carried: one pilot's, or everyone's (and the squad stash's) together.
static func rations(story: StoryState, pid: String = "") -> int:
	if pid != "":
		return Inventory.count(story, pid, "ration")
	var n := Inventory.count(story, Inventory.SQUAD, "ration")
	for p: String in (story.flags.get(Inventory.KEY, {}) as Dictionary):
		if p != Inventory.SQUAD and story.is_alive(p):
			n += Inventory.count(story, p, "ration")
	return n


static func hungry(story: StoryState, campaign: Campaign, pid: String) -> bool:
	return Survival.hungry(story, campaign, pid)


## n field rations shared out between the pilots (bought for the squad, a friendly hub's
## restock).
static func add_rations(story: StoryState, campaign: Campaign, n: int) -> Array:
	start(story, campaign, R_FOOD)
	var alive := _alive(story, campaign)
	if alive.is_empty():
		Inventory.add(story, Inventory.SQUAD, "ration", n)
	else:
		for i in range(n):
			Inventory.add(story, str(alive[i % alive.size()]), "ration", 1)
	var events: Array = [{"type": "rations", "rations": rations(story), "text": "+%d field rations, shared out (%d in the squad's packs now)." % [n, rations(story)], "label": LABEL}]
	# Anyone running low eats now (auto-eat).
	events.append_array(Survival.pass_hours(story, campaign, 0.01))
	return events


## Time on the road or in the field: `nights` days of food and water from each pilot's own
## stash (Survival), and the troops' upkeep from the squad stash (Troops).
static func eat(story: StoryState, campaign: Campaign, nights: int = 1, _cut_off: Array = []) -> Array:
	start(story, campaign, R_FOOD)
	var events := Survival.pass_hours(story, campaign, nights * 24.0)
	# The squad's own troops eat too: a ration per squad per day (Troops).
	if not Troops.squads(story).is_empty():
		events.append_array(Troops.feed(story, campaign, nights))
	return events


## The squad is hosted (a room bought, a patron's quarters, a ship's passage, the communal
## Union Core): meals come with the stay.
static func hosted(story: StoryState, campaign: Campaign) -> bool:
	return bool(story.flags.get("lodged:%d" % story.mission_number, false)) or rides_free(campaign) or communal(story) \
		or bool(story.flags.get("travelled:%d" % story.mission_number, false))


## A night in town during downtime: hosted, or from the squad's stores.
static func downtime_night(story: StoryState, campaign: Campaign) -> Array:
	if not StoryHouseRules.on(campaign, R_FOOD):
		return []
	if hosted(story, campaign):
		Survival.refill(story, campaign)
		return [{"type": "rations", "rations": rations(story), "text": "Meals come with the stay tonight.", "label": LABEL}]
	return eat(story, campaign, 1)


## Eating out: tonight's food for the squad, and how it sits with each pilot (their origin
## against this world's food).
static func meal(story: StoryState, campaign: Campaign) -> Array:
	var events: Array = []
	var here: Array = cfg().get("culture_food", {}).get(str(_world(story).get("culture", "")), [])
	var sv: Dictionary = story.flags.get(SURVIVAL, {})
	var mood: Dictionary = story.flags.get("_mood", {})
	var sick: Dictionary = story.flags.get("_sick", {})
	for pid: String in _alive(story, campaign):
		var likes := Origin.food_likes(campaign.pilots[pid])
		var match_ := likes.any(func(f: String) -> bool: return here.has(f))
		var roll := story.dice.die(6)
		var cs := str(campaign.pilots[pid].get("callsign", ""))
		if roll == 6 or (match_ and roll >= 5):
			mood[pid] = true
			events.append({"type": "meal", "pilot": pid, "text": "%s has found a new favourite (+1 Accuracy on their next skill check)." % cs, "label": LABEL})
		elif roll == 1 and not match_ and not likes.is_empty():
			sick[pid] = true
			events.append({"type": "meal", "pilot": pid, "text": "The food doesn't sit right with %s (+1 Difficulty on skill checks until they rest)." % cs, "label": LABEL})
	story.flags["_mood"] = mood
	story.flags["_sick"] = sick
	Survival.refill(story, campaign)
	if not sv.is_empty():
		sv["hungry"] = {}
		story.flags[SURVIVAL] = sv
	return events


## Free food and water at a friendly hub, once per downtime, when money isn't tracked.
static func restock_refusal(story: StoryState, campaign: Campaign) -> String:
	if not StoryHouseRules.on(campaign, R_FOOD):
		return "Food isn't tracked (that house rule is off)."
	if StoryHouseRules.on(campaign, R_WALLET):
		return "With the wallet on, buy food at the market."
	if story.hub.is_empty():
		return "There's nowhere to stock up out here."
	if story.get_standing(str(story.hub.get("faction", ""))) < int(cfg().get("survival", {}).get("free_restock_standing", 0)):
		return "Nobody here will feed you."
	if bool(story.flags.get("restocked:%d" % story.mission_number, false)):
		return "You've already stocked up here this time."
	return ""


static func restock(story: StoryState, campaign: Campaign) -> Array:
	story.flags["restocked:%d" % story.mission_number] = true
	return add_rations(story, campaign, 2 * _alive(story, campaign).size())


## Skill checks while hungry: +1 Difficulty (house rule).
static func check_opts(story: StoryState, campaign: Campaign, pid: String, opts: Dictionary) -> Dictionary:
	if not StoryHouseRules.on(campaign, R_FOOD):
		return opts
	var o := opts.duplicate(true)
	var src: Array = o.get("sources", [])
	var diff := 0
	if hungry(story, campaign, pid):
		diff += 1
		src.append({"label": "Hungry (house rule)", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": LABEL})
	if (story.flags.get("_sick", {}) as Dictionary).has(pid):
		diff += 1
		src.append({"label": "The food didn't agree with them (house rule)", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": LABEL})
	var mood: Dictionary = story.flags.get("_mood", {})
	if mood.has(pid):
		mood.erase(pid)
		o["accuracy"] = int(o.get("accuracy", 0)) + 1
		src.append({"label": "A good meal (house rule)", "kind": "accuracy", "type": "accuracy", "value": 1, "rule_ref": LABEL})
	o["difficulty"] = int(o.get("difficulty", 0)) + diff
	o["sources"] = src
	return o


static func _alive(story: StoryState, campaign: Campaign) -> Array:
	return campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
