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
				var w: Dictionary = cfg().get("wallet", {})
				story.flags[WALLET] = {"manna": int(w.get("start_manna", 600)), "local": {currency(story): int(w.get("start_local", 120))}, "salvage": 0}
				return [{"type": "wallet_started", "text": "The squad has %s." % describe(story), "label": LABEL}]
		R_FOOD:
			if not story.flags.has(SURVIVAL):
				var n := int(cfg().get("survival", {}).get("start_rations_per_pilot", 3)) * _alive(story, campaign).size()
				story.flags[SURVIVAL] = {"rations": n, "hungry": {}}
				return [{"type": "rations_started", "text": "The squad has %d days of food and water." % n, "label": LABEL}]
	return []


# --- Wallet ------------------------------------------------------------------------------

static func wallet(story: StoryState) -> Dictionary:
	return story.flags.get(WALLET, {})


## This world's money ("dollars" on an Old West world, manna in the Union core).
static func currency(story: StoryState) -> String:
	var c: Dictionary = cfg().get("currencies", {})
	return str(c.get(str(story.hub.get("culture", "")), c.get("default", "scrip")))


## Local money per manna here.
static func rate(story: StoryState) -> int:
	var r: Dictionary = cfg().get("wallet", {}).get("rate", {})
	return maxi(1, int(r.get(str(story.hub.get("culture", "")), r.get("default", 4))))


static func local(story: StoryState) -> int:
	return int(wallet(story).get("local", {}).get(currency(story), 0))


static func describe(story: StoryState) -> String:
	var w := wallet(story)
	var cur := currency(story)
	var t := "%d manna" % int(w.get("manna", 0))
	if cur != "manna":
		t += " and %d %s" % [local(story), cur]
	if int(w.get("salvage", 0)) > 0:
		t += ", salvage worth %d manna" % int(w["salvage"])
	return t


## What `item` costs here: {"manna": n} or {"local": n}, with "text".
static func price(story: StoryState, campaign: Campaign, item: String) -> Dictionary:
	var p: Dictionary = cfg().get("prices", {}).get(item, {})
	if p.is_empty():
		return {}
	var out := {"name": str(p.get("name", item))}
	if p.has("local"):
		if currency(story) == "manna":
			out["manna"] = maxi(1, int(ceil(float(p["local"]) / 4.0)))
		else:
			out["local"] = int(p["local"])
	else:
		out["manna"] = int(p.get("manna", 0))
	out["text"] = ("%d %s" % [out["local"], currency(story)]) if out.has("local") else "%d manna" % out["manna"]
	return out


## Manna-equivalent of everything the squad can pay with: local money first, then manna, then
## salvage (with "fight for it": scrap is as good as money).
static func can_pay(story: StoryState, campaign: Campaign, cost: Dictionary) -> bool:
	if not StoryHouseRules.on(campaign, R_WALLET):
		return false
	var w := wallet(story)
	var salvage := int(w.get("salvage", 0)) if StoryHouseRules.on(campaign, R_FIGHT) else 0
	if cost.has("local"):
		return local(story) + (int(w.get("manna", 0)) + salvage) * rate(story) >= int(cost["local"])
	return int(w.get("manna", 0)) + salvage + local(story) / rate(story) >= int(cost.get("manna", 0))


static func pay(story: StoryState, campaign: Campaign, cost: Dictionary, why: String) -> Array:
	var w: Dictionary = wallet(story)
	var cur := currency(story)
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
	story.flags[WALLET] = w
	return [{"type": "paid", "for": why, "cost": cost.duplicate(), "text": "Paid %s for %s. Left: %s." % [cost.get("text", ""), why, describe(story)], "label": LABEL}]


static func _take_manna(w: Dictionary, campaign: Campaign, n: int) -> void:
	var m := int(w.get("manna", 0))
	if m >= n:
		w["manna"] = m - n
		return
	w["manna"] = 0
	if StoryHouseRules.on(campaign, R_FIGHT):
		w["salvage"] = maxi(0, int(w.get("salvage", 0)) - (n - m))


static func earn(story: StoryState, manna: int, why: String) -> Array:
	var w: Dictionary = wallet(story)
	w["manna"] = int(w.get("manna", 0)) + manna
	story.flags[WALLET] = w
	return [{"type": "earned", "manna": manna, "for": why, "text": "+%d manna: %s. Now: %s." % [manna, why, describe(story)], "label": LABEL}]


# --- Buying ------------------------------------------------------------------------------

## What the market offers right now, with prices ([] with every money rule off).
static func offers(story: StoryState, campaign: Campaign) -> Array:
	var out: Array = []
	if not StoryHouseRules.on(campaign, R_WALLET):
		return out
	for item: String in ["drink", "food", "lodging", "information", "supplies", "repair_kit"]:
		if item == "food" and not StoryHouseRules.on(campaign, R_FOOD):
			continue
		var p := price(story, campaign, item)
		p["item"] = item
		p["affordable"] = can_pay(story, campaign, p)
		out.append(p)
	return out


static func buy_refusal(story: StoryState, campaign: Campaign, item: String) -> String:
	if not StoryHouseRules.on(campaign, R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	var p := price(story, campaign, item)
	if p.is_empty() or item in ["printer", "passage_local", "passage_gate"]:
		return "That isn't for sale here."
	if story.hub.is_empty():
		return "There's nobody to buy from out here."
	if not can_pay(story, campaign, p):
		return "The squad can't afford %s (%s)." % [p["name"], p["text"]] + (" Ask to work it off instead." if StoryHouseRules.on(campaign, R_FIGHT) else "")
	return ""


static func buy(story: StoryState, campaign: Campaign, item: String, pid: String) -> Array:
	var p := price(story, campaign, item)
	var events := pay(story, campaign, p, str(p["name"]).to_lower())
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
			events.append_array(add_rations(story, campaign, int(def.get("rations", 2)) * _alive(story, campaign).size()))
		"lodging":
			for p: String in _alive(story, campaign):
				events.append_array(StoryEffects.rest(story, campaign, p))
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
			events.append_array(earn(story, amount, "%s paid for the job" % hook.get("patron", "the patron")))
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
		events.append_array(eat(story, campaign))
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
	if not has_printer(story):
		return "There's no printer on this world. Travel somewhere with one (the map shows which)."
	if StoryHouseRules.on(campaign, R_WALLET):
		var p := price(story, campaign, "printer")
		if not can_pay(story, campaign, p):
			return "Printer access costs %s." % p["text"] + (" Ask to work it off instead." if StoryHouseRules.on(campaign, R_FIGHT) else "")
	return ""


static func use_printer(story: StoryState, campaign: Campaign, pid: String) -> Array:
	var events: Array = []
	if StoryHouseRules.on(campaign, R_WALLET):
		events.append_array(pay(story, campaign, price(story, campaign, "printer"), "printer access"))
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

static func rations(story: StoryState) -> int:
	return int(story.flags.get(SURVIVAL, {}).get("rations", 0))


static func hungry(story: StoryState, campaign: Campaign, pid: String) -> bool:
	return StoryHouseRules.on(campaign, R_FOOD) and int(story.flags.get(SURVIVAL, {}).get("hungry", {}).get(pid, 0)) > 0


static func add_rations(story: StoryState, campaign: Campaign, n: int) -> Array:
	start(story, campaign, R_FOOD)
	var sv: Dictionary = story.flags[SURVIVAL]
	sv["rations"] = int(sv.get("rations", 0)) + n
	var fed: Array = (sv.get("hungry", {}) as Dictionary).keys()
	sv["hungry"] = {}
	story.flags[SURVIVAL] = sv
	return [{"type": "rations", "rations": sv["rations"], "text": "+%d days of food and water (%d now)%s." % [n, sv["rations"], ", and the hungry get to eat" if not fed.is_empty() else ""], "label": LABEL}]


## A mission uses a day's rations per pilot; without them they go hungry.
static func eat(story: StoryState, campaign: Campaign) -> Array:
	start(story, campaign, R_FOOD)
	var sv: Dictionary = story.flags[SURVIVAL]
	var events: Array = []
	var hun: Dictionary = sv.get("hungry", {})
	for pid: String in _alive(story, campaign):
		if int(sv["rations"]) > 0:
			sv["rations"] = int(sv["rations"]) - 1
			hun.erase(pid)
		else:
			hun[pid] = int(hun.get(pid, 0)) + 1
			var cs := str(campaign.pilots[pid].get("callsign", ""))
			events.append({"type": "hungry", "pilot": pid, "text": "%s is going hungry: +1 Difficulty on skill checks until they eat." % cs, "label": LABEL})
			if int(hun[pid]) >= int(cfg().get("survival", {}).get("harm_after_hungry", 2)):
				events.append_array(StoryEffects.harm(story, campaign, pid, 1, true))
	sv["hungry"] = hun
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
	if not hungry(story, campaign, pid):
		return opts
	var o := opts.duplicate(true)
	o["difficulty"] = int(o.get("difficulty", 0)) + 1
	var src: Array = o.get("sources", [])
	src.append({"label": "Hungry (house rule)", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": LABEL})
	o["sources"] = src
	return o


static func _alive(story: StoryState, campaign: Campaign) -> Array:
	return campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
