class_name Plunder
extends RefCounted
## Pirate loot and the squad's own ship (the pirate career, DESIGN.md). A raid job carries
## "loot": {"name", "value"}. After a won raid, what the squad takes depends on the house
## rules (all "Your idea, not a book rule"; numbers in house_rules.json "own_ship"):
##   - hr_wallet on: the haul goes in the hold as salvage and sells for money (sell_salvage).
##   - hr_own_ship on (wallet off): it's kept as loot, to spend on the ship.
##   - both off, by the book: the haul is a Resource reserve for the squad (Core p.48).
## hr_own_ship: the squad's ship has upgrade slots (hull, engines, printer, cargo, boarding
## gear), bought with money (wallet on) or loot. Kept in story.flags["_ship"] =
## {"loot": int, "slots": {slot: level}}.
##
## StoryEngine action: buy_upgrade {slot}.

const KEY := "_ship"
const RULE := "hr_own_ship"
const REF_RESERVE := "Core p.48: reserves"


static func cfg() -> Dictionary:
	return StoryHouseRules.data().get("own_ship", {})


static func ship(story: StoryState) -> Dictionary:
	return story.flags.get(KEY, {"loot": 0, "slots": {}})


static func level(story: StoryState, campaign: Campaign, slot: String) -> int:
	if not StoryHouseRules.on(campaign, RULE):
		return 0
	return int(ship(story).get("slots", {}).get(slot, 0))


static func after_mission(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool) -> Array:
	var loot: Dictionary = hook.get("loot", {})
	if loot.is_empty() or not won:
		return []
	var name := str(loot.get("name", "the cargo"))
	var value := int(round(int(loot.get("value", 200)) * (1.0 + 0.25 * level(story, campaign, "cargo"))))
	if StoryHouseRules.on(campaign, Economy.R_WALLET):
		Economy.start(story, campaign, Economy.R_WALLET)
		var w: Dictionary = Economy.wallet(story)
		w["salvage"] = int(w.get("salvage", 0)) + value
		story.flags[Economy.WALLET] = w
		return [{"type": "loot", "value": value, "text": "In the hold: %s, worth about %d manna if you can find a buyer." % [name, value], "label": Economy.LABEL}]
	if StoryHouseRules.on(campaign, RULE):
		var s := ship(story).duplicate(true)
		s["loot"] = int(s.get("loot", 0)) + value
		story.flags[KEY] = s
		return [{"type": "loot", "value": value, "text": "In the hold: %s (%d worth of loot to put into the ship)." % [name, value], "label": Economy.LABEL}]
	# By the book there's no money to count: the haul is something the squad can use.
	return StoryEffects.apply({"reserve": str(loot.get("reserve", "reserve_supplies")), "to": "squad", "source": "The haul", "note": name}, story, campaign, {})


static func cost(story: StoryState, campaign: Campaign, slot: String) -> int:
	var costs: Array = cfg().get("slots", {}).get(slot, {}).get("cost", [])
	var lv := level(story, campaign, slot)
	return int(costs[lv]) if lv < costs.size() else -1


static func upgrade_refusal(story: StoryState, campaign: Campaign, slot: String) -> String:
	if not StoryHouseRules.on(campaign, RULE):
		return "The squad doesn't have a ship of its own to upgrade (house rule: own ship)."
	if not cfg().get("slots", {}).has(slot):
		return "Hull, engines, printer, cargo or boarding gear?"
	var c := cost(story, campaign, slot)
	if c < 0:
		return "That's as good as it gets."
	var have := int(Economy.wallet(story).get("manna", 0)) if StoryHouseRules.on(campaign, Economy.R_WALLET) else int(ship(story).get("loot", 0))
	if have < c:
		return "That costs %d; you have %d." % [c, have]
	return ""


static func buy_upgrade(story: StoryState, campaign: Campaign, slot: String) -> Array:
	var c := cost(story, campaign, slot)
	var s := ship(story).duplicate(true)
	if StoryHouseRules.on(campaign, Economy.R_WALLET):
		var w: Dictionary = Economy.wallet(story)
		w["manna"] = int(w["manna"]) - c
		story.flags[Economy.WALLET] = w
	else:
		s["loot"] = int(s.get("loot", 0)) - c
	var slots: Dictionary = s.get("slots", {})
	slots[slot] = int(slots.get(slot, 0)) + 1
	s["slots"] = slots
	story.flags[KEY] = s
	var def: Dictionary = cfg()["slots"][slot]
	return [{"type": "ship_upgraded", "slot": slot, "level": slots[slot], "text": "%s, level %d: %s" % [def.get("name", slot), slots[slot], def.get("text", "")], "label": Economy.LABEL}]


## The ship's printer: a wrecked mech can be reprinted aboard (house rule own ship).
static func has_printer(story: StoryState, campaign: Campaign) -> bool:
	return level(story, campaign, "printer") > 0


## Allied boarding crew on boarding jobs.
static func boarders(story: StoryState, campaign: Campaign) -> Array:
	var n := level(story, campaign, "boarding_gear")
	return [{"name": "Boarding crew", "template": "ph_grunt", "count": n}] if n > 0 else []


## Lower odds of being boarded on the way (hull), and a chance to outrun them (engines).
static func boarding_odds(story: StoryState, campaign: Campaign, chance: int) -> int:
	return maxi(0, chance - 4 * level(story, campaign, "hull") - 3 * level(story, campaign, "engines"))
