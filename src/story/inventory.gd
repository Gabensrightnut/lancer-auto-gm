class_name Inventory
extends RefCounted
## Each pilot's own money and stash (data/game/story/inventory.json), and the squad fund for
## shared things (the ship, the troops' rations, passage): story.flags["_inv"] =
## {pilot id: {wallet: {manna, local: {world: n}}, items: {id: n}, food, water, auto_eat},
##  "squad": {items: {id: n}}}. The squad fund's money is Economy.wallet(story) (no pilot).
## Money only counts with the tracked-wallet house rule, food and water only with the
## food-and-water one (both the user's, off by default).
##
## Trades and gifts go through the StoryEngine (host-authoritative, logged): trade_offer
## {from, to, give: {manna, local, items}, get: {...}} puts an offer up; the other side's
## player answers trade_answer {trade, accept}; it's swapped at once if both still have it.
## A gift (nothing asked back) goes straight across. AI squadmates' stashes are handled by
## their human. Clients only see their own pilots' stashes (view_for), plus open trades.

const FILE := "res://data/game/story/inventory.json"
const KEY := "_inv"
const SQUAD := "squad"
const TRADES := "_trades"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func item_def(id: String) -> Dictionary:
	return data().get("items", {}).get(id, {})


static func item_name(id: String, n: int = 1) -> String:
	var d := item_def(id)
	return str(d.get("name" if n == 1 else "plural", id))


## A pilot's (or the squad's) record, made on first use.
static func of(story: StoryState, who: String) -> Dictionary:
	if not story.flags.has(KEY):
		story.flags[KEY] = {}
	var all: Dictionary = story.flags[KEY]
	if not all.has(who):
		all[who] = {"wallet": {"manna": 0, "local": {}}, "items": {}, "food": 100.0, "water": 100.0, "auto_eat": true} if who != SQUAD else {"items": {}}
	return all[who]


static func wallet(story: StoryState, pid: String) -> Dictionary:
	var rec := of(story, pid)
	if not rec.has("wallet"):
		rec["wallet"] = {"manna": 0, "local": {}}
	return rec["wallet"]


## Starting money for every pilot (tracked wallet turned on).
static func start_wallets(story: StoryState, campaign: Campaign) -> void:
	var st: Dictionary = data().get("pilot_start", {})
	for pid: String in campaign.pilots:
		var rec := of(story, pid)
		if bool(rec.get("_paid", false)):
			continue
		rec["_paid"] = true
		var w := wallet(story, pid)
		w["manna"] = int(w.get("manna", 0)) + int(st.get("manna", 300))
		var loc: Dictionary = w.get("local", {})
		loc[Economy.money_key(story)] = int(loc.get(Economy.money_key(story), 0)) + int(st.get("local", 60))
		w["local"] = loc


## Starting food for every pilot (food and water turned on).
static func start_food(story: StoryState, campaign: Campaign) -> void:
	var st: Dictionary = data().get("pilot_start", {}).get("items", {})
	for pid: String in campaign.pilots:
		var rec := of(story, pid)
		if bool(rec.get("_fed", false)):
			continue
		rec["_fed"] = true
		for id: String in st:
			add(story, pid, id, int(st[id]))


static func count(story: StoryState, who: String, id: String) -> int:
	return int(of(story, who)["items"].get(id, 0))


static func add(story: StoryState, who: String, id: String, n: int) -> void:
	var items: Dictionary = of(story, who)["items"]
	items[id] = int(items.get(id, 0)) + n
	if int(items[id]) <= 0:
		items.erase(id)


static func take(story: StoryState, who: String, id: String, n: int) -> bool:
	if count(story, who, id) < n:
		return false
	add(story, who, id, -n)
	return true


## What a pilot carries, in plain words.
static func describe(story: StoryState, pid: String) -> String:
	var parts := PackedStringArray()
	var items: Dictionary = of(story, pid)["items"]
	for id: String in items:
		parts.append("%d %s" % [int(items[id]), item_name(id, int(items[id]))])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


# --- Field rations: pack and unpack ------------------------------------------------------

static func pack_refusal(story: StoryState, pid: String, n: int, unpack: bool) -> String:
	if n <= 0:
		return "How many?"
	if unpack:
		return "" if count(story, pid, "ration") >= n else "Not enough field rations to open."
	return "" if count(story, pid, "food") >= n and count(story, pid, "water") >= n else "A field ration takes one food and one water."


static func pack(story: StoryState, pid: String, n: int, unpack: bool) -> Array:
	if unpack:
		add(story, pid, "ration", -n)
		add(story, pid, "food", n)
		add(story, pid, "water", n)
		return [{"type": "unpacked", "pilot": pid, "n": n, "text": "Opened %d field ration%s into food and water." % [n, "" if n == 1 else "s"]}]
	add(story, pid, "food", -n)
	add(story, pid, "water", -n)
	add(story, pid, "ration", n)
	return [{"type": "packed", "pilot": pid, "n": n, "text": "Sealed %d day%s of food and water into field rations: they keep, and pack small." % [n, "" if n == 1 else "s"]}]


# --- Selling and buying stash items ------------------------------------------------------

## What a merchant here pays for one (world-dependent; a sealed ration more than its parts).
static func sell_price(story: StoryState, id: String) -> int:
	var d := item_def(id)
	var base := 0.0
	if d.has("makes"):
		for part: String in d["makes"]:
			base += float(item_def(part).get("price_local", 0)) * int(d["makes"][part])
		base *= float(d.get("bonus", 1.25))
	else:
		base = float(d.get("price_local", 0))
	var wealth := Economy.wealth(story)
	return maxi(1, roundi(base * float(data().get("sell_rate", 0.6)) * (1.0 + (3 - wealth) * 0.15)))


static func buy_price(story: StoryState, id: String) -> int:
	return maxi(1, roundi(sell_price(story, id) / float(data().get("sell_rate", 0.6))))


static func sell_refusal(story: StoryState, campaign: Campaign, pid: String, id: String, n: int) -> String:
	if not StoryHouseRules.on(campaign, Economy.R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	if story.hub.is_empty():
		return "There's nobody to sell to out here."
	if item_def(id).is_empty():
		return "Nobody buys that here."
	if n <= 0 or count(story, pid, id) < n:
		return "You don't have that many."
	return ""


static func sell(story: StoryState, campaign: Campaign, pid: String, id: String, n: int) -> Array:
	var each := sell_price(story, id)
	add(story, pid, id, -n)
	var w := wallet(story, pid)
	var loc: Dictionary = w.get("local", {})
	var key := Economy.money_key(story)
	if Economy.communal(story):
		w["manna"] = int(w.get("manna", 0)) + maxi(1, each * n / 4)
	else:
		loc[key] = int(loc.get(key, 0)) + each * n
		w["local"] = loc
	return [{"type": "sold", "pilot": pid, "item": id, "n": n, "text": "Sold %d %s for %d %s." % [n, item_name(id, n), each * n, Economy.currency(story)], "label": Economy.LABEL}]


# --- The squad fund ----------------------------------------------------------------------

## A pilot pays into the squad fund (money for shared things).
static func deposit(story: StoryState, campaign: Campaign, pid: String, manna: int, loc_amount: int) -> Array:
	var w := wallet(story, pid)
	var fund: Dictionary = Economy.wallet(story)
	var key := Economy.money_key(story)
	w["manna"] = int(w.get("manna", 0)) - manna
	fund["manna"] = int(fund.get("manna", 0)) + manna
	var l1: Dictionary = w.get("local", {})
	var l2: Dictionary = fund.get("local", {})
	l1[key] = int(l1.get(key, 0)) - loc_amount
	l2[key] = int(l2.get(key, 0)) + loc_amount
	w["local"] = l1
	fund["local"] = l2
	story.flags[Economy.WALLET] = fund
	return [{"type": "fund_paid", "pilot": pid, "text": "%s puts %d manna%s into the squad fund." % [campaign.pilots[pid].get("callsign", ""), manna,
		(" and %d %s" % [loc_amount, Economy.currency(story)]) if loc_amount > 0 else ""], "label": Economy.LABEL}]


static func deposit_refusal(story: StoryState, campaign: Campaign, pid: String, manna: int, loc_amount: int) -> String:
	if not StoryHouseRules.on(campaign, Economy.R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	if manna < 0 or loc_amount < 0 or manna + loc_amount <= 0:
		return "How much?"
	var w := wallet(story, pid)
	if int(w.get("manna", 0)) < manna or int(w.get("local", {}).get(Economy.money_key(story), 0)) < loc_amount:
		return "You don't have that much."
	return ""


## Mission pay, split between the pilots (evenly, or by the host's shares).
static func split_pay(story: StoryState, campaign: Campaign, manna: int, why: String) -> Array:
	var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
	if alive.is_empty():
		return Economy.earn(story, manna, why)
	var shares: Dictionary = campaign.options.get("pay_split", {})
	var total := 0.0
	for p: String in alive:
		total += float(shares.get(p, 1.0))
	var given := 0
	var parts := PackedStringArray()
	for i in range(alive.size()):
		var p := str(alive[i])
		var cut := (manna - given) if i == alive.size() - 1 else int(floor(manna * float(shares.get(p, 1.0)) / total))
		given += cut
		var w := wallet(story, p)
		w["manna"] = int(w.get("manna", 0)) + cut
		parts.append("%s %d" % [campaign.pilots[p].get("callsign", ""), cut])
	return [{"type": "earned", "manna": manna, "for": why, "split": true, "text": "+%d manna: %s, split %s." % [manna, why, ", ".join(parts)], "label": Economy.LABEL}]


# --- Trading and gifts -------------------------------------------------------------------

static func _has_all(story: StoryState, pid: String, side: Dictionary) -> bool:
	var w := wallet(story, pid)
	var key := Economy.money_key(story)
	if int(side.get("manna", 0)) > int(w.get("manna", 0)) or int(side.get("local", 0)) > int(w.get("local", {}).get(key, 0)):
		return false
	for id: String in side.get("items", {}):
		if count(story, pid, id) < int(side["items"][id]):
			return false
	return true


static func _clean(side: Dictionary) -> Dictionary:
	var items := {}
	for id: String in side.get("items", {}):
		if int(side["items"][id]) > 0:
			items[id] = int(side["items"][id])
	return {"manna": maxi(0, int(side.get("manna", 0))), "local": maxi(0, int(side.get("local", 0))), "items": items}


static func _empty(side: Dictionary) -> bool:
	return int(side.get("manna", 0)) <= 0 and int(side.get("local", 0)) <= 0 and (side.get("items", {}) as Dictionary).is_empty()


static func offer_refusal(story: StoryState, campaign: Campaign, from: String, to: String, give: Dictionary, want: Dictionary) -> String:
	if not campaign.pilots.has(from) or not campaign.pilots.has(to) or from == to:
		return "Trade with which pilot?"
	if not story.is_alive(from) or not story.is_alive(to):
		return "They're not here to trade with."
	if story.phase == "mission":
		return "Not in the middle of a fight."
	if _empty(_clean(give)) and _empty(_clean(want)):
		return "Put something in."
	if not _has_all(story, from, _clean(give)):
		return "You don't have all of that."
	if (int(give.get("manna", 0)) > 0 or int(give.get("local", 0)) > 0 or int(want.get("manna", 0)) > 0 or int(want.get("local", 0)) > 0) and not StoryHouseRules.on(campaign, Economy.R_WALLET):
		return "Money isn't tracked (the wallet house rule is off)."
	return ""


## Puts an offer up (or hands a gift straight over).
static func offer(story: StoryState, campaign: Campaign, from: String, to: String, give: Dictionary, want: Dictionary) -> Array:
	var g := _clean(give)
	var w := _clean(want)
	if _empty(w):
		_move(story, from, to, g)
		var gift := {"type": "gift", "from": from, "to": to, "give": g, "text": "%s gives %s %s." % [_cs(campaign, from), _cs(campaign, to), _side_text(story, g)]}
		story.add_log(str(gift["text"]))
		return [gift]
	var trades: Dictionary = story.flags.get(TRADES, {})
	var id := "t%d" % (int(story.flags.get("_trade_next", 0)) + 1)
	story.flags["_trade_next"] = int(story.flags.get("_trade_next", 0)) + 1
	trades[id] = {"id": id, "from": from, "to": to, "give": g, "get": w}
	story.flags[TRADES] = trades
	return [{"type": "trade_offered", "trade": trades[id].duplicate(true), "text": "%s offers %s %s for %s." % [_cs(campaign, from), _cs(campaign, to), _side_text(story, g) if not _empty(g) else "nothing", _side_text(story, w)]}]


static func answer_refusal(story: StoryState, trade_id: String) -> String:
	return "" if (story.flags.get(TRADES, {}) as Dictionary).has(trade_id) else "That offer's gone."


## The other side answers: both sides swap at once if both still have what they offered.
static func answer(story: StoryState, campaign: Campaign, trade_id: String, accept: bool) -> Array:
	var trades: Dictionary = story.flags.get(TRADES, {})
	var t: Dictionary = trades[trade_id]
	trades.erase(trade_id)
	story.flags[TRADES] = trades
	if not accept:
		return [{"type": "trade_declined", "trade": trade_id, "text": "%s turns the offer down." % _cs(campaign, str(t["to"]))}]
	if not _has_all(story, str(t["from"]), t["give"]) or not _has_all(story, str(t["to"]), t["get"]):
		return [{"type": "trade_failed", "trade": trade_id, "text": "The trade falls through: someone doesn't have it any more."}]
	_move(story, str(t["from"]), str(t["to"]), t["give"])
	_move(story, str(t["to"]), str(t["from"]), t["get"])
	var text := "%s and %s trade: %s for %s." % [_cs(campaign, str(t["from"])), _cs(campaign, str(t["to"])), _side_text(story, t["give"]), _side_text(story, t["get"])]
	story.add_log(text)
	return [{"type": "traded", "trade": trade_id, "from": t["from"], "to": t["to"], "text": text}]


static func cancel(story: StoryState, trade_id: String) -> Array:
	var trades: Dictionary = story.flags.get(TRADES, {})
	trades.erase(trade_id)
	story.flags[TRADES] = trades
	return [{"type": "trade_cancelled", "trade": trade_id}]


static func _move(story: StoryState, from: String, to: String, side: Dictionary) -> void:
	var a := wallet(story, from)
	var b := wallet(story, to)
	var key := Economy.money_key(story)
	a["manna"] = int(a.get("manna", 0)) - int(side.get("manna", 0))
	b["manna"] = int(b.get("manna", 0)) + int(side.get("manna", 0))
	var la: Dictionary = a.get("local", {})
	var lb: Dictionary = b.get("local", {})
	la[key] = int(la.get(key, 0)) - int(side.get("local", 0))
	lb[key] = int(lb.get(key, 0)) + int(side.get("local", 0))
	a["local"] = la
	b["local"] = lb
	for id: String in side.get("items", {}):
		add(story, from, id, -int(side["items"][id]))
		add(story, to, id, int(side["items"][id]))


static func _side_text(story: StoryState, side: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(side.get("manna", 0)) > 0:
		parts.append("%d manna" % int(side["manna"]))
	if int(side.get("local", 0)) > 0:
		parts.append("%d %s" % [int(side["local"]), Economy.currency(story)])
	for id: String in side.get("items", {}):
		parts.append("%d %s" % [int(side["items"][id]), item_name(id, int(side["items"][id]))])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


static func _cs(campaign: Campaign, pid: String) -> String:
	return str(campaign.pilots.get(pid, {}).get("callsign", pid))


# --- What a client may see ---------------------------------------------------------------

## Only this seat's own pilots' stashes (and the squad fund), plus trades involving them.
static func view_for(story: StoryState, seat: String) -> Dictionary:
	var all: Dictionary = story.flags.get(KEY, {})
	if seat == "gm":
		return all.duplicate(true)
	var mine := mine_of(story, seat)
	var out := {}
	for k: String in all:
		if k == SQUAD or mine.has(k):
			out[k] = (all[k] as Dictionary).duplicate(true)
	return out


static func trades_for(story: StoryState, seat: String) -> Dictionary:
	var all: Dictionary = story.flags.get(TRADES, {})
	if seat == "gm":
		return all.duplicate(true)
	var mine := mine_of(story, seat)
	var out := {}
	for k: String in all:
		if mine.has(str(all[k]["from"])) or mine.has(str(all[k]["to"])):
			out[k] = (all[k] as Dictionary).duplicate(true)
	return out


## The pilots a seat looks after: its own (and its second), and the AI squadmates who follow it.
static func mine_of(story: StoryState, seat: String) -> Array:
	var out: Array = [story.pilot_of_seat(seat), str(story.seats.get(seat, {}).get("second", ""))]
	for s: String in story.seats:
		if story.is_ai(s) and Decisions.leader_of(story, s) == seat:
			out.append(story.pilot_of_seat(s))
	return out.filter(func(p: String) -> bool: return p != "")
